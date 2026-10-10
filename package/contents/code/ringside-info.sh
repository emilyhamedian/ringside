#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Hardware facts that ksystemstats doesn't publish, for Ringside's QML.
#
#   ringside-info.sh static       one JSON object describing the machine
#   ringside-info.sh pm BDF...    "BDF runtime_status control" for each PCI
#                                 device, one space between fields even when
#                                 one is empty (unreadable)
#   ringside-info.sh route        the default-route interface, or an empty line
#   ringside-info.sh egress       "4 DEV TUNNEL" and "6 DEV TUNNEL": the interface
#                                 each family's traffic to the internet leaves
#                                 through (empty without a route), and 1 when
#                                 it is a tunnel, else 0; exits 3 without `ip`
#
# It reads sysfs, procfs and udev's database as the logged-in user, and asks
# `ip route get` for routes, which sends nothing. Nothing here touches a GPU
# register, so a sleeping discrete GPU stays asleep.
# The RINGSIDE_* variables point it at fixtures for the tests.

set -u
export LC_ALL=C

sys=${RINGSIDE_SYSFS:-/sys}
proc=${RINGSIDE_PROCFS:-/proc}
udevadm=${RINGSIDE_UDEVADM:-udevadm}
lsblk=${RINGSIDE_LSBLK:-lsblk}
ip=${RINGSIDE_IP:-ip}

# A JSON string literal: control characters dropped, backslashes and quotes escaped.
str() {
    printf '"%s"' "$(printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

first_line() {
    [ -r "$1" ] && head -n 1 "$1" 2>/dev/null
}

upper() {
    printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

cpu_json() {
    model=$(awk -F': *' '/^model name[[:space:]]*:/ { print $2; exit }' "$proc/cpuinfo" 2>/dev/null)
    [ -n "$model" ] || model=$(awk -F': *' '/^(Hardware|Model)[[:space:]]*:/ { print $2; exit }' "$proc/cpuinfo" 2>/dev/null)
    threads=$(grep -c '^processor' "$proc/cpuinfo" 2>/dev/null)
    # ksystemstats names each CPU after its processor number, and those skip
    # offline threads.
    ids=$(awk -F'[[:space:]]*:[[:space:]]*' '$1 == "processor" && $2 ~ /^[0-9]+[[:space:]]*$/ {
              printf "%s%d", sep, $2; sep = "," }' "$proc/cpuinfo" 2>/dev/null)
    cores=$(cat "$sys"/devices/system/cpu/cpu[0-9]*/topology/core_cpus_list 2>/dev/null | sort -u | wc -l | tr -d ' ')
    [ "${cores:-0}" -gt 0 ] || cores=${threads:-0}
    # ksystemstats reads only k10temp on AMD, and prefers Tdie to Tctl when
    # k10temp has both (the Zen and Zen+ parts whose Tctl carries an offset).
    label=""
    for h in "$sys"/class/hwmon/hwmon*; do
        [ "$(first_line "$h/name")" = k10temp ] || continue
        label=Tctl
        grep -qx Tdie "$h"/temp*_label 2>/dev/null && label=Tdie
        break
    done
    printf '"cpu":{"model":%s,"cores":%d,"threads":%d,"ids":[%s],"tempLabel":%s}' \
        "$(str "$model")" "$cores" "${threads:-0}" "$ids" "$(str "$label")"
}

# Module type, speed and sizes from systemd's dmi_memory_id, which udev keeps
# readable for every user. Empty slots are skipped; the slowest configured
# speed is what the memory runs at.
memory_json() {
    if [ -n "${RINGSIDE_DMI_PROPS:-}" ]; then
        dmi=$(cat "$RINGSIDE_DMI_PROPS" 2>/dev/null)
    else
        dmi=$("$udevadm" info -q property -p /devices/virtual/dmi/id 2>/dev/null)
    fi
    printf '%s\n' "$dmi" | awk '
        /^MEMORY_DEVICE_[0-9]+_/ {
            eq = index($0, "=")
            name = substr($0, 1, eq - 1)
            n = name; sub(/^MEMORY_DEVICE_/, "", n); sub(/_.*/, "", n)
            key = substr(name, length("MEMORY_DEVICE_" n "_") + 1)
            value[n, key] = substr($0, eq + 1)
            if (!(n in seen)) { seen[n] = 1; order[++count] = n }
        }
        END {
            type = ""; speed = 0; sizes = ""
            for (i = 1; i <= count; i++) {
                n = order[i]
                if (value[n, "PRESENT"] == "0" || value[n, "SIZE"] + 0 <= 0) continue
                sizes = sizes (sizes == "" ? "" : ",") value[n, "SIZE"]
                if (type == "") type = value[n, "TYPE"]
                s = value[n, "CONFIGURED_SPEED_MTS"] + 0
                if (s <= 0) s = value[n, "SPEED_MTS"] + 0
                if (s > 0 && (speed == 0 || s < speed)) speed = s
            }
            gsub(/[^A-Za-z0-9 -]/, "", type)
            printf "\"memory\":{\"type\":\"%s\",\"speed\":%d,\"modules\":[%s]}", type, speed, sizes
        }'
}

swap_json() {
    kinds=$(awk 'NR > 1 { if ($1 ~ /^\/dev\/zram/) z = 1; else d = 1 }
                 END { printf "%s%s%s", (z ? "\"zram\"" : ""), ((z && d) ? "," : ""), (d ? "\"disk\"" : "") }' \
            "$proc/swaps" 2>/dev/null)
    printf '"swap":[%s]' "$kinds"
}

amdgpu_ids=${RINGSIDE_AMDGPU_IDS:-}
if [ -z "$amdgpu_ids" ]; then
    for f in /usr/share/libdrm/amdgpu.ids /usr/local/share/libdrm/amdgpu.ids; do
        if [ -r "$f" ]; then
            amdgpu_ids=$f
            break
        fi
    done
fi

# Marketing name from libdrm's table, matched on device and revision.
amd_name() {
    [ -n "$amdgpu_ids" ] || return 0
    awk -F',[ \t]*' -v d="$1" -v r="$2" 'toupper($1) == d && toupper($2) == r { print $3; exit }' "$amdgpu_ids"
}

pci_name() {
    "$udevadm" info -q property -p "$1" 2>/dev/null | sed -n 's/^ID_MODEL_FROM_DATABASE=//p'
}

# A Plasma version as one number that compares in order, 6.3.90 -> 6003090.
# Empty when there is no version to read.
version_number() {
    printf '%s\n' "$1" | awk -F. '$1 ~ /^[0-9]+$/ { printf "%d\n", $1 * 1000000 + $2 * 1000 + $3; exit }'
}

# ksystemstats numbered GPUs after their DRM card before Plasma 6.6.90 (the
# 6.7 beta), and by PCI topology order since. It only counts AMD, NVIDIA and
# Intel display devices, but reads Intel only from 6.3.90 (the 6.4 beta) on,
# and Intel on the xe driver only from 6.7.90 (the 6.8 beta) on. An unknown
# version gets the newest behaviour.
gpus_json() {
    v=$(version_number "$1")
    scheme=pci
    [ -n "$v" ] && [ "$v" -lt 6006090 ] && scheme=card
    printf '"gpus":['
    for d in "$sys"/bus/pci/devices/*; do
        case $(first_line "$d/class") in 0x030000|0x030200|0x038000) ;; *) continue ;; esac
        case $(first_line "$d/vendor") in 0x1002|0x10de|0x8086) ;; *) continue ;; esac
        readlink -f "$d"
    done | sort | {
        n=0
        sep=""
        while IFS= read -r p; do
            bdf=${p##*/}
            vendor=$(first_line "$p/vendor"); vendor=${vendor#0x}
            device=$(first_line "$p/device"); device=${device#0x}
            revision=$(first_line "$p/revision"); revision=${revision#0x}
            card=""
            for c in "$p"/drm/card[0-9]*; do
                if [ -e "$c" ]; then
                    card=${c##*/}
                    break
                fi
            done
            if [ "$scheme" = card ]; then
                id=${card:+gpu${card#card}}
            else
                id=gpu$n
            fi
            n=$((n + 1))
            [ -n "$id" ] || continue
            # Leave out an Intel GPU this ksystemstats can't read. It still
            # used up its PCI index above, as it does in ksystemstats.
            if [ "$vendor" = 8086 ] && [ -n "$v" ]; then
                [ "$v" -lt 6003090 ] && continue
                driver=$(readlink "$p/driver" 2>/dev/null)
                [ "${driver##*/}" = xe ] && [ "$v" -lt 6007090 ] && continue
            fi

            # The rules switcheroo-control uses: NVIDIA is always discrete, Intel's
            # integrated GPU sits at 00:02.0, and only an AMD APU reports vddnb (in1).
            kind=discrete
            case $vendor in
                8086) [ "$bdf" = 0000:00:02.0 ] && kind=integrated ;;
                1002)
                    for h in "$p"/hwmon/hwmon*/in1_input; do
                        [ -e "$h" ] && kind=integrated
                    done
                    ;;
            esac

            name=""
            [ "$vendor" = 1002 ] && name=$(amd_name "$(upper "$device")" "$(upper "$revision")")
            control=$(first_line "$p/power/control")
            delay=$(first_line "$p/power/autosuspend_delay_ms")
            case $delay in ''|*[!0-9]*) delay=0 ;; esac

            printf '%s{"id":"%s","bdf":%s,"vendor":"%s","kind":"%s","name":%s,"pciName":%s,"runtimePm":%s,"autosuspendMs":%d}' \
                "$sep" "$id" "$(str "$bdf")" "$vendor" "$kind" "$(str "$name")" "$(str "$(pci_name "$p")")" \
                "$([ "$kind" = discrete ] && [ "$control" = auto ] && echo true || echo false)" "$delay"
            sep=,
        done
    }
    printf ']'
}

default_interface() {
    awk 'NR > 1 && $2 == "00000000" { print $1; exit }' "$proc/net/route" 2>/dev/null
}

# The interface the kernel would send a packet to a public address through.
# `ip route get` only looks the route up in the kernel's tables: nothing is
# sent, to that address or anywhere. A missing, unreachable, blackhole or
# prohibited route makes ip fail with no output; a route to a local address
# answers with loopback. Both count as no route.
egress_dev() {
    "$ip" "$@" 2>/dev/null | awk 'NR == 1 { for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }'
}

# A tunnel (WireGuard, tun) has no link-layer header, ARPHRD_NONE (65534);
# a tap device is an Ethernet one, known by its tun_flags. The name is
# checked as Linux allows one before it goes into a path.
egress() {
    if ! command -v "$ip" >/dev/null 2>&1; then
        printf '4  0\n6  0\n'
        exit 3
    fi
    for family in 4 6; do
        if [ "$family" = 4 ]; then
            dev=$(egress_dev route get 1.1.1.1)
        else
            dev=$(egress_dev -6 route get 2606:4700:4700::1111)
        fi
        case $dev in lo|.|..|*/*|*:*|*[[:space:]]*) dev="" ;; esac
        [ "${#dev}" -le 15 ] || dev=""
        tunnel=0
        if [ -n "$dev" ] && { [ "$(first_line "$sys/class/net/$dev/type")" = 65534 ] ||
                              [ -e "$sys/class/net/$dev/tun_flags" ]; }; then
            tunnel=1
        fi
        printf '%s %s %s\n' "$family" "$dev" "$tunnel"
    done
}

# Whole disks, so that I/O can be summed without counting a partition, LUKS,
# LVM or RAID device on top of the disk under it. /sys/block is the fallback
# when lsblk is missing; there, virtual devices have no device link.
disks_json() {
    printf '"disks":['
    {
        if [ -n "${RINGSIDE_DISKS+set}" ]; then
            printf '%s\n' "$RINGSIDE_DISKS" | tr ' ' '\n'
        elif out=$("$lsblk" -dnr -o NAME,TYPE 2>/dev/null); then
            printf '%s\n' "$out" | awk '$2 == "disk" { print $1 }'
        else
            for b in "$sys"/block/*; do
                [ -e "$b/device" ] && printf '%s\n' "${b##*/}"
            done
        fi
    } | {
        sep=""
        while IFS= read -r d; do
            case $d in ''|zram*|loop*|sr*|ram*|nbd*) continue ;; esac
            printf '%s%s' "$sep" "$(str "$d")"
            sep=,
        done
    }
    printf ']'
}

# The disk holding / and its temperature sensor, named the way libsensors
# names chips: nvme-pci-<domain, bus, device and function packed in hex>.
root_json() {
    uuid=${RINGSIDE_ROOT_UUID-$(findmnt -no UUID / 2>/dev/null)}
    disk=${RINGSIDE_ROOT_DISK-$("$lsblk" -s -n -r -o NAME,TYPE "$(findmnt -no SOURCE / 2>/dev/null | sed 's/\[.*//')" 2>/dev/null |
        awk '$2 == "disk" { print $1; exit }')}
    temp=""
    if [ -n "$disk" ]; then
        for h in "$sys/block/$disk"/device/hwmon*; do
            [ -e "$h/temp1_input" ] || continue
            chip=$(first_line "$h/name")
            bdf=$(readlink -f "$sys/block/$disk/device/device"); bdf=${bdf##*/}
            case $bdf in
                *:*:*.*)
                    domain=${bdf%%:*}; rest=${bdf#*:}
                    bus=${rest%%:*}; rest=${rest#*:}
                    slot=${rest%%.*}; fn=${rest#*.}
                    addr=$(( (0x$domain << 16) | (0x$bus << 8) | (0x$slot << 3) | fn ))
                    temp=$(printf 'lmsensors/%s-pci-%04x/temp1' "$chip" "$addr")
                    ;;
            esac
            break
        done
    fi
    printf '"root":{"uuid":%s,"disk":%s,"tempSensor":%s}' "$(str "$uuid")" "$(str "$disk")" "$(str "$temp")"
}

static() {
    # Qt warns about the C locale; without a terminal it would log that to the
    # journal rather than to the stderr thrown away here.
    plasma=${RINGSIDE_PLASMA_VERSION-$(QT_FORCE_STDERR_LOGGING=1 plasmashell --version 2>/dev/null | awk '{ print $2 }')}
    printf '{"plasma":%s,' "$(str "$plasma")"
    cpu_json; printf ','
    memory_json; printf ','
    swap_json; printf ','
    gpus_json "$plasma"; printf ','
    printf '"defaultInterface":%s,' "$(str "$(default_interface)")"
    disks_json; printf ','
    root_json
    printf '}\n'
}

# power/control is read on every poll because TLP and powertop flip it
# between "on" and "auto" when the laptop is plugged in or unplugged.
pm() {
    for bdf in "$@"; do
        case $bdf in *[!0-9a-fA-F:.]*|'') continue ;; esac
        d=$sys/bus/pci/devices/$bdf/power
        printf '%s %s %s\n' "$bdf" "$(first_line "$d/runtime_status")" "$(first_line "$d/control")"
    done
}

case ${1:-} in
    static) static ;;
    pm) shift; pm "$@" ;;
    route) printf '%s\n' "$(default_interface)" ;;
    egress) egress ;;
    *) echo "usage: $0 static | pm BDF... | route | egress" >&2; exit 2 ;;
esac
