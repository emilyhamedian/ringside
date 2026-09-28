// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import "code/style.js" as Style

// A number in the monospace face with its unit after it, dimmer and
// optionally smaller. A temperature gets a small raised degree sign, or with
// `degreeUnit` set the full unit, "61 °C", like any other unit.
Item {
    id: reading

    // A number and its unit read left to right in every language; mirroring
    // would put "°61" or the unit before the value.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    property string value: ""
    property string unit: ""
    // A temperature. The caller turns this off when the value is a word such
    // as "off"; a missing reading's dash gets no sign either.
    property bool degree: false
    // "C" or "F" to spell the unit out rather than show a bare degree sign.
    property string degreeUnit: ""
    readonly property bool spelled: degree && degreeUnit !== ""
    readonly property string degreeText: spelled ? "°" + degreeUnit : "°"
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
        text: reading.widest === "" ? "" : reading.degree ? reading.degreeText : reading.widestUnit
    }

    // Kirigami.Theme.fixedWidthFont arrived in KF 6.14; before that the
    // fontconfig alias stands in, here and wherever digits are set.
    Text {
        id: number
        text: reading.value
        color: reading.color
        font.family: Kirigami.Theme.fixedWidthFont?.family ?? "monospace" // qmllint disable redundant-optional-chaining
        font.pointSize: reading.pointSize
        textFormat: Text.PlainText
    }

    Text {
        id: suffix
        visible: text !== ""
        text: reading.degree ? (reading.value === "–" ? "" : reading.degreeText) : reading.unit
        readonly property bool raised: reading.degree && !reading.spelled
        anchors.left: number.right
        anchors.leftMargin: raised ? 0 : Math.round(reading.pointSize * 0.4)
        // The degree sign sits high in the sans face; nudge it up a little more.
        y: number.baselineOffset - baselineOffset - (raised ? number.implicitHeight * 0.1 : 0)
        color: raised ? reading.color : reading.unitColor
        font.family: reading.degree ? Kirigami.Theme.defaultFont.family : (Kirigami.Theme.fixedWidthFont?.family ?? "monospace") // qmllint disable redundant-optional-chaining
        font.pointSize: reading.pointSize * (raised ? 0.7 : reading.unitScale)
        textFormat: Text.PlainText
    }
}
