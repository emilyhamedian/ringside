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

for name in panel popups-black popups-white usage; do
    [ -s "$home/shots/$name.png" ] || { printf '%s\n' "$log" >&2; echo "pictures.sh: no $name.png" >&2; exit 1; }
done
cp "$home/shots/panel.png" "$home/shots/usage.png" "$docs/"
# The popups were shot over black and over white: how far white shows
# through is each pixel's transparency, and the black shot divided by its
# opacity its colour, so the shadows stay soft on any page.
python3 -I - "$home/shots" "$docs/popups.png" <<'PY'
import sys
from PIL import Image, ImageChops
shots, out = sys.argv[1], sys.argv[2]
black = Image.open(f"{shots}/popups-black.png").convert("RGB")
white = Image.open(f"{shots}/popups-white.png").convert("RGB")
alpha = ImageChops.invert(ImageChops.subtract(white, black).convert("L"))
Image.merge("RGBa", (*black.split(), alpha)).convert("RGBA").save(out, optimize=True)
PY

ls -l "$docs"/panel.png "$docs"/popups.png "$docs"/usage.png
