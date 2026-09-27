import QtQuick
import org.kde.kirigami as Kirigami

// A number in the monospace face with its unit after it, dimmer and
// optionally smaller, or with a small raised degree sign for temperatures.
Item {
    id: reading

    property string value: ""
    property string unit: ""
    property bool degree: false
    property real pointSize: Kirigami.Theme.defaultFont.pointSize
    property real unitScale: 1
    property color color: Kirigami.Theme.textColor
    property color unitColor: Qt.alpha(color, 0.6)
    readonly property real numberWidth: number.implicitWidth
    baselineOffset: number.baselineOffset

    implicitWidth: number.implicitWidth + (suffix.visible ? suffix.anchors.leftMargin + suffix.implicitWidth : 0)
    implicitHeight: number.implicitHeight

    Text {
        id: number
        text: reading.value
        color: reading.color
        font.family: Kirigami.Theme.fixedWidthFont.family
        font.pointSize: reading.pointSize
        textFormat: Text.PlainText
    }

    Text {
        id: suffix
        visible: text !== ""
        text: reading.degree ? (reading.value === "–" ? "" : "°") : reading.unit
        anchors.left: number.right
        anchors.leftMargin: reading.degree ? 0 : Math.round(reading.pointSize * 0.4)
        // The degree sign sits high in the sans face; nudge it up a little more.
        y: number.baselineOffset - baselineOffset - (reading.degree ? number.implicitHeight * 0.1 : 0)
        color: reading.degree ? reading.color : reading.unitColor
        font.family: reading.degree ? Kirigami.Theme.defaultFont.family : Kirigami.Theme.fixedWidthFont.family
        font.pointSize: reading.pointSize * (reading.degree ? 0.7 : reading.unitScale)
        textFormat: Text.PlainText
    }
}
