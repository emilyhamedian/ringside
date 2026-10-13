// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../code/style.js" as Style

// Stands over a process list's rows, centred, until it has readings.
PlasmaComponents.BusyIndicator {
    anchors.centerIn: parent
    width: Kirigami.Units.iconSizes.smallMedium
    height: width
    Accessible.name: i18nc("@info:status the top processes are being read", "Loading top processes")

    // The theme's own indicator is drawn in its accent colour, which
    // a widget can't change, so this stands in for it in the dim
    // text colour of the popup's captions. Like the theme's, it
    // holds still when animations are off or the window is hidden.
    contentItem: Shape {
        id: spinner

        readonly property real stroke: Math.max(1, width / 13)
        readonly property bool turning: visible && Window.visibility !== Window.Hidden
            && Style.animated(Kirigami.Units)

        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: implicitWidth
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Style.dim(Kirigami.Theme.textColor)
            strokeWidth: spinner.stroke
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: spinner.width / 2
                centerY: spinner.height / 2
                radiusX: Math.min(spinner.width, spinner.height) * 0.43 - spinner.stroke / 2
                radiusY: radiusX
                startAngle: 0
                sweepAngle: 270
            }
        }

        // The theme's fixed two seconds a turn: it doesn't follow
        // the animation speed.
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: 2000
            loops: Animation.Infinite
            running: spinner.turning
        }
    }
}
