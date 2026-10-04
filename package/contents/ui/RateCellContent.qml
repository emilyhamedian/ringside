// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/style.js" as Style

// Two transfer rates in the panel: down and up for the network, read and
// write for the disk. Stacked on the rows a ring's two readings use, so they
// line up across the panel, or side by side on a thin panel. The columns
// keep room for their widest text, so the panel doesn't shift as rates change.
GridLayout {
    id: rates

    required property var monitor
    required property string item
    required property bool vertical
    property bool singleRow: false
    // The width a vertical panel leaves for the rates.
    property real availableWidth: Infinity

    readonly property bool network: item === "network"
    readonly property bool bits: network && monitor.networkBits
    readonly property var lines: network
        ? [Format.rate(monitor.networkDown, bits), Format.rate(monitor.networkUp, bits)]
        : [Format.rate(monitor.diskRead, false), Format.rate(monitor.diskWrite, false)]
    readonly property color markColor: Qt.alpha(Kirigami.Theme.textColor, 0.75)
    readonly property string readLetter: i18nc("@label short for disk reads", "R")
    readonly property string writeLetter: i18nc("@label short for disk writes", "W")

    // A vertical panel has no room for a unit column: the unit shrinks to its
    // prefix, "24.8M". The widest value is four digits and the prefix: "99.9M",
    // "1023K". Where even that doesn't fit, the gaps tighten, then the values
    // drop their decimal ("25M"), then the text shrinks down to a floor.
    // Everything is measured at the base size, never from what is drawn, and
    // rounded up per column as the layout does.
    readonly property real looseSpacing: Math.round(Kirigami.Units.smallSpacing * 1.5)
    readonly property real tightSpacing: Math.round(Kirigami.Units.smallSpacing / 2)
    readonly property real markerWidth: network ? Math.round(base.plain.height * 0.62) * 0.8
                                                : base.room(base.plain, [readLetter, writeLetter])
    readonly property real decimalWidth: Math.ceil(markerWidth) + base.room(base.plain, [Format.whole(1000) + "M"])
    readonly property real wholeWidth: Math.ceil(markerWidth) + base.room(base.plain, [Format.whole(100) + "M"])
    // Text draws a pixel or two wider than its advance (bearings, rounding).
    readonly property real room: availableWidth - 2
    readonly property bool tight: vertical && decimalWidth + looseSpacing > room
    readonly property bool whole: vertical && decimalWidth + tightSpacing > room
    // Shrunk in half points, the steps text is drawn in, rounding down so it
    // still fits.
    readonly property real pointSize: whole
        ? Math.max(Kirigami.Theme.smallFont.pointSize * 0.6,
                   Math.floor(Math.min(1, (room - tightSpacing - 2) / (wholeWidth - 2)) * base.drawnSize * 2) / 2)
        : base.drawnSize

    // "25M" for "24.8M". A byte rate of 1000 to 1023 in one unit rounds to 1
    // of the next, so it keeps to three digits.
    function verticalText(reading) {
        const prefixes = ["", "K", "M", "G", "T", "P"];
        let prefix = reading.unit.charAt(0).replace(/[bB]/, "");
        if (!whole || reading.value === "–") {
            return reading.value + prefix;
        }
        // format.js writes decimals in the user's locale: "24,8" in German.
        let rounded = Math.round(Number.fromLocaleString(Qt.locale(), reading.value));
        if (rounded >= 1000 && prefixes.includes(prefix)) {
            rounded = 1;
            prefix = prefixes[prefixes.indexOf(prefix) + 1];
        }
        return Format.whole(rounded) + prefix;
    }

    // The rates in words, for screen readers.
    readonly property string accessibleDescription: words.describe(item)

    // Room for the widest value and unit at the size drawn.
    readonly property real valueRoom: drawn.room(drawn.plain, [!vertical ? Format.whole(1000)
                                                              : whole ? Format.whole(100) + "M" : Format.whole(1000) + "M"])
    // Units differ in length: b/s and Mb/s, B/s and MiB/s.
    readonly property real unitRoom: drawn.room(drawn.plain, bits ? ["b/s", "kb/s", "Mb/s", "Gb/s", "Tb/s"]
                                                                  : ["B/s", "KiB/s", "MiB/s", "GiB/s", "TiB/s", "PiB/s"])
    // Horizontally each row is a ring's line; a vertical panel spaces its own.
    readonly property real rowHeight: vertical ? -1 : drawn.lineHeight

    columns: vertical ? 2 : singleRow ? 6 : 3
    rowSpacing: vertical ? Math.round(Kirigami.Units.smallSpacing * 0.75) : 0
    columnSpacing: tight ? tightSpacing : looseSpacing

    Words {
        id: words
        monitor: rates.monitor
    }

    ReadoutFont {
        id: base
        pointSize: rates.vertical ? Kirigami.Theme.smallFont.pointSize * 0.9 : base.panelPointSize
    }

    ReadoutFont {
        id: drawn
        pointSize: rates.pointSize
    }

    Repeater {
        model: 2

        delegate: Item {
            id: marker

            required property int index

            Layout.row: rates.singleRow ? 0 : index
            Layout.column: rates.singleRow ? index * 3 : 0
            Layout.leftMargin: rates.singleRow && index === 1 ? Kirigami.Units.smallSpacing : 0
            implicitWidth: rates.network ? arrow.width : letter.implicitWidth
            implicitHeight: rates.vertical ? letter.implicitHeight : rates.rowHeight

            Arrow {
                id: arrow
                visible: rates.network
                anchors.centerIn: parent
                height: Math.round(letter.implicitHeight * 0.62)
                up: marker.index === 1
                color: rates.markColor
            }

            Text {
                id: letter
                visible: !rates.network
                text: marker.index === 1 ? rates.writeLetter : rates.readLetter
                color: rates.markColor
                font: drawn.plain.font
                textFormat: Text.PlainText
            }
        }
    }

    Repeater {
        model: 2

        delegate: Text {
            required property int index

            Layout.row: rates.singleRow ? 0 : index
            Layout.column: rates.singleRow ? index * 3 + 1 : 1
            Layout.alignment: Qt.AlignRight
            Layout.minimumWidth: rates.valueRoom
            Layout.preferredHeight: rates.rowHeight
            horizontalAlignment: Text.AlignRight
            text: rates.vertical ? rates.verticalText(rates.lines[index]) : rates.lines[index].value
            color: Kirigami.Theme.textColor
            font: drawn.plain.font
            textFormat: Text.PlainText
        }
    }

    Repeater {
        model: rates.vertical ? 0 : 2

        delegate: Text {
            required property int index

            Layout.row: rates.singleRow ? 0 : index
            Layout.column: rates.singleRow ? index * 3 + 2 : 2
            Layout.minimumWidth: rates.unitRoom
            Layout.preferredHeight: rates.rowHeight
            text: rates.lines[index].unit
            color: Style.dim(Kirigami.Theme.textColor)
            font: drawn.plain.font
            textFormat: Text.PlainText
        }
    }
}
