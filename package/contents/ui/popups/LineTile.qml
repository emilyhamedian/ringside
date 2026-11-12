// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A caption and its reading on one line of a tile's faint panel: the
// caption at the near end and the reading at the far end, as a bar's label
// and percentage are, with the reading's figures centred on the row. When
// the two don't fit on a line, the reading goes under the caption. The
// reading is the tile's child, named in `reading`; it gives its size and
// baseline, and the tile places it.
Rectangle {
    id: tile

    property string caption: ""
    property Item reading: null
    // The height of the reading's figures.
    property real readingCap: 0
    // The row is at least this tall, so rows one over the other are of a
    // height whatever they hold.
    property real minimumRowHeight: 0
    // Two dashes before the reading, a short stretch of the graph's run-out
    // line: the reading is that line's time.
    property bool keyed: false
    property color keyColor: Kirigami.Theme.textColor
    default property alias content: holder.data

    readonly property real horizontalPadding: Math.round(Kirigami.Units.largeSpacing * 1.5)
    readonly property real verticalPadding: Kirigami.Units.largeSpacing
    // Between the caption and what follows it on the row.
    readonly property real gap: Kirigami.Units.largeSpacing * 2
    readonly property real keyWidth: keyed ? 2 + Kirigami.Units.smallSpacing + 2 : 0
    readonly property real rowHeight: Math.max(minimumRowHeight, reading ? Math.ceil(reading.implicitHeight) : 0)
    readonly property real readingWidth: reading ? Math.ceil(reading.implicitWidth) : 0
    // From the texts' own widths and the tile's, never from where they are
    // placed, so placing them can't change it.
    readonly property bool stacked: keyWidth + Math.ceil(captionRoom.advanceWidth) + gap + readingWidth > width - 2 * horizontalPadding
    readonly property real captionGap: Math.round(Kirigami.Units.smallSpacing / 2)
    // The reading's top in its row, its figures' middle on the row's.
    readonly property real readingY: reading ? Math.round(rowHeight / 2 - (reading.baselineOffset - readingCap / 2)) : 0
    readonly property real rowTop: stacked ? captionText.implicitHeight + captionGap : 0
    readonly property bool mirrored: LayoutMirroring.enabled

    // An x measured from the near edge of the padded area, as the item's x
    // from the left, for `width` wide.
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
            // On the reading's baseline, or over it when stacked.
            y: tile.stacked || !tile.reading ? 0 : tile.readingY + tile.reading.baselineOffset - baselineOffset
            width: room
            label: tile.caption
        }

        // As tall together as the reading's figures, and centred on them.
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
