// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import "../../package/contents/ui"

// The strip's hidden animation (Egg.qml): the code that plays it and the keys
// it only looks at, the rings it numbers along a horizontal or vertical
// strip, and the one property it overrides, the inner arc's opacity, which
// goes back to its own binding; the outer arc keeps following its reading,
// a ring without an inner ring never gains one, and everything a ring does
// besides still works after it.
Item {
    id: root
    width: 1200
    height: 600

    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (match, n) => n <= args.length ? String(args[n - 1]) : match);
    }
    function i18nc(context, text, ...args) {
        return substitute(text, args);
    }
    function i18ncp(context, singular, plural, n, ...args) {
        return substitute(n === 1 ? singular : plural, [n].concat(args));
    }

    readonly property var konami: [Qt.Key_Up, Qt.Key_Up, Qt.Key_Down, Qt.Key_Down, Qt.Key_Left, Qt.Key_Right,
                                   Qt.Key_Left, Qt.Key_Right, Qt.Key_B, Qt.Key_A]

    Component {
        id: monitorComponent
        FakeMonitor {}
    }

    Component {
        id: eggComponent
        Egg {}
    }

    Component {
        id: stripComponent
        Strip {
            items: ["cpu", "gpu", "memory", "network", "claude", "codex"]
            vertical: false
            thickness: 46
            ringsOnly: []
        }
    }

    // A focused item that hands its keys to the egg, as main.qml's do, inside
    // one that hears whatever it leaves.
    Component {
        id: keysComponent
        FocusScope {
            id: outerScope
            required property Egg egg
            property var heard: []
            width: 100
            height: 100
            Keys.onPressed: event => heard.push(event.key)

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => outerScope.egg.watch(event)
            }
        }
    }

    // A lone gauge, for what it does besides.
    Component {
        id: gaugeComponent
        Item {
            property alias gauge: lone
            width: 100
            height: 60
            RingGauge {
                id: lone
                width: 38
                height: 38
                interval: 1000
                value: 40
            }
        }
    }

    TestCase {
        id: testCase
        name: "Egg"
        when: windowShown

        property var monitor: null
        property var strip: null
        property var egg: null

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            monitor = monitorComponent.createObject(testCase);
            egg = eggComponent.createObject(root);
        }

        function cleanup() {
            strip?.destroy();
            wait(0);
            egg.destroy();
            monitor.destroy();
            strip = null;
            egg = null;
        }

        function all(item, test) {
            const found = [];
            const collect = i => {
                if (test(i)) {
                    found.push(i);
                }
                Array.from(i.children).forEach(collect);
            };
            collect(item);
            return found;
        }

        function makeStrip(vertical) {
            strip = stripComponent.createObject(root, Object.assign({ monitor: monitor, vertical: vertical, egg: egg },
                                                                    vertical ? { width: 46 } : { height: 46 }));
            egg.stage = strip;
            egg.vertical = vertical;
            waitForRendering(strip);
            tryVerify(() => gauges().every(g => g.still), 5000, "the arcs at rest");
            tryVerify(() => names().every(n => n.shownSize === n.size), 2000, "the names at rest");
            return strip;
        }

        function rings() {
            return all(strip, i => i.innerRing !== undefined && i.clock !== undefined);
        }

        // A ring's gauge: the ring sits in its face.
        function gaugeOf(ring) {
            return ring.parent.parent;
        }

        function gauges() {
            return rings().map(gaugeOf);
        }

        function names() {
            return all(strip, i => i.room !== undefined && i.sizeFactor !== undefined);
        }

        function wheelOf(ring) {
            return all(ring, i => i !== ring && i.preferredRendererType !== undefined)[0];
        }

        // The cell that holds a ring, and its readout.
        function cellOf(ring) {
            let item = ring;
            while (item.description === undefined) {
                item = item.parent;
            }
            return item;
        }

        // Everything a ring and its cell draw that an egg might touch.
        function snapshot(ring) {
            const g = gaugeOf(ring);
            const outer = ring.outerRing, inner = ring.innerRing;
            const name = all(g, i => i.room !== undefined && i.sizeFactor !== undefined)[0];
            const readout = all(cellOf(ring), i => i.oneLine !== undefined)[0];
            return {
                outerPercent: outer.percent, outerHead: outer.head, outerColor: String(outer.color),
                outerDraw: String(outer.drawColor), outerTrack: String(outer.trackColor), outerRotation: outer.rotation,
                outerScale: outer.scale, outerOpacity: outer.opacity, outerRadius: outer.radius, outerStroke: outer.strokeWidth,
                innerPercent: inner.percent, innerHead: inner.head, innerColor: String(inner.color),
                innerRotation: inner.rotation, innerOpacity: inner.opacity, innerVisible: inner.visible,
                innerHeld: g.innerHeld, faceOpacity: outer.parent.opacity, faceTransforms: outer.parent.transform.length,
                gaugeScale: g.scale, centreWidth: g.centreWidth, nameSize: name ? name.shownSize : null,
                nameOpacity: name ? name.opacity : null, readoutOpacity: readout ? readout.opacity : null,
                description: cellOf(ring).description
            };
        }

        function typeCode(keys) {
            for (const key of keys ?? root.konami) {
                keyClick(key);
            }
        }

        function makeKeys() {
            const keys = createTemporaryObject(keysComponent, root, { egg: egg });
            keys.forceActiveFocus();
            return keys;
        }

        // Ends an egg at once, as a change to Instant does, and allows the next.
        function finish() {
            egg.animated = false;
            compare(egg.playing, false);
            egg.animated = true;
        }

        function test_code_data() {
            const k = root.konami;
            return [
                { tag: "whole", keys: k, plays: true },
                { tag: "a third up", keys: [Qt.Key_Up].concat(k), plays: true },
                { tag: "after a wrong start", keys: [Qt.Key_Up, Qt.Key_Down, Qt.Key_X].concat(k), plays: true },
                { tag: "a wrong key mid-way", keys: k.slice(0, 5).concat([Qt.Key_X]).concat(k.slice(5)), plays: false },
                { tag: "a wrong key at the end", keys: k.slice(0, 9).concat([Qt.Key_X, Qt.Key_A]), plays: false },
                { tag: "a right key twice", keys: k.slice(0, 5).concat(k.slice(4)), plays: false },
                { tag: "short of the end", keys: k.slice(0, 9), plays: false }
            ];
        }

        function test_code(data) {
            makeKeys();
            typeCode(data.keys);
            compare(egg.playing, data.plays);
            if (data.plays) {
                finish();
            }
        }

        // B and A in either case, Shift held or not, and Shift on its own
        // isn't a wrong key.
        function test_lettersInEitherCase_data() {
            return [{ tag: "lower", shift: false, b: "b", a: "a" }, { tag: "upper", shift: true, b: "B", a: "A" }];
        }

        function test_lettersInEitherCase(data) {
            makeKeys();
            typeCode(root.konami.slice(0, 8));
            for (const letter of [data.b, data.a]) {
                if (data.shift) {
                    keyPress(Qt.Key_Shift);
                    keyClick(letter, Qt.ShiftModifier);
                    keyRelease(Qt.Key_Shift);
                } else {
                    keyClick(letter);
                }
            }
            verify(egg.playing);
            finish();
        }

        // The egg only looks: every key goes on to the item's parent, the
        // arrows among them.
        function test_keysGoOn() {
            const keys = makeKeys();
            typeCode([Qt.Key_Left, Qt.Key_Up].concat(root.konami));
            verify(egg.playing);
            compare(keys.heard, [Qt.Key_Left, Qt.Key_Up].concat(root.konami));
            finish();
        }

        // A code typed while it plays counts for nothing, not even towards
        // the next one.
        function test_codeWhilePlaying() {
            makeKeys();
            let starts = 0;
            const count = () => starts += egg.playing ? 1 : 0;
            egg.playingChanged.connect(count);
            typeCode();
            compare(starts, 1);
            typeCode(root.konami.concat(root.konami.slice(0, 8)));
            compare(starts, 1, "no second start");
            tryCompare(egg, "playing", false, 3000);
            typeCode(root.konami.slice(8));
            compare(starts, 1, "the code typed meanwhile doesn't carry over");
            compare(egg.playing, false);
            typeCode();
            compare(starts, 2);
            egg.playingChanged.disconnect(count);
            finish();
        }

        // At Instant nothing plays, and a change to Instant ends one at once.
        function test_instant() {
            makeStrip(false);
            makeKeys();
            const before = rings().map(snapshot);
            egg.animated = false;
            typeCode();
            compare(egg.playing, false);
            compare(egg.progress, 0);
            verify(rings().every(r => !r.active));

            egg.animated = true;
            typeCode();
            verify(egg.playing);
            wait(300);
            verify(rings().some(r => wheelOf(r).visible), "the band shows");
            egg.animated = false;
            compare(egg.playing, false);
            verify(rings().every(r => !wheelOf(r).visible));
            compare(rings().map(snapshot), before);
        }

        function test_numbersTheRingsAlongTheStrip_data() {
            return [{ tag: "horizontal", vertical: false }, { tag: "vertical", vertical: true }];
        }

        // Every shown ring, in order along the strip: left to right, or top
        // to bottom, and the band passes in that order.
        function test_numbersTheRingsAlongTheStrip(data) {
            makeStrip(data.vertical);
            egg.arrange();
            const found = rings();
            compare(found.length, 5, "cpu, gpu, memory, claude, codex");
            const along = r => {
                const p = r.mapToItem(strip, r.width / 2, r.height / 2);
                return data.vertical ? p.y : p.x;
            };
            const ordered = found.slice().sort((a, b) => a.index - b.index);
            compare(ordered.map(r => r.index), [0, 1, 2, 3, 4]);
            verify(ordered.every((r, i) => i === 0 || along(r) > along(ordered[i - 1])), "in order along the strip");
            egg.playing = true;
            egg.progress = 0.1;
            verify(ordered[0].band > 0, "the band at the first");
            compare(ordered[4].band, 0, "and not yet at the last");
            egg.progress = 0.8;
            compare(ordered[0].band, 0, "gone from the first");
            verify(ordered[4].band > 0, "at the last");
            egg.playing = false;
        }

        function test_backToLive_data() {
            return [{ tag: "horizontal", vertical: false }, { tag: "vertical", vertical: true }];
        }

        // Stepped through: at the start, at the end and after it, every ring
        // is as it was without the egg; between, only the band shows and the
        // inner arc dims, and the names, readings and descriptions stay.
        function test_backToLive(data) {
            makeStrip(data.vertical);
            const found = rings();
            const live = found.map(snapshot);
            egg.arrange();
            egg.playing = true;
            for (const p of [0, 0.25, 0.5, 0.75, 1]) {
                egg.progress = p;
                const now = found.map(snapshot);
                if (p === 0 || p === 1) {
                    compare(now, live, "as live at " + p);
                    verify(found.every(r => !wheelOf(r).visible), "no band at " + p);
                    continue;
                }
                found.forEach((r, i) => {
                    const expected = Object.assign({}, live[i], {
                        innerOpacity: gaugeOf(r).innerOn ? live[i].innerOpacity * (1 - 0.6 * r.band) : live[i].innerOpacity
                    });
                    compare(now[i], expected, "only the inner arc's opacity changes, ring " + r.index + " at " + p);
                });
            }
            egg.progress = 0.5;
            verify(found.some(r => wheelOf(r).visible), "the band shows mid-way");
            verify(found.some(r => gaugeOf(r).innerOn && r.innerRing.opacity < 1), "an inner arc dims");
            egg.playing = false;
            compare(found.map(snapshot), live, "as live after");
            verify(found.every(r => !wheelOf(r).visible));
        }

        // A reading that arrives mid-way moves the arc as usual, the band
        // reaching round from it, and shows at the end.
        function test_readingMidEgg() {
            makeStrip(false);
            const cpu = rings().find(r => gaugeOf(r).value === monitor.cpuUsage);
            makeKeys();
            typeCode();
            tryVerify(() => cpu.band > 0.5, 2000);
            monitor.cpuUsage = 71;
            tryVerify(() => cpu.outerRing.percent > 23, 1000, "the arc moves while it plays");
            verify(egg.playing);
            const extents = [];
            const sample = () => {
                if (cpu.band > 0) {
                    extents.push([cpu.extent, cpu.outerRing.percent]);
                }
            };
            egg.progressChanged.connect(sample);
            tryCompare(egg, "playing", false, 3000);
            egg.progressChanged.disconnect(sample);
            verify(extents.every(([extent, percent]) => extent >= percent - 1e-6), "the band reaches round from the reading");
            tryCompare(cpu.outerRing, "percent", 71, 3000);
            compare(gaugeOf(cpu).drawnValue, 71);
        }

        // The CPU ring has no inner ring, and never gains one: no inner arc
        // drawn or held, the name's room and the arc's opacity untouched.
        function test_noInnerRingGained() {
            makeStrip(false);
            const cpu = rings().find(r => gaugeOf(r).value === monitor.cpuUsage);
            const g = gaugeOf(cpu);
            compare(g.inner, false);
            const room = g.centreWidth;
            const seen = [];
            const sample = () => seen.push([cpu.innerRing.opacity, cpu.innerRing.visible, cpu.innerRing.drawn, g.innerHeld, g.centreWidth]);
            egg.progressChanged.connect(sample);
            makeKeys();
            typeCode();
            tryCompare(egg, "playing", false, 3000);
            egg.progressChanged.disconnect(sample);
            verify(seen.length > 10, "sampled " + seen.length);
            verify(seen.every(s => s[0] === 0 && !s[1] && !s[2] && !s[3] && s[4] === room), JSON.stringify(seen.slice(0, 5)));
        }

        // An inner ring that goes mid-way fades out as it would without the
        // egg, which lets go of it at once.
        function test_innerRingGoingMidEgg() {
            makeStrip(false);
            const gpu = rings().find(r => gaugeOf(r).inner);
            const g = gaugeOf(gpu);
            egg.arrange();
            egg.playing = true;
            egg.progress = 0.5;
            verify(gpu.band > 0.9);
            fuzzyCompare(gpu.innerRing.opacity, 1 - 0.6 * gpu.band, 1e-9, "dimmed");
            const seen = [];
            const sample = () => seen.push([gpu.innerRing.opacity, g.innerShown]);
            g.innerShownChanged.connect(sample);
            monitor.gpuInner.phase = "asleep";
            compare(g.innerOn, false);
            compare(gpu.innerRing.opacity, g.innerShown, "its own again at once");
            tryCompare(g, "innerShown", 0, 2000);
            g.innerShownChanged.disconnect(sample);
            verify(seen.some(s => s[1] > 0 && s[1] < 1), "it fades");
            verify(seen.every(s => s[0] === s[1]), JSON.stringify(seen));
            egg.playing = false;
        }

        // The pieces of a ring that move on their own still do after an
        // egg, which starts none of them, and the inner arc's opacity is
        // bound again.
        function test_afterAnEgg() {
            const holder = createTemporaryObject(gaugeComponent, root);
            const g = holder.gauge;
            g.egg = egg;
            g.inner = true;
            g.innerValue = 30;
            egg.stage = holder;
            const ring = all(g, i => i.innerRing !== undefined)[0];
            tryVerify(() => g.still && g.innerShown === 1, 3000);
            const arcs = [ring.outerRing, ring.innerRing];

            const during = [];
            const sample = () => during.push([arcs.some(a => a.animating), g.struck, g.dotsShown, g.gap]);
            egg.progressChanged.connect(sample);
            egg.play();
            verify(egg.playing);
            compare(ring.index, 0);
            tryCompare(egg, "playing", false, 3000);
            egg.progressChanged.disconnect(sample);
            verify(during.length > 10 && during.every(s => !s[0] && s[1] === 0 && s[2] === 0 && s[3] === 0),
                   "no reset, stroke, dots or gaps from the egg");

            g.playResets({ from: 80, early: false }, { from: 60, early: true });
            verify(arcs.every(a => a.animating), "a week's reset plays");
            tryVerify(() => arcs.every(a => !a.animating), 5000);
            compare(ring.outerRing.percent, 40);

            g.stale = true;
            tryCompare(g, "gap", 0.2, 2000, "a stale ring breaks into segments");
            g.stale = false;
            tryCompare(g, "gap", 0, 2000);

            g.pulsing = true;
            const face = ring.outerRing.parent;
            tryVerify(() => face.opacity < 0.9, 2000, "it breathes");
            g.pulsing = false;
            tryCompare(face, "opacity", 1, 2500);

            g.loading = true;
            tryCompare(g, "dotsShown", 1, 1000, "it waits with its dots");
            g.loading = false;
            tryCompare(g, "dotsShown", 0, 3000);

            g.cancelled = true;
            tryCompare(g, "struck", 1, 3000, "it is struck");
            g.cancelled = false;
            tryCompare(g, "struck", 0, 3000);

            g.inner = false;
            tryCompare(g, "innerShown", 0, 2000);
            compare(ring.innerRing.opacity, 0, "the inner arc's opacity follows its fade again");
        }
    }
}
