// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/code/reset.js" as Reset

// When a Claude or Codex week counts as started over (code/reset.js), and
// the two ways a ring shows it: on schedule the spent arc runs out through
// twelve o'clock, early the ring dissolves and resolves in its new reading.
Item {
    id: root
    width: 200
    height: 200

    function i18nc(context, text, ...args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }

    Component {
        id: gaugeComponent
        RingGauge {
            width: 52
            height: 52
            value: 4
            inner: true
            innerValue: 6
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
        name: "ResetDetect"

        readonly property real now: 1000000
        readonly property real week: 7 * 86400
        readonly property var weekly: ({ percent: 50, resetsAt: now + 86400 })

        function test_detect_data() {
            return [
                // Seven days elapsed: the old window had already run out.
                { tag: "scheduled", before: { claude: { weekly: { percent: 78, resetsAt: now - 10 } } },
                  after: { claude: { weekly: { percent: 4, resetsAt: now + week } } },
                  events: { "claude.weekly": { from: 78, early: false } } },
                // The provider reset it early: the old window still had days to run.
                { tag: "early", before: { claude: { weekly: { percent: 78, resetsAt: now + 3 * 86400 } } },
                  after: { claude: { weekly: { percent: 4, resetsAt: now + week } } },
                  events: { "claude.weekly": { from: 78, early: true } } },
                // The provider cleared the reading without moving the window.
                { tag: "cleared", before: { codex: { weekly: { percent: 61, resetsAt: now + 86400 } } },
                  after: { codex: { weekly: { percent: 2, resetsAt: now + 86400 } } },
                  events: { "codex.weekly": { from: 61, early: true } } },
                { tag: "spending", before: { claude: { weekly: { percent: 40, resetsAt: now + 86400 } } },
                  after: { claude: { weekly: { percent: 46, resetsAt: now + 86400 } } }, events: {} },
                { tag: "jitter", before: { codex: { weekly: { percent: 34, resetsAt: now + 86400 } } },
                  after: { codex: { weekly: { percent: 34, resetsAt: now + 86401 } } }, events: {} },
                // The first reading after a restart.
                { tag: "first", before: {}, after: { claude: { weekly: { percent: 12, resetsAt: now + week } } }, events: {} },
                // A failed poll keeps the old reading.
                { tag: "degraded", before: { claude: { weekly: { percent: 30, resetsAt: now + 86400 } } },
                  after: { claude: { weekly: { percent: 30, resetsAt: now + 86400 }, lastError: "boom" } }, events: {} },
                // Model limits are matched by id, wherever they sit in the list.
                { tag: "scoped", before: { codex: { weekly: weekly, scoped: [{ id: "a", percent: 9, resetsAt: now + 86400 },
                                                                            { id: "b", percent: 88, resetsAt: now - 10 }] } },
                  after: { codex: { weekly: weekly, scoped: [{ id: "b", percent: 3, resetsAt: now + week },
                                                             { id: "a", percent: 11, resetsAt: now + 86400 }] } },
                  events: { "codex.scoped.b": { from: 88, early: false } } },
                // A limit that appears or goes away is not a reset.
                { tag: "appears", before: { claude: { weekly: weekly, scoped: [{ id: "Fable", percent: 70, resetsAt: now + 86400 }] } },
                  after: { claude: { weekly: weekly, scoped: [{ id: "Opus", percent: 2, resetsAt: now + week }] } }, events: {} },
                // Signed out, the entry has no windows.
                { tag: "signedOut", before: { claude: { weekly: { percent: 70, resetsAt: now + 86400 } } },
                  after: { claude: { status: "signed_out" } }, events: {} }
            ];
        }

        function test_detect(data) {
            compare(Reset.detect(data.before, data.after, now), data.events);
        }
    }

    TestCase {
        name: "ResetPlay"
        when: windowShown

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }

        // A colour as it is now: one read from a property keeps following it.
        function channels(c) {
            return { r: c.r, g: c.g, b: c.b, a: c.a };
        }

        // The outer arc, then the inner one.
        function arcs(gauge) {
            const found = [];
            const collect = i => {
                if (i.animating !== undefined) {
                    found.push(i);
                }
                i.children.forEach(collect);
            };
            collect(gauge);
            return found;
        }

        function settled(gauge) {
            tryVerify(() => arcs(gauge).every(a => !a.animating), 5000, "the animations end");
            // Resting again: the drawn values follow the readings.
            for (const arc of arcs(gauge)) {
                compare(arc.head, arc.percent);
                compare(arc.tail, 0);
                compare(arc.lift, 0);
                compare(arc.drawColor, arc.color);
                compare(String(arc.litColor), String(arc.shaded(arc.color, true)));
                compare(String(arc.deepColor), String(arc.shaded(arc.color, false)));
            }
            gauge.value = 30;
            tryCompare(arcs(gauge)[0], "head", 30, 2000, "and keep following them");
        }

        function test_onSchedule() {
            const gauge = createTemporaryObject(gaugeComponent, root);
            waitForRendering(gauge);
            gauge.playResets({ from: 78, early: false }, { from: 92, early: false });
            const [outer, inner] = arcs(gauge);
            verify(outer.animating && inner.animating);
            // The spent arc starts from the old reading in its old colour.
            compare(outer.drawColor, Kirigami.Theme.neutralTextColor);
            wait(300);
            verify(outer.head > 78 && outer.head <= 100, "running out through twelve o'clock: " + outer.head);
            compare(outer.lift, 0);
            settled(gauge);
        }

        function test_early() {
            const gauge = createTemporaryObject(gaugeComponent, root);
            waitForRendering(gauge);
            gauge.playResets({ from: 78, early: true }, null);
            const [outer, inner] = arcs(gauge);
            verify(outer.animating && !inner.animating, "only the window that reset plays");
            wait(200);
            verify(outer.lift > 0, "dissolving: " + outer.lift);
            compare(outer.tail, 0);
            settled(gauge);
        }

        // As the spent arc turns from its old colour to its new one, its
        // gradient's ends turn with it, from the old level's shading to the
        // new one's, rather than losing the shading part way.
        function test_onScheduleShadesAsItTurns() {
            const gauge = createTemporaryObject(gaugeComponent, root);
            waitForRendering(gauge);
            const outer = arcs(gauge)[0];
            const from = Kirigami.Theme.neutralTextColor, to = outer.color;
            const ends = [[outer.shaded(from, true), outer.shaded(to, true)], [outer.shaded(from, false), outer.shaded(to, false)]];
            const seen = [];
            createTemporaryObject(samplerComponent, root, {
                sample: () => seen.push([channels(outer.drawColor), channels(outer.litColor), channels(outer.deepColor)])
            });
            gauge.playResets({ from: 78, early: false }, null);
            compare(String(outer.litColor), String(ends[0][0]), "the old level's shading");
            tryVerify(() => !outer.animating, 5000);
            // How far the colour has turned, on the channel that changes most.
            const k = ["r", "g", "b"].reduce((m, c) => Math.abs(to[c] - from[c]) > Math.abs(to[m] - from[m]) ? c : m, "r");
            const turned = seen.map(([draw, lit, deep]) => {
                const t = (draw[k] - from[k]) / (to[k] - from[k]);
                [lit, deep].forEach((end, i) => ["r", "g", "b", "a"].forEach(c => {
                    const expected = ends[i][0][c] + (ends[i][1][c] - ends[i][0][c]) * t;
                    verify(Math.abs(end[c] - expected) < 0.01, (i ? "bottom " : "top ") + c + " at " + t + ": " + end[c] + ", " + expected);
                }));
                return t;
            });
            verify(turned.some(t => t > 0.2 && t < 0.8), "seen part way: " + JSON.stringify(turned));
            settled(gauge);
        }

        // Dissolved, the arc is flat in the track's tone, so its length
        // changes there without a seam.
        function test_earlyHoldsTheTrackTone() {
            const gauge = createTemporaryObject(gaugeComponent, root);
            waitForRendering(gauge);
            const outer = arcs(gauge)[0];
            const seen = [];
            createTemporaryObject(samplerComponent, root, {
                sample: () => seen.push([outer.lift, channels(outer.topColor), channels(outer.bottomColor)])
            });
            gauge.playResets({ from: 78, early: true }, null);
            tryVerify(() => !outer.animating, 5000);
            const held = seen.filter(([lift]) => lift === 1);
            verify(held.length > 0, "held at the tone");
            for (const [, top, bottom] of held) {
                verify(["r", "g", "b", "a"].every(c => Math.abs(top[c] - outer.turnTone[c]) < 0.002
                                                    && Math.abs(bottom[c] - outer.turnTone[c]) < 0.002),
                       JSON.stringify([top, bottom]));
            }
            settled(gauge);
        }

        function test_noInnerRingPlaysOnlyTheOuter() {
            const gauge = createTemporaryObject(gaugeComponent, root, { inner: false });
            gauge.playResets(null, { from: 92, early: false });
            verify(arcs(gauge).every(a => !a.animating));
        }
    }
}
