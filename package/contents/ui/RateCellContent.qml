pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/style.js" as Style

// Two transfer rates in the panel: down and up for the network, read and
// write for the disk. Stacked, or side by side on a thin panel. The columns
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
    readonly property real basePointSize: Kirigami.Theme.smallFont.pointSize * (vertical ? 0.9 : 1.05)
    readonly property real looseSpacing: Math.round(Kirigami.Units.smallSpacing * 1.5)
    readonly property real tightSpacing: Math.round(Kirigami.Units.smallSpacing / 2)
    readonly property real markerWidth: network ? Math.round(base.height * 0.62) * 0.8 : letterSample.advanceWidth
    readonly property real decimalWidth: Math.ceil(markerWidth) + Math.ceil(decimalSample.advanceWidth)
    readonly property real wholeWidth: Math.ceil(markerWidth) + Math.ceil(wholeSample.advanceWidth)
    // Text draws a pixel or two wider than its advance (bearings, rounding).
    readonly property real room: availableWidth - 2
    readonly property bool tight: vertical && decimalWidth + looseSpacing > room
    readonly property bool whole: vertical && decimalWidth + tightSpacing > room
    readonly property real pointSize: whole
        ? Math.max(Kirigami.Theme.smallFont.pointSize * 0.6,
                   Math.min(1, (room - tightSpacing - 2) / (wholeWidth - 2)) * basePointSize)
        : basePointSize

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
        return rounded + prefix;
    }

    function rateText(reading) {
        return reading.value === "–" ? i18nc("@info:tooltip no reading", "unavailable")
                                     : i18nc("@info:tooltip a transfer rate, e.g. 24.8 Mb/s", "%1 %2", reading.value, reading.unit);
    }

    // The rates in words, for screen readers.
    readonly property string accessibleDescription: network
        ? i18nc("@info:tooltip network download and upload rates", "Down %1, up %2", rateText(lines[0]), rateText(lines[1]))
        : i18nc("@info:tooltip disk read and write rates", "Read %1, write %2", rateText(lines[0]), rateText(lines[1]))

    columns: vertical ? 2 : singleRow ? 6 : 3
    rowSpacing: Math.round(Kirigami.Units.smallSpacing * 0.75)
    columnSpacing: tight ? tightSpacing : looseSpacing

    FontMetrics {
        id: base
        font.family: Kirigami.Theme.fixedWidthFont.family
        font.pointSize: rates.basePointSize
    }

    TextMetrics {
        id: letterSample
        font: base.font
        text: rates.readLetter.length > rates.writeLetter.length ? rates.readLetter : rates.writeLetter
    }

    TextMetrics {
        id: decimalSample
        font: base.font
        text: "0000M"
    }

    TextMetrics {
        id: wholeSample
        font: base.font
        text: "000M"
    }

    // Room for the widest value and unit at the size drawn.
    TextMetrics {
        id: valueRoom
        font.family: Kirigami.Theme.fixedWidthFont.family
        font.pointSize: rates.pointSize
        text: !rates.vertical ? "0000" : rates.whole ? "000M" : "0000M"
    }

    TextMetrics {
        id: unitRoom
        font: valueRoom.font
        // Units differ in length: b/s and Mb/s, B/s and MiB/s.
        text: rates.bits ? "Mb/s" : "MiB/s"
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
            implicitHeight: letter.implicitHeight

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
                font.family: Kirigami.Theme.fixedWidthFont.family
                font.pointSize: rates.pointSize
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
            Layout.minimumWidth: Math.ceil(valueRoom.advanceWidth)
            horizontalAlignment: Text.AlignRight
            text: rates.vertical ? rates.verticalText(rates.lines[index]) : rates.lines[index].value
            color: Kirigami.Theme.textColor
            font: valueRoom.font
            textFormat: Text.PlainText
        }
    }

    Repeater {
        model: rates.vertical ? 0 : 2

        delegate: Text {
            required property int index

            Layout.row: rates.singleRow ? 0 : index
            Layout.column: rates.singleRow ? index * 3 + 2 : 2
            Layout.minimumWidth: Math.ceil(unitRoom.advanceWidth)
            text: rates.lines[index].unit
            color: Style.dim(Kirigami.Theme.textColor)
            font: valueRoom.font
            textFormat: Text.PlainText
        }
    }
}
