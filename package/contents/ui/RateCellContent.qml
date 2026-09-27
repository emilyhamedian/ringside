pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "code/format.js" as Format

// Two transfer rates in the panel: down and up for the network, read and
// write for the disk. Stacked, or side by side on a thin panel.
GridLayout {
    id: rates

    required property var monitor
    required property string item
    required property bool vertical
    property bool singleRow: false

    readonly property bool network: item === "network"
    readonly property var lines: network
        ? [Format.rate(monitor.networkDown, monitor.networkBits), Format.rate(monitor.networkUp, monitor.networkBits)]
        : [Format.rate(monitor.diskRead, false), Format.rate(monitor.diskWrite, false)]
    readonly property real pointSize: Kirigami.Theme.smallFont.pointSize * (vertical ? 0.9 : 1.05)
    readonly property color markColor: Qt.alpha(Kirigami.Theme.textColor, 0.75)

    columns: vertical ? 2 : singleRow ? 6 : 3
    rowSpacing: Math.round(Kirigami.Units.smallSpacing * 0.75)
    columnSpacing: Math.round(Kirigami.Units.smallSpacing * 1.5)

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
                text: marker.index === 1 ? i18nc("@label short for disk writes", "W")
                                         : i18nc("@label short for disk reads", "R")
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
            horizontalAlignment: Text.AlignRight
            // On a vertical panel there is no room for a unit column.
            text: rates.lines[index].value + (rates.vertical ? rates.lines[index].unit.charAt(0).replace(/[bB]/, "") : "")
            color: Kirigami.Theme.textColor
            font.family: Kirigami.Theme.fixedWidthFont.family
            font.pointSize: rates.pointSize
            textFormat: Text.PlainText
        }
    }

    Repeater {
        model: rates.vertical ? 0 : 2

        delegate: Text {
            required property int index

            Layout.row: rates.singleRow ? 0 : index
            Layout.column: rates.singleRow ? index * 3 + 2 : 2
            text: rates.lines[index].unit
            color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
            font.family: Kirigami.Theme.fixedWidthFont.family
            font.pointSize: rates.pointSize
            textFormat: Text.PlainText
        }
    }
}
