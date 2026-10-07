// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/history.js" as History
import ".."

PopupPage {
    id: popup

    readonly property real temperature: popup.monitor.diskTemperature

    Words {
        id: words
        monitor: popup.monitor
    }

    // Read or write: the rate over a small line graph of its history, which
    // its peak tops. Each DiskRate below names that peak on its caption line.
    component DiskRate: Tile {
        id: tile

        property real rate: NaN
        property var history: []
        property int length: 60

        Reading {
            readonly property var r: Format.rate(tile.rate, false)
            value: r.value
            unit: r.unit
            pointSize: Kirigami.Theme.defaultFont.pointSize * 1.38
        }

        Graph {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(Kirigami.Units.gridUnit * 1.35)
            values: tile.history
            length: tile.length
            // Anything under 1 MiB/s stays near the floor rather than filling the graph.
            maximum: Math.max(History.peak(tile.history)?.value ?? 0, 1048576)
            ceiling: false
            fillOpacity: 0
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
            return [
                size.unit ? size.value + " " + size.unit : "",
                !free.unit ? ""
                    : m.volumeLabel ? i18nc("@info free space on a volume, e.g. 1.2 TiB free on /", "%1 %2 free on %3",
                                            free.value, free.unit, m.volumeLabel)
                    : i18nc("@info free space, e.g. 1.2 TiB free", "%1 %2 free", free.value, free.unit)
            ].filter(s => s !== "").join(" · ");
        }
        value: Number.isFinite(popup.temperature) ? Format.temperature(popup.temperature, popup.monitor.fahrenheit) : ""
        degreeUnit: popup.monitor.fahrenheit ? "F" : "C"
        valueColor: {
            const level = popup.monitor.heat(popup.temperature);
            return level === 2 ? Kirigami.Theme.negativeTextColor
                 : level === 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
        }
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 1.5)
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing
        uniformCellWidths: true

        DiskRate {
            caption: i18nc("@title:group disk reads", "Read")
            graphTop: words.peakText(popup.monitor.diskReadHistory, false)
            rate: popup.monitor.diskRead
            history: popup.monitor.diskReadHistory
            length: popup.monitor.historyLength
        }

        DiskRate {
            caption: i18nc("@title:group disk writes", "Write")
            graphTop: words.peakText(popup.monitor.diskWriteHistory, false)
            rate: popup.monitor.diskWrite
            history: popup.monitor.diskWriteHistory
            length: popup.monitor.historyLength
        }
    }
}
