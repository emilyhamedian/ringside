// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// A circular track with a progress arc on top, starting at twelve o'clock.
// The arc is lit from above: shaded down the ring, lighter at the top and
// deeper at the bottom, however far round it reaches. It can also play the
// two ways a Claude or Codex weekly window starts over, and break with its
// track into eight segments for a reading that may be out of date, flat in
// one colour.
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
    readonly property bool drawn: span >= Math.max(1, 3.6 * shortest)
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
    // How much the light shows, 0 to 1: a grey ring is flat.
    property real shading: 1
    // The shaded ends of drawColor, top and bottom. A rollover moves them
    // with drawColor, since a colour part way between two levels has no
    // shading of its own.
    property color litColor: shaded(drawColor, true)
    property color deepColor: shaded(drawColor, false)
    // The gradient as drawn, which `lift` takes to the track's tone.
    readonly property color topColor: mix(litColor, turnTone, lift)
    readonly property color bottomColor: mix(deepColor, turnTone, lift)

    readonly property bool animating: rollover.running || turn.running
    readonly property color turnTone: Qt.alpha(Kirigami.Theme.textColor, 0.62)

    // The arc in Qt's angles, clockwise from three o'clock.
    readonly property real start: -90 + 3.6 * tail
    readonly property real span: 3.6 * (head - tail)
    readonly property real end: start + span
    // Qt 6.12 can stroke the arc with its gradient, which costs a good deal
    // less to redraw as the arc moves than the filled band that draws it on
    // earlier Qt. The tests turn it off to check the band.
    property bool stroked: "strokeGradient" in reading

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

    function same(a, b) {
        return Qt.colorEqual(Qt.alpha(a, 1), Qt.alpha(b, 1));
    }

    // `c` with its hue turned up to `degrees` towards `toward`'s and its
    // lightness moved by `light`. A grey has no hue to turn.
    function shade(c, toward, degrees, light) {
        let h = c.hslHue * 360;
        if (h >= 0 && toward.hslHue >= 0) {
            const d = ((toward.hslHue * 360 - h + 540) % 360) - 180;
            h = (h + Math.sign(d) * Math.min(Math.abs(d), degrees) + 360) % 360;
        }
        return Qt.hsla(Math.max(0, h) / 360, c.hslSaturation, Math.max(0, Math.min(1, c.hslLightness + light)), c.a);
    }

    // The gradient's top or bottom end for `c`. Red turns towards amber at
    // the top and towards the accent at the bottom, amber towards the
    // positive colour and towards red, and the text colour takes a faint
    // tint of the accent at the bottom. Any other colour only lightens and
    // deepens.
    function shaded(c, top) {
        const T = Kirigami.Theme;
        const lit = same(c, T.negativeTextColor) ? (top ? shade(c, T.neutralTextColor, 7, 0.03) : shade(c, T.highlightColor, 7, -0.05))
                  : same(c, T.neutralTextColor) ? (top ? shade(c, T.positiveTextColor, 6, 0.04) : shade(c, T.negativeTextColor, 6, -0.05))
                  : same(c, T.textColor) && !top ? shade(mix(c, Qt.alpha(T.highlightColor, c.a), 0.14), c, 0, -0.05)
                  : shade(c, c, 0, top ? 0.05 : -0.05);
        return mix(c, lit, shading);
    }

    // Draws in `c` at once, with the gradient to match.
    function paint(c) {
        drawColor = c;
        litColor = shaded(c, true);
        deepColor = shaded(c, false);
    }

    function rest() {
        head = Qt.binding(() => arc.percent);
        tail = 0;
        drawColor = Qt.binding(() => arc.color);
        litColor = Qt.binding(() => arc.shaded(arc.drawColor, true));
        deepColor = Qt.binding(() => arc.shaded(arc.drawColor, false));
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
        paint(fromColor);
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
            ColorAnimation { target: arc; property: "litColor"; to: arc.shaded(arc.color, true); duration: 300 }
            ColorAnimation { target: arc; property: "deepColor"; to: arc.shaded(arc.color, false); duration: 300 }
            NumberAnimation { target: arc; property: "tail"; to: 100; duration: 720; easing.type: Easing.InOutCubic }
            NumberAnimation { target: arc; property: "head"; to: 100 + arc.percent; duration: 720; easing.type: Easing.InOutCubic }
        }
        ScriptAction { script: arc.rest() }
    }

    SequentialAnimation {
        id: turn

        NumberAnimation { target: arc; property: "lift"; to: 1; duration: 280; easing.type: Easing.OutQuad }
        // Track and arc are the same colour here, so the length change has no visible seam.
        ScriptAction { script: { arc.head = arc.percent; arc.paint(arc.color); } }
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

    // Down the ring's outer edge, top to bottom, wherever the arc ends.
    LinearGradient {
        id: light
        x1: arc.width / 2
        y1: arc.height / 2 - arc.radius - arc.strokeWidth / 2
        x2: x1
        y2: arc.height / 2 + arc.radius + arc.strokeWidth / 2
        GradientStop { position: 0; color: arc.topColor }
        GradientStop { position: 1; color: arc.bottomColor }
    }

    // The arc as a round-capped stroke, where Qt can give it the gradient.
    // A zero-length arc would still draw its caps as a dot, so it draws
    // nothing.
    ShapePath {
        id: reading
        fillColor: "transparent"
        strokeColor: "transparent"
        strokeWidth: arc.strokeWidth
        capStyle: ShapePath.RoundCap

        // Bound here, since Qt 6.6 would reject the property in QML.
        Component.onCompleted: {
            if ("strokeGradient" in reading) {
                reading.strokeGradient = Qt.binding(() => arc.stroked && arc.drawn && arc.gap === 0 ? light : null);
            }
        }

        PathAngleArc {
            centerX: arc.width / 2
            centerY: arc.height / 2
            radiusX: arc.radius
            radiusY: arc.radius
            startAngle: arc.stroked ? arc.start : -90
            sweepAngle: arc.stroked ? arc.span : 0
        }
    }

    // Before Qt 6.12, the arc as a filled band in the stroke's outline:
    // along the outer edge, round the head, back along the inner edge and
    // round the tail. A whole ring is the two edges alone, as the caps would
    // overlap at twelve. Each path keeps still while the other draws, so
    // only one is rebuilt as the arc moves.
    ShapePath {
        id: band
        readonly property real start: arc.stroked ? -90 : arc.start
        readonly property real span: arc.stroked ? 0 : arc.span
        readonly property real end: start + span
        readonly property bool whole: span >= 360

        strokeColor: "transparent"
        fillColor: "transparent"
        fillRule: ShapePath.WindingFill
        fillGradient: !arc.stroked && arc.drawn && arc.gap === 0 ? light : null

        PathAngleArc {
            centerX: arc.width / 2
            centerY: arc.height / 2
            radiusX: arc.radius + arc.strokeWidth / 2
            radiusY: radiusX
            startAngle: band.start
            sweepAngle: band.span
        }
        PathAngleArc {
            moveToStart: false
            centerX: arc.width / 2 + arc.radius * Math.cos(band.end * Math.PI / 180)
            centerY: arc.height / 2 + arc.radius * Math.sin(band.end * Math.PI / 180)
            radiusX: arc.strokeWidth / 2
            radiusY: radiusX
            startAngle: band.end
            sweepAngle: band.whole ? 0 : 180
        }
        PathAngleArc {
            moveToStart: band.whole
            centerX: arc.width / 2
            centerY: arc.height / 2
            radiusX: arc.radius - arc.strokeWidth / 2
            radiusY: radiusX
            startAngle: band.end
            sweepAngle: -band.span
        }
        PathAngleArc {
            moveToStart: false
            centerX: arc.width / 2 + arc.radius * Math.cos(band.start * Math.PI / 180)
            centerY: arc.height / 2 + arc.radius * Math.sin(band.start * Math.PI / 180)
            radiusX: arc.strokeWidth / 2
            radiusY: radiusX
            startAngle: band.start + 180
            sweepAngle: band.whole ? 0 : 180
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
