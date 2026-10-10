// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/style.js" as Style
import ".."

PopupPage {
    id: popup

    // "11.7 GiB", or the dash alone before a reading arrives.
    function size(bytes, trim) {
        const b = Format.bytes(bytes, trim);
        return b.unit ? b.value + " " + b.unit : b.value;
    }

    PopupHeader {
        id: header

        readonly property var used: Format.bytes(popup.monitor.memoryUsed)

        ringValue: popup.monitor.memoryPercent
        interval: popup.monitor.sampleInterval
        title: i18nc("@title", "Memory")
        subtitle: {
            const m = popup.monitor;
            if (m.memoryModules !== "") {
                const installed = m.hardware.memory.modules.reduce((sum, bytes) => sum + Number(bytes), 0);
                return popup.size(installed, true) + " · " + m.memoryModules;
            }
            return m.memoryTotal > 0 ? popup.size(m.memoryTotal, true) : "";
        }
        value: header.used.value
        caption: header.used.unit
            ? i18nc("@info:label unit of the used-memory reading, e.g. GiB used", "%1 used", header.used.unit) : ""
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.25)
        spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)

        Rectangle {
            id: bar

            function share(bytes) {
                const total = popup.monitor.memoryTotal;
                return total > 0 && Number.isFinite(bytes) ? Math.max(0, Math.min(1, bytes / total)) : 0;
            }

            readonly property real step: 0.0001
            readonly property real usedEnd: share(popup.monitor.memoryUsed) * (1 - 2 * step)
            readonly property real cachedEnd: Math.min(1 - step,
                usedEnd + step + share(popup.monitor.memoryCached) * (1 - 2 * step))
            readonly property color usedColor: Kirigami.Theme.textColor
            readonly property color cachedColor: Qt.alpha(Kirigami.Theme.textColor, 0.4)
            readonly property color trackColor: Qt.alpha(Kirigami.Theme.textColor, 0.08)

            Layout.fillWidth: true
            implicitHeight: Kirigami.Units.smallSpacing * 2
            radius: height / 2

            // One rounded rectangle with hard colour steps, so the segments
            // take the track's rounded ends (clip ignores a radius). A step is
            // two stops `step` apart, since QPainter merges stops at one
            // position; the ends above keep every stop in order and in 0–1.
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: bar.usedColor }
                GradientStop { position: bar.usedEnd; color: bar.usedColor }
                GradientStop { position: bar.usedEnd + bar.step; color: bar.cachedColor }
                GradientStop { position: bar.cachedEnd; color: bar.cachedColor }
                GradientStop { position: bar.cachedEnd + bar.step; color: bar.trackColor }
                GradientStop { position: 1; color: bar.trackColor }
            }

            // A gradient ignores layout mirroring; flip the bar so used memory
            // starts on the same side as its legend in a right-to-left layout.
            transform: Scale {
                origin.x: bar.width / 2
                xScale: bar.LayoutMirroring.enabled ? -1 : 1
            }

            Accessible.role: Accessible.ProgressBar
            Accessible.name: i18nc("@info accessible name of the memory usage bar", "Memory use")
            Accessible.description: i18nc("@info accessible description of the memory usage bar",
                                          "Used %1, cached %2, free %3", popup.size(popup.monitor.memoryUsed),
                                          popup.size(popup.monitor.memoryCached), popup.size(popup.monitor.memoryFree))
        }

        // Spread across the bar while the entries fit on one line; a longer
        // translation wraps rather than widening the popup. Asking for no
        // width keeps the entries out of the page's width.
        Flow {
            readonly property real entriesWidth: used.implicitWidth + cached.implicitWidth + free.implicitWidth

            Layout.fillWidth: true
            Layout.preferredWidth: 0
            spacing: Math.max(Kirigami.Units.largeSpacing, Math.floor((width - entriesWidth) / 2))

            LegendEntry {
                id: used
                swatch: bar.usedColor
                text: i18nc("@info:legend used memory, e.g. Used 11.7 GiB", "Used %1", popup.size(popup.monitor.memoryUsed))
            }

            LegendEntry {
                id: cached
                swatch: bar.cachedColor
                text: i18nc("@info:legend memory holding the page cache, e.g. Cached 9.2 GiB", "Cached %1",
                            popup.size(popup.monitor.memoryCached))
            }

            LegendEntry {
                id: free
                text: i18nc("@info:legend memory neither used nor cached, e.g. Free 7.6 GiB", "Free %1",
                            popup.size(popup.monitor.memoryFree))
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        columns: 2
        rowSpacing: Kirigami.Units.largeSpacing
        columnSpacing: Kirigami.Units.largeSpacing
        uniformCellWidths: true

        Tile {
            Layout.columnSpan: 2
            caption: i18nc("@title:group memory in use", "Used")
            spans: popup.monitor
            graphTop: i18nc("@info a percentage", "%1%", Format.percent(100))

            Graph {
                Layout.fillWidth: true
                values: popup.monitor.memoryHistory
                highs: popup.monitor.memoryHighs
                length: popup.monitor.historyLength
            }
        }

        Tile {
            Layout.columnSpan: pressure.visible ? 1 : 2
            caption: i18nc("@title:group", "Swap")
            detail: popup.monitor.swapLabel ? "(" + popup.monitor.swapLabel + ")" : ""
            foot: swapReading

            Reading {
                id: swapReading
                // NaN before the first reading, 0 without swap.
                readonly property bool none: !(popup.monitor.swapTotal > 0)
                readonly property var swap: Format.bytesOf(popup.monitor.swapUsed, popup.monitor.swapTotal)
                value: none ? i18nc("@info no swap space configured", "none") : swap.value
                unit: none ? "" : "/ " + swap.total + " " + swap.unit
                color: none ? Style.dim(Kirigami.Theme.textColor) : Kirigami.Theme.textColor
                pointSize: Kirigami.Theme.defaultFont.pointSize * 1.38
            }
        }

        Tile {
            id: pressure
            // Plasma 6.2 brought the pressure sensors; before that this stays NaN.
            visible: Number.isFinite(popup.monitor.memoryPressure)
            caption: i18nc("@title:group memory pressure", "Pressure")
            detail: i18nc("@title:group pressure stall information, averaged over 10 seconds", "(PSI 10 s)")
            foot: pressureReading

            Reading {
                id: pressureReading
                value: Format.fixed(popup.monitor.memoryPressure, 2)
                pointSize: Kirigami.Theme.defaultFont.pointSize * 1.38
            }
        }
    }

    Divider {}

    ProcessList {
        key: "memory"
        threads: popup.monitor.cpuThreads
        sample: popup.monitor.processSample || null
    }

    // A legend label, led by a square in its segment's colour when it has one.
    component LegendEntry: RowLayout {
        id: entry

        property color swatch: "transparent"
        property alias text: label.text

        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            visible: entry.swatch.a > 0
            Layout.preferredWidth: Math.round(label.implicitHeight * 0.5)
            Layout.preferredHeight: Layout.preferredWidth
            color: entry.swatch
        }

        Text {
            id: label
            color: Style.dim(Kirigami.Theme.textColor)
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            textFormat: Text.PlainText
        }
    }
}
