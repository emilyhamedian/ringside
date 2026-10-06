// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/style.js" as Style

// A number in the theme's face with its unit after it, smaller and dimmer
// and on the same baseline: "4.61 GHz", the countdown's "5d". A temperature's
// "°C" hangs from the top of the digits instead.
// Tabular figures keep the number's width as its digits change, without the
// monospace face's full-width decimal point.
Item {
    id: reading

    // A number and its unit read left to right in every language; mirroring
    // would put "°61" or the unit before the value.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    property string value: ""
    property string unit: ""
    // "C" or "F" for a temperature, set as "°C" at the small font's size
    // close to the digits, since the degree sign brings its own space, with
    // the letter's top level with theirs. A missing reading's dash gets no
    // unit.
    property string degreeUnit: ""
    property real pointSize: Kirigami.Theme.defaultFont.pointSize
    property color color: Kirigami.Theme.textColor
    property color unitColor: Style.dim(color)
    property real unitSpacing: degreeUnit !== "" ? Math.round(Kirigami.Theme.smallFont.pointSize * 0.25) : Style.unitGap(pointSize)
    // Tabular digits are centred in cells of one width, so a narrow last
    // digit such as "1" would leave the degree sign standing apart. The sign
    // keeps the distance from the last digit's ink that it has after a "0",
    // and only the sign moves: the width stays the one after a "0", so the
    // digits of a right-aligned reading hold still as they change.
    readonly property real degreeShift: degreeUnit !== "" ? trailingRoom(zero) - trailingRoom(lastDigit) : 0
    // The heights of a "1" in the locale's digits and of an "H" in the
    // unit's face, whose flat tops the unit lines up. Measured rather than
    // taken from the font's cap height: Arabic-Indic digits are shorter than
    // capitals, and hinting rounds each height to whole pixels.
    readonly property real figureHeight: -figureSample.tightBoundingRect.y
    readonly property real capHeight: -capSample.tightBoundingRect.y
    // The window's scale: with Wayland's fractional scaling the screen
    // reports 2 at 125 %. Qt 6.6 knows only the screen's.
    readonly property real ratio: Window.window?.devicePixelRatio ?? Screen.devicePixelRatio // qmllint disable missing-property
    // How far the unit's baseline sits above the digits', in whole pixels of
    // the screen, so that the two rows of glyphs round the same way.
    readonly property real degreeLift: degreeUnit !== "" ? Math.round((figureHeight - capHeight) * ratio) / ratio : 0
    // Set when a parent speaks for several readings at once.
    property bool accessibleIgnored: false
    readonly property real numberWidth: number.implicitWidth
    readonly property real suffixWidth: suffix.visible ? suffix.implicitWidth : 0
    baselineOffset: number.baselineOffset

    implicitWidth: numberWidth + (suffixWidth > 0 ? unitSpacing + suffixWidth : 0)
    implicitHeight: number.implicitHeight

    function trailingRoom(metrics) {
        return metrics.text === "" ? 0 : metrics.advanceWidth - metrics.tightBoundingRect.x - metrics.tightBoundingRect.width;
    }

    TextMetrics {
        id: lastDigit
        font: number.font
        text: reading.degreeUnit !== "" ? reading.value.slice(-1) : ""
    }

    TextMetrics {
        id: zero
        font: number.font
        text: reading.degreeUnit !== "" ? "0" : ""
    }

    TextMetrics {
        id: figureSample
        font: number.font
        text: reading.degreeUnit !== "" ? Format.whole(1) : ""
    }

    TextMetrics {
        id: capSample
        font: suffix.font
        text: reading.degreeUnit !== "" ? "H" : ""
    }

    Text {
        id: number
        text: reading.value
        color: reading.color
        font.family: Kirigami.Theme.defaultFont.family
        font.features: ({ "tnum": 1 })
        font.pointSize: reading.pointSize
        textFormat: Text.PlainText
        Accessible.ignored: reading.accessibleIgnored
    }

    Text {
        id: suffix
        visible: text !== ""
        text: reading.degreeUnit === "" ? reading.unit : reading.value === "–" ? "" : "°" + reading.degreeUnit
        anchors.left: number.right
        anchors.leftMargin: reading.unitSpacing + reading.degreeShift
        // Hanging from the digits' top keeps the smaller unit inside the
        // number's line box, so the reading is no taller.
        y: number.baselineOffset - baselineOffset - reading.degreeLift
        color: reading.unitColor
        font.family: Kirigami.Theme.defaultFont.family
        font.features: ({ "tnum": 1 })
        font.pointSize: reading.degreeUnit !== "" ? Kirigami.Theme.smallFont.pointSize
                                                  : Style.unitPointSize(reading.pointSize, Kirigami.Theme.smallFont.pointSize)
        textFormat: Text.PlainText
        Accessible.ignored: reading.accessibleIgnored
    }
}
