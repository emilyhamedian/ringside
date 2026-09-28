#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

# Renders the README's pictures into docs/ from tests/qml/Pictures.qml:
# fixed sample readings, twice the size, in Breeze Dark with Plasma's default
# fonts whatever this desktop uses. Needs the Qt 6 qml tool, the Plasma QML
# modules and Python with Pillow, which joins the fold's frames into a GIF.
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
mkdir -p "$home/config" "$home/frames"
scheme=$(find /usr/share/color-schemes -name BreezeDark.colors | head -n 1)
[ -n "$scheme" ] || { echo "pictures.sh: Breeze Dark's colour scheme isn't installed" >&2; exit 1; }
cp "$scheme" "$home/config/kdeglobals"

log=$(XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" QT_FORCE_STDERR_LOGGING=1 \
    QT_QPA_PLATFORMTHEME=kde QT_QUICK_BACKEND=software QT_SCALE_FACTOR=2 \
    "$QML" -platform offscreen tests/qml/Pictures.qml -- --out "$home/frames" 2>&1)
if printf '%s\n' "$log" | grep -qE 'TypeError|ReferenceError|SyntaxError|Binding loop'; then
    printf '%s\n' "$log" >&2
    echo "pictures.sh: script errors while rendering (above)" >&2
    exit 1
fi

for name in panel popups usage standalone; do
    [ -s "$home/frames/$name.png" ] || { printf '%s\n' "$log" >&2; echo "pictures.sh: no $name.png" >&2; exit 1; }
    cp "$home/frames/$name.png" "$docs/$name.png"
done

# Open for a moment, fold, hold the tab, then unfold the same way back.
python3 - "$home/frames" "$docs/fold.gif" <<'EOF'
import sys
from PIL import Image

frames_dir, out = sys.argv[1], sys.argv[2]
fold = [Image.open(f"{frames_dir}/fold-{i}.png").convert("RGB") for i in range(10)]
sequence = fold + fold[-2:0:-1]
durations = [1200] + [40] * 8 + [1200] + [40] * 8
palette = fold[0].quantize(colors=255, method=Image.Quantize.MEDIANCUT)
frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in sequence]
frames[0].save(out, save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True)
EOF
ls -l "$docs"/panel.png "$docs"/popups.png "$docs"/usage.png "$docs"/standalone.png "$docs"/fold.gif
