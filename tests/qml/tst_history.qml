// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/code/history.js" as History

TestCase {
    name: "History"

    function test_pushAppendsWithinCapacity() {
        var a = History.push([], 5, 3);
        compare(a.length, 1);
        compare(a[0], 5);
        var b = History.push(a, 6, 3);
        compare(b.length, 2);
        compare(b[0], 5);
        compare(b[1], 6);
    }

    function test_pushDropsOldestBeyondLength() {
        var full = History.push(History.push(History.push([], 1, 3), 2, 3), 3, 3);
        compare(full.length, 3);
        compare(full[0], 1);
        compare(full[1], 2);
        compare(full[2], 3);

        var pushed = History.push(full, 4, 3);
        compare(pushed.length, 3);
        compare(pushed[0], 2);
        compare(pushed[1], 3);
        compare(pushed[2], 4);
    }

    function test_pushDoesNotMutateItsInput() {
        var original = [1, 2, 3];
        var result = History.push(original, 4, 3);
        compare(original.length, 3);
        compare(original[2], 3);
        compare(result[0], 2);
        compare(result[2], 4);
    }

    function test_pushReplacesNonFiniteValuesWithZero_data() {
        return [
            { tag: "nan", value: NaN },
            { tag: "positiveInfinity", value: Infinity },
            { tag: "negativeInfinity", value: -Infinity },
            { tag: "wrongType", value: "5" },
            { tag: "undefined", value: undefined }
        ];
    }
    function test_pushReplacesNonFiniteValuesWithZero(data) {
        var result = History.push([1, 2], data.value, 3);
        compare(result.length, 3);
        compare(result[2], 0);
    }

    function test_pushWithLengthOfOneKeepsOnlyTheNewest() {
        var result = History.push([1, 2, 3], 4, 1);
        compare(result.length, 1);
        compare(result[0], 4);
    }

    // By default the top sits 0.75 px down and zero 0.75 px up, half the
    // 1.5 px stroke, so a line along either edge draws whole.
    function test_pointsForAFullHistory() {
        var pts = History.points([0, 50, 100], 3, 100, 50, 100);
        compare(pts.length, 3);
        fuzzyCompare(pts[0].x, 0, 0.001);
        fuzzyCompare(pts[0].y, 49.25, 0.001);
        fuzzyCompare(pts[1].x, 50, 0.001);
        fuzzyCompare(pts[1].y, 25, 0.001);
        fuzzyCompare(pts[2].x, 100, 0.001);
        fuzzyCompare(pts[2].y, 0.75, 0.001);
    }

    // With fewer samples than slots, the newest sample stays pinned to the
    // right edge and the history grows in from there.
    function test_pointsForAPartiallyFilledHistoryGrowInFromTheRight() {
        var pts = History.points([80], 3, 100, 50, 100);
        compare(pts.length, 1);
        fuzzyCompare(pts[0].x, 100, 0.001);
        fuzzyCompare(pts[0].y, 0.75 + 0.2 * 48.5, 0.001);
    }

    function test_pointsForEmptyHistory() {
        var pts = History.points([], 3, 100, 50, 100);
        compare(pts.length, 0);
    }

    function test_pointsClampOutOfRangeValues() {
        var pts = History.points([-10, 150], 2, 10, 20, 100);
        fuzzyCompare(pts[0].y, 19.25, 0.001); // below zero clamps to the bottom
        fuzzyCompare(pts[1].y, 0.75, 0.001); // above max clamps to the top
    }

    function test_pointsFallBackToUnitMaxWhenMaxIsNotPositive() {
        var pts = History.points([0.5, 1], 2, 10, 10, 0);
        fuzzyCompare(pts[0].y, 5, 0.001);
        fuzzyCompare(pts[1].y, 0.75, 0.001);
    }

    function test_pointsNeverDividesByZeroBelowTwoSlots() {
        var pts = History.points([5], 1, 10, 10, 10);
        compare(pts.length, 1);
        fuzzyCompare(pts[0].x, 10, 0.001);
        fuzzyCompare(pts[0].y, 5, 0.001);
    }

    // A graph under a labelled rule puts its maximum on the rule; zero stays
    // at the bottom whatever the top.
    function test_pointsTakeATop_data() {
        return [
            { tag: "rule", top: 6.5 },
            { tag: "edge", top: 0 },
            { tag: "fraction", top: 2.25 }
        ];
    }
    function test_pointsTakeATop(data) {
        var pts = History.points([0, 50, 100, 150], 4, 30, 40, 100, data.top);
        fuzzyCompare(pts[0].y, 39.25, 0.001);
        fuzzyCompare(pts[1].y, data.top + (39.25 - data.top) / 2, 0.001);
        fuzzyCompare(pts[2].y, data.top, 0.001);
        fuzzyCompare(pts[3].y, data.top, 0.001);
    }

    // The newest of equal peaks, so the caption follows the line's latest
    // high point.
    function test_peakIsTheNewestLargest_data() {
        return [
            { tag: "single", samples: [4], index: 0, value: 4 },
            { tag: "middle", samples: [1, 9, 3], index: 1, value: 9 },
            { tag: "tieTakesTheNewest", samples: [3, 7, 2, 7, 1], index: 3, value: 7 },
            { tag: "allZero", samples: [0, 0, 0], index: 2, value: 0 },
            { tag: "last", samples: [1, 2, 3], index: 2, value: 3 }
        ];
    }
    function test_peakIsTheNewestLargest(data) {
        var p = History.peak(data.samples);
        compare(p.index, data.index);
        compare(p.value, data.value);
    }

    function test_peakOfNothingIsNull() {
        compare(History.peak([]), null);
    }

    // A temperature history keeps a missing reading as NaN, a gap, where
    // push() would put a 0 that reads as a cold sensor.
    function test_recordKeepsMissingReadingsAsGaps() {
        var a = History.record([], 50, 3);
        a = History.record(a, NaN, 3);
        a = History.record(a, undefined, 3);
        compare(a.length, 3);
        compare(a[0], 50);
        verify(isNaN(a[1]) && isNaN(a[2]));
        var b = History.record(a, 52, 3);
        compare(b.length, 3, "as long as asked");
        verify(isNaN(b[0]) && isNaN(b[1]));
        compare(b[2], 52);
        compare(a.length, 3, "the input is left alone");
    }

    // A temperature graph's floor maps to the bottom as zero does.
    function test_pointsTakeAFloor() {
        var pts = History.points([40, 65, 90], 3, 100, 50, 90, 0.75, 40);
        fuzzyCompare(pts[0].y, 49.25, 0.001);
        fuzzyCompare(pts[1].y, 25, 0.001);
        fuzzyCompare(pts[2].y, 0.75, 0.001);
        verify(isNaN(History.points([NaN], 3, 100, 50, 90, 0.75, 40)[0].y), "a missing sample has no height");
    }

    function test_runsBreakAtMissingSamples() {
        var samples = [NaN, 1, 2, NaN, NaN, 3, 4, 5];
        var points = samples.map((v, i) => ({ x: i, y: v }));
        compare(History.runs(samples, points).map(run => run.map(p => p.x)), [[1, 2], [5, 6, 7]]);
        compare(History.runs([NaN, NaN], [{ x: 0, y: NaN }, { x: 1, y: NaN }]), []);
    }

    // The floor is a round ten at least the margin under the coolest
    // reading; with no reading there is none.
    function test_temperatureFloor_data() {
        return [
            { tag: "steady", samples: [60, 61, 62], low: 50 },
            { tag: "marginOnARoundTen", samples: [45, 50], low: 40 },
            { tag: "justUnder", samples: [44.9, 50], low: 30 },
            { tag: "gapsIgnored", samples: [NaN, 61, NaN], low: 50 },
            { tag: "fahrenheit", samples: [141.8, 143.6], margin: 9, low: 130 }
        ];
    }
    function test_temperatureFloor(data) {
        compare(History.temperatureFloor(data.samples, data.margin ?? 5, NaN), data.low);
    }

    function test_noReadingNoFloor() {
        verify(Number.isNaN(History.temperatureFloor([NaN, NaN], 5, 40)));
        verify(Number.isNaN(History.temperatureFloor([], 5, NaN)));
    }

    // A reading dipping across a round number lowers the floor at once, but
    // it stays down as the dip comes and goes from the span, until every
    // reading is ten and two margins over it.
    function test_temperatureFloorHolds() {
        var low = History.temperatureFloor([45, 46], 5, NaN);
        compare(low, 40);
        for (var i = 0; i < 4; ++i) {
            low = History.temperatureFloor(i % 2 ? [45, 46] : [44.9, 46], 5, low);
            compare(low, 30, "round " + i);
        }
        compare(History.temperatureFloor([49.9, 52], 5, 30), 30, "still under 30 + 20");
        compare(History.temperatureFloor([50, 52], 5, 30), 40, "raised once well clear");
        compare(History.temperatureFloor([46, 52], 5, 40), 40);
        compare(History.temperatureFloor([84, 90], 5, 40), 70, "a big step goes straight there");
    }

    // The top is the hot threshold, or the peak when it runs hotter or
    // there is no threshold.
    function test_temperatureTop() {
        compare(History.temperatureTop([60, 61, 62], 90), 90);
        compare(History.temperatureTop([52, 93.4, NaN], 90), 93.4);
        compare(History.temperatureTop([60, 61.5, NaN], -Infinity), 61.5);
        compare(History.temperatureTop([NaN], 90), 90);
    }

    function levelsOf(pieces) {
        return pieces.map(p => p.level);
    }

    // The line is cut where it crosses a threshold, each piece in one
    // colour, the cut where the straight line between two samples meets it.
    function test_piecesCutAtTheThresholds() {
        var samples = [70, 80, 100, 80, 70];
        var points = samples.map((v, i) => ({ x: i * 10, y: 100 - v }));
        var pieces = History.pieces(samples, points, 75, 90);
        compare(levelsOf(pieces), [0, 1, 2, 1, 0]);
        // 75 is half way from 70 to 80, and 90 half way from 80 to 100.
        compare(pieces[0].points, [{ x: 0, y: 30 }, { x: 5, y: 25 }]);
        compare(pieces[1].points, [{ x: 5, y: 25 }, { x: 10, y: 20 }, { x: 15, y: 10 }]);
        compare(pieces[2].points, [{ x: 15, y: 10 }, { x: 20, y: 0 }, { x: 25, y: 10 }]);
        compare(pieces[4].points, [{ x: 35, y: 25 }, { x: 40, y: 30 }]);
    }

    // One step can cross both thresholds, and a reading on a threshold
    // takes its colour, as the header's reading does.
    function test_piecesCrossBothThresholdsInOneStep() {
        var samples = [60, 90, 90];
        var points = samples.map((v, i) => ({ x: i * 30, y: 100 - v }));
        var pieces = History.pieces(samples, points, 75, 90);
        compare(levelsOf(pieces), [0, 1, 2]);
        compare(pieces[1].points, [{ x: 15, y: 25 }, { x: 30, y: 10 }]);
        compare(pieces[2].points[0], { x: 30, y: 10 });
        compare(pieces[2].points[pieces[2].points.length - 1], { x: 60, y: 10 });
    }

    // A reading on the warm threshold is amber, as the header's is.
    function test_piecesTakeTheWarmColourOnTheThreshold() {
        var samples = [70, 75, 75];
        var points = samples.map((v, i) => ({ x: i * 10, y: 100 - v }));
        var pieces = History.pieces(samples, points, 75, 90);
        compare(levelsOf(pieces), [0, 1]);
        compare(pieces[1].points[0], { x: 10, y: 25 });
        compare(pieces[1].points[pieces[1].points.length - 1], { x: 20, y: 25 });
    }

    function test_piecesBreakAtGapsAndKeepOneColourWithoutThresholds() {
        var samples = [80, NaN, 95, 96];
        var points = samples.map((v, i) => ({ x: i, y: 100 - v }));
        var pieces = History.pieces(samples, points, 75, 90);
        compare(levelsOf(pieces), [1, 2]);
        compare(pieces[0].points.length, 1);
        compare(pieces[1].points.length, 2);
        compare(levelsOf(History.pieces(samples, points, Infinity, Infinity)), [0, 0]);
    }

    function test_peakSkipsGaps() {
        compare(History.peak([NaN, 3, NaN, 2]), { index: 1, value: 3 });
        compare(History.peak([NaN, NaN]), null);
    }

    function test_topsAreTheHighsWhereThereAreAny() {
        compare(History.tops([1, 2], [5, 6]), [5, 6]);
        compare(History.tops([1, 2], []), [1, 2]);
    }

    // 10:00:00 local time on a day, in ms, so bucket numbers are easy to
    // read: a 30 s bucket's starts on :00 or :30, a 10 min one on the tenth
    // minute.
    readonly property real t0: Date.UTC(2026, 9, 8, 10, 0, 0)

    // Readings go into wall-clock buckets: each closes when a reading falls
    // in a later one, giving the average and the highest of its readings.
    // The open bucket isn't kept yet.
    function test_tierAveragesAndKeepsTheHighest() {
        const t = History.tier("hour");
        compare(t.period, 30);
        compare(t.length, 120);
        compare(History.add(t, 10, t0), null);
        compare(History.add(t, 30, t0 + 10000), null);
        compare(History.add(t, 20, t0 + 29999), null);
        compare(t.means, [], "the open bucket isn't shown");
        const closed = History.add(t, 50, t0 + 30000);
        compare(closed, { at: t0 / 30000, mean: 20, high: 30 });
        compare(t.means, [20]);
        compare(t.highs, [30]);
        compare(t.at, t0 / 30000 + 1);
    }

    // Buckets follow the wall clock, not the first reading: one taken at
    // :25 closes at :30 with five seconds behind it.
    function test_tierBucketsAreWallClockAligned() {
        const t = History.tier("day");
        History.add(t, 4, t0 + 9 * 60000 + 55000);
        const closed = History.add(t, 8, t0 + 10 * 60000);
        compare(closed.at * 600000, t0, "the bucket of 10:00 to 10:10");
        compare(closed.mean, 4);
        compare(History.add(t, 8, t0 + 19 * 60000 + 59999), null, "still 10:10 to 10:20");
        verify(History.add(t, 8, t0 + 20 * 60000) !== null, "closed at 10:20");
    }

    // A bucket whose readings were all missing is a gap, not a 0.
    function test_tierMissingReadingsAreGaps() {
        const t = History.tier("hour");
        History.add(t, NaN, t0);
        History.add(t, undefined, t0 + 1000);
        const closed = History.add(t, 7, t0 + 30000);
        verify(Number.isNaN(closed.mean) && Number.isNaN(closed.high));
        History.add(t, NaN, t0 + 31000);
        History.add(t, 9, t0 + 60000);
        compare(t.means.length, 2);
        verify(Number.isNaN(t.means[0]));
        compare(t.means[1], 7, "a missing reading doesn't pull the average down");
    }

    // Time the machine slept, or the widget wasn't sampling, is a run of
    // gaps as long as the buckets it passed, at most the tier's length.
    function test_tierGapsAcrossAWallClockJump() {
        const t = History.tier("hour");
        History.add(t, 10, t0);
        History.add(t, 30, t0 + 8 * 60000 + 5000);
        compare(t.means.length, 16);
        compare(t.means[0], 10);
        verify(t.means.slice(1).every(v => Number.isNaN(v)), t.means.join());
        compare(t.highs.length, 16);
        History.add(t, 40, t0 + 8 * 60000 + 30000);
        compare(t.means[16], 30, "the reading after the jump has a bucket of its own");
        // Three days later every bucket in the hour is a gap.
        History.add(t, 50, t0 + 3 * 86400000);
        compare(t.means.length, 120);
        verify(t.means.every(v => Number.isNaN(v)), "nothing left from before");
    }

    // Never more than a span's worth of buckets.
    function test_tierKeepsItsLength() {
        const t = History.tier("hour");
        for (let s = 0; s <= 200 * 30; s += 15) {
            History.add(t, s, t0 + s * 1000);
        }
        compare(t.means.length, 120);
        compare(t.highs.length, 120);
        compare(t.means[119], (199 * 30 + 199 * 30 + 15) / 2, "the newest closed bucket last");
    }

    // A clock set back a second leaves the reading in the open bucket; set
    // back further, the buckets now in its future go and the record goes on
    // from the new time.
    function test_tierClockSetBack() {
        const t = History.tier("hour");
        History.add(t, 10, t0);
        History.add(t, 20, t0 + 30000);
        History.add(t, 30, t0 + 60000);
        compare(t.means, [10, 20]);
        compare(History.add(t, 40, t0 + 59000), null, "a second back");
        compare(t.at, t0 / 30000 + 2);
        compare(History.add(t, 0, t0 + 90000).mean, 35, "both readings in one bucket");
        History.add(t, 5, t0 + 30000);
        compare(t.means, [10], "the buckets from 10:00:30 on are gone");
        compare(t.at, t0 / 30000 + 1);
        compare(History.add(t, 7, t0 + 60000), { at: t0 / 30000 + 1, mean: 5, high: 5 });
    }

    // Saved buckets come back where they belong, as gaps where none was
    // saved, and only the last span's worth before now.
    function test_restoreKeepsTheSpanBeforeNow() {
        const t = History.tier("hour");
        const now = t0 + 60 * 60000;
        const at = t0 / 30000;
        History.restore(t, [{ at: at - 5, mean: 1, high: 2 }, { at: at, mean: 3, high: 4 }, { at: at + 2, mean: 5, high: null },
                            { at: at + 120, mean: 9, high: 9 }, { at: at + 200, mean: 8, high: 8 }], now);
        compare(t.at, at + 120);
        compare(t.means.length, 120);
        compare(t.means[0], 3, "the oldest that still fits");
        verify(Number.isNaN(t.means[1]), "a gap where nothing was saved");
        compare(t.means[2], 5);
        verify(Number.isNaN(t.highs[2]), "a missing high is a gap");
        verify(t.means.slice(3).every(v => Number.isNaN(v)));
        compare(History.add(t, 6, now + 5000), null, "the open bucket is now's");
        History.restore(t, [{ at: at + 119, mean: 1, high: 1 }], now);
        compare(t.means[119], NaN, "a tier in use isn't restored over");
    }

    function test_restoreOfNothingStartsTheClock() {
        const t = History.tier("day");
        History.restore(t, [], t0);
        compare(t.at, t0 / 600000);
        compare(t.means, []);
    }

    // A temperature's scale comes from all three spans.
    function test_extentCoversEverySpan() {
        const s = History.series();
        compare(History.extent(s), []);
        s.minute = [50, NaN, 52];
        compare(History.extent(s), [50, 52]);
        s.hour.means = [40, NaN];
        s.hour.highs = [61, NaN];
        s.day.means = [38];
        s.day.highs = [93];
        compare(History.extent(s), [38, 93]);
    }

    // Between buckets closing, an extent only takes in each new reading.
    function test_widen() {
        compare(History.widen([], 50), [50, 50]);
        compare(History.widen([40, 60], 50), [40, 60]);
        compare(History.widen([40, 60], 70), [40, 70]);
        compare(History.widen([40, 60], 30), [30, 60]);
        compare(History.widen([40, 60], NaN), [40, 60], "a missing reading leaves it");
        compare(History.widen([], NaN), []);
    }

    // A reading alone between gaps becomes a level line its slot wide,
    // never under 3 px; one in a run, and anything without `half`, stays.
    function test_aLoneReadingIsSpread() {
        compare(History.loneHalf(144, 286), 1.5, "a day's 2 px slot draws 3 px");
        compare(History.loneHalf(120, 595), 2.5);
        const samples = [NaN, 5, NaN, 6, 7];
        const points = samples.map((v, i) => ({ x: i * 10, y: v }));
        compare(History.runs(samples, points, 1.5), [[{ x: 8.5, y: 5 }, { x: 11.5, y: 5 }], [{ x: 30, y: 6 }, { x: 40, y: 7 }]]);
        compare(History.runs(samples, points).length, 2);
        compare(History.runs(samples, points)[0].length, 1, "unspread without a width");
        const pieces = History.pieces(samples, points, 75, 90, 1.5);
        compare(pieces[0].points, [{ x: 8.5, y: 5 }, { x: 11.5, y: 5 }]);
    }

    // The band runs along the highs and back along the line, a stretch at
    // a time; a lone bucket's is a box its slot wide.
    function test_bands() {
        const values = [1, 2, NaN, 3];
        const highs = [4, 5, NaN, 6];
        const low = values.map((v, i) => ({ x: i, y: -v }));
        const high = highs.map((v, i) => ({ x: i, y: -v }));
        compare(History.bands(values, highs, low, high, 0.5), [
            [{ x: 0, y: -4 }, { x: 1, y: -5 }, { x: 1, y: -2 }, { x: 0, y: -1 }],
            [{ x: 2.5, y: -6 }, { x: 3.5, y: -6 }, { x: 3.5, y: -3 }, { x: 2.5, y: -3 }]
        ]);
        // A restored bucket can have an average without its highest.
        compare(History.bands([1, 2, 3], [4, NaN, 6], low, high, 0.5).length, 2, "a missing highest breaks the band");
    }
}
