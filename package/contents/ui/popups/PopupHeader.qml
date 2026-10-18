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
    // See RingGauge: no reading to show, or the last one kept in grey.
    property bool ringCancelled: false
    property bool ringStale: false
    // Waiting for its first reading: see RingGauge.
    property bool ringLoading: false
    property bool processesLoading: false
    // Keep room for the indicator in popups that can list processes.
    property bool processesExpected: false
    // How often a system reading updates, for the ring: see RingGauge.
    property int interval: 0
    property string title: ""
    property bool titleWrapped: false
    property string subtitle: ""
    // A second line under the subtitle, in its style, for what would be lost
    // at the end of a long one.
    property string detail: ""
    property string value: ""
    property string unit: ""
    // "C" or "F" for a temperature.
    property string degreeUnit: ""
    property color valueColor: Kirigami.Theme.textColor
    // Its line stays under the headline even when empty (a CPU or NVIDIA GPU
    // that names no sensor, the dash after a weekly reset), so every
    // header's digits sit level with the title at the same height.
    property string caption: ""
    // In place of value and unit, a row of number and unit pairs set like
    // any other reading: the usage popups' "5d 18h". accessibleValue speaks
    // for the row and its caption together.
    property var parts: []
    property string accessibleValue: ""
    readonly property bool partsShown: parts.length > 0
    readonly property real ringSize: Math.round(Kirigami.Units.gridUnit * 2.9)
    // Every header lays out its parts as if it had a ring, a title and
    // subtitle, and a reading over a caption. Each part is centred on the
    // tallest of those three, whether or not this header shows it. So the
    // titles and digits of every popup sit at one height, nothing moves when
    // a reading or caption comes and goes, and a detail line hangs below the
    // subtitle instead of lifting the title.
    // A wrapped title's height follows its allotted width. Settle it after
    // horizontal layout so resizing a sibling does not re-enter its ancestors.
    property real titleHeight: 0
    Binding {
        target: header
        property: "titleHeight"
        value: titleText.implicitHeight
        delayed: header.titleWrapped
    }
    readonly property real nameHeight: titleHeight + subtitleText.implicitHeight
    readonly property real valueHeight: (partsShown ? partsRow.implicitHeight : headline.implicitHeight)
                                        + valueColumn.spacing + captionText.implicitHeight
    readonly property real bandHeight: Math.max(ringSize, nameHeight, valueHeight)
    readonly property real nameTop: Math.round((bandHeight - nameHeight) / 2)
    readonly property real valueTop: Math.round((bandHeight - valueHeight) / 2)
    // How far the caption moves to sit on the subtitle's baseline, as the
    // two columns' second lines miss by a few pixels; the digits stay level
    // with a single-line title. Applied as a transform, so moving the caption never
    // lays the row out again.
    readonly property real captionShift: Math.round(nameTop + titleText.implicitHeight + subtitleText.baselineOffset
                                                    - (valueTop + valueHeight - captionText.implicitHeight + captionText.baselineOffset))
    default property alias trailing: trailingSlot.data

    Layout.fillWidth: true
    Layout.minimumHeight: bandHeight
    Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
    Layout.rightMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
    Layout.topMargin: Math.round(Kirigami.Units.largeSpacing * 1.75)
    Layout.bottomMargin: Kirigami.Units.largeSpacing
    spacing: Math.round(Kirigami.Units.largeSpacing * 1.75)

    RingGauge {
        id: ring
        visible: header.ringShown
        Accessible.name: header.title
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Math.round((header.bandHeight - header.ringSize) / 2)
        Layout.preferredWidth: header.ringSize
        Layout.preferredHeight: header.ringSize
        strokeWidth: 4
        value: header.ringValue
        cancelled: header.ringCancelled
        stale: header.ringStale
        loading: header.ringLoading
        interval: header.interval
        // Counts with the arc, as the screen reader's value doesn't.
        text: header.ringCancelled || header.ringLoading ? "" : Number.isFinite(header.ringValue) ? i18nc("@info a percentage", "%1%", Format.percent(ring.drawnValue)) : "–"
        // "100%" needs a little more room than "62%".
        textScale: text.length > 3 ? 0.25 : 0.29
    }

    Item {
        implicitWidth: Math.max(titleRow.implicitWidth, subtitleText.implicitWidth, detailText.implicitWidth)
        implicitHeight: header.titleHeight + (subtitleText.visible ? subtitleText.implicitHeight : 0)
            + (detailText.visible ? detailText.implicitHeight : 0)
        Layout.fillWidth: true
        // A wrapped name takes the room left by the ring and reading,
        // rather than making the popup as wide as the unbroken title.
        Layout.preferredWidth: header.titleWrapped ? 0 : -1
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: header.nameTop

        Column {
            width: parent.width
            spacing: 0

            Item {
                id: titleRow
                width: parent.width
                readonly property real processSpace: header.processesExpected ? Kirigami.Units.smallSpacing + processSlot.width : 0
                implicitWidth: titleText.implicitWidth + processSpace
                implicitHeight: titleText.implicitHeight

                Kirigami.Heading {
                    id: titleText
                    anchors.left: parent.left
                    width: Math.max(0, titleRow.width - titleRow.processSpace)
                    text: header.title
                    level: 3
                    font.weight: Font.DemiBold
                    elide: header.titleWrapped ? Text.ElideNone : Text.ElideRight
                    wrapMode: header.titleWrapped ? Text.Wrap : Text.NoWrap
                    leftPadding: header.titleWrapped && header.LayoutMirroring.enabled ? 1 : 0
                    rightPadding: header.titleWrapped && !header.LayoutMirroring.enabled ? 1 : 0
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignLeft
                }

                // Reserve the slot even after loading, so the title and headline
                // reading never move when the scan finishes.
                Item {
                    id: processSlot
                    anchors.left: titleText.left
                    anchors.leftMargin: Math.min(titleText.implicitWidth, titleText.width) + Kirigami.Units.smallSpacing
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: (titleText.height / Math.max(1, titleText.lineCount) - titleText.height) / 2
                    width: 24
                    height: 24

                    ProcessesLoading {
                        anchors.centerIn: parent
                        visible: header.processesLoading
                    }
                }
            }

            Text {
                id: subtitleText
                width: parent.width
                visible: text !== ""
                text: header.subtitle
                color: Style.dim(Kirigami.Theme.textColor)
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
                elide: Text.ElideRight
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
            }

            Text {
                id: detailText
                width: parent.width
                visible: text !== ""
                text: header.detail
                color: subtitleText.color
                font: subtitleText.font
                elide: Text.ElideRight
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
            }
        }
    }

    ColumnLayout {
        id: valueColumn
        visible: header.value !== "" || header.partsShown
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: header.valueTop
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
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Math.round(Math.max(0, header.bandHeight - implicitHeight) / 2)
    }
}
