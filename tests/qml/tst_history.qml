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

    // One sample pushed, as push() makes it, is an arrival a graph eases
    // to; anything else it draws at once.
    function test_arrival_data() {
        return [
            { tag: "growing", before: [1, 2], after: [1, 2, 3], length: 4, arrival: { dropped: undefined } },
            { tag: "full", before: [1, 2, 3], after: [2, 3, 4], length: 3, arrival: { dropped: 1 } },
            { tag: "fullFlat", before: [0, 0, 0], after: [0, 0, 0], length: 3, arrival: { dropped: 0 } },
            { tag: "first", before: [], after: [5], length: 3, arrival: null },
            { tag: "cleared", before: [1, 2, 3], after: [], length: 3, arrival: null },
            { tag: "rewritten", before: [1, 2, 3], after: [9, 3, 4], length: 3, arrival: null },
            { tag: "twoAtOnce", before: [1, 2, 3], after: [3, 4, 5], length: 3, arrival: null },
            { tag: "sameLengthNotFull", before: [1, 2], after: [2, 3], length: 3, arrival: null }
        ];
    }
    function test_arrival(data) {
        compare(History.arrival(data.before, data.after, data.length), data.arrival);
    }
}
