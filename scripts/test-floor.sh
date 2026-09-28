#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

set -u

# Runs the tests that can run on the supported floor, Plasma 6.0 with Qt 6.6
# and KF 6.0, where scripts/test.sh can't: the QtTest suites under
# tests/qml/, tst_format in German and Egyptian Arabic, the hardware helper's
# shell tests and the usage helper's Python tests. Qt 6.6 reports binding
# loops that later Qt doesn't, and the suites fail on them. libplasma ships
# an importable org.kde.plasma.plasmoid module only from 6.5 on, so a failing
# test that was told that module is not installed counts as skipped; any
# other failure fails the run. CI runs this on Fedora 40 as released.
# qmltestrunner is looked for in /usr/lib/qt6/bin, /usr/lib64/qt6/bin and
# then PATH; set QMLTESTRUNNER to use another.
#
# Usage: sh scripts/test-floor.sh

cd "$(dirname "$0")/.." || exit 1

# Without a terminal, Qt sends its log output to the journal.
export QT_FORCE_STDERR_LOGGING=1 QT_QUICK_BACKEND=software

if [ -z "${QMLTESTRUNNER:-}" ]; then
    for QMLTESTRUNNER in /usr/lib/qt6/bin/qmltestrunner /usr/lib64/qt6/bin/qmltestrunner qmltestrunner; do
        command -v "$QMLTESTRUNNER" >/dev/null 2>&1 && break
    done
fi

failed=0
skipped=
log=$(mktemp)
trap 'rm -f "$log"' EXIT

# Prints how many tests failed in a qmltestrunner log, and succeeds only if
# the run finished and every failure came from a test that was told
# org.kde.plasma.plasmoid is not installed. Each message names the test it
# came from, and a load error's details follow it on lines of their own.
plasmoid_only() {
    awk '
        /^[A-Z!]+ *: / { id = $0; sub(/^[A-Z!]+ *: /, "", id); sub(/\) .*/, ")", id) }
        /module "org\.kde\.plasma\.plasmoid" is not installed/ { needs[id] = 1 }
        /^FAIL! / && !(id in needs) { other = 1 }
        /^Totals: / { failures = $4 }
        END { print failures + 0; exit !(failures > 0 && !other) }' "$1"
}

echo "== QtTest suites ($QMLTESTRUNNER) =="
for f in tests/qml/tst_*.qml; do
    echo "-- $f --"
    "$QMLTESTRUNNER" -platform offscreen -input "$f" >"$log" 2>&1
    rc=$?
    cat "$log"
    [ "$rc" -eq 0 ] && continue
    if n=$(plasmoid_only "$log"); then
        echo "scripts/test-floor.sh: $f: skipped $n failed test(s) that need org.kde.plasma.plasmoid"
        skipped="$skipped $f"
    else
        failed=1
    fi
done
# See scripts/test.sh.
for lang in de_DE ar_EG; do
    echo "-- tests/qml/tst_format.qml ($lang) --"
    LANG=$lang.UTF-8 LC_ALL=$lang.UTF-8 "$QMLTESTRUNNER" -platform offscreen \
        -input tests/qml/tst_format.qml || failed=1
done

echo
echo "== tests/helper/test-info.sh =="
sh tests/helper/test-info.sh || failed=1

echo
echo "== tests/python (Python helper) =="
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/python || failed=1

echo
if [ "$failed" -eq 0 ]; then
    echo "scripts/test-floor.sh: all checks passed${skipped:+, skipping tests that need org.kde.plasma.plasmoid in$skipped}"
else
    echo "scripts/test-floor.sh: FAILED" >&2
fi
exit "$failed"
