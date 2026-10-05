// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/code/pace.js" as Pace

TestCase {
    name: "Pace"

    readonly property real day: 86400
    // A week from 0 to 7 days, as a weekly window reports it.
    readonly property real start: 1000000
    readonly property real end: start + 7 * day

    function test_none_data() {
        return [
            { tag: "noReading", percent: NaN, start: start, end: end, at: start + day },
            { tag: "noWindow", percent: 40, start: start, end: start, at: start + day },
            { tag: "noTime", percent: 40, start: start, end: end, at: NaN }
        ];
    }
    function test_none(data) {
        const p = Pace.project(data.percent, data.start, data.end, data.at, []);
        compare(p.state, "none");
        verify(isNaN(p.runOut) && isNaN(p.atReset) && isNaN(p.reachedAt));
        compare(Pace.alarm(p), 0);
    }

    function test_reachedWithItsTime() {
        const history = [[start - day, 100], [start + day, 60], [start + 2 * day, 100], [start + 3 * day, 100]];
        const p = Pace.project(100, start, end, start + 3 * day, history);
        compare(p.state, "reached");
        // The first full point in this window; the one before it was last week's.
        compare(p.reachedAt, start + 2 * day);
        compare(Pace.alarm(p), 2);
    }

    function test_reachedWithoutItsTime() {
        const p = Pace.project(100, start, end, start + 3 * day, [[start + day, 60]]);
        compare(p.state, "reached");
        verify(isNaN(p.reachedAt));
        compare(Pace.project(100, start, end, start + 3 * day, undefined).state, "reached");
    }

    // 70% in the first 18 hours is averaged over a whole day and still runs
    // out on day two, so it warns at once.
    function test_runawayFirstDayIsOut() {
        const p = Pace.project(70, start, end, start + 18 * 3600, []);
        compare(p.state, "out");
        fuzzyCompare(p.runOut, start + day * 100 / 70, 1);
        compare(Pace.alarm(p), 2);
    }

    // 5% in the first 3 hours would last twenty days at a day's average:
    // too early to say anything.
    function test_quietFirstDayIsNone() {
        const p = Pace.project(5, start, end, start + 3 * 3600, []);
        compare(p.state, "none");
        verify(isNaN(p.runOut) && isNaN(p.atReset));
    }

    function test_lasts() {
        const p = Pace.project(30, start, end, start + 3 * day, []);
        compare(p.state, "lasts");
        fuzzyCompare(p.atReset, 70, 1e-9);
        verify(isNaN(p.runOut));
        compare(Pace.alarm(p), 0);
    }

    function test_out() {
        const p = Pace.project(60, start, end, start + 3 * day, []);
        compare(p.state, "out");
        compare(p.runOut, start + 5 * day);
        verify(isNaN(p.atReset));
    }

    // A reading past the reset counts the whole window, not more.
    function test_readingPastTheEndUsesTheWholeWindow() {
        const p = Pace.project(35, start, end, end + day, []);
        compare(p.state, "lasts");
        fuzzyCompare(p.atReset, 35, 1e-9);
    }

    function test_zeroPercent() {
        const settled = Pace.project(0, start, end, start + 2 * day, []);
        compare(settled.state, "lasts");
        compare(settled.atReset, 0);
        compare(Pace.project(0, start, end, start + 3600, []).state, "none");
    }

    // A run-out within a minute of the reset is the reset.
    function test_minuteBeforeTheReset_data() {
        // 50% at the half-way mark runs out at the end; a little faster runs
        // out `early` seconds before it.
        return [
            { tag: "atTheReset", early: 0, expected: "lasts" },
            { tag: "60sEarly", early: 60, expected: "lasts" },
            { tag: "61sEarly", early: 61, expected: "out" }
        ];
    }
    function test_minuteBeforeTheReset(data) {
        const half = (end - start) / 2;
        const at = start + half - data.early / 2;
        const p = Pace.project(50, start, end, at, []);
        compare(p.state, data.expected);
        if (data.expected === "out") {
            fuzzyCompare(p.runOut, end - data.early, 1e-6);
        }
    }

    // A shorter window waits a seventh of itself rather than a whole day.
    function test_shortWindowThreshold() {
        const shortEnd = start + 7 * 3600;
        compare(Pace.project(5, start, shortEnd, start + 1800, []).state, "none");
        compare(Pace.project(5, start, shortEnd, start + 3600, []).state, "lasts");
    }

    function test_ofWindow() {
        const window = { percent: 60, resetsAt: end, windowSeconds: 7 * day, history: [] };
        const at = start + 3 * day;
        compare(Pace.ofWindow(window, at, at + 600).state, "out");
        compare(Pace.ofWindow(window, at, at + 600).runOut, start + 5 * day);
        compare(Pace.ofWindow(null, at, at).state, "none");
        compare(Pace.ofWindow({ percent: 60, resetsAt: null, windowSeconds: 7 * day }, at, at).state, "none");
    }

    // Once the reset has passed, the reading is last week's: nothing to say,
    // even of a limit that was used up.
    function test_resetThatHasPassed() {
        const full = { percent: 100, resetsAt: end, windowSeconds: 7 * day, history: [[start + day, 100]] };
        compare(Pace.ofWindow(full, end - 60, end - 30).state, "reached");
        compare(Pace.ofWindow(full, end - 60, end).state, "none");
        compare(Pace.ofWindow(full, end - 60, end + day).state, "none");
        compare(Pace.alarm(Pace.ofWindow(full, end - 60, end + day)), 0);
    }

    function test_pollTime() {
        const history = [[start + day, 10], [start + 2 * day, 20]];
        compare(Pace.pollTime({ fetchedAt: start + 3 * day, weekly: { history: history } }, end), start + 3 * day);
        compare(Pace.pollTime({ weekly: { history: history } }, end), start + 2 * day);
        compare(Pace.pollTime({ weekly: { history: [] } }, end), end);
        compare(Pace.pollTime({}, end), end);
        compare(Pace.pollTime(null, end), end);
    }

    function test_levelOnlyRises() {
        const out = Pace.project(60, start, end, start + 3 * day, []);
        const lasts = Pace.project(30, start, end, start + 3 * day, []);
        compare(Pace.level(0, out), 2);
        compare(Pace.level(1, out), 2);
        compare(Pace.level(0, lasts), 0);
        compare(Pace.level(1, lasts), 1);
        compare(Pace.level(2, lasts), 2);
    }
}
