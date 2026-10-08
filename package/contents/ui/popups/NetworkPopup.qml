// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/history.js" as History
import "../code/publicaddress.js" as Lookup
import ".."

PopupPage {
    id: popup

    Words {
        id: words
        monitor: popup.monitor
    }

    // Legend and detail text: caption-sized, set as written.
    component Note: Caption {}

    // The public address lookup (PublicAddress.qml), or null where the
    // monitor has none, which reads as switched off.
    readonly property var lookup: popup.monitor.publicAddress ?? null
    readonly property string publicState: lookup ? lookup.status : "off"
    readonly property bool compared: publicState !== "off"
    // What AddressBlock shows, built from the lookup's shared record.
    readonly property var publicInfo: {
        if (!compared) {
            return { state: "off" };
        }
        const record = lookup.record;
        const shown = publicState === "shown"
            ? Lookup.lines(record.result, record.egress, popup.monitor.networkInterface) : { v4: null, v6: null, leak: null };
        const at = ms => words.timeOfDay(ms / 1000, lookup.clock());
        const changed = shown.v4 && record.changed.v4 ? record.changed.v4 : shown.v6 && record.changed.v6 ? record.changed.v6 : null;
        const seen = publicState === "failed" ? record.seen.v4 ?? record.seen.v6 : null;
        let note = null;
        if (shown.leak) {
            note = { warn: true, text: shown.leak.family === "v6"
                ? i18nc("@info %1 is a VPN's network interface", "IPv6 doesn't go through %1", shown.leak.through)
                : i18nc("@info %1 is a VPN's network interface", "IPv4 doesn't go through %1", shown.leak.through) };
        } else if (changed) {
            note = { warn: false, text: i18nc("@info %1 is a time, %2 the address before", "Changed at %1, was %2",
                                              at(changed.at), changed.was) };
        } else if (seen) {
            note = { warn: false, text: i18nc("@info %1 is an address, %2 a time", "Last seen %1 at %2", seen.address, at(seen.at)) };
        }
        return {
            state: publicState,
            service: lookup.serviceName,
            // The one family the service asks, which has no route.
            unrouted: lookup.service.v4 !== "" ? "v4" : "v6",
            v4: shown.v4,
            v6: shown.v6,
            note: note
        };
    }

    PopupHeader {
        ringShown: false
        title: i18nc("@title", "Network")
        // The connection's name on one line and its address on the next, so a
        // long name doesn't push the address out. The interface name goes
        // last: when the line runs long, it's the part to lose.
        subtitle: popup.monitor.networkConnection
        // With the public address on, both addresses go under the header,
        // where a long IPv6 address has the popup's width.
        detail: popup.compared ? "" : [popup.monitor.networkAddress, popup.monitor.networkInterface].filter(s => s !== "").join(" · ")

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

    // Hidden, and so taking no room, while the public address is off.
    AddressBlock {
        visible: popup.compared
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        localAddress: popup.monitor.networkAddress
        localInterface: popup.monitor.networkInterface
        info: popup.publicInfo
    }

    Tile {
        id: throughput

        readonly property var history: popup.monitor.networkDownHistory.concat(popup.monitor.networkUpHistory)

        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 1.5)
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        caption: i18nc("@title:group", "Throughput")
        graphSeconds: popup.monitor.historySeconds
        graphTop: words.peakText(throughput.history, popup.monitor.networkBits)
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
}
