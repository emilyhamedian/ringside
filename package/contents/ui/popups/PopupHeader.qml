import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."

// Title row: a large ring, the name and hardware under it, and the headline
// reading on the right with its caption. Extra content (the network rates)
// can replace the reading.
RowLayout {
    id: header

    property bool ringShown: true
    property real ringValue: NaN
    property string title: ""
    property string subtitle: ""
    property string value: ""
    property string unit: ""
    property bool degree: false
    property color valueColor: Kirigami.Theme.textColor
    property string caption: ""
    default property alias trailing: trailingSlot.data

    Layout.fillWidth: true
    Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
    Layout.rightMargin: Math.round(Kirigami.Units.largeSpacing * 2)
    Layout.topMargin: Math.round(Kirigami.Units.largeSpacing * 1.75)
    Layout.bottomMargin: Kirigami.Units.largeSpacing
    spacing: Math.round(Kirigami.Units.largeSpacing * 1.75)

    RingGauge {
        visible: header.ringShown
        Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 2.9)
        Layout.preferredHeight: Layout.preferredWidth
        strokeWidth: 4
        value: header.ringValue
        text: Number.isFinite(header.ringValue) ? Math.round(header.ringValue) + "%" : "–"
        textScale: 0.29
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Kirigami.Heading {
            Layout.fillWidth: true
            text: header.title
            level: 3
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }

        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: header.subtitle
            color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }

    ColumnLayout {
        visible: header.value !== ""
        spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)

        Reading {
            id: headline
            Layout.alignment: Qt.AlignRight
            value: header.value
            unit: header.unit
            degree: header.degree
            color: header.valueColor
            pointSize: Kirigami.Theme.defaultFont.pointSize * 1.7
        }

        Text {
            Layout.alignment: Qt.AlignRight
            // Line the caption up with the digits; the degree sign hangs past them.
            Layout.rightMargin: headline.implicitWidth - headline.numberWidth
            visible: text !== ""
            text: header.caption
            color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.98
            font.letterSpacing: Kirigami.Theme.smallFont.pointSize * 0.08
            textFormat: Text.PlainText
        }
    }

    ColumnLayout {
        id: trailingSlot
        visible: children.length > 0
    }
}
