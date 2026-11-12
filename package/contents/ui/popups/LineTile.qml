// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A tile with a caption at the start of one row and a reading at the end,
// laid out like a bar's label and percentage. The reading's digits are
// centred vertically in the row. If the caption and the reading don't fit
// side by side, the reading moves under the caption. Put the reading inside
// the tile and name it in `reading`: the tile positions it, and uses its
// size and baseline.
Rectangle {
    id: tile

    property string caption: ""
    property Item reading: null
    // The height of the reading's digits, used to centre them.
    property real readingCap: 0
    // The row's minimum height, so that tiles stacked one above another can
    // share a height whatever they contain.
    property real minimumRowHeight: 0
    // Whether to draw two short dashes before the reading, like a piece of
    // the graph's dashed run-out line, to show that the reading is the time
    // that line marks.
    property bool keyed: false
    property color keyColor: Kirigami.Theme.textColor
    // Whether screen readers read the caption on its own. A line that gives
    // itself an accessible name covering its caption, as the credits line
    // does, sets this to false so the caption isn't read twice.
    property bool captionRead: true
    default property alias content: holder.data

    readonly property real horizontalPadding: Math.round(Kirigami.Units.largeSpacing * 1.5)
    readonly property real verticalPadding: Kirigami.Units.largeSpacing
    // The gap between the caption and the reading.
    readonly property real gap: Kirigami.Units.largeSpacing * 2
    readonly property real keyWidth: keyed ? 2 + Kirigami.Units.smallSpacing + 2 : 0
    readonly property real rowHeight: Math.max(minimumRowHeight, reading ? Math.ceil(reading.implicitHeight) : 0)
    readonly property real readingWidth: reading ? Math.ceil(reading.implicitWidth) : 0
    // Worked out from the text widths and the tile's width only, never from
    // positions, so laying out the row can't change it.
    readonly property bool stacked: keyWidth + Math.ceil(captionRoom.advanceWidth) + gap + readingWidth > width - 2 * horizontalPadding
    readonly property real captionGap: Math.round(Kirigami.Units.smallSpacing / 2)
    // The reading's y within its row, which centres its digits vertically.
    readonly property real readingY: reading ? Math.round(rowHeight / 2 - (reading.baselineOffset - readingCap / 2)) : 0
    readonly property real rowTop: stacked ? captionText.implicitHeight + captionGap : 0
    readonly property bool mirrored: LayoutMirroring.enabled

    // Converts an x measured from the start of the row (the left, or the
    // right in a right-to-left layout) to an x from the left, for an item
    // `width` wide.
    function near(x, width) {
        return mirrored ? holder.width - x - width : x;
    }

    Layout.fillWidth: true
    implicitWidth: 2 * horizontalPadding + keyWidth + Math.ceil(captionRoom.advanceWidth) + gap + readingWidth
    implicitHeight: 2 * verticalPadding + rowTop + rowHeight
    radius: Kirigami.Units.smallSpacing
    color: Qt.alpha(Kirigami.Theme.textColor, 0.05)

    TextMetrics {
        id: captionRoom
        font: captionText.font
        text: captionText.text
    }

    Item {
        id: holder
        anchors.fill: parent
        anchors.leftMargin: tile.horizontalPadding
        anchors.rightMargin: tile.horizontalPadding
        anchors.topMargin: tile.verticalPadding
        anchors.bottomMargin: tile.verticalPadding

        Caption {
            id: captionText
            readonly property real room: holder.width - (tile.stacked ? 0 : tile.gap + tile.keyWidth + tile.readingWidth)
            x: tile.near(0, room)
            // On the reading's baseline, or above the reading when stacked.
            y: tile.stacked || !tile.reading ? 0 : tile.readingY + tile.reading.baselineOffset - baselineOffset
            width: room
            label: tile.caption
            Accessible.ignored: !tile.captionRead
        }

        // Together the two dashes are about as tall as the reading's digits,
        // and centred on them.
        Column {
            visible: tile.keyed && tile.reading !== null
            x: tile.near(tile.stacked ? 0 : holder.width - tile.readingWidth - tile.keyWidth, 2)
            y: tile.reading ? Math.round(tile.rowTop + tile.readingY + tile.reading.baselineOffset - tile.readingCap / 2 - height / 2) : 0
            spacing: 2

            Repeater {
                model: 2

                Rectangle {
                    width: 1.5
                    height: 4
                    color: tile.keyColor
                }
            }
        }
    }

    Binding {
        target: tile.reading
        property: "x"
        value: tile.near(tile.stacked ? tile.keyWidth : holder.width - tile.readingWidth, tile.readingWidth)
        when: tile.reading !== null
    }

    Binding {
        target: tile.reading
        property: "y"
        value: tile.rowTop + tile.readingY
        when: tile.reading !== null
    }
}
