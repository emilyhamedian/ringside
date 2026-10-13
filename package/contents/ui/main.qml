// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import "code/buttons.js" as Buttons
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
    readonly property var items: readings.enabledItems.filter(k => k === "gpu" ? readings.gpuOuter.present
                                                               : k === "claude" ? readings.usage.claudePresent
                                                               : k === "codex" ? readings.usage.codexPresent
                                                               : true)

    // Where the items sit when the applet takes the panel's free space, as
    // a panel spacer beside it would: 0, 1 or 2 for the panel's start,
    // middle or end, and -1 when it takes only the items' room.
    readonly property int fillPlace: ["start", "center", "end"].indexOf(Plasmoid.configuration.fillPanel)
    readonly property bool fills: fillPlace >= 0 && (Plasmoid.formFactor === PlasmaCore.Types.Horizontal || vertical)
    // A right-to-left horizontal panel starts at the right. A test seam.
    property bool mirrored: Application.layoutDirection === Qt.RightToLeft
    // How far along the applet the items sit, from 0 at the start to 1 at the end.
    readonly property real lead: !fills ? 0.5 : (mirrored && !vertical ? 2 - fillPlace : fillPlace) / 2
    // How far the items move from the applet's middle to their place; their
    // size is the applet's minimum.
    readonly property real shift: Math.round((vertical ? height - Layout.minimumHeight : width - Layout.minimumWidth)
                                             * (lead - 0.5))

    // The height an open popup's page has: the screen's, less its panels,
    // the popup's frame and its gap from the screen's edges. Unknown, as in
    // plasmawindowed, it has no limit.
    readonly property real popupRoom: {
        const screen = Plasmoid.containment?.availableScreenRect.height ?? 0;
        return screen > 0 ? screen - popup.topPadding - popup.bottomPadding - 2 * popup.margin : Infinity;
    }

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
                               Items.isUsage(item) ? { monitor: readings, room: popupRoom, item: item }
                                                   : { monitor: readings, room: popupRoom });
        popup.visible = true;
    }

    function openSystemMonitor() {
        popup.visible = false;
        launcher.connectSource("kstart --application org.kde.plasma-systemmonitor");
    }

    preferredRepresentation: fullRepresentation
    // Keys a focused item in the strip leaves go to the hidden animation,
    // which only looks at them.
    Keys.onPressed: event => eggClock.watch(event)

    // With every item hidden the applet keeps a square the panel's
    // thickness, for the icon below. Filling, it grows along the panel from
    // there; the panel then gives it the room it would leave at its end.
    Layout.minimumWidth: vertical ? 0 : items.length > 0 ? strip.implicitWidth : thickness
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: vertical || fills ? Infinity : Layout.minimumWidth
    Layout.minimumHeight: vertical ? (items.length > 0 ? strip.implicitHeight : thickness) : 0
    Layout.preferredHeight: Layout.minimumHeight
    Layout.maximumHeight: vertical && !fills ? Layout.minimumHeight : Infinity
    Layout.fillWidth: vertical || fills
    Layout.fillHeight: !vertical || fills

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action", "Open System Monitor…")
            icon.name: "utilities-system-monitor"
            visible: readings.systemShown
            onTriggered: root.openSystemMonitor()
        }
    ]

    Monitor {
        id: readings
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

    // A click in the applet's room away from its items, as when it fills the
    // panel, closes an open popup. Plasma's panel takes no focus, so the
    // popup isn't deactivated and wouldn't close by itself. Right-clicks are
    // left to the panel's menu.
    MouseArea {
        anchors.fill: parent
        enabled: popup.visible
        acceptedButtons: Qt.LeftButton
        onClicked: popup.visible = false
    }

    // The strip and the icon, moved along the panel to the items' place.
    // This moves rather than they do: on Qt 6.6 a strip that moves lays
    // itself out again, which can change its size, a binding loop.
    Item {
        x: root.vertical ? 0 : root.shift
        y: root.vertical ? root.shift : 0
        width: parent.width
        height: parent.height

        Strip {
            id: strip
            anchors.centerIn: parent
            // Cells take the panel's full thickness, so their hover and pressed
            // backgrounds line up with the rest of the panel.
            width: root.vertical ? parent.width : implicitWidth
            height: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? parent.height : implicitHeight
            visible: root.items.length > 0
            monitor: readings
            items: root.items
            vertical: root.vertical
            thickness: root.thickness
            ringsOnly: Plasmoid.configuration.ringsOnly
            location: Plasmoid.location
            openItem: popup.visible ? root.openItem : ""
            egg: eggClock
            onActivated: (item, cell) => root.toggle(item, cell)
        }

        // With every item hidden, something still has to be there to right-click.
        // A filling applet keeps it a square where the items would be.
        Kirigami.Icon {
            anchors.centerIn: parent
            width: root.fills && !root.vertical ? parent.height : parent.width
            height: root.fills && root.vertical ? parent.width : parent.height
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
                    if (Buttons.pressedBy(event)) {
                        Plasmoid.internalAction("configure").trigger();
                        event.accepted = true;
                    }
                }
            }
        }
    }

    Egg {
        id: eggClock
        stage: strip
        vertical: root.vertical
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
            // As the applet's own, for any popup.
            Keys.onPressed: event => eggClock.watch(event)
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
