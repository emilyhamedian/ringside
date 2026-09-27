import QtQuick
import org.kde.kirigami as Kirigami
import "code/style.js" as Style

// A number in the monospace face with its unit after it, dimmer and
// optionally smaller, or with a small raised degree sign for temperatures.
Item {
    id: reading

    // A number and its unit read left to right in every language; mirroring
    // would put "°61" or the unit before the value.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    property string value: ""
    property string unit: ""
    // A temperature. The degree sign follows a number, not a dash or a word
    // such as "off".
    property bool degree: false
    property real pointSize: Kirigami.Theme.defaultFont.pointSize
    property real unitScale: 1
    property color color: Kirigami.Theme.textColor
    property color unitColor: Style.dim(color)
    // The widest number and unit the reading can show. Their room is kept
    // while the value is narrower, so the panel doesn't shift as it changes;
    // a temperature keeps room for its degree sign. Empty keeps nothing.
    property string widest: ""
    property string widestUnit: ""
    readonly property real numberWidth: Math.max(number.implicitWidth, Math.ceil(widestNumber.advanceWidth))
    readonly property real suffixWidth: Math.max(suffix.visible ? suffix.implicitWidth : 0, Math.ceil(widestSuffix.advanceWidth))
    baselineOffset: number.baselineOffset

    implicitWidth: numberWidth + (suffixWidth > 0 ? suffix.anchors.leftMargin + suffixWidth : 0)
    implicitHeight: number.implicitHeight

    TextMetrics {
        id: widestNumber
        font: number.font
        text: reading.widest
    }

    TextMetrics {
        id: widestSuffix
        font: suffix.font
        text: reading.widest === "" ? "" : reading.degree ? "°" : reading.widestUnit
    }

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
        text: reading.degree ? (/\d$/.test(reading.value) ? "°" : "") : reading.unit
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
