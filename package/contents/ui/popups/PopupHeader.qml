// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/style.js" as Style
import "../code/format.js" as Format
import ".."

// Title row: a large ring, the name and hardware under it, and the headline
// reading on the right with its caption. Extra content (the network rates)
// can replace the reading.
RowLayout {
    id: header

    property bool ringShown: true
    property real ringValue: NaN
    // Raises the ring's level past its own reading's, as a weekly limit on
    // course to run out does.
    property int ringMinimumLevel: 0
    property string title: ""
    property string subtitle: ""
    property string value: ""
    property string unit: ""
    // "C" or "F" for a temperature.
    property string degreeUnit: ""
    property color valueColor: Kirigami.Theme.textColor
    property string caption: ""
    // Keeps the caption's line under a headline that has no caption, so the
    // digits stay level with the title as they are in a header with one.
    property bool keepsCaptionLine: false
    // In place of value and unit, a row of number and unit pairs set like
    // any other reading: the usage popups' "5d 18h". accessibleValue speaks
    // for the row and its caption together.
    property var parts: []
    property string accessibleValue: ""
    readonly property bool partsShown: parts.length > 0
    // How far the caption moves to sit on the subtitle's baseline. The two
    // columns centre on the row each by its own height, so their second
    // lines miss by a few pixels; the digits stay level with the title.
    // Worked out from implicit sizes and applied as a transform, so moving
    // the caption never lays the row out again.
    readonly property real captionShift: {
        if (!subtitleText.visible || !captionText.visible) {
            return 0;
        }
        const subtitleBaseline = (titleText.implicitHeight - subtitleText.implicitHeight) / 2 + subtitleText.baselineOffset;
        const valueHeight = partsShown ? partsRow.implicitHeight : headline.implicitHeight;
        const captionBaseline = (valueHeight + valueColumn.spacing - captionText.implicitHeight) / 2 + captionText.baselineOffset;
        return Math.round(subtitleBaseline - captionBaseline);
    }
    default property alias trailing: trailingSlot.data

    Layout.fillWidth: true
    Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
    Layout.rightMargin: Math.round(Kirigami.Units.largeSpacing * 2)
    Layout.topMargin: Math.round(Kirigami.Units.largeSpacing * 1.75)
    Layout.bottomMargin: Kirigami.Units.largeSpacing
    spacing: Math.round(Kirigami.Units.largeSpacing * 1.75)

    RingGauge {
        visible: header.ringShown
        Accessible.name: header.title
        Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 2.9)
        Layout.preferredHeight: Layout.preferredWidth
        strokeWidth: 4
        value: header.ringValue
        minimumLevel: header.ringMinimumLevel
        text: Number.isFinite(header.ringValue) ? i18nc("@info a percentage", "%1%", Format.percent(header.ringValue)) : "–"
        // "100%" needs a little more room than "62%".
        textScale: text.length > 3 ? 0.25 : 0.29
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Kirigami.Heading {
            id: titleText
            Layout.fillWidth: true
            text: header.title
            level: 3
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
        }

        Text {
            id: subtitleText
            Layout.fillWidth: true
            visible: text !== ""
            text: header.subtitle
            color: Style.dim(Kirigami.Theme.textColor)
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
            elide: Text.ElideRight
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
        }
    }

    ColumnLayout {
        id: valueColumn
        visible: header.value !== "" || header.partsShown
        spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)

        Reading {
            id: headline
            visible: !header.partsShown
            Layout.alignment: Qt.AlignRight
            value: header.value
            unit: header.unit
            degreeUnit: header.degreeUnit
            color: header.valueColor
            pointSize: Kirigami.Theme.defaultFont.pointSize * 1.7
        }

        // Follows the popup's mirroring, so under RTL the largest unit sits
        // rightmost and is read first; each pair stays left to right. The
        // model is a count, so a countdown that steps keeps its Readings.
        Row {
            id: partsRow
            visible: header.partsShown
            Layout.alignment: Qt.AlignRight
            spacing: Math.round(Kirigami.Theme.defaultFont.pointSize * 1.7 * 0.45)
            Accessible.role: Accessible.StaticText
            Accessible.name: header.accessibleValue

            Repeater {
                model: header.parts.length

                delegate: Reading {
                    required property int index
                    value: header.parts[index]?.value ?? ""
                    unit: header.parts[index]?.unit ?? ""
                    color: header.valueColor
                    pointSize: Kirigami.Theme.defaultFont.pointSize * 1.7
                    // A letter right after its number: "5d", not "5 d".
                    unitSpacing: Math.round(pointSize * 0.08)
                    accessibleIgnored: true
                }
            }
        }

        Text {
            id: captionText
            Layout.alignment: Qt.AlignRight
            // Line the caption up with the digits; the unit hangs past them.
            // The reading stays left to right under RTL, so there the digits
            // already start at the caption's edge.
            Layout.rightMargin: header.partsShown || header.LayoutMirroring.enabled
                ? 0 : headline.implicitWidth - headline.numberWidth
            visible: text !== "" || header.keepsCaptionLine
            Accessible.ignored: header.partsShown || text === ""
            text: header.caption
            color: Style.dim(Kirigami.Theme.textColor)
            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.98
            font.letterSpacing: Kirigami.Theme.smallFont.pointSize * 0.08
            textFormat: Text.PlainText
            transform: Translate { y: header.captionShift }
        }
    }

    ColumnLayout {
        id: trailingSlot
        visible: children.length > 0
    }
}
