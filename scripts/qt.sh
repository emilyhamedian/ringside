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

# Runs the QtTest suites under tests/qml/ with $QMLTESTRUNNER, then the
# locale and data-unit runs, and fails when any of them does. The graph
# history tests' database and the data-unit settings go in the folder $1
# rather than the user's own.
qt_suites() {
    suites_rc=0
    for f in tests/qml/tst_*.qml; do
        echo "-- $f --"
        XDG_DATA_HOME=$1 QT_QUICK_BACKEND=software "$QMLTESTRUNNER" -platform offscreen -input "$f" || suites_rc=1
    done
    # Numbers follow the locale. A German run catches a slide back to
    # toFixed(), an Egyptian Arabic one ASCII digits among the locale's own,
    # in the formatting, in the room the panel's readings keep, and in the
    # Claude and Codex cells, popups and pace sentences.
    # Qt reads LANG and LC_ALL with its own locale data, so the glibc locales
    # aren't needed; without them Qt warns that it switched to C.UTF-8, which
    # is harmless.
    for lang in de_DE ar_EG; do
        for f in tests/qml/tst_format.qml tests/qml/tst_cells.qml tests/qml/tst_usage.qml; do
            echo "-- $f ($lang) --"
            LANG=$lang.UTF-8 LC_ALL=$lang.UTF-8 QT_QUICK_BACKEND=software "$QMLTESTRUNNER" -platform offscreen \
                -input "$f" || suites_rc=1
        done
    done
    # Sizes follow KDE's Region & Language → Data and storage units, which
    # Monitor learns from KDE's own formatter: tst_units runs once for each
    # of its three choices, in English, under a kdeglobals that makes it.
    dialect=0
    for units in iec jedec metric; do
        echo "-- tests/qml/units/tst_units.qml ($units) --"
        mkdir -p "$1/$units"
        printf '[Locale]\nBinaryUnitDialect=%s\n' "$dialect" > "$1/$units/kdeglobals"
        XDG_CONFIG_HOME=$1/$units LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US QT_QUICK_BACKEND=software \
            "$QMLTESTRUNNER" -platform offscreen -input tests/qml/units/tst_units.qml "Units::test_$units" || suites_rc=1
        dialect=$((dialect + 1))
    done
    return "$suites_rc"
}
