// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// A circular track with a progress arc on top, starting at twelve o'clock.
// The arc can also play the two ways a Claude or Codex weekly window starts
// over, and break with its track into eight segments for a reading that may
// be out of date.
Shape {
    id: arc

    required property real radius
    required property real strokeWidth
    required property color color
    required property color trackColor
    // 0 to 100, drawn as given: RingGauge moves it.
    property real percent: 0
    // The shortest arc drawn, in percent. An arc unwinding to no reading
    // draws nothing once it is shorter than its width, where its round caps
    // would leave a dot.
    property real shortest: 0
    readonly property bool drawn: sweep.sweepAngle >= Math.max(1, 3.6 * shortest)
    // How much of the track is drawn, 0 to 1 clockwise from twelve: less
    // than all while it fills in over a waiting ring's dots (RingGauge).
    property real trackSweep: 1
    // The share of each eighth of the ring left open, track and arc alike;
    // 0 draws them whole.
    property real gap: 0

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

    // Only implicit: a gauge stretches its arcs over itself, which keeps
    // them on its exact centre, and a set size would fight that.
    implicitWidth: 2 * radius + strokeWidth
    implicitHeight: implicitWidth
    preferredRendererType: Shape.CurveRenderer

    function mix(from, to, amount) {
        return Qt.rgba(from.r + (to.r - from.r) * amount, from.g + (to.g - from.g) * amount,
                       from.b + (to.b - from.b) * amount, from.a + (to.a - from.a) * amount);
    }

    // SVG path data for the segments between two points, in percent from
    // twelve, which may run past 100 as a rollover's head does.
    function segments(from, to) {
        const slot = 100 / 8;
        const point = p => {
            const angle = 2 * Math.PI * p / 100;
            return (width / 2 + radius * Math.sin(angle)) + " " + (height / 2 - radius * Math.cos(angle));
        };
        let d = "";
        for (let i = Math.floor(from / slot); i * slot < to; ++i) {
            const a = Math.max(from, i * slot);
            const b = Math.min(to, (i + 1 - gap) * slot);
            if (b > a) {
                d += "M " + point(a) + " A " + radius + " " + radius + " 0 0 1 " + point(b) + " ";
            }
        }
        return d;
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
        strokeColor: arc.trackSweep > 0 && arc.gap === 0 ? arc.mix(arc.trackColor, arc.turnTone, arc.lift) : "transparent"
        strokeWidth: arc.strokeWidth
        // A part track ends square where the dots take over.
        capStyle: arc.trackSweep < 1 ? ShapePath.FlatCap : ShapePath.SquareCap

        PathAngleArc {
            centerX: arc.width / 2
            centerY: arc.height / 2
            radiusX: arc.radius
            radiusY: arc.radius
            startAngle: -90
            sweepAngle: 360 * arc.trackSweep
        }
    }

    ShapePath {
        fillColor: "transparent"
        // A zero-length arc with round caps would still draw a dot.
        strokeColor: arc.drawn && arc.gap === 0 ? arc.mix(arc.drawColor, arc.turnTone, arc.lift) : "transparent"
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
        }
    }

    // The broken ring: flat ends, so each gap shows as cut.
    ShapePath {
        fillColor: "transparent"
        strokeColor: arc.gap > 0 && arc.trackSweep > 0 ? arc.mix(arc.trackColor, arc.turnTone, arc.lift) : "transparent"
        strokeWidth: arc.strokeWidth
        capStyle: ShapePath.FlatCap

        PathSvg {
            path: arc.gap > 0 ? arc.segments(0, 100 * arc.trackSweep) : ""
        }
    }

    ShapePath {
        fillColor: "transparent"
        strokeColor: arc.gap > 0 && arc.drawn ? arc.mix(arc.drawColor, arc.turnTone, arc.lift) : "transparent"
        strokeWidth: arc.strokeWidth
        capStyle: ShapePath.FlatCap

        PathSvg {
            path: arc.gap > 0 && arc.drawn ? arc.segments(arc.tail, arc.head) : ""
        }
    }
}
