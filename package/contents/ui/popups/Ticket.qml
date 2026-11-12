// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// A ticket shape: a card with rounded corners and a half-circle notch in
// each short end, outlined and faintly filled. The Shape sits inside an Item
// so that the size the Shape computes from its path never reaches a layout,
// which would otherwise loop. The outline sits on pixel centres, so its
// straight edges stay sharp at 1x.
Item {
    id: ticket

    property color color: Kirigami.Theme.textColor
    property color fillColor: "transparent"
    property real lineWidth: 1
    property real corner: 3
    property real notch: 3

    // Where the outline's centre runs: `near` at the top and left edges,
    // `far` at the right edge and `low` at the bottom edge.
    readonly property real near: lineWidth / 2
    readonly property real far: width - near
    readonly property real low: height - near
    readonly property real middle: height / 2

    function arc(radius, sweep, x, y) {
        return " A " + radius + " " + radius + " 0 0 " + sweep + " " + x + " " + y;
    }

    // Drawn clockwise from the top left. Each corner's arc curves outward and
    // each notch's arc curves inward.
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
