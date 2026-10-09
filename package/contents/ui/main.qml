// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import "code/items.js" as Items

// The items sit straight in the panel (there is no full representation to
// expand), and each opens its own popup. One AppletPopup serves them all,
// moved to whichever item was clicked.
PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real thickness: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height
                                    : vertical ? width : Kirigami.Units.gridUnit * 2.5
    // The items switched on that have something to show: a GPU, a signed-in CLI.
    readonly property var items: monitor.enabledItems.filter(k => k === "gpu" ? monitor.gpuOuter.present
                                                               : k === "claude" ? monitor.usage.claudePresent
                                                               : k === "codex" ? monitor.usage.codexPresent
                                                               : true)

    // The clicked item's name and cell; the popup follows the cell.
    property string openItem: ""
    // Cleared when the cell goes away, say when its item is switched off,
    // and the popup goes with it.
    property Item openCell: null
    onOpenCellChanged: if (!openCell && popup.visible) Qt.callLater(reattach)

    // A cell goes only when its item does; other items coming and going
    // leave it be (see Strip). The popup closes with it, or moves to the
    // item's new cell should the item be back by then.
    function reattach() {
        if (openCell || !popup.visible) {
            return;
        }
        const index = items.indexOf(openItem);
        const cell = index >= 0 ? strip.cellAt(index) : null;
        if (cell) {
            openCell = cell;
        } else {
            popup.visible = false;
        }
    }

    function toggle(item, cell) {
        if (popup.visible && openItem === item) {
            popup.visible = false;
            return;
        }
        openItem = item;
        openCell = cell;
        popupContent.setSource(Qt.resolvedUrl("popups/" + ({ cpu: "CpuPopup", gpu: "GpuPopup", memory: "MemoryPopup",
                                                             network: "NetworkPopup", disk: "DiskPopup",
                                                             claude: "UsagePopup", codex: "UsagePopup" })[item] + ".qml"),
                               Items.isUsage(item) ? { monitor: monitor, item: item } : { monitor: monitor });
        popup.visible = true;
    }

    function openSystemMonitor() {
        popup.visible = false;
        launcher.connectSource("kstart --application org.kde.plasma-systemmonitor");
    }

    preferredRepresentation: fullRepresentation

    // With every item hidden the applet keeps a square the panel's
    // thickness, for the icon below.
    Layout.minimumWidth: vertical ? 0 : items.length > 0 ? strip.implicitWidth : thickness
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: vertical ? Infinity : Layout.minimumWidth
    Layout.minimumHeight: vertical ? (items.length > 0 ? strip.implicitHeight : thickness) : 0
    Layout.preferredHeight: Layout.minimumHeight
    Layout.maximumHeight: vertical ? Layout.minimumHeight : Infinity
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action", "Open System Monitor…")
            icon.name: "utilities-system-monitor"
            visible: monitor.systemShown
            onTriggered: root.openSystemMonitor()
        }
    ]

    Monitor {
        id: monitor
        config: Plasmoid.configuration
        // Keys the graphs' saved history to this widget.
        widgetId: String(Plasmoid.id)
        // KPluginMetaData's version, there since Plasma 6.0; qmllint has no
        // type information for KPluginMetaData.
        version: Plasmoid.metaData?.version ?? "" // qmllint disable unresolved-type
        openPopup: popup.visible ? root.openItem : ""
        onSystemMonitorRequested: root.openSystemMonitor()
        onConfigureRequested: {
            popup.visible = false;
            Plasmoid.internalAction("configure").trigger();
        }
    }

    Strip {
        id: strip
        anchors.centerIn: parent
        // Cells take the panel's full thickness, so their hover and pressed
        // backgrounds line up with the rest of the panel.
        width: root.vertical ? parent.width : implicitWidth
        height: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? parent.height : implicitHeight
        visible: root.items.length > 0
        monitor: monitor
        items: root.items
        vertical: root.vertical
        thickness: root.thickness
        ringsOnly: Plasmoid.configuration.ringsOnly
        location: Plasmoid.location
        openItem: popup.visible ? root.openItem : ""
        onActivated: (item, cell) => root.toggle(item, cell)
    }

    // With every item hidden, something still has to be there to right-click.
    Kirigami.Icon {
        anchors.fill: parent
        visible: root.items.length === 0
        source: Plasmoid.icon
        active: mouse.containsMouse
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            activeFocusOnTab: parent.visible
            Accessible.role: Accessible.Button
            Accessible.name: i18nc("@action:button", "Configure Ringside…")
            Accessible.onPressAction: Plasmoid.internalAction("configure").trigger()
            onClicked: Plasmoid.internalAction("configure").trigger()
            Keys.onPressed: event => {
                if ([Qt.Key_Space, Qt.Key_Enter, Qt.Key_Return, Qt.Key_Select].includes(event.key)) {
                    Plasmoid.internalAction("configure").trigger();
                    event.accepted = true;
                }
            }
        }
    }

    PlasmaCore.AppletPopup {
        id: popup

        property int savedStatus: PlasmaCore.Types.PassiveStatus

        // Plasma places the popup's window even while it is hidden, and warns
        // when there is no visual parent, so the applet stands in while the
        // popup is hidden. An open popup whose cell was just rebuilt keeps no
        // parent until reattach() finds the new cell, rather than jumping to
        // the applet.
        visualParent: root.openCell ?? (popup.visible ? null : root)
        hideOnWindowDeactivate: true
        popupDirection: switch (Plasmoid.location) {
            case PlasmaCore.Types.TopEdge: return Qt.BottomEdge;
            case PlasmaCore.Types.LeftEdge: return Qt.RightEdge;
            case PlasmaCore.Types.RightEdge: return Qt.LeftEdge;
            default: return Qt.TopEdge;
        }
        floating: Plasmoid.location === PlasmaCore.Types.Floating
        margin: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentPrefersFloatingApplets)
                ? Kirigami.Units.largeSpacing : 0
        removeBorderStrategy: Plasmoid.location === PlasmaCore.Types.Floating
                              ? PlasmaCore.AppletPopup.AtScreenEdges
                              : PlasmaCore.AppletPopup.AtScreenEdges | PlasmaCore.AppletPopup.AtPanelEdges
        backgroundHints: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentPrefersOpaqueBackground)
                         ? PlasmaCore.AppletPopup.SolidBackground : PlasmaCore.AppletPopup.StandardBackground
        // appletInterface stays unset: it would save one size for every popup.

        onVisibleChanged: {
            if (visible) {
                savedStatus = Plasmoid.status;
                // Keeps an auto-hiding panel shown while the popup is open.
                Plasmoid.status = PlasmaCore.Types.RequiresAttentionStatus;
                requestActivate();
            } else {
                Plasmoid.status = savedStatus;
                release.restart();
            }
        }

        mainItem: Loader {
            id: popupContent

            Layout.preferredWidth: item ? (item as Item).implicitWidth : 0
            Layout.preferredHeight: item ? (item as Item).implicitHeight : 0
            // As Plasma's own applet popups do for right-to-left languages.
            LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
            LayoutMirroring.childrenInherit: true
            focus: true
            Keys.onEscapePressed: popup.visible = false
        }
    }

    // Unloads the popup's contents, and the sensors and process list they
    // run, a moment after it closes.
    Timer {
        id: release
        interval: 100
        onTriggered: {
            if (!popup.visible) {
                popupContent.source = "";
                root.openCell = null;
            }
        }
    }

    P5Support.DataSource {
        id: launcher
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    Connections {
        target: Plasmoid

        function onActivated() {
            const cell = strip.cellAt(0);
            if (cell) {
                root.toggle(root.items[0], cell);
            }
        }

        function onUserConfiguringChanged() {
            if (Plasmoid.userConfiguring) {
                popup.visible = false;
            }
        }

        function onContextualActionsAboutToShow() {
            popup.visible = false;
        }
    }
}
