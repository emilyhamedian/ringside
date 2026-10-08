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

    // The top is the hot threshold, or a round five over a hotter peak; the
    // floor a round ten at least the margin under the coolest reading.
    function test_temperatureScale_data() {
        return [
            { tag: "steady", samples: [60, 61, 62], hot: 90, low: 50, high: 90 },
            { tag: "marginOnARoundTen", samples: [45, 50], hot: 90, low: 40, high: 90 },
            { tag: "justUnder", samples: [44.9, 50], hot: 90, low: 30, high: 90 },
            { tag: "pastHot", samples: [52, 93.4], hot: 90, low: 40, high: 95 },
            { tag: "peakOnAFive", samples: [70, 95], hot: 90, low: 60, high: 95 },
            { tag: "gapsIgnored", samples: [NaN, 61, NaN], hot: 90, low: 50, high: 90 },
            { tag: "nothing", samples: [NaN], hot: 90, low: 80, high: 90 },
            { tag: "fahrenheit", samples: [141.8, 143.6], hot: 194, margin: 9, low: 130, high: 194 }
        ];
    }
    function test_temperatureScale(data) {
        compare(History.temperatureScale(data.samples, data.hot, data.margin ?? 5), { low: data.low, high: data.high });
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

    function test_piecesBreakAtGapsAndKeepOneColourWithoutThresholds() {
        var samples = [80, NaN, 95, 96];
        var points = samples.map((v, i) => ({ x: i, y: 100 - v }));
        var pieces = History.pieces(samples, points, 75, 90);
        compare(levelsOf(pieces), [1, 2]);
        compare(pieces[0].points.length, 1);
        compare(pieces[1].points.length, 2);
        compare(levelsOf(History.pieces(samples, points, Infinity, Infinity)), [0, 0]);
    }
}
