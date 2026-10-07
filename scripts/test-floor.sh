#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

set -u

# Runs the tests on the supported floor, Plasma 6.0 with Qt 6.6 and KF 6.0,
# where scripts/test.sh can't: the QtTest suites under tests/qml/, tst_format,
# tst_cells and tst_usage in German and Egyptian Arabic, the gallery, the
# hardware helper's shell tests and the usage helper's Python tests. Qt 6.6
# reports binding loops that later Qt doesn't, and the suites and the gallery
# fail on them. libplasma ships an importable org.kde.plasma.plasmoid module
# only from 6.5 on, so the stand-in in tests/floor goes on the import path.
# CI runs this on Fedora 40 as released. qmltestrunner is looked for in
# /usr/lib/qt6/bin, /usr/lib64/qt6/bin and then PATH; set QMLTESTRUNNER to use
# another.
#
# Usage: sh scripts/test-floor.sh

cd "$(dirname "$0")/.." || exit 1

# Without a terminal, Qt sends its log output to the journal. tst_main
# reads main.qml's source, which Qt allows only when asked.
export QT_FORCE_STDERR_LOGGING=1 QT_QUICK_BACKEND=software QML_XHR_ALLOW_FILE_READ=1
export QML_IMPORT_PATH="$PWD/tests/floor${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"

if [ -z "${QMLTESTRUNNER:-}" ]; then
    for QMLTESTRUNNER in /usr/lib/qt6/bin/qmltestrunner /usr/lib64/qt6/bin/qmltestrunner qmltestrunner; do
        command -v "$QMLTESTRUNNER" >/dev/null 2>&1 && break
    done
fi

failed=0

echo "== QtTest suites ($QMLTESTRUNNER) =="
for f in tests/qml/tst_*.qml; do
    echo "-- $f --"
    "$QMLTESTRUNNER" -platform offscreen -input "$f" || failed=1
done
# See scripts/test.sh.
for lang in de_DE ar_EG; do
    for f in tests/qml/tst_format.qml tests/qml/tst_cells.qml tests/qml/tst_usage.qml; do
        echo "-- $f ($lang) --"
        LANG=$lang.UTF-8 LC_ALL=$lang.UTF-8 "$QMLTESTRUNNER" -platform offscreen \
            -input "$f" || failed=1
    done
done

echo
echo "== scripts/gallery.sh =="
# Every popup in every state the gallery shows, which fails on a binding
# or polish loop or a script error.
shots=$(mktemp -d)
trap 'rm -rf "$shots"' EXIT
sh scripts/gallery.sh "$shots/gallery.png" || failed=1

echo
echo "== tests/helper/test-info.sh =="
sh tests/helper/test-info.sh || failed=1

echo
echo "== tests/python (Python helper) =="
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/python || failed=1

echo
if [ "$failed" -eq 0 ]; then
    echo "scripts/test-floor.sh: all checks passed"
else
    echo "scripts/test-floor.sh: FAILED" >&2
fi
exit "$failed"
