// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// A circular track with a progress arc on top, starting at twelve o'clock.
// The arc can also play the two ways a Claude or Codex weekly window starts
// over.
Shape {
    id: arc

    required property real radius
    required property real strokeWidth
    required property color color
    required property color trackColor
    // 0 to 100.
    property real percent: 0

    // What is actually drawn. These normally track the properties above; a
    // reset animation drives them directly and rebinds them when it ends, so
    // the ring always comes to rest in its ordinary state.
    property real head: percent
    property real tail: 0
    property color drawColor: color
    // 0 while resting, 1 with track and arc held at the same neutral tone.
    property real lift: 0

    readonly property bool animating: rollover.running || turn.running
    readonly property color turnTone: Qt.alpha(Kirigami.Theme.textColor, 0.62)

    width: 2 * radius + strokeWidth
    height: width
    preferredRendererType: Shape.CurveRenderer

    function mix(from, to, amount) {
        return Qt.rgba(from.r + (to.r - from.r) * amount, from.g + (to.g - from.g) * amount,
                       from.b + (to.b - from.b) * amount, from.a + (to.a - from.a) * amount);
    }

    function rest() {
        head = Qt.binding(() => arc.percent);
        tail = 0;
        drawColor = Qt.binding(() => arc.color);
        lift = 0;
    }

    // The window has started over. On schedule, the spent arc finishes its lap
    // and leaves through twelve o'clock with the new week trailing behind it;
    // when the provider reset it early, the ring dissolves to one neutral tone
    // and resolves in the colour of its new reading.
    function playReset(fromPercent, fromColor, early) {
        rollover.stop();
        turn.stop();
        head = fromPercent;
        tail = 0;
        drawColor = fromColor;
        lift = 0;
        if (early) {
            turn.start();
        } else {
            rollover.start();
        }
    }

    SequentialAnimation {
        id: rollover

        NumberAnimation { target: arc; property: "head"; to: 100; duration: 520; easing.type: Easing.InOutCubic }
        PauseAnimation { duration: 120 }
        ParallelAnimation {
            ColorAnimation { target: arc; property: "drawColor"; to: arc.color; duration: 300 }
            NumberAnimation { target: arc; property: "tail"; to: 100; duration: 720; easing.type: Easing.InOutCubic }
            NumberAnimation { target: arc; property: "head"; to: 100 + arc.percent; duration: 720; easing.type: Easing.InOutCubic }
        }
        ScriptAction { script: arc.rest() }
    }

    SequentialAnimation {
        id: turn

        NumberAnimation { target: arc; property: "lift"; to: 1; duration: 280; easing.type: Easing.OutQuad }
        // Track and arc are the same colour here, so the length change has no visible seam.
        ScriptAction { script: { arc.head = arc.percent; arc.drawColor = arc.color; } }
        PauseAnimation { duration: 90 }
        NumberAnimation { target: arc; property: "lift"; to: 0; duration: 620; easing.type: Easing.InOutQuad }
        ScriptAction { script: arc.rest() }
    }

    ShapePath {
        fillColor: "transparent"
        strokeColor: arc.mix(arc.trackColor, arc.turnTone, arc.lift)
        strokeWidth: arc.strokeWidth

        PathAngleArc {
            centerX: arc.width / 2
            centerY: arc.height / 2
            radiusX: arc.radius
            radiusY: arc.radius
            startAngle: -90
            sweepAngle: 360
        }
    }

    ShapePath {
        fillColor: "transparent"
        // A zero-length arc with round caps would still draw a dot.
        strokeColor: sweep.sweepAngle >= 1 ? arc.mix(arc.drawColor, arc.turnTone, arc.lift) : "transparent"
        strokeWidth: arc.strokeWidth
        capStyle: ShapePath.RoundCap

        PathAngleArc {
            id: sweep
            centerX: arc.width / 2
            centerY: arc.height / 2
            radiusX: arc.radius
            radiusY: arc.radius
            startAngle: -90 + 3.6 * arc.tail
            sweepAngle: 3.6 * (arc.head - arc.tail)

            Behavior on sweepAngle {
                enabled: !arc.animating
                NumberAnimation {
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
