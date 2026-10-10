// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"

// A ring's arc, lit from above: its gradient's ends for each level, flat
// on a grey or struck ring and while a reset holds it at the track's tone,
// drawn lighter at the top than at the bottom, and an outline that is the
// round-capped stroke's it replaced, from no arc to a whole ring. Each
// check that draws runs on the filled band, and on Qt 6.12 and later also
// on the stroke that carries the gradient there.
Item {
    id: root
    width: 400
    height: 400

    // grabImage() reads the window, so the arcs are drawn over black.
    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    function i18nc(context, text, ...args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }

    Component {
        id: arcComponent
        RingArc {
            width: 2 * radius + strokeWidth + 4
            height: width
            radius: 17
            strokeWidth: 3
            color: Kirigami.Theme.negativeTextColor
            trackColor: "transparent"
        }
    }

    // The arc as it was drawn before it was shaded: one round-capped
    // stroke, with nothing for an arc shorter than `shortest`.
    Component {
        id: strokeComponent
        Shape {
            id: stroke
            property real radius
            property real strokeWidth
            property real head
            property real tail
            property real shortest
            readonly property real sweep: 3.6 * (head - tail)
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: stroke.sweep >= Math.max(1, 3.6 * stroke.shortest) ? "white" : "transparent"
                strokeWidth: stroke.strokeWidth
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: stroke.width / 2
                    centerY: stroke.height / 2
                    radiusX: stroke.radius
                    radiusY: stroke.radius
                    startAngle: -90 + 3.6 * stroke.tail
                    sweepAngle: stroke.sweep
                }
            }
        }
    }

    Component {
        id: gaugeComponent
        RingGauge {
            width: 38
            height: 38
            value: 95
            inner: true
            innerValue: 80
        }
    }

    Component {
        id: samplerComponent
        FrameAnimation {
            property var sample: null
            running: true
            onTriggered: sample()
        }
    }

    TestCase {
        name: "Ring"
        when: windowShown

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }

        // From `a`'s hue to `b`'s, in degrees, the short way round.
        function turn(a, b) {
            return ((b.hslHue * 360 - a.hslHue * 360 + 540) % 360) - 180;
        }

        function near(a, b, within, what) {
            verify(Math.abs(a - b) <= within, what + ": " + a + " vs " + b);
        }

        // `end` is `from` with its hue turned `degrees` towards `toward`
        // (up to the whole way) and its lightness moved by `light`.
        function shaded(end, from, toward, degrees, light, what) {
            const d = turn(from, toward);
            near(turn(from, end), Math.sign(d) * Math.min(Math.abs(d), degrees), 0.5, what + " hue");
            near(end.hslSaturation, from.hslSaturation, 0.01, what + " saturation");
            near(end.hslLightness, Math.max(0, Math.min(1, from.hslLightness + light)), 0.006, what + " lightness");
            near(end.a, from.a, 0.002, what + " alpha");
        }

        function same(a, b, what) {
            verify(["r", "g", "b", "a"].every(k => Math.abs(a[k] - b[k]) < 0.002), what + ": " + a + " vs " + b);
        }

        function test_ends_data() {
            const T = Kirigami.Theme;
            const purple = Qt.rgba(0.56, 0.27, 0.68, 1);
            return [
                { tag: "red", color: T.negativeTextColor, top: [T.neutralTextColor, 7, 0.03], bottom: [T.highlightColor, 7, -0.05] },
                { tag: "amber", color: T.neutralTextColor, top: [T.positiveTextColor, 6, 0.04], bottom: [T.negativeTextColor, 6, -0.05] },
                { tag: "normal", color: T.textColor, top: [T.textColor, 0, 0.05], tint: true },
                // An inner ring's, at its own opacity.
                { tag: "inner red", color: Qt.alpha(T.negativeTextColor, 0.55), top: [T.neutralTextColor, 7, 0.03], bottom: [T.highlightColor, 7, -0.05] },
                { tag: "inner normal", color: Qt.alpha(T.textColor, 0.55), top: [T.textColor, 0, 0.05], tint: true },
                // A colour of a gauge's own only lightens and deepens.
                { tag: "custom", color: purple, top: [purple, 0, 0.05], bottom: [purple, 0, -0.05] }
            ];
        }

        function test_ends(data) {
            const arc = createTemporaryObject(arcComponent, root, { color: data.color });
            same(arc.drawColor, data.color, "drawColor is the level's");
            shaded(arc.topColor, data.color, data.top[0], data.top[1], data.top[2], "top");
            if (data.tint) {
                // The text colour takes a faint tint of the accent at the bottom.
                const tinted = arc.mix(data.color, Qt.alpha(Kirigami.Theme.highlightColor, data.color.a), 0.14);
                shaded(arc.bottomColor, tinted, tinted, 0, -0.05, "bottom");
                verify(Math.abs(turn(arc.bottomColor, Kirigami.Theme.highlightColor)) < Math.abs(turn(data.color, Kirigami.Theme.highlightColor))
                       || data.color.hslHue < 0, "tinted towards the accent");
            } else {
                shaded(arc.bottomColor, data.color, data.bottom[0], data.bottom[1], data.bottom[2], "bottom");
            }
            verify(arc.topColor.hslLightness > arc.bottomColor.hslLightness, "lighter at the top");
        }

        // A reset's neutral tone holds the arc flat, the track's colour.
        function test_liftIsFlat() {
            const arc = createTemporaryObject(arcComponent, root, { trackColor: Qt.alpha(Kirigami.Theme.textColor, 0.16) });
            arc.lift = 1;
            same(arc.topColor, arc.turnTone, "top");
            same(arc.bottomColor, arc.turnTone, "bottom");
            arc.lift = 0.5;
            verify(arc.topColor.hslLightness > arc.bottomColor.hslLightness, "shaded on the way");
        }

        // Out of date: the arc breaks into flat grey segments in place of
        // its shaded stroke or band, and the ends meet.
        function test_greyIsFlat() {
            const gauge = createTemporaryObject(gaugeComponent, root);
            root.arcs(gauge).forEach(arc => compare(root.painted(arc), 1, "shaded while current"));
            gauge.stale = true;
            tryCompare(gauge, "greyed", 1, 2000);
            for (const arc of root.arcs(gauge)) {
                compare(arc.shading, 0);
                same(arc.topColor, arc.drawColor, "top");
                same(arc.bottomColor, arc.drawColor, "bottom");
                compare(root.painted(arc), 0, "the segments draw it");
            }
        }

        // Struck: the arcs unwind as they grey, and the light fades with
        // the colour, leaving the ends flat once grey.
        function test_struckIsFlat() {
            const gauge = createTemporaryObject(gaugeComponent, root);
            waitForRendering(gauge);
            const outer = root.arcs(gauge)[0];
            const seen = [];
            createTemporaryObject(samplerComponent, root, {
                sample: () => seen.push([gauge.greyed, outer.drawn, outer.topColor.hslLightness - outer.bottomColor.hslLightness,
                                         String(outer.topColor), String(outer.bottomColor)])
            });
            gauge.cancelled = true;
            tryCompare(gauge, "greyed", 1, 3000);
            tryCompare(outer, "percent", 0, 3000);
            wait(50);
            const what = JSON.stringify(seen);
            verify(seen.some(([greyed, drawn]) => greyed > 0.5 && drawn), "unwinding as it greys: " + what);
            verify(seen.every(([, , light], i) => i === 0 || light <= seen[i - 1][2] + 0.002), "the light fades: " + what);
            verify(seen.filter(([greyed]) => greyed === 1).every(([, , , top, bottom]) => top === bottom), what);
            compare(seen[seen.length - 1][0], 1);
        }

        // The ways this Qt draws an arc: the band, and the stroke if it can
        // take a gradient.
        function ways() {
            const arc = createTemporaryObject(arcComponent, root);
            return arc.stroked ? [false, true] : [false];
        }

        function test_drawnLitFromAbove_data() {
            return ways().map(stroked => ({ tag: stroked ? "stroke" : "band", stroked: stroked }));
        }

        // The arc is drawn with the gradient: lighter at twelve than at six.
        function test_drawnLitFromAbove(data) {
            const arc = createTemporaryObject(arcComponent, root, { radius: 40, strokeWidth: 10, percent: 100, stroked: data.stroked });
            waitForRendering(arc);
            let image = grabImage(arc);
            const c = Math.floor(arc.width / 2);
            const top = image.pixel(c, c - arc.radius), bottom = image.pixel(c, c + arc.radius);
            verify(top.hslLightness - bottom.hslLightness > 0.05, top + " over " + bottom);
            arc.shading = 0;
            waitForRendering(arc);
            image = grabImage(arc);
            same(image.pixel(c, c - arc.radius), image.pixel(c, c + arc.radius), "flat");
        }

        // The band's outline against the stroke it replaced, in one flat
        // colour: the same pixels, but for anti-aliasing at the edges.
        function test_outline_data() {
            const cases = [
                { tag: "0", head: 0 },
                { tag: "tiny under shortest", head: 1, shortest: 2.8 },
                { tag: "tiny", head: 0.5 },
                { tag: "12", head: 12 },
                { tag: "50", head: 50 },
                { tag: "99.9", head: 99.9 },
                { tag: "100", head: 100 },
                // A rollover's arc, running on past twelve.
                { tag: "rollover", tail: 30, head: 125 },
                { tag: "head behind tail", tail: 40, head: 20 },
                { tag: "zero length", tail: 40, head: 40 },
                { tag: "popup", head: 63, radius: 52, strokeWidth: 9 },
                { tag: "half pixel", head: 37, radius: 13.25, strokeWidth: 2.5 }
            ];
            return ways().reduce((all, stroked) => all.concat(cases.map(c => Object.assign({}, c, {
                tag: (stroked ? "stroke " : "band ") + c.tag, stroked: stroked }))), []);
        }

        function test_outline(data) {
            const geometry = { radius: data.radius ?? 17, strokeWidth: data.strokeWidth ?? 3 };
            const arc = createTemporaryObject(arcComponent, root, Object.assign({
                color: "white", shading: 0, percent: data.head, shortest: data.shortest ?? 0, stroked: data.stroked }, geometry));
            arc.tail = data.tail ?? 0;
            const stroke = createTemporaryObject(strokeComponent, root, Object.assign({
                x: arc.width + 8, width: arc.width, height: arc.height,
                head: data.head, tail: data.tail ?? 0, shortest: data.shortest ?? 0 }, geometry));
            waitForRendering(stroke);
            const drawn = grabImage(arc), expected = grabImage(stroke);
            let area = 0, difference = 0, worst = 0;
            // White over black: a pixel's red is how much of it is covered.
            for (let y = 0; y < arc.height; ++y) {
                for (let x = 0; x < arc.width; ++x) {
                    const a = drawn.pixel(x, y).r, b = expected.pixel(x, y).r;
                    area += b;
                    difference += a - b;
                    worst = Math.max(worst, Math.abs(a - b));
                }
            }
            compare(arc.drawn, area > 0, "drawn as the stroke was");
            // A stroke's edges come out a little inside the true circle, by
            // a few hundredths of a pixel; the band's lie on it.
            verify(worst <= 0.25, "worst pixel " + worst);
            const along = 2 * area / arc.strokeWidth;
            verify(area === 0 || Math.abs(difference) / along <= 0.1, "edges apart by " + difference / along + " px");
        }
    }

    // A gauge's arcs, outer then inner.
    function arcs(gauge) {
        const found = [];
        const collect = i => {
            if (i.playReset !== undefined) {
                found.push(i);
            }
            Array.from(i.children).forEach(collect);
        };
        collect(gauge);
        return found.sort((a, b) => b.radius - a.radius);
    }

    // 1 while an arc draws its reading, with the gradient on the stroke or
    // on the filled band, whichever draws it on this Qt; else 0.
    function painted(arc) {
        const paths = Array.from(arc.data).filter(o => o.capStyle !== undefined);
        return (arc.stroked ? paths.find(o => o.capStyle === ShapePath.RoundCap).strokeGradient
                            : paths.find(o => o.fillRule === ShapePath.WindingFill).fillGradient) !== null ? 1 : 0;
    }
}
