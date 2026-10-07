// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import "../../package/contents/ui"
import "../../package/contents/ui/popups"
import "../../package/contents/ui/code/style.js" as Style

// The panel strip and the four popups with FakeMonitor's readings, then the
// states they have to cope with, then the same under Breeze Light. The
// top-process lists show FakeMonitor's processSample; only the CPU popup's
// frequency, load average and per-thread bars read this machine.
// scripts/gallery.sh renders it to a PNG; qml tests/qml/Gallery.qml shows it
// in a window, and adding -- --snapshot out.png saves a PNG and quits.
Rectangle {
    id: gallery

    readonly property string snapshotPath: Qt.application.arguments.indexOf("--snapshot") >= 0
        ? Qt.application.arguments[Qt.application.arguments.indexOf("--snapshot") + 1] : ""

    // A bare qml runtime has no KI18n; the views find these on the root.
    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (match, n) => n <= args.length ? String(args[n - 1]) : match);
    }
    function i18n(text, ...args) {
        return substitute(text, args);
    }
    function i18nc(context, text, ...args) {
        return substitute(text, args);
    }
    function i18np(singular, plural, n, ...args) {
        return substitute(n === 1 ? singular : plural, [n].concat(args));
    }
    function i18ncp(context, singular, plural, n, ...args) {
        return substitute(n === 1 ? singular : plural, [n].concat(args));
    }

    width: layout.implicitWidth + 2 * layout.x
    height: layout.implicitHeight + 2 * layout.y
    color: Kirigami.Theme.backgroundColor
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    FakeMonitor {
        id: normal
    }

    // Hot, with its top processes still being read.
    FakeMonitor {
        id: hot
        cpuTemperature: 92
        processSample: []
    }

    FakeMonitor {
        id: asleep
        gpuOuter.phase: "asleep"
    }

    FakeMonitor {
        id: integrated
        gpuOuter.kind: "integrated"
        gpuOuter.name: "AMD Radeon 780M Graphics"
        gpuOuter.usage: 18
        gpuOuter.temperature: 52
        gpuOuter.vramUsed: 0.4 * integrated.gib
        gpuOuter.vramTotal: 0.5 * integrated.gib
        gpuOuter.clock: 1200
        gpuOuter.power: NaN
        gpuOuter.history: integrated.wave(18, 12, 9)
        gpuInner.present: false
    }

    FakeMonitor {
        id: bare
        memoryPressure: NaN
        swapUsed: 0
        swapTotal: 0
        swapLabel: ""
    }

    // The discrete GPU picked for the inner ring, asleep.
    FakeMonitor {
        id: innerAsleep
        gpuOuter.kind: "integrated"
        gpuOuter.name: "AMD Radeon 780M Graphics"
        gpuOuter.usage: 18
        gpuOuter.temperature: 52
        gpuOuter.vramUsed: 0.4 * innerAsleep.gib
        gpuOuter.vramTotal: 0.5 * innerAsleep.gib
        gpuOuter.knownVramTotal: 0.5 * innerAsleep.gib
        gpuOuter.clock: 1200
        gpuOuter.power: NaN
        gpuInner.kind: "discrete"
        gpuInner.name: "AMD Radeon RX 7700S"
        gpuInner.phase: "asleep"
        gpuInner.knownVramTotal: 8 * innerAsleep.gib
    }

    // A hybrid laptop: Intel publishes no GPU temperature.
    FakeMonitor {
        id: intel
        cpuModel: "Intel Core i7-12700H"
        cpuTemperature: 78
        gpuOuter.name: "NVIDIA GeForce RTX 3060 Laptop GPU"
        gpuOuter.temperatureLabel: ""
        gpuOuter.usage: 64
        gpuOuter.temperature: 71
        gpuOuter.vramUsed: 2.2 * intel.gib
        gpuOuter.vramTotal: 6 * intel.gib
        gpuOuter.knownVramTotal: 6 * intel.gib
        gpuOuter.clock: 1650
        gpuOuter.power: 62
        gpuInner.name: "Intel Iris Xe Graphics"
        gpuInner.temperatureLabel: ""
        gpuInner.reportsTemperature: false
        gpuInner.reportsVram: false
        gpuInner.temperature: NaN
        gpuInner.vramUsed: NaN
        gpuInner.vramTotal: NaN
        gpuInner.knownVramTotal: NaN
        gpuInner.clock: 1100
    }

    // Every ring past a threshold: hot, warm, full, nearly out.
    FakeMonitor {
        id: alert
        cpuUsage: 95
        cpuTemperature: 92
        memoryUsed: 29.4 * alert.gib
        gpuOuter.usage: 77
        gpuOuter.temperature: 78
        usage.entries: ({
            claude: { status: "ok", weekly: alert.usage.window(95, 4 * 3600 + 12 * 60, []) },
            codex: { status: "ok", weekly: alert.usage.window(81, 5 * alert.usage.day, []) }
        })
    }

    // Claude's last day, which it lasts at this pace.
    FakeMonitor {
        id: lastDay
        usage.entries: ({
            claude: { status: "ok", weekly: lastDay.usage.window(70, 23 * 3600 + 5 * 60, []), scoped: [] }
        })
    }

    // A drive that reports no temperature, warm or hot ones, and every disk.
    FakeMonitor {
        id: diskUnheated
        diskTemperature: NaN
    }

    FakeMonitor {
        id: diskHot
        diskTemperature: 78
        diskDevice: "all"
    }

    // The only GPU, asleep.
    FakeMonitor {
        id: onlyAsleep
        gpuOuter.phase: "asleep"
        gpuInner.present: false
    }

    // The Memory popup with every string about a third longer, as German and
    // the Romance languages often run. Its views find these functions before
    // the root's, as this component's root is the nearer context object.
    component LongMemoryPopup: Item {
        id: stretched

        required property var monitor

        function i18n(text, ...args) {
            return stretch(gallery.i18n(text, ...args));
        }
        function i18nc(context, text, ...args) {
            return stretch(gallery.i18nc(context, text, ...args));
        }
        function i18np(singular, plural, n, ...args) {
            return stretch(gallery.i18np(singular, plural, n, ...args));
        }
        function i18ncp(context, singular, plural, n, ...args) {
            return stretch(gallery.i18ncp(context, singular, plural, n, ...args));
        }
        function stretch(s) {
            return s + "ß".repeat(Math.round(s.length * 0.35));
        }

        implicitWidth: popup.implicitWidth
        implicitHeight: popup.implicitHeight

        MemoryPopup {
            id: popup
            monitor: stretched.monitor
        }
    }

    component Note: Text {
        color: Style.dim(Kirigami.Theme.textColor)
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        textFormat: Text.PlainText
    }

    // The strip centred on a stretch of panel, as main.qml places it. The
    // outline marks the panel's thickness.
    component Panel: ColumnLayout {
        id: panel

        required property string label
        required property real thickness
        property var monitor: normal
        property var ringsOnly: []
        // Right to left, as main.qml lays the strip out in such a locale.
        property bool mirrored: false

        spacing: Kirigami.Units.smallSpacing

        Note {
            text: panel.label
        }

        Rectangle {
            color: "transparent"
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
            Layout.preferredWidth: strip.implicitWidth + 4 * Kirigami.Units.gridUnit
            Layout.preferredHeight: panel.thickness

            // Breeze's panel keeps 4 px of margin either side of an applet.
            Strip {
                id: strip
                anchors.centerIn: parent
                height: panel.thickness - 8
                monitor: panel.monitor
                items: ["cpu", "gpu", "memory", "claude", "network", "disk"]
                vertical: false
                thickness: panel.thickness - 8
                ringsOnly: panel.ringsOnly
                LayoutMirroring.enabled: panel.mirrored
                LayoutMirroring.childrenInherit: true
            }
        }
    }

    // A left or right panel. Breeze's panel keeps 4 px of margin either side
    // of an applet, so the strip gets the thickness less 8 px.
    component VerticalPanel: ColumnLayout {
        id: side

        required property string label
        required property real thickness
        property var monitor: normal

        Layout.alignment: Qt.AlignTop
        spacing: Kirigami.Units.smallSpacing

        Note {
            text: side.label
        }

        Rectangle {
            color: "transparent"
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
            Layout.preferredWidth: side.thickness
            Layout.preferredHeight: column.implicitHeight + 2 * Kirigami.Units.gridUnit

            Strip {
                id: column
                anchors.centerIn: parent
                width: side.thickness - 8
                height: implicitHeight
                monitor: side.monitor
                items: ["cpu", "gpu", "memory", "claude", "codex", "network", "disk"]
                vertical: true
                thickness: width
                ringsOnly: []
            }
        }
    }

    // A popup on the theme's dialog background, sized to its implicit size
    // as AppletPopup sizes its main item.
    component PopupFrame: ColumnLayout {
        id: popup

        required property string label
        // The dialog SVG follows the system colour scheme, not the colours
        // set on the item, so an overridden section draws a flat background.
        property bool flat: false
        default property alias page: holder.data

        Layout.alignment: Qt.AlignTop
        spacing: Kirigami.Units.smallSpacing

        Note {
            text: popup.label
        }

        Item {
            id: dialog

            readonly property var margin: popup.flat
                ? { left: Kirigami.Units.smallSpacing, top: Kirigami.Units.smallSpacing,
                    right: Kirigami.Units.smallSpacing, bottom: Kirigami.Units.smallSpacing }
                : frame.fixedMargins

            Layout.preferredWidth: holder.childrenRect.width + margin.left + margin.right
            Layout.preferredHeight: holder.childrenRect.height + margin.top + margin.bottom

            KSvg.FrameSvgItem {
                id: frame
                anchors.fill: parent
                visible: !popup.flat
                imagePath: "dialogs/background"
            }

            Rectangle {
                anchors.fill: parent
                visible: popup.flat
                color: Kirigami.Theme.backgroundColor
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
                radius: Kirigami.Units.smallSpacing
            }

            Item {
                id: holder
                x: dialog.margin.left
                y: dialog.margin.top
            }
        }
    }

    ColumnLayout {
        id: layout

        x: 3 * Kirigami.Units.gridUnit
        y: x
        spacing: 2 * Kirigami.Units.gridUnit

        Panel {
            label: "Panel · 46 px"
            thickness: 46
        }

        Panel {
            label: "Panel · 44 px"
            thickness: 44
        }

        Panel {
            label: "Panel · 38 px"
            thickness: 38
        }

        Panel {
            label: "Panel · 30 px"
            thickness: 30
        }

        Panel {
            label: "Panel · 72 px"
            thickness: 72
        }

        Panel {
            label: "Panel · 46 px · alerts"
            thickness: 46
            monitor: alert
        }

        Panel {
            label: "Panel · 46 px · right to left · Claude's last day, 23h 5m left"
            thickness: 46
            monitor: lastDay
            mirrored: true
        }

        Panel {
            label: "Panel · 46 px · the only GPU asleep"
            thickness: 46
            monitor: onlyAsleep
        }

        Panel {
            label: "Panel · 46 px · rings only · CPU 92 °C"
            thickness: 46
            monitor: hot
            ringsOnly: ["cpu", "gpu", "memory"]
        }

        Panel {
            label: "Panel · 46 px · iGPU outer, dGPU inner asleep"
            thickness: 46
            monitor: innerAsleep
        }

        Panel {
            label: "Panel · 46 px · NVIDIA outer, Intel inner (no temperature)"
            thickness: 46
            monitor: intel
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            VerticalPanel {
                label: "Vertical · 36 px"
                thickness: 36
            }

            VerticalPanel {
                label: "Vertical · 46 px"
                thickness: 46
            }

            VerticalPanel {
                label: "Vertical · 46 px · CPU 92 °C"
                thickness: 46
                monitor: hot
            }

            VerticalPanel {
                label: "Vertical · 60 px"
                thickness: 60
            }
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            PopupFrame {
                label: "CPU"
                CpuPopup { monitor: normal }
            }

            PopupFrame {
                label: "GPU"
                GpuPopup { monitor: normal }
            }

            PopupFrame {
                label: "Memory"
                MemoryPopup { monitor: normal }
            }

            PopupFrame {
                label: "Network"
                NetworkPopup { monitor: normal }
            }

            PopupFrame {
                label: "Disk"
                DiskPopup { monitor: normal }
            }
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            PopupFrame {
                label: "CPU · 92 °C · top processes loading"
                CpuPopup { monitor: hot }
            }

            PopupFrame {
                label: "GPU · discrete asleep"
                GpuPopup { monitor: asleep }
            }

            PopupFrame {
                label: "GPU · one integrated GPU"
                GpuPopup { monitor: integrated }
            }

            PopupFrame {
                label: "Memory · no PSI, no swap"
                MemoryPopup { monitor: bare }
            }

            PopupFrame {
                label: "Memory · every string a third longer"
                LongMemoryPopup { monitor: normal }
            }
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            PopupFrame {
                label: "GPU · iGPU outer, dGPU inner asleep"
                GpuPopup { monitor: innerAsleep }
            }

            PopupFrame {
                label: "GPU · NVIDIA and Intel"
                GpuPopup { monitor: intel }
            }

            PopupFrame {
                label: "GPU · the only GPU asleep"
                GpuPopup { monitor: onlyAsleep }
            }

            PopupFrame {
                label: "Disk · no temperature"
                DiskPopup { monitor: diskUnheated }
            }

            PopupFrame {
                label: "Disk · all disks, 78 °C"
                DiskPopup { monitor: diskHot }
            }
        }

        // Claude and Codex, in the panel and in their popups.
        UsageGallery {
            monitor: normal
        }

        // Breeze Light's colours, for the contrast of dim text on a light scheme.
        Rectangle {
            Layout.fillWidth: true
            implicitWidth: light.implicitWidth + 2 * light.x
            implicitHeight: light.implicitHeight + 2 * light.y
            color: Kirigami.Theme.backgroundColor

            Kirigami.Theme.inherit: false
            Kirigami.Theme.textColor: "#232629"
            Kirigami.Theme.disabledTextColor: "#707d8a"
            Kirigami.Theme.backgroundColor: "#eff0f1"
            Kirigami.Theme.alternateBackgroundColor: "#e3e5e7"
            Kirigami.Theme.highlightColor: "#3daee9"
            Kirigami.Theme.highlightedTextColor: "#ffffff"
            Kirigami.Theme.linkColor: "#2980b9"
            Kirigami.Theme.visitedLinkColor: "#9b59b6"
            Kirigami.Theme.negativeTextColor: "#da4453"
            Kirigami.Theme.neutralTextColor: "#f67400"
            Kirigami.Theme.positiveTextColor: "#27ae60"

            ColumnLayout {
                id: light

                x: 2 * Kirigami.Units.gridUnit
                y: x
                spacing: 2 * Kirigami.Units.gridUnit

                Note {
                    text: "Breeze Light colours are set on this section only; the popup footers keep the system's."
                }

                Panel {
                    label: "Breeze Light · panel · 46 px"
                    thickness: 46
                }

                Panel {
                    label: "Breeze Light · panel · 46 px · alerts"
                    thickness: 46
                    monitor: alert
                }

                Panel {
                    label: "Breeze Light · panel · 46 px · rings only · CPU 92 °C"
                    thickness: 46
                    monitor: hot
                    ringsOnly: ["cpu", "gpu", "memory"]
                }

                RowLayout {
                    spacing: 2 * Kirigami.Units.gridUnit

                    PopupFrame {
                        label: "Breeze Light · CPU"
                        flat: true
                        CpuPopup { monitor: normal }
                    }

                    PopupFrame {
                        label: "Breeze Light · GPU"
                        flat: true
                        GpuPopup { monitor: normal }
                    }

                    PopupFrame {
                        label: "Breeze Light · Memory"
                        flat: true
                        MemoryPopup { monitor: normal }
                    }

                    PopupFrame {
                        label: "Breeze Light · Network"
                        flat: true
                        NetworkPopup { monitor: normal }
                    }

                    PopupFrame {
                        label: "Breeze Light · Disk"
                        flat: true
                        DiskPopup { monitor: normal }
                    }
                }
            }
        }
    }

    // Long enough for the process lists' first scan and the CPU sensors.
    Timer {
        interval: 5000
        running: gallery.snapshotPath.length > 0
        onTriggered: gallery.grabToImage(result => {
            result.saveToFile(gallery.snapshotPath);
            Qt.quit();
        })
    }
}
