import QtQuick
import QtTest
import "../../package/contents/ui/code/processes.js" as Processes

TestCase {
    name: "Processes"

    function test_topGroupsRowsSharingAName() {
        var rows = [
            { name: "chrome", usage: 10, memory: 100 },
            { name: "chrome", usage: 5, memory: 50 },
            { name: "firefox", usage: 20, memory: 80 }
        ];
        var result = Processes.top(rows, "usage", 5);
        compare(result.length, 2);
        compare(result[0].name, "firefox");
        compare(result[0].usage, 20);
        compare(result[0].count, 1);
        compare(result[1].name, "chrome");
        compare(result[1].usage, 15);
        compare(result[1].memory, 150);
        compare(result[1].count, 2);
    }

    function test_topSortsByMemoryWhenThatIsTheKey() {
        var rows = [
            { name: "chrome", usage: 10, memory: 100 },
            { name: "chrome", usage: 5, memory: 50 },
            { name: "firefox", usage: 20, memory: 80 }
        ];
        var result = Processes.top(rows, "memory", 5);
        compare(result[0].name, "chrome");
        compare(result[0].memory, 150);
        compare(result[1].name, "firefox");
        compare(result[1].memory, 80);
    }

    function test_topBreaksTiesAlphabeticallyByName() {
        var rows = [
            { name: "zed", usage: 10, memory: 1 },
            { name: "alpha", usage: 10, memory: 1 }
        ];
        var result = Processes.top(rows, "usage", 5);
        compare(result[0].name, "alpha");
        compare(result[1].name, "zed");
    }

    // A process using no CPU but real memory should still show in the memory
    // list, just not in the usage list.
    function test_topFiltersOutZeroOnlyForTheChosenKey() {
        var rows = [{ name: "idle", usage: 0, memory: 50 }];
        compare(Processes.top(rows, "usage", 5).length, 0);
        var byMemory = Processes.top(rows, "memory", 5);
        compare(byMemory.length, 1);
        compare(byMemory[0].name, "idle");
    }

    function test_topSkipsRowsWithoutAName() {
        var rows = [
            { name: "", usage: 10, memory: 10 },
            { usage: 5, memory: 5 },
            { name: "real", usage: 1, memory: 1 }
        ];
        var result = Processes.top(rows, "usage", 5);
        compare(result.length, 1);
        compare(result[0].name, "real");
    }

    function test_topTreatsNonFiniteUsageAndMemoryAsZero() {
        var rows = [
            { name: "flaky", usage: NaN, memory: 20 },
            { name: "flaky", usage: 5, memory: Infinity }
        ];
        var result = Processes.top(rows, "usage", 5);
        compare(result.length, 1);
        compare(result[0].usage, 5); // NaN contributed 0, not NaN
        compare(result[0].memory, 20); // Infinity contributed 0, not Infinity
        compare(result[0].count, 2);
    }

    function test_topLimitsToCount() {
        var rows = [{ name: "a", usage: 3 }, { name: "b", usage: 2 }, { name: "c", usage: 1 }];
        var result = Processes.top(rows, "usage", 2);
        compare(result.length, 2);
        compare(result[0].name, "a");
        compare(result[1].name, "b");
    }
}
