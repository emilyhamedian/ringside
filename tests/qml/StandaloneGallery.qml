// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.plasma.core as PlasmaCore
import "../../package/contents/ui"
import "../../package/contents/ui/code/style.js" as Style

// A section of Gallery.qml: the Standalone layout open on a right and a
// bottom panel at two scales, alarmed, empty and with every reading at its
// widest, squeezed into a thin panel it shares with other widgets, and
// folding into its tab. Each strip sits on the theme's panel background with
// Breeze's 4 px either side; the outline marks the panel's extent where the
// background matches the window.
ColumnLayout {
    id: section

    required property var monitor
    readonly property var items: ["cpu", "gpu", "memory", "network", "claude", "codex"]
    readonly property int margin: 4

    spacing: 2 * Kirigami.Units.gridUnit

    // Level colours and dimming: a hot, busy CPU, the discrete GPU asleep,
    // Claude near its limit, and Codex after a failed poll.
    FakeMonitor {
        id: alarmed
        cpuUsage: 81
        cpuTemperature: 92
        gpuOuter.phase: "asleep"
        usage.entries: ({
            claude: { status: "ok", weekly: alarmed.usage.window(93, 4 * 3600 + 12 * 60, []),
                      scoped: [Object.assign({ id: "Opus", label: "Opus" },
                                             alarmed.usage.window(78, 4 * 3600 + 12 * 60, []))] },
            codex: { status: "ok", weekly: alarmed.usage.window(34, 5 * alarmed.usage.day + 4 * 3600, []), scoped: [],
                     lastError: "rate limited", lastErrorAt: 0 }
        })
    }

    // Each line at the widest it gets, to fill the room the strip keeps:
    // every byte of memory in use, and Claude spent with a day to go. The
    // only GPU is asleep.
    FakeMonitor {
        id: widest
        cpuUsage: 100
        cpuTemperature: 148
        memoryTotal: 1023 * 1048576
        memoryUsed: 1023 * 1048576
        gpuOuter.phase: "asleep"
        gpuInner.present: false
        usage.entries: ({
            claude: { status: "ok", weekly: widest.usage.window(100, 23 * 3600 + 59 * 60, []), scoped: [] }
        })
    }

    // A machine whose only GPU is Intel's, which publishes no temperature.
    FakeMonitor {
        id: intelOnly
        cpuModel: "Intel Core i7-1360P"
        gpuOuter.kind: "integrated"
        gpuOuter.name: "Intel Iris Xe Graphics"
        gpuOuter.temperatureLabel: ""
        gpuOuter.reportsTemperature: false
        gpuOuter.reportsVram: false
        gpuOuter.temperature: NaN
        gpuOuter.vramUsed: NaN
        gpuOuter.vramTotal: NaN
        gpuOuter.knownVramTotal: NaN
        gpuOuter.power: NaN
        gpuInner.present: false
    }

    // A machine whose only GPU is asleep.
    FakeMonitor {
        id: sleeping
        gpuOuter.phase: "asleep"
        gpuInner.present: false
    }

    component Outline: Rectangle {
        color: "transparent"
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
    }

    component Note: Text {
        color: Style.dim(Kirigami.Theme.textColor)
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        textFormat: Text.PlainText
    }

    // The strip open in a panel as thick as it asks for at `sizeFactor`, or as
    // `thickness` when that is set, as in a panel shared with other widgets.
    component OpenPanel: ColumnLayout {
        id: open

        required property string label
        required property int location
        property var items: section.items
        property var enabledItems: items
        property var monitor: section.monitor
        property string openItem: ""
        property real sizeFactor: 1
        property real thickness: strip.minimumThickness * sizeFactor + 2 * section.margin
        readonly property bool vertical: location === PlasmaCore.Types.LeftEdge || location === PlasmaCore.Types.RightEdge

        Layout.alignment: Qt.AlignTop
        spacing: Kirigami.Units.smallSpacing

        Note {
            text: open.label
        }

        KSvg.FrameSvgItem {
            imagePath: "widgets/panel-background"
            Layout.preferredWidth: open.vertical ? open.thickness : strip.implicitWidth + 2 * section.margin
            Layout.preferredHeight: open.vertical ? strip.implicitHeight + 2 * section.margin : open.thickness

            StandaloneStrip {
                id: strip
                x: section.margin
                y: section.margin
                width: open.vertical ? open.thickness - 2 * section.margin : implicitWidth
                height: open.vertical ? implicitHeight : open.thickness - 2 * section.margin
                monitor: open.monitor
                items: open.items
                enabledItems: open.enabledItems
                vertical: open.vertical
                location: open.location
                openItem: open.openItem
                visibilityMode: 1
            }

            Outline {
                anchors.fill: parent
            }
        }
    }

    // A point in the fold: the panel keeps its thickness while the dials
    // shrink toward the tab, then snaps to the 44 px tab once they are gone.
    component FoldStage: ColumnLayout {
        id: stage

        required property real progress
        property int location: PlasmaCore.Types.RightEdge
        property var items: ["cpu", "claude", "codex"]
        readonly property bool vertical: location === PlasmaCore.Types.LeftEdge || location === PlasmaCore.Types.RightEdge
        readonly property real thickness: progress === 0 ? 44 : strip.minimumThickness + 2 * section.margin

        Layout.alignment: Qt.AlignTop
        spacing: Kirigami.Units.smallSpacing

        Note {
            text: stage.progress === 1 ? "Open, chevron shown"
                : stage.progress === 0 ? "Folded tab"
                : Math.round((1 - stage.progress) * 100) + "% folded"
        }

        KSvg.FrameSvgItem {
            imagePath: "widgets/panel-background"
            Layout.preferredWidth: stage.vertical ? stage.thickness : strip.implicitWidth + 2 * section.margin
            Layout.preferredHeight: stage.vertical ? strip.implicitHeight + 2 * section.margin : stage.thickness

            StandaloneStrip {
                id: strip
                anchors.fill: parent
                anchors.margins: section.margin
                monitor: section.monitor
                items: stage.items
                enabledItems: stage.items
                vertical: stage.vertical
                location: stage.location
                expandedThickness: minimumThickness
                visibilityMode: stage.progress === 0 ? 2 : 1
                expansionProgress: stage.progress
                handleProgress: 1
            }

            Outline {
                anchors.fill: parent
            }
        }
    }

    Note {
        text: "Standalone: large dials in a panel of their own"
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        OpenPanel {
            label: "Right · Claude's popup open"
            location: PlasmaCore.Types.RightEdge
            openItem: "claude"
        }

        OpenPanel {
            label: "Right · alarmed"
            location: PlasmaCore.Types.RightEdge
            monitor: alarmed
            items: ["cpu", "gpu", "claude", "codex"]
        }

        OpenPanel {
            label: "Right · widest readings"
            location: PlasmaCore.Types.RightEdge
            monitor: widest
            items: ["cpu", "gpu", "memory", "claude"]
        }

        OpenPanel {
            label: "Right · scale 2"
            location: PlasmaCore.Types.RightEdge
            items: ["gpu", "network", "claude"]
            sizeFactor: 2
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            spacing: 2 * Kirigami.Units.gridUnit

            OpenPanel {
                label: "Right · signed out"
                location: PlasmaCore.Types.RightEdge
                items: []
                enabledItems: ["claude", "codex"]
            }

            OpenPanel {
                label: "Right · the only GPU asleep"
                location: PlasmaCore.Types.RightEdge
                monitor: sleeping
                items: ["gpu"]
            }

            OpenPanel {
                label: "Right · Intel's GPU alone"
                location: PlasmaCore.Types.RightEdge
                monitor: intelOnly
                items: ["cpu", "gpu"]
            }
        }

        Repeater {
            model: [1, 0.65, 0.3, 0]
            delegate: FoldStage {
                required property real modelData
                progress: modelData
            }
        }
    }

    OpenPanel {
        label: "Bottom · scale 1"
        location: PlasmaCore.Types.BottomEdge
        items: ["cpu", "gpu", "memory", "network", "disk", "claude", "codex"]
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        OpenPanel {
            label: "Bottom · scale 2"
            location: PlasmaCore.Types.BottomEdge
            items: ["memory", "disk", "codex"]
            sizeFactor: 2
        }

        OpenPanel {
            label: "Bottom · widest readings"
            location: PlasmaCore.Types.BottomEdge
            monitor: widest
            items: ["cpu", "gpu", "memory", "claude"]
        }

        OpenPanel {
            label: "Bottom · 46 px panel shared with other widgets"
            location: PlasmaCore.Types.BottomEdge
            items: ["cpu", "memory", "claude"]
            thickness: 46
        }

        FoldStage {
            progress: 0
            location: PlasmaCore.Types.BottomEdge
        }
    }
}
