// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// A hidden animation, kept out of the README, the changelog, the settings
// and the translations, and with no text of its own. Typing the Konami code
// (Up Up Down Down Left Right Left Right B A; the letters in either case)
// while the widget has keyboard focus, on a focused item in the strip or in
// any open popup, plays Prism along the strip: a band of the theme's colours
// travels from ring to ring, each ring's arc running out to a full, turning
// ring of them and drawing back to its reading. It changes only what is
// drawn: accessible names and descriptions stay as they are, and nothing is
// announced.
//
// main.qml hands watch() every key the strip and the popup see, from
// Keys.onPressed on the applet and on the popup's content. watch() only
// looks: it never accepts a key, so arrows still reach the popup's controls
// (a control that takes an arrow itself, as the span button takes Down,
// keeps it, and the code has to be typed elsewhere). A wrong key starts the
// code over, a code typed while Prism plays counts for nothing, and at
// Plasma's Instant speed nothing plays.
//
// This file is the clock: `progress` runs from 0 to 1 over `length` while
// `playing`. Each panel ring holds an Egg.Ring (RingGauge, where `egg` is
// set by the strip and is null elsewhere), which play() numbers along the
// strip, top to bottom on a vertical one, so the band can pass along it.
//
// The hook's contract: a Ring draws its colour band over the ring, and
// overrides one property of the ring itself, the inner arc's opacity, which
// dims while the band passes. It does so through a Binding whose `when`
// holds only while Prism plays, so the opacity goes back to its own binding
// afterwards; the outer arc is never overridden, so readings that arrive
// meanwhile move it as usual and the band follows them. Two traps:
// - Touch the inner arc only while the gauge's `innerOn` holds. Overriding
//   its length on a ring with no inner reading makes RingArc.drawn true,
//   which holds an inner ring the gauge doesn't have and shrinks the name.
// - Don't change the gauge's strokeWidth or radius: they set the name's
//   room (RingGauge.centreWidth), and RingName eases any change of room.
Item {
    id: egg

    // The strip the rings are in, and whether it runs down the panel.
    property Item stage: null
    property bool vertical: false
    // Off at Plasma's Instant speed. The tests turn it off to stand in.
    property bool animated: Kirigami.Units.longDuration > 1

    // In milliseconds.
    readonly property int length: 2000
    property bool playing: false
    property real progress: 0

    // The theme's accent and status colours, each once (an accent colour can
    // also be the link colour), red last.
    readonly property var colours: {
        const all = [Kirigami.Theme.highlightColor, Kirigami.Theme.linkColor, Kirigami.Theme.visitedLinkColor,
                     Kirigami.Theme.positiveTextColor, Kirigami.Theme.neutralTextColor, Kirigami.Theme.textColor,
                     Kirigami.Theme.negativeTextColor];
        const out = [];
        for (const c of all) {
            if (!out.some(o => Qt.colorEqual(o, c))) {
                out.push(c);
            }
        }
        return out;
    }

    readonly property var code: [Qt.Key_Up, Qt.Key_Up, Qt.Key_Down, Qt.Key_Down, Qt.Key_Left, Qt.Key_Right,
                                 Qt.Key_Left, Qt.Key_Right, Qt.Key_B, Qt.Key_A]
    // Held to type a capital letter, so not a wrong key.
    readonly property var modifierKeys: [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta,
                                         Qt.Key_CapsLock]
    // How much of the code the last keys typed.
    property int typed: 0

    function watch(event) {
        if (event.isAutoRepeat || modifierKeys.includes(event.key)) {
            return;
        }
        if (playing) {
            typed = 0;
            return;
        }
        // The longest start of the code the keys end with, so a third Up
        // still leaves two typed.
        const keys = code.slice(0, typed).concat(event.key);
        typed = 0;
        for (let n = keys.length; n > 0; --n) {
            if (keys.slice(-n).every((key, i) => key === code[i])) {
                typed = n;
                break;
            }
        }
        if (typed === code.length) {
            typed = 0;
            play();
        }
    }

    function play() {
        if (!animated || playing) {
            return;
        }
        arrange();
        playing = true;
        run.restart();
    }

    // Numbers the strip's shown rings along it; a hidden one sits it out.
    function arrange() {
        const rings = [];
        const visit = item => {
            if (item.clock === egg) {
                item.index = -1;
                if (item.visible) {
                    rings.push(item);
                }
            }
            for (const child of item.children) {
                visit(child);
            }
        };
        if (stage) {
            visit(stage);
        }
        const along = ring => {
            const centre = ring.mapToItem(stage, ring.width / 2, ring.height / 2);
            return vertical ? centre.y : centre.x;
        };
        rings.map(ring => [along(ring), ring]).sort((a, b) => a[0] - b[0]).forEach(([, ring], i) => ring.index = i);
    }

    // A change to Instant mid-way ends it at once.
    onAnimatedChanged: {
        if (!animated) {
            run.complete();
        }
    }

    NumberAnimation {
        id: run
        target: egg
        property: "progress"
        from: 0
        to: 1
        duration: egg.length
        onRunningChanged: {
            if (!running) {
                egg.playing = false;
            }
        }
    }

    // One ring's part, drawn over its arcs.
    component Ring: Item {
        id: ring

        required property Egg clock
        required property RingArc outerRing
        required property RingArc innerRing
        // RingGauge's own, as they are without the egg.
        required property bool innerOn
        required property real innerShown
        // Its place along the strip, from arrange(); -1 sits it out.
        property int index: -1

        readonly property bool active: clock !== null && clock.playing && index >= 0
        // Seconds since the start, and since the band reached this ring,
        // 0.12 s after the one before.
        readonly property real time: active ? clock.progress * clock.length / 1000 : 0
        readonly property real at: time - 0.12 * index
        readonly property real span: 1.45
        // How far the band is over this ring, 0 to 1: it eases in over
        // 0.4 s and out over the last 0.45 s of its pass.
        readonly property real band: at <= 0 || at >= span ? 0 : Math.min(inOut(at / 0.4), inOut((span - at) / 0.45))
        // How far round the band reaches, in percent: from the reading to
        // the whole ring.
        readonly property real extent: band > 0 ? outerRing.percent + (100 - outerRing.percent) * inOut(Math.min(1, band * 1.4)) : 0
        readonly property real spin: -90 + 330 * time + 55 * index
        readonly property int colourCount: clock ? clock.colours.length : 1

        function stopAt(k) {
            return Math.min(k, colourCount) / colourCount;
        }

        function stopColour(k) {
            return clock ? clock.colours[Math.min(k, colourCount) % colourCount] : "transparent";
        }

        function inOut(x) {
            x = Math.max(0, Math.min(1, x));
            return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
        }

        // A point `percent` round from twelve, `distance` from the middle.
        function point(distance, percent) {
            const angle = 2 * Math.PI * percent / 100;
            return (width / 2 + distance * Math.sin(angle)) + " " + (height / 2 - distance * Math.cos(angle));
        }

        function circle(distance) {
            return "M " + point(distance, 0) + " A " + distance + " " + distance + " 0 1 1 " + point(distance, 50)
                 + " A " + distance + " " + distance + " 0 1 1 " + point(distance, 0) + " Z ";
        }

        Binding {
            target: ring.innerRing
            property: "opacity"
            value: ring.innerShown * (1 - 0.6 * ring.band)
            when: ring.active && ring.innerOn
        }

        // The band over the arc and its track, filled with a turning sweep
        // of the colours.
        Shape {
            id: wheel
            anchors.fill: parent
            visible: ring.band > 0
            opacity: Math.min(1, ring.band * 2.5)
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                fillRule: ShapePath.OddEvenFill
                // Each colour once round the ring, the first again to close
                // it; stops past the colours there are pile up on that one.
                fillGradient: ConicalGradient {
                    centerX: wheel.width / 2
                    centerY: wheel.height / 2
                    angle: ring.spin
                    GradientStop { position: ring.stopAt(0); color: ring.stopColour(0) }
                    GradientStop { position: ring.stopAt(1); color: ring.stopColour(1) }
                    GradientStop { position: ring.stopAt(2); color: ring.stopColour(2) }
                    GradientStop { position: ring.stopAt(3); color: ring.stopColour(3) }
                    GradientStop { position: ring.stopAt(4); color: ring.stopColour(4) }
                    GradientStop { position: ring.stopAt(5); color: ring.stopColour(5) }
                    GradientStop { position: ring.stopAt(6); color: ring.stopColour(6) }
                    GradientStop { position: ring.stopAt(7); color: ring.stopColour(7) }
                }
                PathSvg {
                    path: {
                        const r = ring.outerRing.radius, w = ring.outerRing.strokeWidth, e = ring.extent;
                        const far = r + w / 2, near = r - w / 2;
                        if (e <= 0.1) {
                            return "";
                        }
                        if (e >= 99.9) {
                            return ring.circle(far) + ring.circle(near);
                        }
                        const large = e > 50 ? 1 : 0;
                        return "M " + ring.point(far, 0) + " A " + far + " " + far + " 0 " + large + " 1 " + ring.point(far, e)
                             + " L " + ring.point(near, e) + " A " + near + " " + near + " 0 " + large + " 0 " + ring.point(near, 0) + " Z";
                    }
                }
            }
        }
    }
}
