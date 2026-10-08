// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A captioned reading on a faint rounded panel.
Rectangle {
    id: tile

    property string caption: ""
    property string detail: ""
    // For a tile with a graph, the Monitor: the span its graphs show
    // follows the caption in place of the detail, "USAGE · 1 min", as the
    // control that changes it (SpanButton).
    property var spans: null
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

    TextMetrics {
        id: space
        font: caption.font
        text: " "
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
            // The dot and the span after the caption, each a space apart.
            readonly property real spanWidth: span.visible ? Math.ceil(2 * space.advanceWidth + dot.implicitWidth + span.implicitWidth) : 0
            visible: caption.text !== ""
            Layout.fillWidth: true
            implicitWidth: caption.implicitWidth + spanWidth + (top.text !== "" ? spacing + top.implicitWidth : 0)
            implicitHeight: caption.implicitHeight

            Caption {
                id: caption
                anchors.left: parent.left
                // With a span, as wide as its text, so the span follows it.
                // The dot is a text of its own rather than the caption's,
                // so it stays between the two in either direction.
                width: span.visible
                    ? Math.min(implicitWidth, parent.width - captionLine.spanWidth - (top.visible ? top.width + captionLine.spacing : 0))
                    : parent.width - (top.visible ? top.width + captionLine.spacing : 0)
                visible: text !== ""
                label: tile.caption
                detail: tile.spans !== null ? "" : tile.detail
            }

            Text {
                id: dot
                anchors.left: caption.right
                anchors.leftMargin: space.advanceWidth
                anchors.baseline: caption.baseline
                visible: span.visible
                text: "·"
                color: caption.color
                font: caption.font
                textFormat: Text.PlainText
            }

            SpanButton {
                id: span
                anchors.left: dot.right
                anchors.leftMargin: space.advanceWidth
                anchors.baseline: caption.baseline
                visible: tile.spans !== null
                monitor: tile.spans ?? ({ graphSpan: "minute" })
            }

            // With tabular digits, so a changing peak doesn't jostle the
            // caption beside it. The caption's detail gives way first, then
            // this, so the caption's label and its span stay whole. It shows
            // whole or not at all: a stub of a peak says nothing, and the
            // reading over the graph still gives the rate.
            Caption {
                id: top
                anchors.right: parent.right
                width: Math.max(0, Math.min(Math.ceil(implicitWidth),
                                            captionLine.width - captionLine.spacing - Math.ceil(labelRoom.advanceWidth)
                                            - captionLine.spanWidth))
                visible: text !== "" && width >= Math.ceil(implicitWidth)
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
