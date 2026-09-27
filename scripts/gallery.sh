#!/bin/sh
set -eu

# Renders tests/qml/Gallery.qml, the panel strip and every popup with fixed
# readings, to a PNG. Needs the Qt 6 qml tool and the Plasma QML modules, so
# run it on the Plasma host. QT_SCALE_FACTOR=2 renders at twice the size.
#
# Usage: sh scripts/gallery.sh [out.png]    (default /tmp/ringside-gallery.png)

out=${1:-/tmp/ringside-gallery.png}
case $out in
    /*) ;;
    *) out=$PWD/$out ;;
esac

cd "$(dirname "$0")/.."

# Arch and Debian keep the Qt 6 tools in /usr/lib/qt6/bin, Fedora and openSUSE
# in /usr/lib64/qt6/bin; the bare qml on PATH may be Qt 5.
if [ -z "${QML:-}" ]; then
    for QML in /usr/lib/qt6/bin/qml /usr/lib64/qt6/bin/qml qml6; do
        command -v "$QML" >/dev/null 2>&1 && break
    done
fi

rm -f "$out"
log=$(QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORMTHEME=kde QT_QUICK_BACKEND=software \
    "$QML" -platform offscreen tests/qml/Gallery.qml -- --snapshot "$out" 2>&1)
printf '%s\n' "$log" >&2
[ -s "$out" ] || { echo "gallery.sh: no image written to $out" >&2; exit 1; }
# A script error still leaves an image, with a part missing.
if printf '%s\n' "$log" | grep -qE 'TypeError|ReferenceError|SyntaxError|Binding loop'; then
    echo "gallery.sh: script errors while rendering (above)" >&2
    exit 1
fi
echo "$out"
