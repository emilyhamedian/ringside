#!/bin/sh
# Like fake-info.sh, but runtime_status can't be read: the helper prints an
# empty field, "BDF  auto".
if [ "${1:-}" = pm ]; then
    shift
    for bdf in "$@"; do
        printf '%s  auto\n' "$bdf"
    done
    exit 0
fi
exec sh "$(dirname "$0")/fake-info.sh" "$@"
