// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Shapes
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/popups"
import "../../package/contents/ui/code/format.js" as Format
import "../../package/contents/ui/code/history.js" as History

// How readings move: a ring's arc follows a new reading without passing it
// and bends when another arrives mid-move, its colour turns as it passes 75
// and 90 %, and the number in a popup's ring counts with it; a history
// graph draws a new sample in one frame, with no motion; a week graph's new
// stretch draws on, its run-out fades in after it and eases when a poll
// moves it, and its run-out, marker and old week fade; a second GPU's
// ring fades its track in and then draws its arc in, and goes the other way
// round, and its popup section fades in and out. A Claude or Codex ring
// struck after failed checks unwinds before its stroke draws on, and takes
// the stroke off before its arcs grow back. One waiting for its first
// check holds its dots still for a second, then a lit dot travels round
// them until a reading fills the track in or a failure strikes it. A
// duration of 0, as Plasma's Instant animation speed gives, puts everything
// in place at once.
// The test runner's Kirigami units are the defaults, at speed 1.
Item {
    id: root
    width: 600
    height: 400

    // A bare qml runtime has no KI18n; the views find these on the root.
    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }
    function i18n(text, ...args) { return substitute(text, args); }
    function i18nc(context, text, ...args) { return substitute(text, args); }
    function i18np(s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }
    function i18ncp(c, s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }

    function tone(level) {
        return level === 2 ? Kirigami.Theme.negativeTextColor
             : level === 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
    }

    // Every item under `item`, itself included, that `test` accepts.
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

    Component {
        id: followerComponent
        Follower {
            settle: 400
            target: 10
        }
    }

    Component {
        id: gaugeComponent
        RingGauge {
            width: 60
            height: 60
            value: 70
        }
    }

    Component {
        id: headerComponent
        PopupHeader {
            width: 400
            ringValue: 40
            title: "CPU"
        }
    }

    Component {
        id: graphComponent
        Graph {
            width: 220
            height: 60
            length: 12
        }
    }

    Component {
        id: weekComponent
        WeekGraph {
            width: 700
            height: 100
        }
    }

    Component {
        id: monitorComponent
        FakeMonitor {}
    }

    Component {
        id: gpuCellComponent
        RingCellContent {
            item: "gpu"
            ring: 46
            textShown: true
            twoLines: true
        }
    }

    Component {
        id: usageCellComponent
        UsageCellContent {
            item: "claude"
            ring: 34
            textShown: true
            twoLines: true
        }
    }

    // A window of its own for a cell, which a test can hide.
    Component {
        id: windowComponent
        Window {
            width: 120
            height: 60
            visible: true
        }
    }

    Component {
        id: popupHost
        Loader {
            width: 400
        }
    }

    // Calls `sample` once a frame, after the frame's animations have run.
    Component {
        id: samplerComponent
        FrameAnimation {
            property var sample: null
            running: true
            onTriggered: sample()
        }
    }

    TestCase {
        id: testCase
        name: "Follower"
        when: windowShown

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }

        // Every value `shown` takes from now on.
        function trace(follower) {
            const values = [];
            follower.shownChanged.connect(() => values.push(follower.shown));
            return values;
        }

        function test_reachesTheTargetWithoutPassingIt() {
            const f = createTemporaryObject(followerComponent, testCase);
            const values = trace(f);
            f.target = 90;
            verify(f.moving, "frames run while it moves");
            compare(f.shown, 10, "and it starts where it was");
            tryCompare(f, "shown", 90, 2000);
            verify(!f.moving, "and stop once it is there");
            verify(values.length > 3, "over several frames: " + values.length);
            verify(values.every((v, i) => v <= 90 && (i === 0 || v >= values[i - 1])), JSON.stringify(values));
        }

        // A reading the other way mid-move keeps the arc's place and speed:
        // it carries on a little, turns and settles on the new reading,
        // never past it.
        function test_bendsWhenInterrupted() {
            const f = createTemporaryObject(followerComponent, testCase);
            f.target = 90;
            tryVerify(() => f.shown > 40, 2000);
            const place = f.shown;
            const speed = f.velocity;
            verify(speed > 0);
            const values = trace(f);
            f.target = 20;
            compare(f.shown, place, "no jump");
            compare(f.velocity, speed, "nor a change of speed");
            tryCompare(f, "shown", 20, 3000);
            verify(Math.max(...values) > place, "carries on before it turns: " + JSON.stringify(values));
            verify(values.every(v => v >= 20), "never past the new reading: " + JSON.stringify(values));
        }

        // Rushing towards a reading, a nearer one arrives: the arc is slowed
        // so it doesn't pass it.
        function test_aNearerTargetIsNotPassed() {
            const f = createTemporaryObject(followerComponent, testCase, { settle: 0 });
            f.target = 62;
            f.settle = 400;
            f.target = 30;
            tryVerify(() => f.shown < 55, 2000);
            const place = f.shown;
            const values = trace(f);
            f.target = 45;
            compare(f.shown, place, "no jump");
            tryCompare(f, "shown", 45, 3000);
            verify(values.every(v => v >= 45), "never below the nearer reading: " + JSON.stringify(values));
        }

        // It comes to rest on the target once within its precision, sooner
        // the coarser that is, and at once where that is more than the change.
        function test_restsWithinItsPrecision() {
            // Stepped at 60 Hz by hand: a slow frame on a busy runner takes
            // the exact step over it and could land them all at once.
            const steps = precision => {
                const f = createTemporaryObject(followerComponent, testCase, { precision: precision });
                f.target = 11;
                f.frames.stop();
                const values = [];
                while (f.shown !== 11 && values.length < 600) {
                    f.advance(1 / 60);
                    values.push(f.shown);
                }
                compare(f.shown, 11);
                compare(f.velocity, 0);
                return values;
            };
            const [fine, coarse, loose] = [0.05, 0.5, 5].map(steps);
            verify(coarse.length < fine.length, "fewer frames: " + coarse.length + " against " + fine.length);
            verify(coarse.every((v, i) => v <= 11 && (i === 0 || v >= coarse[i - 1])), JSON.stringify(coarse));
            compare(loose, [11]);
        }

        // Plasma's Instant speed: no frames, and the value at once.
        function test_noSettleFollowsAtOnce() {
            const f = createTemporaryObject(followerComponent, testCase, { settle: 0 });
            f.target = 70;
            compare(f.shown, 70);
            verify(!f.moving);
        }

        function test_droppingTheSettleMidMoveLandsAtOnce() {
            const f = createTemporaryObject(followerComponent, testCase);
            f.target = 90;
            verify(f.moving);
            f.settle = 0;
            compare(f.shown, 90);
            verify(!f.moving);
            f.target = 30;
            compare(f.shown, 30, "and follows at once from then on");
        }

        function test_disabledFollowsAtOnce() {
            const f = createTemporaryObject(followerComponent, testCase);
            f.target = 90;
            f.enabled = false;
            compare(f.shown, 90);
            verify(!f.moving);
            f.enabled = true;
            f.target = 50;
            verify(f.moving, "moving again once enabled");
        }
    }

    TestCase {
        id: rings
        name: "RingMotion"
        when: windowShown

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }

        // The outer arc, the larger.
        function outerArc(gauge) {
            return root.all(gauge, i => i.playReset !== undefined).sort((a, b) => b.radius - a.radius)[0];
        }

        // { percent, color, text } of each frame from now on, `text` being the
        // middle's for a header ring.
        function frames(gauge, middle) {
            const seen = [];
            const arc = outerArc(gauge);
            createTemporaryObject(samplerComponent, rings, {
                sample: () => seen.push({ percent: arc.percent, color: String(arc.color), text: middle ? middle.text : "",
                                          textColor: middle ? String(middle.color) : "" })
            });
            return seen;
        }

        // A reading that prints the same whole percent leaves the arc
        // where it is; one that prints another moves it there.
        function test_wholePercentsOnly() {
            const gauge = createTemporaryObject(gaugeComponent, root, { value: 40.2 });
            const arc = outerArc(gauge);
            compare(arc.percent, 40);
            gauge.value = 40.4;
            compare(arc.percent, 40);
            const seen = frames(gauge);
            wait(100);
            verify(seen.every(f => f.percent === 40), "no motion: " + JSON.stringify(seen));
            gauge.value = 40.6;
            tryCompare(arc, "percent", 41, 2000);
        }

        // A point more comes to rest once the arc is within a quarter of a
        // pixel of it, without frames that move it by less.
        function test_restsWithinAQuarterPixel() {
            const gauge = createTemporaryObject(gaugeComponent, root, { value: 40 });
            const arc = outerArc(gauge);
            const seen = frames(gauge);
            gauge.value = 41;
            tryCompare(arc, "percent", 41, 2000);
            const pixels = seen.map(f => Math.abs(41 - f.percent) * 2 * Math.PI * arc.radius / 100);
            verify(pixels.some(p => p > 0.25), "it moves: " + JSON.stringify(pixels));
            verify(pixels.every(p => p === 0 || p >= 0.25), JSON.stringify(pixels));
        }

        // 70 to 92: the arc sweeps in the base colour, turns amber on the
        // frame it reaches 75 and red on the frame it reaches 90, not when
        // the reading arrives. The reading's own colour changes at once.
        function test_colourTurnsAtTheCrossing() {
            const gauge = createTemporaryObject(gaugeComponent, root);
            const arc = outerArc(gauge);
            compare(String(arc.color), String(root.tone(0)));
            const seen = frames(gauge);
            gauge.value = 92;
            compare(gauge.outerTone, root.tone(2), "the reading's colour");
            compare(String(arc.color), String(root.tone(0)), "the arc's, before it moves");
            tryCompare(arc, "percent", 92, 2000);
            compare(String(arc.color), String(root.tone(2)));
            for (const f of seen) {
                compare(f.color, String(root.tone(Format.level(f.percent))), "at " + f.percent);
            }
            for (const [low, high] of [[70, 75], [75, 90], [90, 92]]) {
                verify(seen.some(f => f.percent > low && f.percent < high), "drawn between " + low + " and " + high);
            }
        }

        // Back down from 95 to 88 the arc never passes 90 on the way, so it
        // turns amber only as it leaves 90.
        function test_noFlashOnTheWayDown() {
            const gauge = createTemporaryObject(gaugeComponent, root, { value: 95 });
            const seen = frames(gauge);
            gauge.value = 88;
            tryCompare(outerArc(gauge), "percent", 88, 2000);
            for (const f of seen) {
                compare(f.color, String(root.tone(Format.level(f.percent))), "at " + f.percent);
            }
        }

        // The header ring's number counts through the percentages the arc
        // passes, in its colour, and ends on the reading.
        function test_numberCountsWithTheArc() {
            const header = createTemporaryObject(headerComponent, root);
            const gauge = root.all(header, i => i.drawnValue !== undefined)[0];
            const middle = root.all(gauge, i => i.text === "40%" && i.font !== undefined)[0];
            verify(middle, "40% in the middle");
            const seen = frames(gauge, middle);
            header.ringValue = 85;
            tryCompare(middle, "text", "85%", 2000);
            const counted = seen.map(f => f.text).filter((t, i, list) => i === 0 || t !== list[i - 1]);
            verify(counted.length > 5, "counted: " + JSON.stringify(counted));
            const numbers = counted.map(t => parseInt(t));
            verify(numbers.every((n, i) => i === 0 || n > numbers[i - 1]), "upwards: " + JSON.stringify(counted));
            for (const f of seen) {
                compare(f.text, Format.percent(f.percent) + "%", "with the arc");
                compare(f.textColor, f.color, "in the arc's colour");
            }
            header.ringValue = NaN;
            compare(middle.text, "–", "no reading says so at once");
        }

        // A system popup's ring is still before the next reading.
        function test_settleWithinHalfTheInterval() {
            const header = createTemporaryObject(headerComponent, root, { interval: 500 });
            const gauge = root.all(header, i => i.drawnValue !== undefined)[0];
            compare(gauge.settle, Math.min(Kirigami.Units.veryLongDuration, 250));
            header.interval = 0;
            compare(gauge.settle, Kirigami.Units.veryLongDuration, "the Claude and Codex popups' readings are minutes apart");
            verify(Kirigami.Units.longDuration > 1, "the test runs at an animation speed");
        }

        // At Plasma's Instant speed the arc, its colour and the number are
        // in place in the same frame, as before the follower.
        function test_instant() {
            const header = createTemporaryObject(headerComponent, root);
            const gauge = root.all(header, i => i.drawnValue !== undefined)[0];
            gauge.settle = 0;
            const middle = root.all(gauge, i => i.text === "40%" && i.font !== undefined)[0];
            header.ringValue = 92;
            compare(outerArc(gauge).percent, 92);
            compare(String(outerArc(gauge).color), String(root.tone(2)));
            compare(middle.text, "92%");
        }
    }

    TestCase {
        id: graphs
        name: "GraphMotion"
        when: windowShown

        readonly property var start: [20, 35, 30, 50, 45, 60, 40, 55, 70, 65, 50, 60]

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }

        function xy(points) {
            return points.map(p => [p.x, p.y]);
        }

        function rest(g, values, maximum) {
            return xy(History.points(values, g.length, g.width, g.height, maximum ?? g.maximum, g.topY));
        }

        // The points each of a graph's ShapePaths draws, as drawn: its
        // band, its area, its line and the dashed second line, each of
        // their stretches one after another.
        function strokes(g) {
            return g.children.filter(c => c.preferredRendererType !== undefined)
                .reduce((paths, shape) => paths.concat(Array.from(shape.data)), [])
                .filter(p => p.pathElements !== undefined)
                .map(p => xy(Array.from(p.pathElements[0].paths).reduce((all, run) => all.concat(Array.from(run)), [])));
        }

        // A new sample is drawn in the frame it arrives in, each point a
        // slot to the left, with nothing in between; a rate's new top comes
        // with it. Every frame after it shows the new line.
        function test_aSampleDrawsInOneFrame_data() {
            return [{ tag: "percentage" }, { tag: "rate", maximum: 180 }];
        }
        function test_aSampleDrawsInOneFrame(data) {
            const g = createTemporaryObject(graphComponent, root, { values: start });
            const before = strokes(g);
            compare(before[2], rest(g, start));
            let frames = [];
            createTemporaryObject(samplerComponent, graphs, { sample: () => frames.push(strokes(g)) });
            wait(50);
            frames = [];
            const next = History.push(start, 90, 12);
            g.values = next;
            if (data.maximum) {
                g.maximum = data.maximum;
            }
            const after = strokes(g);
            compare(after[2], rest(g, next, data.maximum), "drawn as it arrives");
            wait(Math.max(3 * Kirigami.Units.longDuration, 200));
            verify(frames.length > 2, "frames sampled: " + frames.length);
            frames.forEach((f, i) => compare(f, after, "frame " + i));
        }

    }

    TestCase {
        id: weeks
        name: "WeekMotion"
        when: windowShown

        readonly property real start: 1000000
        readonly property real day: 86400
        readonly property real week: 7 * day

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }

        function window(history, percent) {
            return { resetsAt: start + week, windowSeconds: week, percent: percent, history: history };
        }

        // Two days in at 20 %, on course to last the week.
        function make(options) {
            return createTemporaryObject(weekComponent, root, Object.assign({
                window: window([[start, 0], [start + 2 * day, 20]], 20),
                projected: "main",
                pollAt: start + 2 * day,
                nowMs: (start + 2 * day) * 1000
            }, options));
        }

        // A day later at 60 %, now on course to run out on day five.
        function poll(g) {
            g.window = window([[start, 0], [start + 2 * day, 20], [start + 3 * day, 60]], 60);
            g.pollAt = start + 3 * day;
            g.nowMs = g.pollAt * 1000;
        }

        function end(points) {
            const p = points[points.length - 1];
            return [p.x, p.y];
        }

        // The run-out's line and time, as drawn: the graph's own, not the
        // last week's.
        function runOutOf(g) {
            return g.children.find(i => i.level !== undefined && i.label !== undefined);
        }

        // The new stretch draws on from the old end and lands on the new
        // reading; the run-out it brings, its line and its time, waits until
        // then and fades in.
        function test_drawsOnThenTheRunOutFadesIn() {
            const g = make();
            const old = end(g.mainPoints);
            const shown = runOutOf(g);
            compare(g.runOutOpacity, 0);
            verify(!shown.visible);
            const seen = [];
            createTemporaryObject(samplerComponent, weeks, { sample: () => seen.push([g.drawClock, shown.opacity]) });
            poll(g);
            compare(end(g.mainDrawn), old, "from the old end");
            verify(g.drawClock < 1);
            verify(Number.isFinite(g.runOutAt), "on course to run out");
            tryVerify(() => g.drawClock === 1, 2000, "drawn on");
            compare(end(g.mainDrawn), end(g.mainPoints), "on the new reading");
            tryCompare(shown, "opacity", 1, 2000);
            verify(shown.visible);
            verify(seen.length > 3);
            verify(seen.every(([clock, opacity]) => clock === 1 || opacity === 0), "no run-out while it draws on: " + JSON.stringify(seen));
            verify(seen.some(([, opacity]) => opacity > 0 && opacity < 1), "faded in: " + JSON.stringify(seen));
            compare(g.runOutX, Math.round(g.xAt(g.runOutAt)));
        }

        // A poll that moves the run-out eases the line along the axis to its
        // new place, slowing as it lands, and the time follows at once.
        function test_runOutEasesToItsNewPlace() {
            const g = make({ window: window([[start, 0], [start + 2 * day, 50]], 50), runOutText: "Thu 12:00 AM" });
            compare(g.runOutOpacity, 1);
            const from = g.runOutX;
            // Each frame's time and place.
            const seen = [];
            createTemporaryObject(samplerComponent, weeks, { sample: () => seen.push([Date.now(), g.runOutX]) });
            g.window = window([[start, 0], [start + 2 * day, 50], [start + 3 * day, 60]], 60);
            g.pollAt = start + 3 * day;
            g.nowMs = g.pollAt * 1000;
            g.runOutText = "Fri 12:00 AM";
            const to = Math.round(g.xAt(g.runOutAt));
            verify(to > from + 20, from + " to " + to);
            tryCompare(g, "runOutX", to, 2000);
            compare(g.runOutOpacity, 1, "shown all along");
            compare(g.shownRunOutText, "Fri 12:00 AM");
            const xs = seen.map(([, x]) => x);
            verify(xs.filter(x => x > from && x < to).length > 2, "eased: " + JSON.stringify(xs));
            verify(xs.every((x, i) => i === 0 || x >= xs[i - 1]), "one way: " + JSON.stringify(xs));
            // Half way through the move, counted from the first frame it
            // shows in, so no earlier than that, an ease out has gone seven
            // eighths of the way and a steady move only half.
            const began = seen.find(([, x]) => x > from)[0];
            const half = seen.find(([t]) => t - began >= g.duration / 2);
            verify(half !== undefined, "a frame half way: " + JSON.stringify(seen));
            verify((half[1] - from) / (to - from) > 0.75,
                   "slowing as it lands: " + (half[1] - from) + " of " + (to - from) + " at " + JSON.stringify(seen));
        }

        // A poll while the line still draws on puts the rest of that stretch
        // in at once and draws the new one on from its end, so the line
        // never runs back on itself.
        function test_aPollMidDrawDrawsOnFromTheLastReading() {
            const g = make();
            poll(g);
            tryVerify(() => g.drawIn > 0.2 && g.drawIn < 0.8, 2000, "part way");
            const last = end(g.mainPoints);
            const xs = () => g.mainDrawn.map(p => p.x);
            const seen = [];
            createTemporaryObject(samplerComponent, weeks, { sample: () => seen.push(xs()) });
            g.window = window([[start, 0], [start + 2 * day, 20], [start + 3 * day, 60], [start + 4 * day, 70]], 70);
            seen.push(xs());
            compare([g.mainFrom.x, g.mainFrom.y], last, "from the reading it was drawing to");
            compare(end(g.mainDrawn), last);
            tryVerify(() => g.drawClock === 1, 2000, "drawn on");
            compare(end(g.mainDrawn), end(g.mainPoints));
            verify(seen.length > 3);
            verify(seen.every(list => list.every((x, i) => i === 0 || x >= list[i - 1])), "never back: " + JSON.stringify(seen));
        }

        // A run-out that goes fades out where it was.
        function test_runOutFadesOutWhereItWas() {
            const g = make({ window: window([[start, 0], [start + 3 * day, 60]], 60), pollAt: start + 3 * day,
                             nowMs: (start + 3 * day) * 1000 });
            compare(g.runOutOpacity, 1, "shown at once when the popup opens");
            const x = g.runOutX;
            const shown = runOutOf(g);
            // A long fade, so a loaded machine still catches it part way.
            g.duration = 2000;
            g.projected = "";
            verify(!Number.isFinite(g.runOutAt));
            // Read together: a slow machine can see the fade at any point.
            tryVerify(() => shown.opacity > 0 && shown.opacity < 1 && g.timeShown, 2000, "fading out, its time with it");
            compare(g.runOutX, x, "where it was");
            tryVerify(() => !shown.visible, 4000, "gone");
            verify(!g.timeShown, "and then its room");
        }

        // An amber run-out that goes because the limit is used up fades out
        // amber, as it was, though the limit is now red.
        function test_runOutFadesOutInItsLevel() {
            const at = start + 3 * day;
            const g = make({ window: window([[start, 0], [at, 80]], 80), pollAt: at, nowMs: at * 1000 });
            const shown = runOutOf(g);
            compare(g.runOutOpacity, 1);
            compare(shown.level, 1, "amber");
            const levels = [];
            createTemporaryObject(samplerComponent, weeks, { sample: () => { if (shown.visible) levels.push(shown.level); } });
            g.window = window([[start, 0], [at, 80], [at + 3600, 100]], 100);
            g.pollAt = at + 3600;
            g.nowMs = g.pollAt * 1000;
            verify(!Number.isFinite(g.runOutAt), "used up");
            tryCompare(shown, "opacity", 0, 2000);
            verify(levels.length > 3);
            verify(levels.every(l => l === 1), "faded out amber: " + JSON.stringify(levels));
        }

        // The marker for now fades in once the reading is hours old.
        function test_staleMarkerFades() {
            const g = make();
            const marker = g.children.find(i => i.width === 1 && i.radius !== undefined
                                               && String(i.color) === String(Qt.alpha(g.color, 0.45 * g.color.a)));
            verify(marker && !marker.visible);
            g.nowMs = (start + 2 * day + 3 * 3600) * 1000;
            verify(g.stale);
            tryVerify(() => marker.opacity > 0 && marker.opacity < 1, 1000, "fading in");
            tryCompare(marker, "opacity", 1, 1000);
        }

        // A week that starts over while the popup is open: the last week's
        // line, run-out and marker for now fade out together as the new
        // week's first reading fades in as a dot.
        function test_newWeekFadesTheOldOneOut() {
            const g = make({ window: window([[start, 0], [start + 3 * day, 95]], 95), pollAt: start + 3 * day,
                             nowMs: (start + 3 * day + 3 * 3600) * 1000, runOutText: "Sat 12:00 AM" });
            compare(g.runOutOpacity, 1);
            verify(g.markerShown);
            const old = g.mainPoints.map(p => [p.x, p.y]);
            const runOut = [g.runOutX, g.shownRunOutText, runOutOf(g).level];
            compare(runOut[2], 2, "red, as the new week's 1 % isn't");
            verify(g.runOutX > 0 && g.shownRunOutText !== "");
            const markerX = g.markerShownX;
            g.window = { resetsAt: start + 2 * week, windowSeconds: week, percent: 1, history: [[start + week + 3600, 1]] };
            g.pollAt = start + week + 3600;
            g.nowMs = g.pollAt * 1000;
            compare(g.ghostMain.map(p => [p.x, p.y]), old);
            compare([g.ghostRunOutX, g.ghostRunOutText, g.ghostRunOutLevel], runOut);
            compare(g.ghostMarkerX, markerX);
            compare(g.ghostOpacity, 1);
            compare(g.runOutOpacity, 0, "the new week's own run-out starts out");
            verify(!g.markerShown, "and so does its marker");
            const dot = g.children.find(i => i.shown !== undefined && i.color === g.color);
            verify(dot.shown);
            verify(dot.opacity < 1, "the new week's dot fades in");
            verify(g.timeShown, "last week's time keeps its room while it fades");
            tryCompare(g, "ghostOpacity", 0, 2000);
            tryCompare(dot, "opacity", 1, 1000);
            verify(!g.timeShown);
        }

        // At a new week with the model's run-out shown, the model's window
        // may change before the week's: last week's run-out still fades out
        // in its own level.
        function test_newWeekKeepsTheSecondRunOutLevel() {
            const at = start + 3 * day;
            const g = make({ window: window([[start, 0], [at, 60]], 60), projected: "second", pollAt: at,
                             nowMs: (at + 3 * 3600) * 1000, runOutText: "Fri 12:00 AM",
                             secondWindow: window([[start, 0], [at, 95]], 95) });
            compare(g.runOutOpacity, 1);
            compare(runOutOf(g).level, 2);
            const next = history => ({ resetsAt: start + 2 * week, windowSeconds: week, percent: 1, history: history });
            g.secondWindow = next([[start + week + 3600, 1]]);
            g.window = next([[start + week + 3600, 1]]);
            compare(g.ghostOpacity, 1);
            compare(g.ghostRunOutLevel, 2, "last week's red");
            tryCompare(g, "ghostOpacity", 0, 2000);
        }

        // A reset time that jitters by a second between polls is the same
        // week: the new stretch draws on, the run-out stays, and no last
        // week fades out, with a reading or without one.
        function test_jitteredResetIsTheSameWeek() {
            const history = [[start, 0], [start + 3 * day, 60]];
            const g = make({ window: window(history, 60), pollAt: start + 3 * day, nowMs: (start + 3 * day) * 1000 });
            compare(g.runOutOpacity, 1);
            const seen = [];
            createTemporaryObject(samplerComponent, weeks, { sample: () => seen.push([g.ghostOpacity, g.runOutOpacity]) });
            const grown = history.concat([[start + 3 * day + 3600, 61]]);
            g.window = Object.assign(window(grown, 61), { resetsAt: start + week + 1 });
            compare(g.ghostMain, []);
            compare(g.ghostOpacity, 0);
            compare(g.runOutOpacity, 1);
            verify(g.drawClock < 1, "the new stretch draws on");
            tryVerify(() => g.drawClock === 1, 2000, "drawn on");
            g.window = window(grown, 61);
            compare(g.drawClock, 1, "nothing new to draw");
            wait(2 * Kirigami.Units.longDuration);
            verify(seen.length > 3);
            verify(seen.every(([ghost, runOut]) => ghost === 0 && runOut === 1), JSON.stringify(seen));
        }

        // At Plasma's Instant speed every change is drawn at once.
        function test_instant() {
            const g = make({ duration: 0 });
            poll(g);
            compare(g.drawClock, 1);
            compare(g.mainDrawn, g.mainPoints);
            compare(g.runOutOpacity, 1);
            compare(g.runOutX, Math.round(g.xAt(g.runOutAt)));
            g.window = { resetsAt: start + 2 * week, windowSeconds: week, percent: 1, history: [[start + week + 3600, 1]] };
            compare(g.ghostOpacity, 0);
        }

        // A graph closed mid-change leaves nothing to run.
        function test_closedMidChange() {
            const g = make();
            poll(g);
            g.destroy();
            wait(50);
        }
    }

    TestCase {
        id: gpus
        name: "GpuMotion"
        when: windowShown

        property var monitor: null
        property var made: []

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            monitor = monitorComponent.createObject(gpus);
        }

        // What reads the monitor goes first. A sampler, made on the cell it
        // reads, goes with it, so no frame reads a cell that has gone.
        function cleanup() {
            made.forEach(o => o.destroy());
            made = [];
            wait(0);
            monitor.destroy();
        }

        function cell() {
            const c = gpuCellComponent.createObject(root, { monitor: monitor });
            made.push(c);
            return c;
        }

        function gauge(c) {
            return root.all(c, i => i.centreWidth !== undefined)[0];
        }

        function innerArc(g) {
            return root.all(g, i => i.playReset !== undefined).sort((a, b) => a.radius - b.radius)[0];
        }

        function outerArc(g) {
            return root.all(g, i => i.playReset !== undefined).sort((a, b) => b.radius - a.radius)[0];
        }

        // The path an arc draws its reading with, after its track.
        function readingPath(arc) {
            return Array.from(arc.data).filter(o => o.strokeColor !== undefined).pop();
        }

        // An arc's width as a length along it, in percent.
        function widthAlong(arc) {
            return 100 * arc.strokeWidth / (2 * Math.PI * arc.radius);
        }

        function nameIn(c) {
            return root.all(c, i => i.room !== undefined && i.fits !== undefined)[0];
        }

        function line(c, which) {
            return root.all(c, i => i.objectName === which)[0];
        }

        // The middle with one ring and with two, at rest.
        function rooms(g) {
            const single = Math.max(0, 2 * (g.reach - 2 * g.strokeWidth / 2 - 1));
            const dual = Math.max(0, 2 * (g.innerRadius - g.innerStrokeWidth / 2 - 1));
            return { single: single, dual: dual };
        }

        // The second GPU wakes: the name makes room at once, the inner track
        // fades in, and only then does the arc draw in to its reading.
        function test_secondRingFadesInThenDrawsIn() {
            monitor.gpuInner.phase = "asleep";
            const c = cell();
            const g = gauge(c);
            const arc = innerArc(g);
            const room = rooms(g);
            compare(g.centreWidth, room.single);
            verify(!arc.visible);
            const seen = [];
            createTemporaryObject(samplerComponent, c, { sample: () => seen.push([g.innerShown, arc.percent]) });
            monitor.gpuInner.phase = "live";
            compare(g.centreWidth, room.dual, "the name makes room at once");
            compare(g.innerShown, 0, "the track starts out");
            tryCompare(arc, "percent", 3, 2000);
            compare(g.innerShown, 1);
            verify(seen.some(([shown]) => shown > 0 && shown < 1), "the track fades in");
            verify(seen.every(([shown, percent]) => shown === 1 || percent === 0), "no arc until the track is in: " + JSON.stringify(seen));
        }

        // The second GPU sleeps: the arc unwinds out of sight first, then
        // the track fades out as the name takes its room back, and the cell
        // is as it is with one ring.
        function test_secondRingUnwindsThenFadesOut() {
            monitor.gpuInner.usage = 40;
            const c = cell();
            const g = gauge(c);
            const arc = innerArc(g);
            const path = readingPath(arc);
            const room = rooms(g);
            compare(arc.percent, 40);
            const seen = [];
            createTemporaryObject(samplerComponent, c, {
                sample: () => seen.push([arc.percent, g.innerShown, g.centreWidth, path.strokeColor.a])
            });
            monitor.gpuInner.phase = "asleep";
            compare(g.innerShown, 1, "the track stays while the arc unwinds");
            tryCompare(g, "innerShown", 0, 2000);
            verify(!arc.visible);
            compare(g.centreWidth, room.single);
            verify(seen.every(([, shown, width, alpha]) => alpha === 0 || shown === 1 && width === room.dual),
                   "the track and the name wait for the arc: " + JSON.stringify(seen));
            verify(seen.every(([, shown, width]) => shown === 1 || width === room.single),
                   "the name takes its room back as the track goes: " + JSON.stringify(seen));
            verify(seen.some(([percent]) => percent > 0.5 && percent < 39.5), "unwinding");
            tryCompare(nameIn(c), "shownSize", nameIn(c).size, 1000, "the name grows to its size");
        }

        // Two rings to one goes at the pace of the track's fade, not of a
        // reading: the arc is out of sight in less time than the track then
        // takes to fade.
        function test_twoRingsToOneAtTheTracksPace() {
            monitor.gpuInner.usage = 20;
            const c = cell();
            const g = gauge(c);
            const seen = [];
            createTemporaryObject(samplerComponent, c, { sample: () => seen.push([Date.now(), g.innerShown]) });
            const start = Date.now();
            monitor.gpuInner.phase = "asleep";
            tryCompare(g, "innerShown", 0, 2000);
            wait(50);
            const fading = seen.find(([, shown]) => shown < 1)[0];
            const gone = seen.find(([, shown]) => shown === 0)[0];
            verify(fading - start < gone - fading, "unwound in " + (fading - start) + " ms, faded in " + (gone - fading) + " ms");
        }

        // A first reading, as after a GPU wakes, draws in at the track's
        // pace; an ordinary reading over the same distance takes the ring's
        // full settle.
        function test_firstReadingDrawsInAtTheTracksPace() {
            monitor.gpuOuter.usage = 0;
            const c = cell();
            const g = gauge(c);
            const arc = outerArc(g);
            const seen = [];
            createTemporaryObject(samplerComponent, c, { sample: () => seen.push([Date.now(), arc.percent]) });
            const timed = usage => {
                const start = Date.now();
                monitor.gpuOuter.usage = usage;
                tryCompare(arc, "percent", 46, 2000);
                wait(50);
                return seen.find(([at, percent]) => at >= start && percent === 46)[0] - start;
            };
            tryVerify(() => !g.shifting, 1000);
            const ordinary = timed(46);
            monitor.gpuOuter.usage = NaN;
            tryCompare(arc, "percent", 0, 2000);
            tryVerify(() => !g.shifting, 1000);
            const first = timed(46);
            verify(first < 0.75 * ordinary, "first " + first + " ms, ordinary " + ordinary + " ms");
            compare(g.arcSettle, g.settle, "and back to a reading's pace");
        }

        // A reading that goes missing, as when the discrete GPU wakes before
        // its first reading, unwinds the arc out of sight, without its round
        // caps lingering as a dot at twelve o'clock.
        function test_noCapLeftByAMissingReading() {
            monitor.gpuOuter.usage = 12;
            const c = cell();
            const arc = outerArc(gauge(c));
            const path = readingPath(arc);
            const width = widthAlong(arc);
            const seen = [];
            createTemporaryObject(samplerComponent, c, { sample: () => seen.push([arc.percent, path.strokeColor.a]) });
            monitor.gpuOuter.usage = NaN;
            tryCompare(arc, "percent", 0, 2000);
            verify(seen.some(([percent]) => percent > 0 && percent < width), "it unwinds through its width: " + JSON.stringify(seen));
            verify(seen.every(([percent, alpha]) => percent >= width || alpha === 0), JSON.stringify(seen));
        }

        // The name scales as a texture, so its strokes soften rather than
        // drop out, and is drawn as text again once it is at its size.
        function test_nameScalesAsATexture() {
            const c = cell();
            const name = nameIn(c);
            // A 12 pt small font, as the host's test theme has, so the
            // name is smaller inside two rings than inside one; at the
            // floor's 7 pt it fits whole in both.
            name.sizeFactor = 12 / Kirigami.Theme.smallFont.pointSize;
            tryCompare(name, "shownSize", name.size, 1000);
            verify(!name.layer.enabled);
            const seen = [];
            createTemporaryObject(samplerComponent, c, { sample: () => seen.push([name.shownSize !== name.size, name.layer.enabled]) });
            monitor.gpuInner.phase = "asleep";
            tryVerify(() => name.shownSize !== name.size, 2000, "scaling");
            tryCompare(name, "shownSize", name.size, 2000);
            verify(seen.every(([scaling, layered]) => scaling === layered), JSON.stringify(seen));
            verify(!name.layer.enabled, "drawn as text at rest");
        }

        // A ring resized, as the panel's thickness changes, has its name at
        // the new size at once, shown or left out, so the name keeps up with
        // its ring; only a change of room at one size eases it.
        function test_nameKeepsUpWithAResize() {
            const c = cell();
            const name = nameIn(c);
            const seen = [];
            createTemporaryObject(samplerComponent, c, { sample: () => seen.push([name.shownSize, name.size, name.opacity]) });
            const sizes = [];
            const fitted = [];
            for (const ring of [22, 46, 30, 60, 46]) {
                c.ring = ring;
                compare(name.shownSize, name.size, ring + " px: at its size at once");
                compare(name.opacity, name.fits ? 1 : 0, ring + " px: shown or left out at once");
                sizes.push(name.size);
                fitted.push(name.fits);
                wait(20);
            }
            verify(new Set(sizes).size > 1 && fitted.includes(true) && fitted.includes(false), JSON.stringify([sizes, fitted]));
            verify(seen.every(([shown, size, opacity]) => shown === size && (opacity === 0 || opacity === 1)), JSON.stringify(seen));
            verify(!name.layer.enabled);
        }

        // A change back mid-fade turns the track round where it is. It is
        // made from a frame, after the cell's first has been drawn: polling
        // for the middle of the fade misses it on a busy machine.
        function test_reversesCleanly() {
            monitor.gpuInner.phase = "asleep";
            const c = cell();
            const g = gauge(c);
            waitForRendering(c);
            const turn = { at: NaN, after: NaN };
            const seen = [];
            createTemporaryObject(samplerComponent, c, { sample: () => {
                if (Number.isNaN(turn.at) && g.innerShown > 0 && g.innerShown < 1) {
                    turn.at = g.innerShown;
                    monitor.gpuInner.phase = "asleep";
                    turn.after = g.innerShown;
                }
                if (!Number.isNaN(turn.at)) {
                    seen.push(g.innerShown);
                }
            } });
            monitor.gpuInner.phase = "live";
            tryVerify(() => !Number.isNaN(turn.at), 2000, "fading in");
            compare(turn.after, turn.at, "no jump");
            tryCompare(g, "innerShown", 0, 2000);
            verify(seen.every((v, i) => i === 0 || v <= seen[i - 1] + 1e-9), "straight back out: " + JSON.stringify(seen));
            compare(innerArc(g).percent, 0, "and the arc never started");
        }

        // A hand-off to the integrated GPU fades the readings out, changes
        // them and fades them back in; ordinary readings change at once.
        function test_readingsFadeToAnotherGpu() {
            const c = cell();
            const readout = line(c, "first").parent;
            compare(line(c, "first").text, "12%");
            monitor.gpuOuter.usage = 15;
            compare(line(c, "first").text, "15%", "a reading changes at once");
            monitor.gpuOuter.phase = "asleep";
            compare(line(c, "first").text, "15%", "held as it fades");
            tryVerify(() => readout.opacity < 1, 1000, "fading out");
            tryCompare(line(c, "first"), "text", "3%", 1000);
            tryCompare(readout, "opacity", 1, 1000);
            compare(line(c, "second").text, "41°");
        }

        // At Plasma's Instant speed the ring, the name and the readings are
        // as they will be at once.
        function test_instant() {
            const c = cell();
            c.animated = false;
            const g = gauge(c);
            g.settle = 0;
            const room = rooms(g);
            monitor.gpuInner.phase = "asleep";
            compare(g.innerShown, 0);
            compare(g.centreWidth, room.single);
            monitor.gpuInner.phase = "live";
            compare(g.innerShown, 1);
            compare(innerArc(g).percent, 3);
            compare(g.centreWidth, room.dual);
            monitor.gpuOuter.phase = "asleep";
            compare(line(c, "first").text, "3%");
            compare(line(c, "first").parent.opacity, 1);
        }

        function load() {
            const loader = popupHost.createObject(root);
            made.push(loader);
            loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/GpuPopup.qml"), { monitor: monitor });
            const popup = loader.item;
            waitForRendering(popup);
            return popup;
        }

        function sections(popup) {
            return root.all(popup, i => i.awake !== undefined && i.first !== undefined);
        }

        function visibleTexts(popup) {
            return root.all(popup, i => typeof i.text === "string" && i.text !== "" && i.visible
                            && (function () { for (let p = i; p; p = p.parent) { if (!p.visible) return false; } return true; })())
                .map(i => i.text);
        }

        // A GPU going to sleep fades its section out with its last readings,
        // then gives way to its line at the end: the popup changes height
        // once. Waking, the section opens at once below the integrated GPU's
        // and fades in.
        function test_popupSectionFadesOutThenIn() {
            const popup = load();
            const [inner, outer] = sections(popup);
            verify(inner.first, "the integrated GPU's section opens the page");
            const heights = [];
            popup.implicitHeightChanged.connect(() => heights.push(popup.implicitHeight));
            const before = popup.implicitHeight;
            monitor.gpuOuter.phase = "asleep";
            verify(outer.visible);
            verify(outer.slot.usage === 12, "keeping its last reading");
            verify(!visibleTexts(popup).some(t => t.endsWith(" · off")), "no line yet");
            tryVerify(() => outer.opacity < 1, 1000, "fading out");
            compare(outer.slot.temperature, 48);
            const temperatureGraph = root.all(outer, i => i.hasReading !== undefined)[0];
            verify(temperatureGraph.visible, "its temperature graph fades out with it");
            tryCompare(outer, "visible", false, 1000);
            verify(visibleTexts(popup).includes("AMD Radeon RX 7700S · off"));
            verify(inner.first, "the integrated GPU's section still opens the page");
            // The height follows at the layout's next polish.
            tryVerify(() => heights.length > 0, 1000, "the popup's height changes");
            waitForRendering(popup);
            compare(heights.length, 1, "one change of height: " + JSON.stringify(heights));
            heights.length = 0;
            monitor.gpuOuter.phase = "live";
            verify(outer.visible, "open at once");
            verify(outer.opacity < 1, "and fading in");
            verify(inner.first && !outer.first, "below the integrated GPU's");
            verify(!visibleTexts(popup).some(t => t.endsWith(" · off")));
            tryCompare(outer, "opacity", 1, 1000);
            compare(popup.implicitHeight, before);
            compare(heights.length, 1, "one change of height: " + JSON.stringify(heights));
        }

        // Waking again before the section has gone, it fades back up and the
        // popup keeps its height.
        function test_popupSectionTurnsBack() {
            const popup = load();
            const outer = sections(popup)[1];
            const before = popup.implicitHeight;
            monitor.gpuOuter.phase = "asleep";
            tryVerify(() => outer.opacity < 0.9, 1000, "fading out");
            monitor.gpuOuter.phase = "live";
            tryCompare(outer, "opacity", 1, 1000);
            wait(Kirigami.Units.longDuration);
            verify(outer.visible);
            compare(popup.implicitHeight, before);
        }

        function test_popupInstant() {
            const popup = load();
            popup.animated = false;
            const outer = sections(popup)[1];
            monitor.gpuOuter.phase = "asleep";
            verify(!outer.visible);
            verify(visibleTexts(popup).includes("AMD Radeon RX 7700S · off"));
        }
    }

    TestCase {
        id: strikes
        name: "StrikeMotion"
        when: windowShown

        property var monitor: null
        property var made: []

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            monitor = monitorComponent.createObject(strikes);
        }

        function cleanup() {
            made.forEach(o => o.destroy());
            made = [];
            wait(0);
            monitor.destroy();
        }

        function cell() {
            const c = usageCellComponent.createObject(root, { monitor: monitor });
            made.push(c);
            waitForRendering(c);
            return c;
        }

        function outerArc(c) {
            return root.all(c, i => i.playReset !== undefined).sort((a, b) => b.radius - a.radius)[0];
        }

        function line(c, which) {
            return root.all(c, i => i.objectName === which)[0];
        }

        // Claude's entry with a check that failed, the reading ten minutes old.
        function failed(ok) {
            const now = Date.now() / 1000;
            return Object.assign({}, ok, { fetchedAt: now - 600, lastError: "down", lastErrorAt: Math.floor(now),
                                           reason: "other", host: "", retryAt: Math.floor(now) + 300 });
        }

        function setClaude(entry) {
            monitor.usage.entries = Object.assign({}, monitor.usage.entries, { claude: entry });
        }

        // The stroke and its path, which runs from the bottom left.
        function strike(c) {
            return root.all(c, i => i.lineWidth !== undefined)[0];
        }

        function strikePath(c) {
            return Array.from(strike(c).data).find(o => o.strokeColor !== undefined);
        }

        // How much of the stroke's length is drawn, 0 to 1.
        function drawnLength(c) {
            const path = strikePath(c);
            return (path.pathElements[0].x - path.startX) / (2 * strike(c).half);
        }

        // The stroke starts as the arcs near the end of their way down, and
        // the dashes come with it; on recovery the stroke comes off, the
        // readings return, and only then do the arcs grow back. Each way
        // takes about Plasma's long duration and a half.
        function test_strikeFollowsTheUnwind() {
            const ok = monitor.usage.entries.claude;
            const c = cell();
            const g = c.children[0];
            const arc = outerArc(c);
            const seen = [];
            createTemporaryObject(samplerComponent, c, {
                sample: () => seen.push({ at: Date.now(), struck: g.struck, percent: arc.percent, first: line(c, "first").text,
                                          opacity: strike(c).opacity, drawn: drawnLength(c) })
            });
            const start = Date.now();
            setClaude(failed(ok));
            tryCompare(g, "struck", 1, 3000);
            // Timed here: the last frame may not have been sampled yet.
            const struckAt = Date.now() - start;
            tryCompare(arc, "percent", 0, 3000);
            const first = seen.find(f => f.struck > 0);
            verify(first.percent <= 52 / 3, "the arc is mostly down when the stroke starts: " + first.percent);
            verify(first.at - start >= Kirigami.Units.longDuration / 2 - 20, "it waits for the arcs: " + (first.at - start) + " ms");
            // It starts as a short stroke fading in, then draws to its end.
            verify(seen.filter(f => f.struck > 0).every(f => Math.abs(f.opacity - Math.min(1, 4 * f.struck)) < 1e-6
                                                        && Math.abs(f.drawn - (0.15 + 0.85 * f.struck)) < 1e-6),
                   JSON.stringify(seen));
            verify(seen.some(f => f.struck > 0 && f.struck < 1), "the stroke draws on");
            verify(seen.every(f => (f.first === "––%") === (f.struck > 0.25)), "the dashes come with the stroke: " + JSON.stringify(seen));
            verify(struckAt <= 2.5 * Kirigami.Units.longDuration + 200, "struck in " + struckAt + " ms");

            seen.length = 0;
            const back = Date.now();
            setClaude(ok);
            tryCompare(g, "struck", 0, 3000);
            const offAt = Date.now() - back;
            verify(offAt <= Kirigami.Units.longDuration + 200, "off in " + offAt + " ms");
            tryCompare(arc, "percent", 52, 3000);
            const grown = seen.find(f => f.percent > 0);
            verify(grown.struck <= 0.25, "the stroke is off before the arc grows: " + grown.struck);
            verify(seen.some(f => f.struck > 0 && f.struck < 1), "the stroke comes off");
            verify(seen.every(f => (f.first === "––%") === (f.struck > 0.25)), "the readings return with it");
        }

        // A grey reading that grows too old unwinds in grey into the stroke:
        // no amber or red, and never brighter than the grey, as the arcs
        // pass down through the levels.
        function test_greyIntoTheStrike() {
            const base = monitor.usage.entries.claude;
            const hot = Object.assign({}, base, { weekly: Object.assign({}, base.weekly, { percent: 93 }),
                                                  scoped: [Object.assign({}, base.scoped[0], { percent: 97 })] });
            setClaude(hot);
            const c = cell();
            const g = c.children[0];
            const arcs = root.all(c, i => i.playReset !== undefined).sort((a, b) => b.radius - a.radius);
            tryCompare(arcs[0], "percent", 93, 3000);
            setClaude(Object.assign(failed(hot), { fetchedAt: Date.now() / 1000 - 60 }));
            tryCompare(g, "greyed", 1, 3000);
            const text = Kirigami.Theme.textColor;
            const seen = [];
            createTemporaryObject(samplerComponent, c, {
                sample: () => seen.push(arcs.map(a => [a.color.r, a.color.g, a.color.b, a.color.a]))
            });
            setClaude(failed(hot));
            tryCompare(g, "struck", 1, 3000);
            tryCompare(arcs[0], "percent", 0, 3000);
            verify(seen.length > 0);
            const plain = rgba => Math.abs(rgba[0] - text.r) < 0.01 && Math.abs(rgba[1] - text.g) < 0.01
                && Math.abs(rgba[2] - text.b) < 0.01;
            verify(seen.every(([outer, inner]) => plain(outer) && plain(inner)), "no amber or red: " + JSON.stringify(seen));
            verify(seen.every(([outer]) => outer[3] <= 0.42 * text.a + 0.01), "no brighter than grey: " + JSON.stringify(seen));
        }

        // A ring made struck, as a popup's opening on a failed check, shows
        // its stroke whole from the first frame rather than drawing it.
        function test_madeStruck() {
            const g = createTemporaryObject(gaugeComponent, root, { cancelled: true });
            verify(g.settle > 0);
            const seen = [];
            createTemporaryObject(samplerComponent, g, { sample: () => seen.push(g.struck) });
            compare(g.struck, 1);
            wait(2 * Kirigami.Units.longDuration);
            verify(seen.length > 0 && seen.every(v => v === 1), JSON.stringify(seen));
        }

        // A change of Plasma's speed to Instant while the stroke waits to
        // draw strikes the ring at once.
        function test_instantWhileStriking() {
            const c = cell();
            const g = c.children[0];
            setClaude(failed(monitor.usage.entries.claude));
            wait(20);
            verify(g.struck < 1, "still to draw");
            g.settle = 0;
            compare(g.struck, 1);
            wait(2 * Kirigami.Units.longDuration);
            compare(g.struck, 1, "and stays");
        }

        // Grey comes and goes as a fade, with the arcs where they are.
        function test_greyFades() {
            const ok = monitor.usage.entries.claude;
            const c = cell();
            const g = c.children[0];
            const seen = [];
            createTemporaryObject(samplerComponent, c, { sample: () => seen.push(g.greyed) });
            setClaude(Object.assign(failed(ok), { fetchedAt: Date.now() / 1000 - 60 }));
            tryCompare(g, "greyed", 1, 3000);
            verify(seen.some(v => v > 0 && v < 1), "it fades: " + JSON.stringify(seen));
            compare(outerArc(c).percent, 52);
            compare(g.struck, 0);
        }

        // At Plasma's Instant speed a failed check is struck in one frame,
        // and a good one puts it back in one.
        function test_instant() {
            const ok = monitor.usage.entries.claude;
            const c = cell();
            const g = c.children[0];
            g.settle = 0;
            const seen = [];
            createTemporaryObject(samplerComponent, c, { sample: () => seen.push([g.struck, outerArc(c).percent]) });
            setClaude(failed(ok));
            waitForRendering(c);
            wait(50);
            verify(seen.length > 0 && seen.every(([struck, percent]) => struck === 1 && percent === 0), JSON.stringify(seen));
            seen.length = 0;
            setClaude(ok);
            waitForRendering(c);
            wait(50);
            verify(seen.length > 0 && seen.every(([struck, percent]) => struck === 0 && percent === 52), JSON.stringify(seen));
        }
    }

    TestCase {
        id: loads
        name: "LoadingMotion"
        when: windowShown

        property var monitor: null
        property var made: []

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            monitor = monitorComponent.createObject(loads);
            monitor.usage.entries = {};
            monitor.usage.pending = ["claude"];
        }

        function cleanup() {
            made.forEach(o => o.destroy());
            made = [];
            wait(0);
            monitor.destroy();
        }

        // Claude's cell, loading, with `settle` set first where given.
        function cell(settle) {
            const c = usageCellComponent.createObject(root, { monitor: monitor });
            made.push(c);
            if (settle !== undefined) {
                c.children[0].settle = settle;
            }
            return c;
        }

        function bead(c) {
            return root.all(c, i => i.turning !== undefined)[0];
        }

        function dots(c) {
            return root.all(c, i => i.covered !== undefined)[0];
        }

        function outerArc(c) {
            return root.all(c, i => i.playReset !== undefined).sort((a, b) => b.radius - a.radius)[0];
        }

        // The outer ring's track, the first of its paths.
        function track(c) {
            return Array.from(outerArc(c).data).filter(o => o.capStyle !== undefined)[0];
        }

        function readout(c) {
            return root.all(c, i => i.oneLine !== undefined)[0];
        }

        function line(c, which) {
            return root.all(c, i => i.objectName === which)[0];
        }

        // What holds the mark in the ring's middle, which dims it.
        function middle(c) {
            const face = outerArc(c).parent;
            let item = root.all(c, i => i.markName !== undefined)[0];
            while (item.parent !== face) {
                item = item.parent;
            }
            return item;
        }

        function okClaude() {
            const usage = monitor.usage;
            return { status: "ok", fetchedAt: usage.createdAt, weekly: usage.window(52, 2 * usage.day, []), scoped: [] };
        }

        function failedClaude() {
            const now = Math.floor(Date.now() / 1000);
            return { status: "error", lastError: "down", lastErrorAt: now, reason: "other", host: "", retryAt: now + 300 };
        }

        function setClaude(entry) {
            monitor.usage.entries = { claude: entry };
        }

        // Every frame's state of the ring's waiting look.
        function record(c) {
            const g = c.children[0];
            const seen = [];
            createTemporaryObject(samplerComponent, c, {
                sample: () => seen.push({ at: Date.now(), moving: g.moving, motion: g.motion, dots: g.dotsShown, sweep: g.sweep,
                                          covered: dots(c).covered, circles: dots(c).data[0].pathElements[0].path.split("M ").length - 1,
                                          struck: g.struck, percent: outerArc(c).percent,
                                          track: outerArc(c).trackColor.a, trackSweep: outerArc(c).trackSweep, cap: track(c).capStyle,
                                          text: readout(c).opacity, first: line(c, "first").text, mark: middle(c).opacity })
            });
            return seen;
        }

        // The ring as drawn.
        function shot(c) {
            return grabImage(c.children[0]);
        }

        // For the first second the dots stand still, so a reply within it
        // only fills the ring in: nothing ever moves.
        function test_stillForASecond() {
            const c = cell();
            const g = c.children[0];
            const seen = record(c);
            const start = Date.now();
            // Well inside the second, so a slow run still checks the shots
            // before the lit dot is due.
            wait(600);
            verify(seen.length > 10 && seen.every(f => !f.moving && f.motion === 0 && f.dots === 1 && f.sweep === 0),
                   JSON.stringify(seen.slice(-3)));
            const still = shot(c);
            wait(100);
            verify(still.equals(shot(c)), "nothing moves");
            verify(Date.now() - start < 1000);
            setClaude(okClaude());
            tryCompare(g, "dotsShown", 0, 3000);
            compare(g.sweep, 1);
            wait(1200);
            verify(seen.every(f => !f.moving && f.motion === 0), "nothing ever moved");
            verify(!g.waited);
        }

        // After a second a lit dot travels round the still dots, fading
        // in, at its own pace, until a 30 s timer stops it, which leaves
        // the dots still.
        function test_beadTravels() {
            const c = cell();
            const g = c.children[0];
            const start = Date.now();
            tryCompare(g, "moving", true, 3000);
            verify(Date.now() - start >= 950, "after a second: " + (Date.now() - start));
            tryCompare(g, "motion", 1, 1000);
            verify(bead(c).visible);
            const a = shot(c);
            wait(250);
            verify(!a.equals(shot(c)), "the dot travels");
            compare(g.dotsShown, 1, "the dots stay");

            const cap = g.resources.find(r => r.interval === 30000);
            verify(cap && cap.running, "a 30 s stop");
            cap.triggered();
            verify(!g.moving);
            tryCompare(g, "motion", 0, 1000);
            verify(!bead(c).visible);
            compare(g.dotsShown, 1, "still dots");
            const b = shot(c);
            wait(250);
            verify(b.equals(shot(c)), "nothing moves after the stop");
        }

        // Started where the clock says, two rings travel in step.
        function test_inStep() {
            const one = cell();
            wait(700);
            const two = cell();
            const [g1, g2] = [one.children[0], two.children[0]];
            tryCompare(g2, "moving", true, 3000);
            wait(300);
            g1.capped = true;
            g2.capped = true;
            const d = Math.abs(bead(one).rotation - bead(two).rotation) % 360;
            verify(Math.min(d, 360 - d) < 15, bead(one).rotation + " and " + bead(two).rotation);
        }

        // Hidden, the window stops the dot; shown again, it goes on.
        function test_stopsWhileHidden() {
            const w = createTemporaryObject(windowComponent, root);
            const c = usageCellComponent.createObject(w.contentItem, { monitor: monitor });
            made.push(c);
            const g = c.children[0];
            tryCompare(g, "moving", true, 3000);
            w.visible = false;
            verify(!g.moving, "stopped while hidden");
            w.visible = true;
            tryCompare(g, "moving", true, 1000);
        }

        // An invisible ring, as on a popup page not shown, stops the dot
        // too, though its window shows.
        function test_stopsWhileInvisible() {
            const c = cell();
            const g = c.children[0];
            tryCompare(g, "motion", 1, 3000);
            c.visible = false;
            verify(!g.moving, "stopped while invisible");
            tryCompare(g, "motion", 0, 1000);
            c.visible = true;
            tryCompare(g, "moving", true, 1000);
        }

        // A ring that waits again after its 30 s stop, as when the item is
        // turned off and on, moves again after a second.
        function test_waitingAgainAfterTheStop() {
            const c = cell();
            const g = c.children[0];
            tryCompare(g, "moving", true, 3000);
            g.resources.find(r => r.interval === 30000).triggered();
            verify(g.capped && !g.moving);
            monitor.usage.pending = [];
            wait(50);
            monitor.usage.pending = ["claude"];
            tryCompare(g, "moving", true, 3000, "moving again");
        }

        // At Instant nothing moves: the dots stay still, and the reading
        // replaces them in one frame, the numbers with it.
        function test_instant() {
            const c = cell(0);
            const g = c.children[0];
            const seen = record(c);
            wait(1300);
            verify(g.waited && !g.moving);
            verify(seen.every(f => f.motion === 0), "never moves");
            setClaude(okClaude());
            waitForRendering(c);
            wait(50);
            const after = seen.filter(f => f.first !== "–");
            verify(after.length > 0 && after.every(f => f.dots === 0 && f.sweep === 1 && f.percent === 52 && f.text === 1),
                   JSON.stringify(after.slice(0, 3)));
        }

        // A reading fades the dot out first, then fills the track in over
        // the dots from twelve, covering them as it goes, while the arc
        // draws in on top and the numbers and the mark fade in.
        function test_arrival() {
            const c = cell();
            const g = c.children[0];
            tryCompare(g, "motion", 1, 3000);
            const seen = record(c);
            const start = Date.now();
            setClaude(okClaude());
            tryCompare(g, "dotsShown", 0, 3000);
            tryCompare(readout(c), "opacity", 1, 3000);
            tryCompare(outerArc(c), "percent", 52, 3000);
            // The sampler may not have run since the frame that ended the fill.
            tryVerify(() => seen.some(f => f.sweep === 1) && seen.some(f => f.motion === 0), 1000,
                      "sampled to the end: " + JSON.stringify(seen.slice(-3)));
            const filling = seen.filter(f => f.sweep > 0 && f.sweep < 1);
            verify(filling.length >= 5, "the track fills in: " + JSON.stringify(seen.map(f => f.sweep)));
            verify(seen.filter(f => f.sweep >= 0.4).every(f => f.motion === 0), "the dot is gone first");
            const gone = seen.find(f => f.motion === 0);
            verify(gone.at - start <= Kirigami.Units.shortDuration + 80, "the dot fades in " + (gone.at - start) + " ms");
            const filled = seen.find(f => f.sweep === 1);
            verify(filled.at - start <= Kirigami.Units.veryLongDuration + 150, "filled in " + (filled.at - start) + " ms");
            verify(filling.every((f, i) => i === 0 || f.covered >= filling[i - 1].covered), "the dots go as the track reaches them");
            verify(filling.some(f => f.covered > 0 && f.covered < dots(c).count));
            verify(filling.every(f => f.circles === dots(c).count - f.covered), "drawn ahead of the track only");
            verify(filling.every(f => f.track > 0), "the track is drawn as it fills");
            verify(filling.every(f => Math.abs(f.trackSweep - f.sweep) < 1e-9), "only as far as it has filled");
            verify(filling.every(f => f.cap === ShapePath.FlatCap), "a part track ends square, over no dot");
            compare(track(c).capStyle, ShapePath.SquareCap, "a whole track as before");
            verify(seen.some(f => f.percent > 0 && f.sweep < 1), "the arc draws in with it");
            verify(seen.some(f => f.text > 0 && f.text < 1), "the numbers fade in");
            verify(seen.some(f => f.mark > 0.4 && f.mark < 1), "the mark brightens");
            verify(seen.every(f => f.struck === 0));
            compare(middle(c).opacity, 1);
        }

        // A first check that fails fades the dot and the dots into the
        // track where they are, never filling from twelve, holds the mark
        // dim, and only then draws the stroke, the failed dashes with it.
        function test_failure() {
            const c = cell();
            const g = c.children[0];
            tryCompare(g, "motion", 1, 3000);
            const seen = record(c);
            setClaude(failedClaude());
            tryCompare(g, "struck", 1, 3000);
            wait(50);
            verify(seen.every(f => f.sweep === 0 || f.sweep === 1), "no fill from twelve");
            verify(seen.some(f => f.dots > 0 && f.dots < 1 && f.track > 0), "the dots fade into the track");
            verify(seen.every(f => f.covered === 0 || f.dots === 0), "no dot is covered");
            const firstStroke = seen.find(f => f.struck > 0);
            verify(firstStroke.dots === 0, "the stroke waits for the dots: " + JSON.stringify(firstStroke));
            verify(seen.every(f => f.mark <= 0.4 + 1e-6), "the mark stays dim: " + JSON.stringify(seen.map(f => f.mark)));
            verify(seen.every(f => (f.first === "––%") === (f.struck > 0.25)), "the dashes come with the stroke");
            verify(seen.every(f => f.text === 1), "nothing fades in");
            const end = seen[seen.length - 1];
            compare([end.dots, end.sweep, end.motion], [0, 1, 0]);
            fuzzyCompare(end.track, 0.16 * Kirigami.Theme.textColor.a, 0.002);
        }
    }
}
