// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/code/format.js" as Format
import "../../package/contents/ui/code/processes.js" as Processes
import "../../package/contents/ui/popups"

Item {
    id: root
    width: 400
    height: 300

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

    SignalSpy {
        id: spy
    }

    TestCase {
        name: "Processes"
        when: windowShown

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            spy.clear();
            spy.target = null;
            spy.signalName = "";
        }

        // Every item under `item` that `test` accepts.
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

        function rowsOf(list) {
            return all(list, c => c.entry !== undefined);
        }

        function indicatorOf(list) {
            const found = all(list, c => c.running !== undefined);
            compare(found.length, 1);
            return found[0];
        }

        // The list's process model, among its resources.
        function modelOf(list) {
            const found = Array.from(list.resources).filter(o => o.availableAttributes !== undefined);
            compare(found.length, 1);
            return found[0];
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
        // as it did on Plasma 6.0 to 6.2. Memory comes with the model's first
        // scan, so the list has it as soon as it is made.
        function test_listReadsTheProcessModel() {
            failOnWarning(/QModelIndex/);
            var list = createTemporaryObject(liveList, root);
            verify(list);
            verify(list.rows.length > 0, "read as the list is made");
            verify(!list.loading);
            verify(!indicatorOf(list).visible);
            verify(list.rows[0].name.length > 0);
            verify(list.rows[0].memory > 0);
        }

        // CPU shares need a second scan, a little over two seconds in at the
        // latest, after which the list stops waiting whatever it found.
        function test_cpuListStopsWaiting() {
            failOnWarning(/QModelIndex/);
            const list = createTemporaryObject(liveList, root, { key: "usage" });
            verify(list);
            tryVerify(() => !list.loading, 5000);
            verify(!indicatorOf(list).visible);
            list.rows.forEach(r => verify(r.usage > 0, r.name));
        }

        // Just after two seconds the list asks the model for its attributes
        // again, which scans then unless a tick just has, and stops waiting
        // even with nothing to show. By a key no process has, the list never
        // has rows, so the indicator shows until then.
        function test_listAsksAgainAndStopsWaiting() {
            failOnWarning(/QModelIndex/);
            const start = Date.now();
            const list = createTemporaryObject(liveList, root, { key: "none" });
            verify(list);
            spy.target = modelOf(list);
            spy.signalName = "enabledAttributesChanged";
            waitForRendering(list);
            verify(list.loading && indicatorOf(list).visible, "waiting at first");
            wait(Math.max(0, 1800 - (Date.now() - start)));
            verify(list.loading && indicatorOf(list).visible, "still waiting at 1.8 s");
            compare(spy.count, 0);
            tryVerify(() => !list.loading, 4000);
            const waited = Date.now() - start;
            verify(waited >= 2000 && waited < 4000, "stopped waiting after " + waited + " ms");
            compare(spy.count, 1, "asked the model again");
            verify(list.scanned);
            compare(list.rows.length, 0);
            verify(!indicatorOf(list).visible);
        }

        // After that the list reads each scan as the model reports it, with
        // no timer of its own. A scan on a quiet machine can change nothing,
        // so the test reports changes itself, three in a row: the list reads
        // each on the next turn of the event loop, where a timer reading
        // every two seconds would catch one at most.
        function test_listFollowsTheScans() {
            failOnWarning(/QModelIndex/);
            const list = createTemporaryObject(liveList, root);
            verify(list);
            tryVerify(() => list.scanned, 5000);
            const model = modelOf(list);
            spy.target = list;
            spy.signalName = "rowsChanged";
            for (let change = 1; change <= 3; ++change) {
                const reads = spy.count;
                model.dataChanged(model.index(0, 0), model.index(0, 0));
                tryVerify(() => spy.count > reads, 500, "read change " + change);
            }
            verify(list.rows.length > 0);
        }

        // Until the list has readings a busy indicator lies over its empty rows,
        // which keep the list's height, and a screen reader hears what it waits
        // for. The first readings take its place.
        function test_busyUntilTheFirstReadings_data() {
            return [{ tag: "usage" }, { tag: "memory" }];
        }

        function test_busyUntilTheFirstReadings(data) {
            const list = createTemporaryObject(sampleList, root, { key: data.tag });
            verify(list);
            waitForRendering(list);
            const indicator = indicatorOf(list);
            verify(list.loading);
            verify(indicator.visible && indicator.running);
            // Qt gives the control its role once a screen reader is active.
            compare(indicator.Accessible.name, "Loading top processes");
            verify(!indicator.Accessible.ignored);
            const rows = rowsOf(list);
            compare(rows.length, 3);
            verify(rows.every(r => r.entry === null && r.Accessible.name === ""), "no rows yet");
            const area = rows[0].parent;
            const middle = indicator.mapToItem(area, Qt.point(indicator.width / 2, indicator.height / 2));
            verify(Math.abs(middle.x - area.width / 2) <= 0.5 && Math.abs(middle.y - area.height / 2) <= 0.5,
                   "over the rows' middle: " + JSON.stringify(middle) + " in " + area.width + "×" + area.height);
            verify(indicator.height <= area.height, indicator.height + " in " + area.height);
            const height = list.implicitHeight;

            list.sample = [{ name: "firefox", usage: 8.4, memory: 3.9 * 1024 ** 3, count: 1 }];
            waitForRendering(list);
            verify(!list.loading);
            verify(!indicator.visible, "gone with the readings");
            compare(list.implicitHeight, height, "the list keeps its height");
        }

        // A list made with its rows, as the gallery's are, never shows the
        // indicator.
        function test_sampleShowsNoIndicator() {
            const list = createTemporaryObject(sampleList, root, { key: "usage", sample: [{ name: "firefox", usage: 8.4, memory: 3.9 * 1024 ** 3, count: 1 }] });
            verify(list);
            const indicator = indicatorOf(list);
            verify(!list.loading && !indicator.visible, "not at first");
            spy.target = indicator;
            spy.signalName = "visibleChanged";
            waitForRendering(list);
            verify(!indicator.visible);
            compare(spy.count, 0, "nor on the first frame");
        }

        // Rows arriving in a list that started empty, as the first scan's do,
        // are read and spoken from their own process.
        function test_rowsArriveAfterAnEmptyStart_data() {
            return [{ tag: "usage", spoken: "firefox, " + Format.fixed(8.4, 1) + "%" },
                    { tag: "memory", spoken: "firefox, " + Format.fixed(3.9, 1) + " GiB" }];
        }

        function test_rowsArriveAfterAnEmptyStart(data) {
            const list = createTemporaryObject(sampleList, root, { key: data.tag });
            verify(list);
            const rows = rowsOf(list);
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
}
