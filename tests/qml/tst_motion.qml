// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/popups"
import "../../package/contents/ui/code/format.js" as Format
import "../../package/contents/ui/code/history.js" as History

// How readings move: a ring's arc follows a new reading without passing it
// and bends when another arrives mid-move, its colour turns as it passes 75
// and 90 %, and the number in a popup's ring counts with it; a history
// graph's points ease to a new sample in their slots; a week graph's new
// stretch draws on and its run-out, marker and old week fade; a second GPU's
// ring fades its track in and then draws its arc in, and goes the other way
// round, and its popup section fades in and out. A duration of 0, as
// Plasma's Instant animation speed gives, puts everything in place at once.
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
        id: ruleComponent
        LimitRule {
            width: 200
            height: 40
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

        // A new sample: nothing is drawn ahead of it, then every point eases
        // from the height it had in its slot, the newest from the last
        // reading, and comes to rest on the new samples.
        function test_easesInPlace() {
            const g = createTemporaryObject(graphComponent, root, { values: start });
            const before = xy(g.mainDrawn);
            compare(before, rest(g, start));
            const next = History.push(start, 90, 12);
            g.values = next;
            compare(xy(g.mainDrawn), before, "nothing drawn ahead of the easing");
            tryVerify(() => g.mainFrom.length > 0, 1000, "easing");
            compare(xy(g.mainFrom), before, "each point from its slot's old height");
            verify(g.progress < 1);
            tryVerify(() => g.progress === 1, 2000, "eased");
            compare(xy(g.mainDrawn), rest(g, next));
            compare(xy(g.mainPoints), rest(g, next), "at rest where the samples put it");
        }

        // A rate's new top comes with its sample and eases in with it, so the
        // line meets the peak its caption names as it comes to rest.
        function test_newTopEasesWithTheSample() {
            const g = createTemporaryObject(graphComponent, root, { values: start, maximum: 100 });
            const before = xy(g.mainDrawn);
            const next = History.push(start, 180, 12);
            g.values = next;
            g.maximum = 180;
            tryVerify(() => g.mainFrom.length > 0, 1000, "easing");
            compare(xy(g.mainFrom), before, "from the line drawn at the old top");
            tryVerify(() => g.progress === 1, 2000, "eased");
            compare(xy(g.mainDrawn), rest(g, next, 180));
        }

        // A sample mid-ease starts from where the line is drawn, between
        // where the last one eased from and to, not from either end.
        function test_aSampleMidEaseStartsWhereTheLineIs() {
            const g = createTemporaryObject(graphComponent, root, { values: start });
            const first = History.push(start, 95, 12);
            g.values = first;
            tryVerify(() => g.progress > 0.2 && g.progress < 0.8, 2000, "half way");
            const from = xy(g.mainFrom);
            const to = rest(g, first);
            g.values = History.push(first, 10, 12);
            tryVerify(() => g.mainFrom.length > 0 && g.mainFrom[0].y !== from[0][1], 1000, "easing again");
            const again = xy(g.mainFrom);
            let between = 0;
            for (let i = 0; i < again.length; ++i) {
                const [low, high] = [Math.min(from[i][1], to[i][1]), Math.max(from[i][1], to[i][1])];
                verify(again[i][1] >= low - 1e-9 && again[i][1] <= high + 1e-9, "slot " + i + " in reach");
                between += again[i][1] > low && again[i][1] < high ? 1 : 0;
            }
            verify(between > again.length / 2, "drawn part way: " + between + " of " + again.length);
        }

        // While the history grows in, each sample moves a slot left and the
        // new one grows out of the old end.
        function test_growingIn() {
            const g = createTemporaryObject(graphComponent, root, { values: [30, 60] });
            const before = xy(g.mainDrawn);
            g.values = [30, 60, 20];
            tryVerify(() => g.mainFrom.length > 0, 1000, "easing");
            compare(xy(g.mainFrom), before.concat([before[1]]));
            tryVerify(() => g.progress === 1, 2000, "eased");
            compare(xy(g.mainDrawn), rest(g, [30, 60, 20]));
        }

        // A sample that changes nothing drawn, and any change but a sample,
        // such as a cleared history, are drawn at once, with no frames.
        function test_noEasingWhereNothingMoves() {
            const flat = Array(12).fill(0);
            const g = createTemporaryObject(graphComponent, root, { values: flat });
            g.values = History.push(flat, 0, 12);
            wait(50);
            compare(g.mainFrom, []);
            compare(g.progress, 1);
            g.values = [];
            tryCompare(g, "mainDrawn", []);
            compare(g.progress, 1);
        }

        // New readings that move the 100 % label to the other end fade it
        // out there and back in at its new end; a resize moves it at once.
        function test_ruleLabelFadesToItsOtherEnd() {
            const rule = createTemporaryObject(ruleComponent, root);
            const label = rule.children.find(c => c.text !== undefined);
            compare(label.x, 0);
            rule.series = [[{ x: 0, y: 1 }, { x: 200, y: 39 }]];
            compare(rule.atStart, false, "decided at once");
            compare(label.x, 0, "still at the start");
            tryVerify(() => label.opacity < 1, 1000, "fading");
            compare(label.x, 0, "while it fades out");
            tryCompare(label, "x", rule.width - label.implicitWidth, 1000);
            tryCompare(label, "opacity", 1, 1000);

            rule.series = [[{ x: 0, y: 1 }, { x: 180, y: 1 }]];
            tryCompare(label, "x", 0, 1000);
            tryCompare(label, "opacity", 1, 1000);
            rule.width = 400;
            compare(rule.atStart, false);
            compare(label.x, rule.width - label.implicitWidth, "resized: moved at once");
            compare(label.opacity, 1);
        }

        // A resize that leaves the label where it was, as a popup's first
        // layout does, still lets the next readings that move it fade it.
        function test_ruleLabelFadesAfterAResize() {
            const rule = createTemporaryObject(ruleComponent, root);
            const label = rule.children.find(c => c.text !== undefined);
            rule.width = 300;
            compare(label.x, 0);
            wait(10);
            rule.series = [[{ x: 0, y: 1 }, { x: 300, y: 39 }]];
            compare(rule.atStart, false);
            compare(label.x, 0, "still at the start");
            tryVerify(() => label.opacity < 1, 1000, "fading");
            tryCompare(label, "x", rule.width - label.implicitWidth, 1000);
            tryCompare(label, "opacity", 1, 1000);
        }

        // A graph is still before the next sample, however slow Plasma's
        // animation speed.
        function test_easesWithinHalfTheInterval() {
            const g = createTemporaryObject(graphComponent, root, { values: start, interval: 300 });
            compare(g.duration, Math.min(Kirigami.Units.longDuration, 150));
            g.interval = 0;
            compare(g.duration, Kirigami.Units.longDuration);
            verify(Kirigami.Units.longDuration > 150, "the test runs at an animation speed the cap shortens");
        }

        // At Plasma's Instant speed a sample is drawn as it arrives.
        function test_instant() {
            const g = createTemporaryObject(graphComponent, root, { values: start, duration: 0 });
            const next = History.push(start, 90, 12);
            g.values = next;
            compare(xy(g.mainDrawn), rest(g, next));
            g.maximum = 180;
            compare(xy(g.mainDrawn), rest(g, next, 180));
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

        // The new stretch draws on from the old end and lands on the new
        // reading; the run-out it brings waits until then and fades in.
        function test_drawsOnThenTheRunOutFadesIn() {
            const g = make();
            const old = end(g.mainPoints);
            compare(g.runOutOpacity, 0);
            const seen = [];
            createTemporaryObject(samplerComponent, weeks, { sample: () => seen.push([g.drawClock, g.runOutOpacity]) });
            poll(g);
            compare(end(g.mainDrawn), old, "from the old end");
            verify(g.drawClock < 1);
            compare(g.projection.length, 2, "on course to run out");
            tryVerify(() => g.drawClock === 1, 2000, "drawn on");
            compare(end(g.mainDrawn), end(g.mainPoints), "on the new reading");
            tryCompare(g, "runOutOpacity", 1, 2000);
            verify(seen.length > 3);
            verify(seen.every(([clock, opacity]) => clock === 1 || opacity === 0), "no run-out while it draws on: " + JSON.stringify(seen));
            compare(g.runOutEnd.x, g.projection[1].x);
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
            const at = g.shownRunOutAt;
            g.projected = "";
            compare(g.projection.length, 0);
            tryVerify(() => g.runOutOpacity > 0 && g.runOutOpacity < 1, 1000, "fading out");
            compare(g.shownRunOutAt, at, "where it was");
            tryCompare(g, "runOutOpacity", 0, 1000);
        }

        // The marker for now fades in once the reading is hours old.
        function test_staleMarkerFades() {
            const g = make();
            const marker = g.children.find(i => i.width === 1 && i.radius !== undefined && i.y > 0 && i.height > 10);
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
            const g = make({ window: window([[start, 0], [start + 3 * day, 60]], 60), pollAt: start + 3 * day,
                             nowMs: (start + 3 * day + 3 * 3600) * 1000 });
            compare(g.runOutOpacity, 1);
            verify(g.markerShown);
            const old = g.mainPoints.map(p => [p.x, p.y]);
            const runOut = g.projection.map(p => [p.x, p.y]);
            const markerX = g.markerShownX;
            g.window = { resetsAt: start + 2 * week, windowSeconds: week, percent: 1, history: [[start + week + 3600, 1]] };
            g.pollAt = start + week + 3600;
            g.nowMs = g.pollAt * 1000;
            compare(g.ghostMain.map(p => [p.x, p.y]), old);
            compare(g.ghostRunOut.map(p => [p.x, p.y]), runOut);
            compare(g.ghostMarkerX, markerX);
            compare(g.ghostOpacity, 1);
            compare(g.runOutOpacity, 0, "the new week's own run-out starts out");
            verify(!g.markerShown, "and so does its marker");
            const dot = g.children.find(i => i.shown !== undefined && i.color === g.color);
            verify(dot.shown);
            verify(dot.opacity < 1, "the new week's dot fades in");
            tryCompare(g, "ghostOpacity", 0, 2000);
            tryCompare(dot, "opacity", 1, 1000);
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
            compare(g.runOutEnd.x, g.projection[1].x);
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

        // What reads the monitor goes first.
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
            createTemporaryObject(samplerComponent, gpus, { sample: () => seen.push([g.innerShown, arc.percent]) });
            monitor.gpuInner.phase = "live";
            compare(g.centreWidth, room.dual, "the name makes room at once");
            compare(g.innerShown, 0, "the track starts out");
            tryCompare(arc, "percent", 3, 2000);
            compare(g.innerShown, 1);
            verify(seen.some(([shown]) => shown > 0 && shown < 1), "the track fades in");
            verify(seen.every(([shown, percent]) => shown === 1 || percent === 0), "no arc until the track is in: " + JSON.stringify(seen));
        }

        // The second GPU sleeps: the arc unwinds first, then the track fades
        // out, the name taking its room back half way, and the cell is as
        // it is with one ring.
        function test_secondRingUnwindsThenFadesOut() {
            monitor.gpuInner.usage = 40;
            const c = cell();
            const g = gauge(c);
            const arc = innerArc(g);
            const room = rooms(g);
            compare(arc.percent, 40);
            const seen = [];
            createTemporaryObject(samplerComponent, gpus, { sample: () => seen.push([arc.percent, g.innerShown, g.centreWidth]) });
            monitor.gpuInner.phase = "asleep";
            compare(g.innerShown, 1, "the track stays while the arc unwinds");
            tryCompare(g, "innerShown", 0, 2000);
            verify(!arc.visible);
            compare(g.centreWidth, room.single);
            verify(seen.every(([percent, shown]) => percent < 0.5 || shown === 1), "the track waits for the arc: " + JSON.stringify(seen));
            verify(seen.every(([, shown, width]) => width === (shown >= 0.5 ? room.dual : room.single)), "the room comes back half way");
            verify(seen.some(([percent]) => percent > 0.5 && percent < 39.5), "unwinding");
            tryCompare(nameIn(c), "shownSize", nameIn(c).size, 1000, "the name grows to its size");
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
            createTemporaryObject(samplerComponent, gpus, { sample: () => seen.push([name.shownSize !== name.size, name.layer.enabled]) });
            monitor.gpuInner.phase = "asleep";
            tryVerify(() => name.shownSize !== name.size, 2000, "scaling");
            tryCompare(name, "shownSize", name.size, 2000);
            verify(seen.every(([scaling, layered]) => scaling === layered), JSON.stringify(seen));
            verify(!name.layer.enabled, "drawn as text at rest");
        }

        // A change back mid-fade turns the track round where it is.
        function test_reversesCleanly() {
            monitor.gpuInner.phase = "asleep";
            const c = cell();
            const g = gauge(c);
            monitor.gpuInner.phase = "live";
            tryVerify(() => g.innerShown > 0.3 && g.innerShown < 0.9, 2000, "fading in");
            const seen = [];
            createTemporaryObject(samplerComponent, gpus, { sample: () => seen.push(g.innerShown) });
            const shown = g.innerShown;
            monitor.gpuInner.phase = "asleep";
            compare(g.innerShown, shown, "no jump");
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
        // once. Waking, the section opens at once and fades in.
        function test_popupSectionFadesOutThenIn() {
            const popup = load();
            const [outer, inner] = sections(popup);
            const heights = [];
            popup.implicitHeightChanged.connect(() => heights.push(popup.implicitHeight));
            const before = popup.implicitHeight;
            monitor.gpuOuter.phase = "asleep";
            verify(outer.visible);
            verify(outer.slot.usage === 12, "keeping its last reading");
            verify(!visibleTexts(popup).some(t => t.endsWith(" · off")), "no line yet");
            tryVerify(() => outer.opacity < 1, 1000, "fading out");
            compare(outer.slot.temperature, 48);
            tryCompare(outer, "visible", false, 1000);
            verify(visibleTexts(popup).includes("AMD Radeon RX 7700S · off"));
            verify(inner.first, "the integrated GPU's section now opens the page");
            // The height follows at the layout's next polish.
            tryVerify(() => heights.length > 0, 1000, "the popup's height changes");
            waitForRendering(popup);
            compare(heights.length, 1, "one change of height: " + JSON.stringify(heights));
            heights.length = 0;
            monitor.gpuOuter.phase = "live";
            verify(outer.visible, "open at once");
            verify(outer.opacity < 1, "and fading in");
            verify(!inner.first);
            verify(!visibleTexts(popup).some(t => t.endsWith(" · off")));
            tryCompare(outer, "opacity", 1, 1000);
            compare(popup.implicitHeight, before);
            compare(heights.length, 1, "one change of height: " + JSON.stringify(heights));
        }

        // Waking again before the section has gone, it fades back up and the
        // popup keeps its height.
        function test_popupSectionTurnsBack() {
            const popup = load();
            const outer = sections(popup)[0];
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
            const outer = sections(popup)[0];
            monitor.gpuOuter.phase = "asleep";
            verify(!outer.visible);
            verify(visibleTexts(popup).includes("AMD Radeon RX 7700S · off"));
        }
    }
}
