// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
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

    // A legend entry: a sample of the line as the graph draws it, then its name.
    component Key: RowLayout {
        id: key

        property string text
        property color color
        property bool dashed: false
        property bool area: false
        readonly property alias label: label

        Layout.minimumWidth: implicitWidth
        spacing: Kirigami.Units.smallSpacing

        Shape {
            Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 0.9)
            Layout.preferredHeight: label.implicitHeight
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                fillColor: key.area ? Qt.alpha(key.color, 0.15 * key.color.a) : "transparent"
                startX: 0
                startY: label.implicitHeight / 2
                PathLine { x: Math.round(Kirigami.Units.gridUnit * 0.9); y: label.implicitHeight / 2 }
                PathLine { x: Math.round(Kirigami.Units.gridUnit * 0.9); y: label.implicitHeight * 0.8 }
                PathLine { x: 0; y: label.implicitHeight * 0.8 }
            }

            ShapePath {
                strokeColor: key.color
                strokeWidth: 1.5
                strokeStyle: key.dashed ? ShapePath.DashLine : ShapePath.SolidLine
                dashPattern: [3, 2]
                capStyle: ShapePath.FlatCap
                fillColor: "transparent"
                startX: 0
                startY: label.implicitHeight / 2
                PathLine { x: Math.round(Kirigami.Units.gridUnit * 0.9); y: label.implicitHeight / 2 }
            }
        }

        Note {
            id: label
            text: key.text
        }
    }

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
        // Kept while the service is asked again after a failure, so the block
        // keeps its height and the last address stays in view. There is no
        // record before the first check.
        const seen = record && (publicState === "failed" || publicState === "checking") ? record.seen.v4 ?? record.seen.v6 : null;
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
        onRetryRequested: popup.lookup.retry()
    }

    Tile {
        id: throughput

        readonly property var history: popup.monitor.networkDownHistory.concat(popup.monitor.networkUpHistory)
        // Up has no band of its own, but its highest readings count for the
        // top, so neither line runs past what the caption names.
        readonly property var tops: History.tops(history,
                                                 popup.monitor.networkDownHighs.concat(popup.monitor.networkUpHighs))

        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 1.5)
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        caption: i18nc("@title:group", "Throughput")
        spans: popup.monitor
        graphTop: words.peakText(throughput.tops, popup.monitor.networkBits)
        foot: downKey.label

        Graph {
            Layout.fillWidth: true
            ceiling: false
            values: popup.monitor.networkDownHistory
            highs: popup.monitor.networkDownHighs
            second: true
            secondValues: popup.monitor.networkUpHistory
            length: popup.monitor.historyLength
            // 1 Mb/s at least, so an idle link doesn't draw its noise at full height.
            maximum: Math.max(History.peak(throughput.tops)?.value ?? 0, 125000)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)
            spacing: Math.round(Kirigami.Units.largeSpacing * 1.75)

            Key {
                id: downKey
                text: i18nc("@label graph legend, beside a sample of the solid line", "Down")
                color: Kirigami.Theme.textColor
                area: true
            }

            Key {
                text: i18nc("@label graph legend, beside a sample of the dashed line", "Up")
                color: Kirigami.Theme.textColor
                dashed: true
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
