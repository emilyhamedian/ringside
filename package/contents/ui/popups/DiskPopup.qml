// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/history.js" as History
import "../code/style.js" as Style
import ".."

PopupPage {
    id: popup

    readonly property real temperature: popup.monitor.diskTemperature

    Words {
        id: words
        monitor: popup.monitor
    }

    // Read or write: the rate over a graph of its history, which its peak
    // tops, a tile across the page as the other popups open on. Each names
    // its graph's span and peak on its caption line.
    component DiskRate: Tile {
        id: tile

        property real rate: NaN
        property var history: []
        property var highs: []
        readonly property var tops: History.tops(history, highs)
        // Writes the reading at a point (see Graph.describe).
        property var describe: null
        property GraphCursor cursor: null

        graphReading: rateGraph.reading

        Reading {
            readonly property var r: Format.rate(tile.rate, false)
            value: r.value
            unit: r.unit
            pointSize: Style.tilePointSize(Kirigami.Theme.defaultFont.pointSize)
        }

        Graph {
            id: rateGraph
            cursor: tile.cursor
            Layout.fillWidth: true
            describe: tile.describe
            values: tile.history
            highs: tile.highs
            length: tile.spans.historyLength
            // Anything under 1 MiB/s stays near the floor rather than filling the graph.
            maximum: Math.max(History.peak(tile.tops)?.value ?? 0, 1048576)
            ceiling: false
        }
    }

    // The device on one line and its size and the volume's free space on the
    // next, as the network header gives the address a line of its own; the
    // drive's temperature where the CPU and GPU headers have theirs, or
    // nothing there when none is known.
    PopupHeader {
        ringShown: false
        title: i18nc("@title", "Disk")
        subtitle: popup.monitor.diskDevice === "all" ? i18nc("@info disk I/O of every disk", "all disks") : popup.monitor.diskDevice
        detail: {
            const m = popup.monitor;
            const size = Format.bytes(m.diskSize, true);
            const free = Format.bytes(m.volumeFree, true);
            return words.joined([
                size.unit ? words.bytesText(size) : "",
                !free.unit ? ""
                    : m.volumeLabel ? i18nc("@info free space on a volume, e.g. 1.2 TiB free on /", "%1 %2 free on %3",
                                            free.value, free.unit, m.volumeLabel)
                    : i18nc("@info free space, e.g. 1.2 TiB free", "%1 %2 free", free.value, free.unit)
            ]);
        }
        value: Number.isFinite(popup.temperature) ? Format.temperature(popup.temperature, popup.monitor.fahrenheit) : ""
        degreeUnit: popup.monitor.fahrenheit ? "F" : "C"
        valueColor: Style.levelColor(popup.monitor.heat(popup.temperature), Kirigami.Theme)
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 1.5)
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        spacing: Kirigami.Units.largeSpacing

        DiskRate {
            id: read
            cursor: popup.graphCursor
            caption: i18nc("@title:group disk reads", "Read")
            spans: popup.monitor
            graphTop: words.peakText(read.tops, false)
            describe: i => words.pointText(read.history, read.highs, i, v => words.rateText(Format.rate(v, false)))
            rate: popup.monitor.diskRead
            history: popup.monitor.diskReadHistory
            highs: popup.monitor.diskReadHighs
        }

        DiskRate {
            id: write
            cursor: popup.graphCursor
            caption: i18nc("@title:group disk writes", "Write")
            spans: popup.monitor
            graphTop: words.peakText(write.tops, false)
            describe: i => words.pointText(write.history, write.highs, i, v => words.rateText(Format.rate(v, false)))
            rate: popup.monitor.diskWrite
            history: popup.monitor.diskWriteHistory
            highs: popup.monitor.diskWriteHighs
        }

        // Last, after the rates the popup is for.
        TemperatureTile {
            cursor: popup.graphCursor
            monitor: popup.monitor
            history: popup.monitor.diskTemperatureHistory
            highs: popup.monitor.diskTemperatureHighs
            extent: popup.monitor.diskTemperatureExtent
        }
    }
}
