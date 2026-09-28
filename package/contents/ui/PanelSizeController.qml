// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

// Folds a panel that holds only Ringside down to the tab and back, and
// remembers how thick the user made it. Plasma's panel window exposes its
// thickness in logical pixels; an ordinary window has none, and a panel
// shared with other widgets is never touched.
Item {
    id: controller

    // The folded panel's thickness: the tab plus the theme's margins.
    readonly property int tabThickness: 44
    property var panelWindow: null
    property bool dedicated: false
    property bool collapsed: false
    // Panel thickness beyond the applet's content: the theme's margins on
    // both sides, measured by the host rather than assumed.
    property real chrome: 8
    property real minimumContentThickness: 80
    property int expandedThickness: 0
    property bool adjusting: false
    property var controlledWindow: null
    readonly property bool managesPanel: dedicated && panelWindow !== null
                                        && typeof panelWindow.thickness === "number"
    // Edit mode; Plasma 6.0's panel window doesn't publish it.
    readonly property bool configuring: panelWindow?.userConfiguring ?? false
    signal rememberThickness(int thickness)

    visible: false

    function releasePanel() {
        if (controlledWindow && expandedThickness > 0) {
            adjusting = true;
            controlledWindow.thickness = Math.max(controlledWindow.thickness, expandedThickness);
            adjusting = false;
        }
        controlledWindow = null;
    }

    function sync() {
        if (!managesPanel || configuring) {
            return;
        }
        // Remember the user's open thickness, never the tab's, across shell
        // restarts.
        const minimum = Math.ceil(minimumContentThickness + chrome);
        const expanded = Math.max(expandedThickness || panelWindow.thickness, minimum);
        if (expandedThickness !== expanded) {
            rememberThickness(expanded);
        }
        controlledWindow = panelWindow;
        adjusting = true;
        panelWindow.thickness = collapsed ? tabThickness : expanded;
        adjusting = false;
    }

    // Applied at once, in the same event as the layout flags that change the
    // panel's length, so Plasma resizes its window once rather than twice.
    onCollapsedChanged: sync()
    onChromeChanged: Qt.callLater(sync)
    onExpandedThicknessChanged: Qt.callLater(sync)
    onPanelWindowChanged: {
        if (controlledWindow !== panelWindow) {
            releasePanel();
        }
        Qt.callLater(sync);
    }
    onMinimumContentThicknessChanged: Qt.callLater(sync)
    onDedicatedChanged: {
        if (!dedicated) {
            releasePanel();
        }
        Qt.callLater(sync);
    }
    Component.onCompleted: Qt.callLater(sync)
    Component.onDestruction: releasePanel()

    Connections {
        target: controller.managesPanel ? controller.panelWindow : null
        // userConfiguringChanged arrived with Plasma 6.1.
        ignoreUnknownSignals: true

        function onThicknessChanged() {
            if (!controller.adjusting && (!controller.collapsed || controller.configuring)) {
                controller.rememberThickness(Math.round(controller.panelWindow.thickness));
            }
        }

        // Edit mode shows the panel at its open thickness, so the user
        // resizes the real size.
        function onUserConfiguringChanged() {
            if (controller.panelWindow.userConfiguring && controller.expandedThickness > 0) {
                controller.adjusting = true;
                controller.panelWindow.thickness = controller.expandedThickness;
                controller.adjusting = false;
            }
            Qt.callLater(controller.sync);
        }
    }
}
