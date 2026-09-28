#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Runs package/contents/code/ringside-info.sh against small fake sysfs/procfs
# trees under tests/helper/fixtures/ and checks its JSON (or, for "pm", its
# plain text) against a recorded expected output.
#
# Each fixtures/<case>/ directory holds:
#   env          shell snippet exporting the RINGSIDE_* variables for this case
#   args         the arguments to pass after ringside-info.sh (e.g. "static")
#   expected.json  or  expected.txt
#
# Cases may share a sysfs/procfs tree (see legacy-ids and empty-slot, which
# point their env at another case's tree) rather than duplicating fixtures.
# Every "static" case pins RINGSIDE_DISKS or RINGSIDE_LSBLK, so the host's
# own disks never reach the output.
#
# Usage: sh tests/helper/test-info.sh

set -u

SCRIPT_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH="" cd -- "$SCRIPT_DIR/../.." && pwd)
FIXTURES="$SCRIPT_DIR/fixtures"
INFO_SH="$REPO_ROOT/package/contents/code/ringside-info.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

if command -v jq >/dev/null 2>&1; then
    JSON_TOOL=jq
elif command -v python3 >/dev/null 2>&1; then
    JSON_TOOL=python3
else
    JSON_TOOL=none
fi

normalise_json() {
    case $JSON_TOOL in
        jq) jq -S . "$1" 2>/dev/null ;;
        python3) python3 -m json.tool "$1" 2>/dev/null ;;
        none) cat "$1" ;;
    esac
}

pass=0
fail=0

# git doesn't store empty directories, so a case that needs one passes here
# and fails in a fresh clone. Put a file in it (drm/cardN/dev, say).
empty=$(find "$FIXTURES" -type d -empty)
if [ -n "$empty" ]; then
    echo "FAIL  empty fixture directories, which a clone won't have:"
    printf '%s\n' "$empty" | sed "s|^$FIXTURES/|        |"
    fail=$((fail + 1))
fi

for case_dir in "$FIXTURES"/*/; do
    case_dir=${case_dir%/}
    name=$(basename "$case_dir")
    [ "$name" = "common" ] && continue
    [ -f "$case_dir/env" ] || continue

    args=$(cat "$case_dir/args" 2>/dev/null || echo static)
    actual="$WORK/$name.out"

    (
        # shellcheck disable=SC1090,SC1091
        . "$case_dir/env"
        # shellcheck disable=SC2086
        sh "$INFO_SH" $args
    ) >"$actual" 2>"$WORK/$name.err"

    if [ -f "$case_dir/expected.json" ]; then
        expected="$case_dir/expected.json"
        if [ "$JSON_TOOL" = none ]; then
            ok=false
            diff -q "$actual" "$expected" >/dev/null 2>&1 && ok=true
        else
            a=$(normalise_json "$actual")
            e=$(normalise_json "$expected")
            if [ -z "$a" ] || [ -z "$e" ]; then
                ok=false
            elif [ "$a" = "$e" ]; then
                ok=true
            else
                ok=false
            fi
        fi
    elif [ -f "$case_dir/expected.txt" ]; then
        expected="$case_dir/expected.txt"
        ok=false
        diff -q "$actual" "$expected" >/dev/null 2>&1 && ok=true
    else
        echo "SKIP  $name (no expected.json or expected.txt)"
        continue
    fi

    if [ "$ok" = true ]; then
        echo "PASS  $name"
        pass=$((pass + 1))
    else
        echo "FAIL  $name"
        echo "      command: ringside-info.sh $args"
        if [ -s "$WORK/$name.err" ]; then
            echo "      stderr:"
            sed 's/^/        /' "$WORK/$name.err"
        fi
        echo "      diff (expected vs actual):"
        diff -u "$expected" "$actual" 2>/dev/null | sed 's/^/        /'
        fail=$((fail + 1))
    fi
done

echo
echo "test-info: $pass passed, $fail failed (json tool: $JSON_TOOL)"
[ "$fail" -eq 0 ]
