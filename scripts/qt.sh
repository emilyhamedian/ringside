# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=sh

# Sourced from the repository's root by the scripts that run Qt's tools.

# Prints where the Qt 6 tool $1 is. Arch and Debian keep the Qt 6 tools in
# /usr/lib/qt6/bin, Fedora and openSUSE in /usr/lib64/qt6/bin; elsewhere
# $2, or $1 without it, is taken from PATH, or named bare if it isn't there.
qt_tool() {
    for tool in /usr/lib/qt6/bin/"$1" /usr/lib64/qt6/bin/"$1"; do
        [ -x "$tool" ] && { echo "$tool"; return; }
    done
    command -v "${2:-$1}" || echo "${2:-$1}"
}

# Calls $1 for every suite and locale/data-unit run, with the file, locale
# and unit dialect as arguments. The caller decides when to run each one.
qt_suites() {
    for f in tests/qml/tst_*.qml; do
        "$1" "$f" "" ""
    done
    # Numbers follow the locale. A German run catches a slide back to
    # toFixed(), an Egyptian Arabic one ASCII digits among the locale's own,
    # in the formatting, in the room the panel's readings keep, and in the
    # Claude, Codex and Kimi cells, popups and pace sentences.
    # Qt reads LANG and LC_ALL with its own locale data, so the glibc locales
    # aren't needed; without them Qt warns that it switched to C.UTF-8, which
    # is harmless.
    for lang in de_DE ar_EG; do
        for f in tests/qml/tst_format.qml tests/qml/tst_cells.qml tests/qml/tst_usage.qml; do
            "$1" "$f" "$lang" ""
        done
    done
    # Sizes follow KDE's Region & Language → Data and storage units, which
    # Monitor learns from KDE's own formatter: tst_units runs once for each
    # of its three choices, in English, under a kdeglobals that makes it.
    for units in iec jedec metric; do
        "$1" tests/qml/units/tst_units.qml en_US "$units"
    done
}

# Each process gets its own history database, settings, caches and temporary
# files. In particular, parallel locale runs must not share Qt's storage.
qt_suite() (
    export HOME="$1/home" XDG_CONFIG_HOME="$1/config" XDG_DATA_HOME="$1/data"
    export XDG_CACHE_HOME="$1/cache" XDG_STATE_HOME="$1/state"
    export XDG_RUNTIME_DIR="$1/runtime" TMPDIR="$1/tmp" QT_QUICK_BACKEND=software
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" \
        "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "$TMPDIR" || exit 1
    chmod 700 "$XDG_RUNTIME_DIR" || exit 1
    if [ -n "$3" ]; then
        export LANG="$3.UTF-8" LC_ALL="$3.UTF-8"
    fi
    if [ -n "$4" ]; then
        case $4 in
            iec) dialect=0 ;;
            jedec) dialect=1 ;;
            metric) dialect=2 ;;
            *) return 1 ;;
        esac
        printf '[Locale]\nBinaryUnitDialect=%s\n' "$dialect" > "$XDG_CONFIG_HOME/kdeglobals" || exit 1
        export LANGUAGE=en_US
        set -- "$2" "Units::test_$4"
    else
        set -- "$2"
    fi
    exec "$QMLTESTRUNNER" -platform offscreen -input "$@"
)
