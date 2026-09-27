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

rm -f "$out"
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORMTHEME=kde QT_QUICK_BACKEND=software \
    "${QML:-/usr/lib/qt6/bin/qml}" -platform offscreen tests/qml/Gallery.qml -- --snapshot "$out"
[ -s "$out" ] || { echo "gallery.sh: no image written to $out" >&2; exit 1; }
echo "$out"
