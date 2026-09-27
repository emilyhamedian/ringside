#!/bin/sh
# Hardware facts that ksystemstats doesn't publish, for Ringside's QML.
#
#   ringside-info.sh static       one JSON object describing the machine
#   ringside-info.sh pm BDF...    "BDF runtime_status" for each PCI device
#
# It reads sysfs, procfs and udev's database as the logged-in user. Nothing
# here touches a GPU register, so a sleeping discrete GPU stays asleep.
# The RINGSIDE_* variables point it at fixtures for the tests.

set -u
export LC_ALL=C

sys=${RINGSIDE_SYSFS:-/sys}
proc=${RINGSIDE_PROCFS:-/proc}
udevadm=${RINGSIDE_UDEVADM:-udevadm}

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
    cores=$(cat "$sys"/devices/system/cpu/cpu[0-9]*/topology/core_cpus_list 2>/dev/null | sort -u | wc -l | tr -d ' ')
    [ "${cores:-0}" -gt 0 ] || cores=${threads:-0}
    # ksystemstats reads Tctl or Tdie on AMD; name it the way the sensor does.
    label=""
    for h in "$sys"/class/hwmon/hwmon*; do
        case $(first_line "$h/name") in
            k10temp|zenpower) label=$(first_line "$h/temp1_label"); break ;;
        esac
    done
    printf '"cpu":{"model":%s,"cores":%d,"threads":%d,"tempLabel":%s}' \
        "$(str "$model")" "$cores" "${threads:-0}" "$(str "$label")"
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

# ksystemstats numbered GPUs after their DRM card before Plasma 6.7, and by
# PCI topology order since. It only counts AMD, NVIDIA and Intel display devices.
gpus_json() {
    plasma=$1
    case $plasma in
        6.[0-6]|6.[0-6].*) scheme=card ;;
        *) scheme=pci ;;
    esac
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

# The disk holding / and its temperature sensor, named the way libsensors
# names chips: nvme-pci-<domain, bus, device and function packed in hex>.
root_json() {
    uuid=${RINGSIDE_ROOT_UUID-$(findmnt -no UUID / 2>/dev/null)}
    disk=${RINGSIDE_ROOT_DISK-$(lsblk -s -n -r -o NAME,TYPE "$(findmnt -no SOURCE / 2>/dev/null | sed 's/\[.*//')" 2>/dev/null |
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
    plasma=${RINGSIDE_PLASMA_VERSION-$(plasmashell --version 2>/dev/null | awk '{ print $2 }')}
    printf '{"plasma":%s,' "$(str "$plasma")"
    cpu_json; printf ','
    memory_json; printf ','
    swap_json; printf ','
    gpus_json "$plasma"; printf ','
    printf '"defaultInterface":%s,' "$(str "$(default_interface)")"
    root_json
    printf '}\n'
}

pm() {
    for bdf in "$@"; do
        case $bdf in *[!0-9a-fA-F:.]*|'') continue ;; esac
        printf '%s %s\n' "$bdf" "$(first_line "$sys/bus/pci/devices/$bdf/power/runtime_status")"
    done
}

case ${1:-} in
    static) static ;;
    pm) shift; pm "$@" ;;
    *) echo "usage: $0 static | pm BDF..." >&2; exit 2 ;;
esac
