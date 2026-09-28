#!/bin/sh
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

# Adds a floating panel on the right screen edge holding only Ringside, in
# the Standalone layout with Claude and Codex switched on and the system
# items off. Install Ringside first (sh scripts/install.sh). Remove the panel
# later from panel edit mode like any other panel.
#
# Usage: sh scripts/add-panel.sh

script=$(cat <<'JS'
if (knownWidgetTypes.indexOf("dev.emily.ringside") < 0) {
    throw new Error("Ringside is not installed; run sh scripts/install.sh first.");
}
const panel = new Panel();
panel.location = "right";
panel.alignment = "center";
panel.lengthMode = "fit";
panel.floating = true;
// Stay on top of windows without reserving space: maximized windows extend
// underneath, which is when Ringside folds to its tab.
panel.hiding = "windowsgobelow";
// Ignored before Plasma 6.7.5; pick Translucent in panel edit mode there.
panel.opacity = "translucent";
// The dials plus the theme's margins; Ringside grows this if it needs more.
panel.height = 68;
const ringside = panel.addWidget("dev.emily.ringside");
ringside.currentConfigGroup = ["Panel"];
ringside.writeConfig("layout", 1);
// Claude and Codex are on only when the order lists them.
ringside.writeConfig("itemOrder", ["claude", "codex", "cpu", "gpu", "memory", "network", "disk"]);
ringside.writeConfig("hiddenItems", ["cpu", "gpu", "memory", "network", "disk"]);
ringside.reloadConfig();
JS
)

# dbus-send has the same name on every distribution; qdbus does not.
dbus-send --session --print-reply --dest=org.kde.plasmashell /PlasmaShell \
    org.kde.PlasmaShell.evaluateScript string:"$script" >/dev/null
