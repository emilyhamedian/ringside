// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/history.js" as History
import "../code/style.js" as Style
import ".."

// Opened by both the network and the disk items.
PopupPage {
    id: popup

    readonly property real diskTemperature: popup.monitor.diskTemperature
    readonly property bool diskTemperatureShown: Number.isFinite(diskTemperature)

    // What a rate graph's caption line says about its top, which is the
    // peak in view: "peak 24.8 Mb/s", or nothing before the first sample.
    // Under the graph's floor the top is the floor, and this still names
    // the peak.
    function peakNote(samples, bits) {
        const top = History.peak(samples);
        if (top === null) {
            return "";
        }
        const r = Format.rate(top.value, bits);
        return i18nc("@title:group at the end of a rate graph's caption line, after THROUGHPUT · 60 s or READ: its highest rate, as in peak 24.8 Mb/s",
                     "peak %1 %2", r.value, r.unit);
    }

    Words {
        id: words
        monitor: popup.monitor
    }

    // Legend and detail text: caption-sized, set as written.
    component Note: Caption {}

    // Read or write: the rate over a small line graph of its history, which
    // its peak tops. Each DiskRate below names that peak on its caption
    // line through peakNote().
    component DiskRate: Tile {
        id: tile

        property real rate: NaN
        property var history: []
        property int length: 60
        readonly property real peak: History.peak(history)?.value ?? 0

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
            maximum: Math.max(tile.peak, 1048576)
            ceiling: false
            fillOpacity: 0
        }
    }

    PopupHeader {
        ringShown: false
        title: i18nc("@title", "Network & Disk")
        // The interface name goes last: when the line runs long, it's the part to lose.
        subtitle: [popup.monitor.networkConnection, popup.monitor.networkAddress, popup.monitor.networkInterface]
            .filter(s => s !== "").join(" · ")

        // The arrows in a column that follows the layout's direction, and
        // each rate's number and unit left to right beside them, as in the
        // panel. The numbers end on one line and the units start on one,
        // at the tiles' size.
        GridLayout {
            id: rates

            readonly property var down: Format.rate(popup.monitor.networkDown, popup.monitor.networkBits)
            readonly property var up: Format.rate(popup.monitor.networkUp, popup.monitor.networkBits)
            readonly property real pointSize: Kirigami.Theme.defaultFont.pointSize * 1.38
            readonly property real valueWidth: Math.max(downRate.numberWidth, upRate.numberWidth)
            readonly property real pairWidth: valueWidth + downRate.unitSpacing + Math.max(downRate.suffixWidth, upRate.suffixWidth)
            readonly property real arrowHeight: Math.round(downRate.implicitHeight * 0.62)
            readonly property color markColor: Qt.alpha(Kirigami.Theme.textColor, 0.75)

            columns: 2
            rowSpacing: 0
            columnSpacing: Math.round(Kirigami.Units.smallSpacing * 1.75)
            // Spoken as one, since the arrows say nothing on their own.
            Accessible.role: Accessible.StaticText
            Accessible.name: i18nc("@info accessible name of the network rates, e.g. Down 24.8 Mb/s, up 1.2 Mb/s",
                                   "Down %1, up %2", words.rateText(down), words.rateText(up))

            Arrow {
                Layout.preferredWidth: Layout.preferredHeight * 0.8
                Layout.preferredHeight: rates.arrowHeight
                color: rates.markColor
            }
            Item {
                implicitWidth: rates.pairWidth
                implicitHeight: downRate.implicitHeight

                Reading {
                    id: downRate
                    x: rates.valueWidth - numberWidth
                    value: rates.down.value
                    unit: rates.down.unit
                    pointSize: rates.pointSize
                    accessibleIgnored: true
                }
            }

            Arrow {
                Layout.preferredWidth: Layout.preferredHeight * 0.8
                Layout.preferredHeight: rates.arrowHeight
                up: true
                color: rates.markColor
            }
            Item {
                implicitWidth: rates.pairWidth
                implicitHeight: upRate.implicitHeight

                Reading {
                    id: upRate
                    x: rates.valueWidth - numberWidth
                    value: rates.up.value
                    unit: rates.up.unit
                    pointSize: rates.pointSize
                    accessibleIgnored: true
                }
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 1.5)
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        columns: 2
        rowSpacing: Kirigami.Units.largeSpacing
        columnSpacing: Kirigami.Units.largeSpacing
        uniformCellWidths: true

        Tile {
            id: throughput

            readonly property var history: popup.monitor.networkDownHistory.concat(popup.monitor.networkUpHistory)

            Layout.columnSpan: 2
            caption: i18nc("@title:group", "Throughput")
            graphSeconds: popup.monitor.historySeconds
            graphTop: popup.peakNote(throughput.history, popup.monitor.networkBits)
            foot: downNote

            Graph {
                Layout.fillWidth: true
                ceiling: false
                values: popup.monitor.networkDownHistory
                second: true
                secondValues: popup.monitor.networkUpHistory
                length: popup.monitor.historyLength
                // 1 Mb/s at least, so an idle link doesn't draw its noise at full height.
                maximum: Math.max(History.peak(throughput.history)?.value ?? 0, 125000)
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)
                spacing: Math.round(Kirigami.Units.largeSpacing * 1.75)

                Note {
                    id: downNote
                    Layout.minimumWidth: implicitWidth
                    text: i18nc("@label graph legend, the solid line", "— Down")
                }

                Note {
                    Layout.minimumWidth: implicitWidth
                    text: i18nc("@label graph legend, the dashed line", "- - Up")
                }

                Note {
                    readonly property var down: Format.bytes(popup.monitor.networkTotalDown)
                    readonly property var up: Format.bytes(popup.monitor.networkTotalUp)

                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    visible: down.unit !== "" && up.unit !== ""
                    text: i18nc("@info bytes received and sent since boot, e.g. Since boot ↓ 3.2 GiB · ↑ 410 MiB",
                                "Since boot ↓ %1 %2 · ↑ %3 %4", down.value, down.unit, up.value, up.unit)
                }
            }
        }

        RowLayout {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: 0

            Caption {
                label: i18nc("@title:group", "Disk")
            }

            Note {
                Layout.fillWidth: true
                // Rounded up: the layout snaps to whole pixels, and a fraction short elides.
                Layout.maximumWidth: Math.ceil(implicitWidth)
                text: {
                    const m = popup.monitor;
                    const size = Format.bytes(m.diskSize, true);
                    const free = Format.bytes(m.volumeFree, true);
                    const parts = [
                        m.diskDevice === "all" ? i18nc("@info disk I/O of every disk", "all disks") : m.diskDevice,
                        size.unit ? size.value + " " + size.unit : "",
                        !free.unit ? ""
                            : m.volumeLabel ? i18nc("@info free space on a volume, e.g. 1.2 TiB free on /", "%1 %2 free on %3",
                                                    free.value, free.unit, m.volumeLabel)
                            : i18nc("@info free space, e.g. 1.2 TiB free", "%1 %2 free", free.value, free.unit)
                    ].filter(s => s !== "");
                    // The separators stay in the details' colour when the temperature is highlighted.
                    return parts.map(s => " · " + s).join("") + (popup.diskTemperatureShown ? " · " : "");
                }
            }

            Note {
                visible: popup.diskTemperatureShown
                text: popup.monitor.fahrenheit
                      ? i18nc("@info a temperature, the unit against the number as in the popups' readings, e.g. 102°F", "%1°F",
                              Format.temperature(popup.diskTemperature, true))
                      : i18nc("@info a temperature, the unit against the number as in the popups' readings, e.g. 39°C", "%1°C",
                              Format.temperature(popup.diskTemperature, false))
                color: {
                    const level = popup.monitor.heat(popup.diskTemperature);
                    return level === 2 ? Kirigami.Theme.negativeTextColor
                         : level === 1 ? Kirigami.Theme.neutralTextColor : Style.dim(Kirigami.Theme.textColor);
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        DiskRate {
            caption: i18nc("@title:group disk reads", "Read")
            graphTop: popup.peakNote(popup.monitor.diskReadHistory, false)
            rate: popup.monitor.diskRead
            history: popup.monitor.diskReadHistory
            length: popup.monitor.historyLength
        }

        DiskRate {
            caption: i18nc("@title:group disk writes", "Write")
            graphTop: popup.peakNote(popup.monitor.diskWriteHistory, false)
            rate: popup.monitor.diskWrite
            history: popup.monitor.diskWriteHistory
            length: popup.monitor.historyLength
        }
    }
}
