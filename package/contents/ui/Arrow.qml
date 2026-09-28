// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes

// The thin down or up arrow beside a transfer rate, sized to its text. A
// Shape's implicit size follows its scaled path; wrapped in a plain Item, that
// change can't reach a layout and re-enter the scale binding.
Item {
    id: arrow

    property bool up: false
    property color color

    width: height * 0.8

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: arrow.color
            strokeWidth: 1.7 * arrow.height / 10
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            scale: Qt.size(arrow.width / 8, arrow.height / 10)

            PathSvg {
                path: arrow.up ? "M4 9.2V0.8M0.8 4.1l3.2-3.3 3.2 3.3" : "M4 0.8v8.4M0.8 5.9l3.2 3.3 3.2-3.3"
            }
        }
    }
}
