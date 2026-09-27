pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

// The items sit straight in the panel (there is no full representation to
// expand), and each opens its own popup under it. One AppletPopup serves them
// all, moved to whichever item was clicked.
PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real thickness: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height
                                    : vertical ? width : Kirigami.Units.gridUnit * 2.5
    readonly property var knownItems: ["cpu", "gpu", "memory", "network", "disk"]
    readonly property var items: {
        const config = Plasmoid.configuration;
        const order = config.itemOrder.filter(k => knownItems.includes(k));
        knownItems.forEach(k => { if (!order.includes(k)) order.push(k); });
        return order.filter(k => !config.hiddenItems.includes(k) && (k !== "gpu" || monitor.gpuOuter.present));
    }

    // The clicked item's name and cell; the popup follows the cell.
    property string openItem: ""
    property Item openCell: null

    function toggle(item, cell) {
        if (popup.visible && openItem === item) {
            popup.visible = false;
            return;
        }
        openItem = item;
        openCell = cell;
        popupContent.setSource(Qt.resolvedUrl("popups/" + ({ cpu: "CpuPopup", gpu: "GpuPopup", memory: "MemoryPopup",
                                                             network: "NetworkPopup", disk: "NetworkPopup" })[item] + ".qml"),
                               { monitor: monitor });
        popup.visible = true;
    }

    function openSystemMonitor() {
        popup.visible = false;
        launcher.connectSource("kstart --application org.kde.plasma-systemmonitor");
    }

    preferredRepresentation: fullRepresentation
    toolTipMainText: ""
    toolTipSubText: ""

    Layout.minimumWidth: vertical ? 0 : strip.implicitWidth
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: vertical ? Infinity : Layout.minimumWidth
    Layout.minimumHeight: vertical ? strip.implicitHeight : 0
    Layout.preferredHeight: Layout.minimumHeight
    Layout.maximumHeight: vertical ? Layout.minimumHeight : Infinity
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action", "Open System Monitor…")
            icon.name: "utilities-system-monitor"
            onTriggered: root.openSystemMonitor()
        }
    ]

    Monitor {
        id: monitor
        config: Plasmoid.configuration
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
        visible: root.items.length > 0
        monitor: monitor
        items: root.items
        vertical: root.vertical
        thickness: root.thickness
        ringSize: Plasmoid.configuration.ringSize
        ringsOnly: Plasmoid.configuration.ringsOnly
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
            onClicked: Plasmoid.internalAction("configure").trigger()
        }
    }

    PlasmaCore.AppletPopup {
        id: popup

        property int savedStatus: PlasmaCore.Types.PassiveStatus

        visualParent: root.openCell
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

            Layout.preferredWidth: item ? item.implicitWidth : 0
            Layout.preferredHeight: item ? item.implicitHeight : 0
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
