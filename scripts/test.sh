#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later
# Check functions and the Qt suite callback are invoked indirectly, which
# ShellCheck 0.10 and later report as SC2329 and 0.9 (Ubuntu 24.04's, as CI
# runs) as SC2317.
# shellcheck disable=SC2317,SC2329

set -u

# Runs the whole check suite: qmllint over the QML, the QtTest suites under
# tests/qml/, the hardware helper's shell tests, the usage helper's Python
# tests, and shellcheck and reuse lint where they are installed (always in
# CI). Needs the Qt 6 qmllint and qmltestrunner and the Plasma QML modules,
# so run it on a Plasma 6.8 or later host. The tools are looked for in
# /usr/lib/qt6/bin, /usr/lib64/qt6/bin and then PATH, and must prove to be
# Qt 6 builds; set QMLLINT and QMLTESTRUNNER to use others.
#
# Usage: [TEST_JOBS=N] sh scripts/test.sh
# Independent checks run in parallel (nproc by default). Each says PASS or
# FAIL in one line as it finishes; their complete logs then print in the
# order below.

cd "$(dirname "$0")/.." || exit 1

# Without a terminal, Qt sends its log output to the journal. tst_main
# reads main.qml's source, which Qt allows only when asked.
export QT_FORCE_STDERR_LOGGING=1 QML_XHR_ALLOW_FILE_READ=1

# shellcheck source=scripts/qt.sh
. scripts/qt.sh
QMLLINT=${QMLLINT:-$(qt_tool qmllint)}
QMLTESTRUNNER=${QMLTESTRUNNER:-$(qt_tool qmltestrunner)}
export QMLLINT QMLTESTRUNNER

failed=0
fail() {
    printf 'scripts/test.sh: %s\n' "$*" >&2
    failed=1
}

check_qmllint() {
    version=$("$QMLLINT" --version 2>&1)
    if ! printf '%s\n' "$version" | grep -q '^qmllint 6\.'; then
        fail "need the Qt 6 qmllint, but $QMLLINT --version says: ${version:-nothing}. Set QMLLINT to it."
    else
        # fakeplasmoid stands in for Plasma's own module, and qmllint 6.12 says
        # its singleton is undeclared even though its qmldir declares it.
        qml_files=$(find package/contents/ui tests/qml -path tests/qml/fakeplasmoid -prune -o -name '*.qml' -print | sort)
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
}

check_javascript() {
    # Qt's JavaScript engine has no Array.prototype.flatMap. Whole-line comments
    # don't count. grep exits 2 on an error, such as having no -P.
    unsupported=$(grep -rnP '^(?!\s*//).*\.flatMap\(' package/contents/ui tests/qml)
    case $? in
        0) fail "use of a JavaScript API unsupported by Qt:"
           printf '%s\n' "$unsupported" >&2 ;;
        1) echo "none" ;;
        *) fail "grep -P failed, so the check for unsupported JavaScript APIs did not run" ;;
    esac
}

check_qt() {
    # qmltestrunner has no --version: a Qt 6 build states its QtTest version
    # when it runs a test, and a Qt 5 one can't load the unversioned imports.
    printf 'import QtTest\nTestCase { name: "probe" }\n' > "$check_dir/tst_probe.qml" || return 1
    probe_out=$(qt_suite "$check_dir" "$check_dir/tst_probe.qml" "" "" 2>&1)
    probe_rc=$?
    if ! printf '%s\n' "$probe_out" | grep -q '^Config: Using QtTest library 6\.'; then
        fail "need the Qt 6 qmltestrunner, but $QMLTESTRUNNER ran a probe test with: ${probe_out:-no output}. Set QMLTESTRUNNER to it."
    elif [ "$probe_rc" -ne 0 ]; then
        printf '%s\n' "$probe_out"
        fail "QtTest probe exited $probe_rc"
    else
        printf '%s\n' "$probe_out"
    fi
}

check_qml() {
    qt_suite "$check_dir" "$@"
}

check_helper() {
    sh tests/helper/test-info.sh
}

check_python() {
    # test_python311 checks the helper's syntax against Python 3.11, whatever
    # this machine has.
    PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/python
}

check_shellcheck() {
    # The hardware helper's fixtures also hold executable stand-ins for the
    # commands it runs, such as ip and lsblk, named without a .sh suffix.
    sh_files=$(find package/contents/code scripts tests \( -name '*.sh' -o -path 'tests/helper/fixtures/*' -type f -perm -u+x \) | sort)
    if command -v shellcheck >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        shellcheck $sh_files || failed=1
    elif [ -n "${CI:-}" ]; then
        fail "shellcheck not installed, and CI is set"
    else
        echo "scripts/test.sh: shellcheck not installed, skipping"
    fi
}

check_reuse() {
    if command -v reuse >/dev/null 2>&1; then
        reuse lint || failed=1
    elif [ -n "${CI:-}" ]; then
        fail "reuse not installed, and CI is set"
    else
        echo "scripts/test.sh: reuse not installed, skipping"
    fi
}

run_check() {
    check_dir=$1
    shift
    started=$(date +%s)
    "$@" > "$check_dir/output" 2>&1 || failed=1
    printf '%s\n' "$failed" > "$check_dir/status"
    # One short write per line, so lines from parallel checks don't mix.
    if [ "$failed" -eq 0 ]; then result=PASS; else result=FAIL; fi
    printf '%s  %s (%s s)\n' "$result" "$(cat "$check_dir/title")" "$(($(date +%s) - started))"
}

# xargs starts fresh shells, so a check's failure cannot change another's
# status. Status files also catch a worker that exits without finishing.
if [ "${1:-}" = --check ]; then
    check_dir=$2/$3
    shift 3
    run_check "$check_dir" "$@"
    exit $?
fi

jobs=${TEST_JOBS-$(nproc)}
case $jobs in
    ''|*[!0-9]*) echo "scripts/test.sh: TEST_JOBS must be a positive integer" >&2; exit 1 ;;
esac
if ! [ "$jobs" -gt 0 ] 2>/dev/null; then
    echo "scripts/test.sh: TEST_JOBS must be a positive integer" >&2
    exit 1
fi
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' 0
trap 'exit 130' INT
trap 'exit 143' TERM
checks=0

add_check() {
    checks=$((checks + 1))
    mkdir "$work/$checks" || exit 1
    printf '%s\n' "$1" > "$work/$checks/title" || exit 1
}

queue_check() {
    add_check "$1"
    shift
    # Fixed-size NUL-delimited records preserve empty locale/unit arguments.
    printf '%s\0' "$checks" "$1" "${2:-}" "${3:-}" "${4:-}" >> "$work/jobs" || exit 1
}

queue_qml() {
    title=$1
    if [ -n "$3" ]; then
        title="$title ($3)"
    elif [ -n "$2" ]; then
        title="$title ($2)"
    fi
    queue_check "$title" check_qml "$@"
}

printf 'scripts/test.sh: running checks with up to %s jobs\n' "$jobs"
queue_check "qmllint ($QMLLINT)" check_qmllint
queue_check "Unsupported JavaScript APIs" check_javascript
add_check "QtTest probe ($QMLTESTRUNNER)"
# Only suite runs depend on this short version probe. All other checks still
# run when the selected qmltestrunner cannot load Qt 6 tests.
run_check "$work/$checks" check_qt
if [ "$failed" -eq 0 ]; then
    qt_suites queue_qml
fi
queue_check tests/helper/test-info.sh check_helper
queue_check "tests/python (Python helper)" check_python
queue_check shellcheck check_shellcheck
queue_check "reuse lint" check_reuse

xargs -0 -n 5 -P "$jobs" sh scripts/test.sh --check "$work" < "$work/jobs" || fail "could not run every check"

printf '\nscripts/test.sh: every check has finished; their output follows\n'

check=1
while [ "$check" -le "$checks" ]; do
    check_dir=$work/$check
    status=$(cat "$check_dir/status" 2>/dev/null)
    if [ "$status" = 0 ]; then
        result=PASS
    else
        result=FAIL
        failed=1
    fi
    printf '\n== %s: %s ==\n' "$result" "$(cat "$check_dir/title")"
    cat "$check_dir/output" || failed=1
    [ -n "$status" ] || echo "scripts/test.sh: check did not finish" >&2
    check=$((check + 1))
done

echo
if [ "$failed" -eq 0 ]; then
    echo "scripts/test.sh: all checks passed"
else
    echo "scripts/test.sh: FAILED" >&2
fi
exit "$failed"
