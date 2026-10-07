// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format

// A captioned reading on a faint rounded panel.
Rectangle {
    id: tile

    property string caption: ""
    property string detail: ""
    // The time the tile's graph spans, shown after the caption in place of
    // the detail: "USAGE · 60 s", "USAGE · 2 min".
    property int graphSeconds: 0
    // What the top of the tile's graph stands for, at the far end of the
    // caption line over the top's end, outside the graph so that no line
    // runs through it: "100%", "peak 24.8 Mb/s".
    property string graphTop: ""
    // The text the content ends on, such as a reading, if it doesn't end on
    // a graph: its line has room for descenders below its ink.
    property Item foot: null
    default property alias content: body.data

    readonly property real horizontalPadding: Math.round(Kirigami.Units.largeSpacing * 1.5)
    readonly property real verticalPadding: Math.round(Kirigami.Units.largeSpacing * 1.25)
    // The caption's line box has room for accents over its capitals. Half
    // of that comes off the top padding; the ink at the foot, a graph's
    // floor or a text's baseline, sits as far from the bottom as the
    // capitals then sit from the top. Worked out from the fonts, never from
    // the content's layout, so the tile's height can't feed back into it.
    readonly property real topTrim: caption.visible ? Math.round((captionMetrics.ascent - capHeight) / 2) : 0
    readonly property real inkInset: verticalPadding + (caption.visible ? captionMetrics.ascent - capHeight - topTrim : 0)
    readonly property real bottomPadding: Math.max(0, Math.round(inkInset - (foot ? foot.implicitHeight - foot.baselineOffset : 0)))
    // capitalHeight needs Qt 6.9; the ink of "H" stands in before that.
    readonly property real capHeight: captionMetrics.capitalHeight ?? capSample.tightBoundingRect.height // qmllint disable missing-property

    Layout.fillWidth: true
    implicitWidth: column.implicitWidth + 2 * horizontalPadding
    implicitHeight: column.implicitHeight + verticalPadding - topTrim + bottomPadding
    radius: Kirigami.Units.smallSpacing
    color: Qt.alpha(Kirigami.Theme.textColor, 0.05)

    FontMetrics {
        id: captionMetrics
        font: caption.font
    }

    TextMetrics {
        id: capSample
        font: caption.font
        text: "H"
    }

    // The caption's label, and an ellipsis when its detail is cut off.
    TextMetrics {
        id: labelRoom
        font: caption.font
        text: caption.label.toLocaleUpperCase() + (caption.detail !== "" ? "…" : "")
    }

    ColumnLayout {
        id: column

        // Anchored at the top rather than filling the tile, whose height comes
        // from this layout's: Qt 6.6 rearranges a layout as soon as its height
        // changes, and when the content depends on the tile's width (the CPU
        // popup's bar rows) that re-enters the tile's implicitHeight binding.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: tile.horizontalPadding
        anchors.rightMargin: tile.horizontalPadding
        anchors.topMargin: tile.verticalPadding - tile.topTrim
        spacing: Math.round(Kirigami.Units.smallSpacing / 2)

        // Placed by hand rather than by a RowLayout: the room left for the
        // graph's top depends on the line's width, which a layout would feed
        // back into the tile's.
        Item {
            id: captionLine
            readonly property real spacing: Kirigami.Units.largeSpacing
            visible: caption.text !== ""
            Layout.fillWidth: true
            implicitWidth: caption.implicitWidth + (top.text !== "" ? spacing + top.implicitWidth : 0)
            implicitHeight: caption.implicitHeight

            Caption {
                id: caption
                anchors.left: parent.left
                width: parent.width - (top.visible ? top.width + captionLine.spacing : 0)
                visible: text !== ""
                label: tile.caption
                detail: {
                    if (tile.graphSeconds <= 0) {
                        return tile.detail;
                    }
                    const minutes = Format.spanMinutes(tile.graphSeconds);
                    return "· " + (minutes > 0
                        ? i18nc("@title:group time a graph spans, as in USAGE · 2 min", "%1 min", minutes)
                        : i18nc("@title:group time a graph spans, as in USAGE · 60 s", "%1 s", tile.graphSeconds));
                }
            }

            // With tabular digits, so a changing peak doesn't jostle the
            // caption beside it. The caption's detail gives way first, then
            // this, so the caption's label stays whole.
            Caption {
                id: top
                anchors.right: parent.right
                width: Math.max(0, Math.min(Math.ceil(implicitWidth),
                                            captionLine.width - captionLine.spacing - Math.ceil(labelRoom.advanceWidth)))
                visible: text !== ""
                text: tile.graphTop
                font.features: ({ "tnum": 1 })
                horizontalAlignment: Text.AlignRight
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
        }
    }
}
