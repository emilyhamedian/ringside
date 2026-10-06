#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

# Renders the README's pictures into docs/ from tests/qml/Pictures.qml:
# fixed sample readings, twice the size, in Breeze Dark with Plasma's default
# fonts whatever this desktop uses. Needs the Qt 6 qml tool and the Plasma
# QML modules.
#
# Usage: sh scripts/pictures.sh

cd "$(dirname "$0")/.." || exit 1
docs=$PWD/docs

if [ -z "${QML:-}" ]; then
    for QML in /usr/lib/qt6/bin/qml /usr/lib64/qt6/bin/qml qml6; do
        command -v "$QML" >/dev/null 2>&1 && break
    done
fi

# A settings folder of its own, so the user's colours and fonts stay out.
home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
mkdir -p "$home/config" "$home/shots"
scheme=$(find /usr/share/color-schemes -name BreezeDark.colors | head -n 1)
[ -n "$scheme" ] || { echo "pictures.sh: Breeze Dark's colour scheme isn't installed" >&2; exit 1; }
cp "$scheme" "$home/config/kdeglobals"

# The status is kept rather than tested by set -e, so a failed load still
# prints its log.
rc=0
log=$(XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" QT_FORCE_STDERR_LOGGING=1 \
    QT_QPA_PLATFORMTHEME=kde QT_QUICK_BACKEND=software QT_SCALE_FACTOR=2 \
    "$QML" -platform offscreen tests/qml/Pictures.qml -- --out "$home/shots" 2>&1) || rc=$?
if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$log" >&2
    echo "pictures.sh: $QML exited with status $rc" >&2
    exit 1
fi
if printf '%s\n' "$log" | grep -qE 'TypeError|ReferenceError|SyntaxError|Binding loop'; then
    printf '%s\n' "$log" >&2
    echo "pictures.sh: script errors while rendering (above)" >&2
    exit 1
fi

for name in panel popups usage; do
    [ -s "$home/shots/$name.png" ] || { printf '%s\n' "$log" >&2; echo "pictures.sh: no $name.png" >&2; exit 1; }
    cp "$home/shots/$name.png" "$docs/$name.png"
done

ls -l "$docs"/panel.png "$docs"/popups.png "$docs"/usage.png
