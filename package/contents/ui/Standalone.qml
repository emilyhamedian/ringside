// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

// The Standalone layout in the applet: large dials that fold into a tab
// behind maximized windows, or when asked. In a panel that holds only
// Ringside it also sets the panel's thickness, folding it to the tab and
// remembering how thick the user made it.
Item {
    id: standalone

    required property var monitor
    required property var items
    required property var enabledItems
    property string openItem: ""
    // Folded or folding; the popup has nowhere to stay.
    readonly property bool collapsed: strip.collapsed
    signal activated(string item, Item cell)

    // For the PlasmoidItem's Layout.minimum/preferred sizes. The tab needs
    // 28 px across; along the strip, whatever the dials take.
    readonly property real layoutMinimumWidth: strip.vertical ? (strip.compactLayout ? 28 : strip.minimumThickness)
                                                              : strip.implicitWidth
    readonly property real layoutMinimumHeight: strip.vertical ? strip.implicitHeight
                                                               : (strip.compactLayout ? 28 : strip.minimumThickness)
    readonly property bool layoutFillWidth: strip.vertical || strip.compactLayout
    readonly property bool layoutFillHeight: !strip.vertical || strip.compactLayout

    function cellAt(index) {
        return strip.cellAt(index);
    }

    // Thickness the panel adds around the applet: the theme's margins on both
    // sides. Measured with the dials open and at rest, since Plasma applies
    // the panel's thickness at once while the applet follows.
    property real panelChrome: 8
    function samplePanelChrome() {
        if (panelSizing.managesPanel && !strip.collapsed && strip.expansionProgress === 1
                && strip.geometryReady && strip.contentThickness > 0) {
            const chrome = panelSizing.panelWindow.thickness - strip.contentThickness;
            if (chrome >= 0) {
                panelChrome = chrome;
            }
        }
    }

    WindowWatch {
        id: watch
        active: Plasmoid.configuration.visibilityMode === 0
    }

    PanelSizeController {
        id: panelSizing
        panelWindow: standalone.Window.window
        // The list of applets has no QML type for the linter to check.
        dedicated: Plasmoid.containment?.applets.length === 1 // qmllint disable unresolved-type
        collapsed: strip.compactLayout
        chrome: standalone.panelChrome
        minimumContentThickness: strip.minimumThickness
        expandedThickness: Plasmoid.configuration.panelThickness
        onRememberThickness: thickness => { Plasmoid.configuration.panelThickness = thickness; }
    }

    StandaloneStrip {
        id: strip
        anchors.fill: parent
        monitor: standalone.monitor
        items: standalone.items
        enabledItems: standalone.enabledItems
        openItem: standalone.openItem
        expandedThickness: panelSizing.managesPanel
                           ? Math.max(panelSizing.expandedThickness, minimumThickness + standalone.panelChrome)
                             - standalone.panelChrome
                           : contentThickness
        compactThickness: panelSizing.managesPanel ? panelSizing.tabThickness - standalone.panelChrome : contentThickness
        editing: panelSizing.managesPanel && panelSizing.configuring
        vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        location: Plasmoid.location
        covered: watch.covered
        visibilityMode: Plasmoid.configuration.visibilityMode
        onVisibilityModeRequested: mode => { Plasmoid.configuration.visibilityMode = mode; }
        onActivated: (item, cell) => standalone.activated(item, cell)
        onContentThicknessChanged: standalone.samplePanelChrome()
        onExpansionProgressChanged: standalone.samplePanelChrome()
    }
}
