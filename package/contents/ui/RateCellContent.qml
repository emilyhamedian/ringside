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
// each rate is its arrow or letter, then its value and unit, each in a slot
// that fits any reading: values come in three figures (format.js panelRate),
// so they all take the room of "99.9" but those from 100, a point narrower,
// and the units the room of the widest. Values end at their slot's end, so
// the units line up after them; a shorter unit leaves its room after it. The
// value and its unit read in that order either way, as a number keeps its
// sign; only the marker moves to the other side.
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
        ? [reading(monitor.panel.networkDown, bits), reading(monitor.panel.networkUp, bits)]
        : [reading(monitor.panel.diskRead, false), reading(monitor.panel.diskWrite, false)]
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

    // Across the panel in three figures, for the fixed slots; along a
    // vertical panel as verticalText() fits it.
    function reading(bytesPerSecond, bits) {
        return vertical ? Format.rate(bytesPerSecond, bits) : Format.panelRate(bytesPerSecond, bits);
    }

    // "25M" for "24.8M", in these letters whatever KDE calls the unit in the
    // user's language. A byte rate of 1000 to 1023 in a unit of 1024 rounds
    // to 1 of the next, so it keeps to three digits.
    function verticalText(reading) {
        const prefixes = bits ? ["", "k", "M", "G", "T"] : ["", "K", "M", "G", "T", "P"];
        let scale = reading.scale;
        if (!whole || reading.value === "–") {
            return reading.value + prefixes[scale];
        }
        // format.js writes decimals in the user's locale: "24,8" in German.
        let rounded = Math.round(Number.fromLocaleString(Qt.locale(), reading.value));
        if (rounded >= 1000 && scale < prefixes.length - 1) {
            rounded = 1;
            ++scale;
        }
        return Format.whole(rounded) + prefixes[scale];
    }

    // The rates in words, for screen readers.
    readonly property string accessibleDescription: words.describe(item)

    // Between a marker and its value: across the panel twice the gap before
    // the unit, so the unit reads as the value's and the marker stands apart;
    // along a vertical panel, what fits.
    readonly property real markerGap: tight ? tightSpacing : looseSpacing
    // Between a value and its unit, close enough that they read as one.
    readonly property real unitGap: Math.round(Kirigami.Units.smallSpacing * 0.75)
    readonly property real markerWidth: markerRoom(drawn)
    // Along a vertical panel, room for the widest value at the size drawn.
    readonly property real valueRoom: drawn.room(drawn.plain, [whole ? Format.whole(100) + "M" : Format.whole(1000) + "M"])
    // Across the panel, room for any value and any unit.
    readonly property real valuesWidth: drawn.room(drawn.plain, [Format.decimal(10, 1), Format.whole(100)])
    readonly property real unitsWidth: drawn.room(drawn.plain, Format.panelRateUnits(bits))
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
            readonly property real valueWidth: rates.vertical ? rates.valueRoom : rates.valuesWidth
            readonly property real unitWidth: rates.vertical ? 0 : rates.unitsWidth

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

            // The value and its unit, never mirrored, after the marker,
            // wherever that sits; the layout's rounding up to a whole pixel
            // falls after them. Placed by x, since with mirroring off its own
            // anchors would read left to right.
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
