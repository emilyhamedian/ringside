// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// A ticket's outline: a card with rounded corners and a half-round bite out
// of each short end, lined and faintly filled. An Item around the Shape, so
// the size the Shape takes from its path never reaches a layout. The line
// sits on pixel centres, so the straight edges stay sharp at 1x.
Item {
    id: ticket

    property color color: Kirigami.Theme.textColor
    property color fillColor: "transparent"
    property real lineWidth: 1
    property real corner: 3
    property real notch: 3

    // The line's centre on each side: near the top and left, far right,
    // low at the bottom.
    readonly property real near: lineWidth / 2
    readonly property real far: width - near
    readonly property real low: height - near
    readonly property real middle: height / 2

    function arc(radius, sweep, x, y) {
        return " A " + radius + " " + radius + " 0 0 " + sweep + " " + x + " " + y;
    }

    // Clockwise from the top left: each corner's arc turns outward, each
    // bite's inward.
    readonly property string outline: "M " + (near + corner) + " " + near
        + " H " + (far - corner) + arc(corner, 1, far, near + corner)
        + " V " + (middle - notch) + arc(notch, 0, far, middle + notch)
        + " V " + (low - corner) + arc(corner, 1, far - corner, low)
        + " H " + (near + corner) + arc(corner, 1, near, low - corner)
        + " V " + (middle + notch) + arc(notch, 0, near, middle - notch)
        + " V " + (near + corner) + arc(corner, 1, near + corner, near) + " Z"

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: ticket.color
            strokeWidth: ticket.lineWidth
            fillColor: ticket.fillColor
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: ticket.outline }
        }
    }
}
