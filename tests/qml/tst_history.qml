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

    function test_pointsForAFullHistory() {
        var pts = History.points([0, 50, 100], 3, 100, 50, 100);
        compare(pts.length, 3);
        fuzzyCompare(pts[0].x, 0, 0.001);
        fuzzyCompare(pts[0].y, 50, 0.001);
        fuzzyCompare(pts[1].x, 50, 0.001);
        fuzzyCompare(pts[1].y, 25, 0.001);
        fuzzyCompare(pts[2].x, 100, 0.001);
        fuzzyCompare(pts[2].y, 0, 0.001);
    }

    // With fewer samples than slots, the newest sample stays pinned to the
    // right edge and the history grows in from there.
    function test_pointsForAPartiallyFilledHistoryGrowInFromTheRight() {
        var pts = History.points([80], 3, 100, 50, 100);
        compare(pts.length, 1);
        fuzzyCompare(pts[0].x, 100, 0.001);
        fuzzyCompare(pts[0].y, 10, 0.001);
    }

    function test_pointsForEmptyHistory() {
        var pts = History.points([], 3, 100, 50, 100);
        compare(pts.length, 0);
    }

    function test_pointsClampOutOfRangeValues() {
        var pts = History.points([-10, 150], 2, 10, 20, 100);
        fuzzyCompare(pts[0].y, 20, 0.001); // below zero clamps to the bottom
        fuzzyCompare(pts[1].y, 0, 0.001); // above max clamps to the top
    }

    function test_pointsFallBackToUnitMaxWhenMaxIsNotPositive() {
        var pts = History.points([0.5, 1], 2, 10, 10, 0);
        fuzzyCompare(pts[0].y, 5, 0.001);
        fuzzyCompare(pts[1].y, 0, 0.001);
    }

    function test_pointsNeverDividesByZeroBelowTwoSlots() {
        var pts = History.points([5], 1, 10, 10, 10);
        compare(pts.length, 1);
        fuzzyCompare(pts[0].x, 10, 0.001);
        fuzzyCompare(pts[0].y, 5, 0.001);
    }

    function test_niceMaxRoundsUpToOneTwoOrFiveTimesAPowerOfTen_data() {
        return [
            { tag: "roundsUpToFive", samples: [45], floor: 0, expected: 50 },
            { tag: "roundsUpToTwo", samples: [120], floor: 0, expected: 200 },
            { tag: "roundsUpToTen", samples: [999], floor: 0, expected: 1000 },
            { tag: "exactPowerOfTenStaysItself", samples: [1000], floor: 0, expected: 1000 }
        ];
    }
    function test_niceMaxRoundsUpToOneTwoOrFiveTimesAPowerOfTen(data) {
        compare(History.niceMax(data.samples, data.floor), data.expected);
    }

    function test_niceMaxNeverGoesBelowTheFloor() {
        compare(History.niceMax([], 10), 10);
        compare(History.niceMax([1, 2], 50), 50);
        compare(History.niceMax([-5, 3], 10), 10);
    }
}
