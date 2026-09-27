#!/bin/sh
set -eu

# Install the widget for the current user, or upgrade it in place.
# Plasma keeps running the old version until plasmashell restarts.

cd "$(dirname "$0")/.."

id=$(sed -n 's/.*"Id": *"\([^"]*\)".*/\1/p' package/metadata.json)

if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$id"; then
    kpackagetool6 --type Plasma/Applet --upgrade package
else
    kpackagetool6 --type Plasma/Applet --install package
fi
