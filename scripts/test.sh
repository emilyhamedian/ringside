#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

set -u

# Runs the whole check suite: qmllint over the QML, the QtTest suites under
# tests/qml/, the hardware helper's shell tests, the usage helper's Python
# tests, and shellcheck and reuse lint where they are installed (always in
# CI). Needs the Qt 6 qmllint and qmltestrunner and the Plasma QML modules,
# so run it on a Plasma 6.5 or later host: older libplasma builds ship no
# importable org.kde.plasma.plasmoid module. The tools are looked for in
# /usr/lib/qt6/bin, /usr/lib64/qt6/bin and then PATH, and must prove to be
# Qt 6 builds; set QMLLINT and QMLTESTRUNNER to use others.
#
# Usage: sh scripts/test.sh

cd "$(dirname "$0")/.." || exit 1

# Without a terminal, Qt sends its log output to the journal.
export QT_FORCE_STDERR_LOGGING=1

find_tool() {
    for tool in /usr/lib/qt6/bin/"$1" /usr/lib64/qt6/bin/"$1"; do
        [ -x "$tool" ] && { echo "$tool"; return; }
    done
    command -v "$1" || echo "$1"
}
QMLLINT=${QMLLINT:-$(find_tool qmllint)}
QMLTESTRUNNER=${QMLTESTRUNNER:-$(find_tool qmltestrunner)}

failed=0
fail() {
    printf 'scripts/test.sh: %s\n' "$*" >&2
    failed=1
}

echo "== qmllint ($QMLLINT) =="
version=$("$QMLLINT" --version 2>&1)
if ! printf '%s\n' "$version" | grep -q '^qmllint 6\.'; then
    fail "need the Qt 6 qmllint, but $QMLLINT --version says: ${version:-nothing}. Set QMLLINT to it."
else
    qml_files=$(find package/contents/ui tests/qml -name '*.qml' | sort)
    # shellcheck disable=SC2086
    lint_out=$("$QMLLINT" $qml_files 2>&1)
    lint_rc=$?
    printf '%s\n' "$lint_out"
    # qmllint exits 255 (-1) when it reports a problem, on Qt 6.6 and 6.7
    # even for accepted warnings. Any other status, or 255 with nothing
    # reported, means it did not finish.
    case $lint_rc in
        0) ;;
        255) printf '%s\n' "$lint_out" | grep -qE '^(Error|Warning):' ||
                 fail "qmllint exited $lint_rc without reporting a problem" ;;
        *) fail "qmllint exited $lint_rc" ;;
    esac
    # The one accepted warning is [unqualified] on an i18n call, which Plasma
    # provides at run time. Its header gives the column, counted in
    # characters, and the next line quotes the source; awk runs in the C
    # locale, so at() skips UTF-8 continuation bytes to find that column.
    # A deliberate duck-typed access is marked "// qmllint disable
    # missing-property", which qmllint honours by staying quiet.
    bad=$(printf '%s\n' "$lint_out" | LC_ALL=C awk '
        function at(s, col,    i, n, c) {
            for (i = 1; i <= length(s); i++) {
                c = substr(s, i, 1)
                if ((c < "\200" || c >= "\300") && ++n == col) return i
            }
            return 0
        }
        held != "" {
            if (/^(Error|Warning):/ || substr($0, at($0, col), 4) != "i18n") print held
            held = ""
        }
        /^(Error|Warning):/ {
            if (/\[unqualified\]$/ && match($0, /:[0-9]+: /)) {
                col = substr($0, RSTART + 1, RLENGTH - 3) + 0
                held = $0
            } else {
                print
            }
        }
        END { if (held != "") print held }')
    if [ -n "$bad" ]; then
        fail "qmllint: unexpected warnings/errors:"
        printf '%s\n' "$bad" >&2
    fi
fi

echo
echo "== APIs newer than Plasma 6.0, Qt 6.6 and KF 6.0 =="
# CI's floor job runs only the tests that load on Plasma 6.0, and only the
# paths they reach, so this check stands in for the rest.
# Kirigami.Theme.fixedWidthFont arrived in KF 6.14 and FontMetrics'
# capitalHeight in Qt 6.9, and before then each reads as undefined, so each
# needs its fallback straight after it on the same line:
# fixedWidthFont?.family ?? "monospace", and capitalHeight ?? something.
# Qt's JavaScript engine has no Array.prototype.flatMap. Whole-line comments
# don't count. grep exits 2 on an error, such as having no -P.
newer=$(grep -rnP '^(?!\s*//).*(fixedWidthFont(?!\?\.family\s*\?\?\s*"monospace")|capitalHeight(?!\s*\?\?)|\.flatMap\()' \
    package/contents/ui tests/qml)
case $? in
    0) fail "use of an API newer than the supported floor, without a fallback:"
       printf '%s\n' "$newer" >&2 ;;
    1) echo "none" ;;
    *) fail "grep -P failed, so the check for newer APIs did not run" ;;
esac

echo
echo "== QtTest suites ($QMLTESTRUNNER) =="
# qmltestrunner has no --version: a Qt 6 build states its QtTest version
# when it runs a test, and a Qt 5 one can't load the unversioned imports.
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
printf 'import QtTest\nTestCase { name: "probe" }\n' > "$probe/tst_probe.qml"
probe_out=$(QT_QUICK_BACKEND=software "$QMLTESTRUNNER" -platform offscreen -input "$probe/tst_probe.qml" 2>&1)
if ! printf '%s\n' "$probe_out" | grep -q '^Config: Using QtTest library 6\.'; then
    fail "need the Qt 6 qmltestrunner, but $QMLTESTRUNNER ran a probe test with: ${probe_out:-no output}. Set QMLTESTRUNNER to it."
else
    for f in tests/qml/tst_*.qml; do
        echo "-- $f --"
        QT_QUICK_BACKEND=software "$QMLTESTRUNNER" -platform offscreen -input "$f" || failed=1
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
                -input "$f" || failed=1
        done
    done
fi

echo
echo "== tests/helper/test-info.sh =="
sh tests/helper/test-info.sh || failed=1

echo
echo "== tests/python (Python helper) =="
# The helper has to run on Python 3.11, whatever this machine has.
PYTHONDONTWRITEBYTECODE=1 python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), feature_version=(3, 11))' \
    package/contents/code/usage.py || fail "usage.py needs a newer Python than 3.11"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/python || failed=1

echo
echo "== shellcheck =="
sh_files=$(find package/contents/code scripts tests \( -name '*.sh' -o -name '*.bash' \) | sort)
if command -v shellcheck >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    shellcheck $sh_files || failed=1
elif [ -n "${CI:-}" ]; then
    fail "shellcheck not installed, and CI is set"
else
    echo "scripts/test.sh: shellcheck not installed, skipping"
fi

echo
echo "== reuse lint =="
if command -v reuse >/dev/null 2>&1; then
    reuse lint || failed=1
elif [ -n "${CI:-}" ]; then
    fail "reuse not installed, and CI is set"
else
    echo "scripts/test.sh: reuse not installed, skipping"
fi

echo
if [ "$failed" -eq 0 ]; then
    echo "scripts/test.sh: all checks passed"
else
    echo "scripts/test.sh: FAILED" >&2
fi
exit "$failed"
