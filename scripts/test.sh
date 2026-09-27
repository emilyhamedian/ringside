#!/bin/sh
set -u

# Runs the whole check suite: qmllint over the QML, the QtTest suites under
# tests/qml/, and the hardware-helper shell tests. Needs the Qt 6 tools
# (qmllint, qmltestrunner), so run it on a Plasma host, not in a bare
# container: QMLLINT/QMLTESTRUNNER can point at non-default locations.
#
# Usage: sh scripts/test.sh

cd "$(dirname "$0")/.."

QMLLINT=${QMLLINT:-/usr/lib/qt6/bin/qmllint}
QMLTESTRUNNER=${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}
[ -x "$QMLLINT" ] || QMLLINT=$(command -v qmllint || true)
[ -x "$QMLTESTRUNNER" ] || QMLTESTRUNNER=$(command -v qmltestrunner || true)

failed=0

echo "== qmllint =="
if [ -z "${QMLLINT:-}" ]; then
    echo "qmllint not found (need the Qt 6 build, e.g. /usr/lib/qt6/bin/qmllint)" >&2
    failed=1
else
    qml_files=$(find package/contents/ui tests/qml -name '*.qml' | sort)
    # shellcheck disable=SC2086
    lint_out=$("$QMLLINT" $qml_files 2>&1)
    printf '%s\n' "$lint_out"
    # "unqualified" (i18n calls) and "missing-property" (duck-typed monitor)
    # are accepted ongoing warnings; anything else must not regress.
    bad=$(printf '%s\n' "$lint_out" | grep -E '^(Error|Warning):' | grep -vE '\[(unqualified|missing-property)\]')
    if [ -n "$bad" ]; then
        echo "qmllint: unexpected warnings/errors:" >&2
        printf '%s\n' "$bad" >&2
        failed=1
    fi
fi

echo
echo "== QtTest suites =="
if [ -z "${QMLTESTRUNNER:-}" ]; then
    echo "qmltestrunner not found (need the Qt 6 build, e.g. /usr/lib/qt6/bin/qmltestrunner)" >&2
    failed=1
else
    for f in tests/qml/tst_*.qml; do
        echo "-- $f --"
        QT_QUICK_BACKEND=software "$QMLTESTRUNNER" -platform offscreen -input "$f" || failed=1
    done
fi

echo
echo "== tests/helper/test-info.sh =="
sh tests/helper/test-info.sh || failed=1

echo
if [ "$failed" -eq 0 ]; then
    echo "scripts/test.sh: all checks passed"
else
    echo "scripts/test.sh: FAILED" >&2
fi
exit "$failed"
