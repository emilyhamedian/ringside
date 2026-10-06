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
// line up across the panel, or side by side on a thin panel. Across the panel
// each rate is its arrow or letter, then its value and unit, as wide as their
// text with every digit counted as the widest, so a rate moves only when it
// gains or loses a character. Stacked, the two values end at the edge the
// wider one sets, so their units line up. The value and its unit read in that
// order either way, as a number keeps its sign; only the marker moves to the
// other side. reservedWidth is the room the widest rates take, which the
// strip keeps, so changing rates never move what comes after the strip.
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
    readonly property real decimalWidth: Math.ceil(markerRoom(base)) + base.room(base.plain, [Format.whole(1000) + "M"])
    readonly property real wholeWidth: Math.ceil(markerRoom(base)) + base.room(base.plain, [Format.whole(100) + "M"])
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

    // An arrow's height, and the room the arrows or the wider of the letters
    // take, in `face`: the one measure both fitting and drawing use.
    function arrowHeight(face) {
        return Math.round(face.lineHeight * 0.62);
    }
    function markerRoom(face) {
        return network ? arrowHeight(face) * 0.8 : face.room(face.plain, [readLetter, writeLetter]);
    }

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

    // Between a marker and its value: across the panel a small spacing, at
    // least the gap before the unit, so an arrow never touches a long value;
    // along a vertical panel, what fits.
    readonly property real markerGap: !vertical ? Kirigami.Units.smallSpacing : tight ? tightSpacing : looseSpacing
    // Between a value and its unit, close enough that they read as one.
    readonly property real unitGap: Math.round(Kirigami.Units.smallSpacing * 0.75)
    readonly property real markerWidth: markerRoom(drawn)
    // Room for the widest value and unit at the size drawn. Bits move to the
    // next unit at 999.5, so they never need a fourth digit, though "99.9"
    // can be wider than "999"; bytes can show 1023.
    readonly property real valueRoom: drawn.room(drawn.plain, !vertical ? (bits ? [Format.whole(999), Format.decimal(99.9, 1)] : [Format.whole(1000)])
                                                             : [whole ? Format.whole(100) + "M" : Format.whole(1000) + "M"])
    // Units differ in length: b/s and Mb/s, B/s and MiB/s.
    readonly property real unitRoom: drawn.room(drawn.plain, bits ? ["b/s", "kb/s", "Mb/s", "Gb/s", "Tb/s"]
                                                                  : ["B/s", "KiB/s", "MiB/s", "GiB/s", "TiB/s", "PiB/s"])
    // The wider of the two values and of the two units now shown.
    readonly property real valuesWidth: drawn.room(drawn.plain, [lines[0].value, lines[1].value])
    readonly property real unitsWidth: drawn.room(drawn.plain, [lines[0].unit, lines[1].unit])
    // A rate with room for the widest value and unit, rounded up to a whole
    // pixel as the layout rounds each rate.
    readonly property real rateRoom: Math.ceil(markerWidth + markerGap + valueRoom + (vertical ? 0 : unitGap + unitRoom))
    readonly property real reservedWidth: singleRow ? 2 * rateRoom + columnSpacing : rateRoom
    // Horizontally each row is a ring's line; a vertical panel spaces its own.
    readonly property real rowHeight: vertical ? -1 : drawn.lineHeight

    columns: singleRow ? 2 : 1
    rowSpacing: vertical ? Math.round(Kirigami.Units.smallSpacing * 0.75) : 0
    // Between the two rates side by side.
    columnSpacing: looseSpacing + Kirigami.Units.smallSpacing

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
            id: rate

            required property int index
            readonly property var reading: rates.lines[index]
            // Side by side, a letter's marker is as wide as the letter, so the
            // first rate starts at the cell's padding; stacked, both take the
            // wider one, so the values line up.
            readonly property real markerWidth: rates.singleRow && !rates.network
                ? drawn.room(drawn.plain, [index === 1 ? rates.writeLetter : rates.readLetter]) : rates.markerWidth
            // Stacked, both rates take the wider value and unit; side by
            // side, each its own.
            readonly property real valueWidth: rates.vertical ? rates.valueRoom
                                             : rates.singleRow ? drawn.room(drawn.plain, [reading.value]) : rates.valuesWidth
            readonly property real unitWidth: rates.vertical ? 0
                                            : rates.singleRow ? drawn.room(drawn.plain, [reading.unit]) : rates.unitsWidth

            Layout.row: rates.singleRow ? 0 : index
            Layout.column: rates.singleRow ? index : 0
            implicitWidth: markerWidth + rates.markerGap + valueWidth + (rates.vertical ? 0 : rates.unitGap + unitWidth)
            implicitHeight: rates.vertical ? value.implicitHeight : rates.rowHeight

            Item {
                anchors.left: parent.left
                width: rate.markerWidth
                height: parent.height

                Arrow {
                    visible: rates.network
                    anchors.centerIn: parent
                    height: rates.arrowHeight(drawn)
                    up: rate.index === 1
                    color: rates.markColor
                }

                // Toward the value across the panel; along a vertical one
                // the letters line up at the start.
                Text {
                    anchors.left: rates.vertical ? parent.left : undefined
                    anchors.right: rates.vertical ? undefined : parent.right
                    visible: !rates.network
                    text: rate.index === 1 ? rates.writeLetter : rates.readLetter
                    color: rates.markColor
                    font: drawn.plain.font
                    textFormat: Text.PlainText
                }
            }

            // The value and its unit, never mirrored, beside the marker; the
            // layout's rounding up to a whole pixel falls after them. Placed
            // by x, since with mirroring off its own anchors would read left
            // to right.
            Item {
                x: rate.LayoutMirroring.enabled ? parent.width - rate.markerWidth - rates.markerGap - width
                                                : rate.markerWidth + rates.markerGap
                width: rate.valueWidth + (unit.visible ? rates.unitGap + rate.unitWidth : 0)
                height: parent.height
                LayoutMirroring.enabled: false
                LayoutMirroring.childrenInherit: true

                Text {
                    id: value
                    width: rate.valueWidth
                    height: parent.height
                    // Along a vertical panel the values line up at the end.
                    horizontalAlignment: rates.vertical && rate.LayoutMirroring.enabled ? Text.AlignLeft : Text.AlignRight
                    text: rates.vertical ? rates.verticalText(rate.reading) : rate.reading.value
                    color: Kirigami.Theme.textColor
                    font: drawn.plain.font
                    textFormat: Text.PlainText
                }

                Text {
                    id: unit
                    visible: !rates.vertical
                    anchors.left: value.right
                    anchors.leftMargin: rates.unitGap
                    height: parent.height
                    text: rate.reading.unit
                    color: Style.dim(Kirigami.Theme.textColor)
                    font: drawn.plain.font
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
