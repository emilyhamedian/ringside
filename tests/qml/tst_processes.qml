// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/code/format.js" as Format
import "../../package/contents/ui/code/processes.js" as Processes
import "../../package/contents/ui/popups"

TestCase {
    name: "Processes"

    // A bare qml runtime has no KI18n; the list finds this on the root.
    function i18nc(context, text, ...args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }

    Component {
        id: liveList
        ProcessList {
            key: "memory"
            threads: 1
        }
    }

    Component {
        id: sampleList
        ProcessList {
            threads: 1
            sample: []
        }
    }

    function init() {
        failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
    }

    // The attribute lists below are cut down from what each libksysguard's
    // process model offers. From 6.3 the list asks for "memory" and nothing
    // it is picked from.
    function test_attributesAskForMemoryWhereItIsOffered() {
        var available = ["pid", "vmSize", "vmRSS", "vmURSS", "vmShared", "vmPSS", "memory", "name", "usage"];
        compare(Processes.attributes(available), ["name", "usage", "memory"]);
    }

    // 6.0 offers PSS and private memory, 6.2 resident memory as well.
    function test_attributesFallBackToWhatMemoryIsPickedFrom() {
        compare(Processes.attributes(["pid", "vmSize", "vmURSS", "vmShared", "vmPSS", "name", "usage"]),
                ["name", "usage", "vmPSS", "vmURSS"]);
        compare(Processes.attributes(["pid", "vmSize", "vmRSS", "vmURSS", "vmShared", "vmPSS", "name", "usage"]),
                ["name", "usage", "vmPSS", "vmURSS", "vmRSS"]);
    }

    function test_attributesAskForNothingUnoffered() {
        compare(Processes.attributes(["usage"]), ["usage"]);
        compare(Processes.attributes([]), []);
    }

    // Values go with the attribute in their column, wherever that is.
    function test_readingMatchesValuesToColumns() {
        var result = Processes.reading(["usage", "memory", "name"], [12.5, 2048, "kwin_x11"]);
        compare(result.name, "kwin_x11");
        compare(result.usage, 12.5);
        compare(result.memory, 2048 * 1024);
    }

    // Before 6.3, memory is the first of PSS, private and resident memory
    // with a value, as "memory" is from 6.3. Private memory can come out
    // negative on 6.0, where it is resident less shared.
    function test_readingPicksMemoryAsLibksysguard63Does() {
        var columns = ["name", "usage", "vmPSS", "vmURSS", "vmRSS"];
        compare(Processes.reading(columns, ["a", 0, 300, 200, 400]).memory, 300 * 1024);
        compare(Processes.reading(columns, ["a", 0, 0, 200, 400]).memory, 200 * 1024);
        compare(Processes.reading(columns, ["a", 0, 0, -16, 400]).memory, 400 * 1024);
        compare(Processes.reading(columns, ["a", 0, 0, 0, 0]).memory, 0);
    }

    function test_readingWithoutAMemoryColumn() {
        var result = Processes.reading(["name", "usage"], ["a", 3]);
        compare(result.name, "a");
        compare(result.usage, 3);
        compare(result.memory, 0);
    }

    // The real list against libksysguard's process model, which sees at least
    // this test runner. Reading a column the model doesn't have warns about an
    // invalid QModelIndex for every process and leaves the memory list empty,
    // as it did on Plasma 6.0 to 6.2.
    function test_listReadsTheProcessModel() {
        failOnWarning(/QModelIndex/);
        var list = createTemporaryObject(liveList, this);
        verify(list);
        tryVerify(() => list.rows.length > 0, 5000);
        verify(list.rows[0].name.length > 0);
        verify(list.rows[0].memory > 0);
    }

    // Rows arriving in a list that started empty, as the first scan's do,
    // are read and spoken from their own process.
    function test_rowsArriveAfterAnEmptyStart_data() {
        return [{ tag: "usage", spoken: "firefox, " + Format.fixed(8.4, 1) + "%" },
                { tag: "memory", spoken: "firefox, " + Format.fixed(3.9, 1) + " GiB" }];
    }

    function test_rowsArriveAfterAnEmptyStart(data) {
        const list = createTemporaryObject(sampleList, this, { key: data.tag });
        verify(list);
        const rows = Array.from(list.children).filter(c => c.entry !== undefined);
        compare(rows.length, 3);
        list.sample = [{ name: "firefox", usage: 8.4, memory: 3.9 * 1024 ** 3, count: 1 }];
        compare(rows.map(r => r.Accessible.name), [data.spoken, "", ""]);
    }

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
