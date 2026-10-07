// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/popups"
import "../../package/contents/ui/code/format.js" as Format
import "../../package/contents/ui/code/report.js" as Report
import "../../package/contents/ui/code/style.js" as Style

// The Claude and Codex items. UsageData runs the stub scenarios in data/
// (fake-usage-*.py) in place of usage.py, so no credentials are read and no
// service is called. The cell, the popup and the week graph read FakeUsage
// through FakeMonitor.
Item {
    id: root
    width: 800
    height: 900

    // A bare qml runtime has no KI18n; the views find these on the root.
    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }
    function i18n(text, ...args) { return substitute(text, args); }
    function i18nc(context, text, ...args) { return substitute(text, args); }
    function i18np(s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }
    function i18ncp(c, s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }

    // A C-locale expectation in the digits and decimal mark Format uses
    // for the test's locale: "52%" is "٥٢%" under Arabic.
    function localized(text) {
        return text.replace(/\d+(?:\.(\d+))?/g, (m, decimals) => Format.fixed(Number(m), decimals ? decimals.length : 0));
    }

    function stub(scenario) {
        return decodeURIComponent(Qt.resolvedUrl("data/fake-usage-" + scenario + ".py").toString().replace(/^file:\/\//, ""));
    }

    // Every visible text under an item.
    function texts(item) {
        const found = [];
        const collect = i => {
            if (i.visible && typeof i.text === "string" && i.text !== "") {
                found.push(i.text);
            }
            i.children.forEach(collect);
        };
        collect(item);
        return found;
    }

    // The first item under `item`, itself included, that `test` accepts.
    function find(item, test) {
        if (test(item)) {
            return item;
        }
        for (const child of item.children) {
            const hit = find(child, test);
            if (hit) {
                return hit;
            }
        }
        return null;
    }

    // The width of a space in a text's font.
    TextMetrics {
        id: spaceProbe
        text: " "
    }

    Component {
        id: configComponent
        QtObject {
            property int usageRefreshMinutes: 5
            property string claudeInnerLimit: ""
            property string codexInnerLimit: ""
            property string knownLimits: ""
            property string usageStatus: ""
            property int knownLimitsWrites: 0
            property int usageStatusWrites: 0
            onKnownLimitsChanged: ++knownLimitsWrites
            onUsageStatusChanged: ++usageStatusWrites
        }
    }

    Component {
        id: usageComponent
        UsageData {}
    }

    Component {
        id: spyComponent
        SignalSpy {}
    }

    Component {
        id: monitorComponent
        FakeMonitor {}
    }

    Component {
        id: cellComponent
        UsageCellContent {
            item: "claude"
            ring: 34
            textShown: true
            twoLines: true
        }
    }

    Component {
        id: graphComponent
        WeekGraph {
            width: 700
            height: 100
        }
    }

    Component {
        id: host
        Loader {}
    }

    TestCase {
        name: "Report"

        function test_helperFailure_data() {
            return [
                { tag: "no python3", data: { "exit code": 127, "exit status": 0, stderr: "sh: 1: python3: not found\n" },
                  failure: { reason: "missing", code: 127, detail: "" } },
                { tag: "crash", data: { "exit code": 11, "exit status": 1, stderr: "" },
                  failure: { reason: "crashed", code: 11, detail: "" } },
                { tag: "unreadable output", data: { "exit code": 0, "exit status": 0, stderr: "" },
                  failure: { reason: "unreadable", code: 0, detail: "" } },
                { tag: "traceback", data: { "exit code": 1, "exit status": 0,
                                            stderr: "Traceback (most recent call last):\n  File \"x\"\nKeyError: 'weekly'\n\n" },
                  failure: { reason: "exited", code: 1, detail: "KeyError: 'weekly'" } }
            ];
        }

        function test_helperFailure(data) {
            compare(Report.helperFailure(data.data), data.failure);
        }

        function test_markFailedMarksOnlyShownEntries() {
            const before = { claude: { status: "ok", weekly: { percent: 40 } }, codex: { status: "signed_out" } };
            const after = Report.markFailed(before, "boom", 1000);
            compare(after.claude.weekly.percent, 40);
            compare(after.claude.lastError, "boom");
            compare(after.claude.lastErrorAt, 1000);
            compare(after.codex, before.codex);
            verify(before.claude.lastError === undefined, "the input is not modified");
        }

        function test_markFailedAddsNoEntry() {
            compare(Object.keys(Report.markFailed({}, "boom", 1000)).length, 0);
            compare(Object.keys(Report.markFailed({ codex: { status: "ok" } }, "boom", 1000)), ["codex"]);
        }
    }

    TestCase {
        id: data
        name: "UsageData"
        when: windowShown

        property var config: null
        property var usage: null

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }

        // Created with the stub in place, so the first poll never runs usage.py.
        function make(scenario, providers) {
            config = createTemporaryObject(configComponent, data);
            usage = createTemporaryObject(usageComponent, data,
                                          { config: config, helperPath: root.stub(scenario), providers: providers });
            return usage;
        }

        function spy(signalName) {
            return createTemporaryObject(spyComponent, data, { target: usage, signalName: signalName });
        }

        // Runs a scenario, or the same one again, and waits for its report.
        function poll(scenario) {
            const landed = spy("entriesChanged");
            if (usage.helperPath === root.stub(scenario)) {
                usage.refresh();
            } else {
                usage.helperPath = root.stub(scenario);
            }
            landed.wait(10000);
        }

        function start(scenario, providers) {
            make(scenario, providers ?? ["claude", "codex"]);
            spy("entriesChanged").wait(10000);
        }

        function timers() {
            return usage.resources.filter(r => r.triggeredOnStart !== undefined);
        }

        function test_okReport() {
            start("ok");
            compare(usage.entry("claude").weekly.percent, 52);
            compare(usage.entry("codex").weekly.percent, 24);
            verify(usage.claudePresent && usage.codexPresent);
            verify(!usage.degraded("claude") && !usage.degraded("codex"));
            compare(usage.inner("claude").id, "Fable");
            compare(usage.inner("codex"), null);
            compare(usage.helperError, "");
            compare(JSON.parse(config.knownLimits),
                    { claude: [{ id: "Fable", label: "Fable", reported: true }], codex: [] });
            compare(JSON.parse(config.usageStatus), { claude: { status: "ok", message: "" },
                                                      codex: { status: "ok", message: "" }, helperError: "" });
        }

        function test_innerFollowsTheChoice() {
            start("ok");
            config.claudeInnerLimit = "none";
            compare(usage.inner("claude"), null);
            config.claudeInnerLimit = "Fable";
            compare(usage.inner("claude").percent, 78);
            config.claudeInnerLimit = "Sonnet";
            compare(usage.inner("claude"), null, "a picked limit that isn't reported shows none");
        }

        function test_failedPollKeepsTheLastReading() {
            start("ok");
            poll("failed");
            compare(usage.entry("claude").weekly.percent, 52);
            compare(usage.entry("claude").lastError, "HTTP Error 500: Internal Server Error");
            verify(Math.abs(usage.entry("claude").lastErrorAt - Date.now() / 1000) < 60);
            compare(usage.entry("codex").lastError, "HTTP Error 429: Too Many Requests");
            verify(usage.degraded("claude") && usage.degraded("codex"));
            verify(usage.claudePresent && usage.codexPresent, "a failed poll keeps the items");
            // The helper holds a refused provider back itself; the widget
            // never polls sooner than its interval.
            compare(timers().filter(t => t.running).map(t => t.interval), [5 * 60000]);
            compare(JSON.parse(config.usageStatus).claude,
                    { status: "error", message: "HTTP Error 500: Internal Server Error" });
            compare(JSON.parse(config.usageStatus).codex.status, "rate_limited");

            poll("ok");
            verify(!usage.degraded("claude") && !usage.degraded("codex"));
        }

        // Signed out replaces the reading; a tool that never answered stays
        // hidden, and the settings page learns why.
        function test_signedOutAndMissing() {
            start("signed-out");
            compare(usage.entry("claude").status, "signed_out");
            compare(usage.entry("codex"), null);
            verify(!usage.claudePresent && !usage.codexPresent);
            compare(JSON.parse(config.usageStatus).codex, { status: "error", message: "codex CLI not found" });

            poll("ok");
            verify(usage.claudePresent && usage.codexPresent);
            poll("signed-out");
            verify(!usage.claudePresent, "signing out hides Claude");
            verify(usage.codexPresent && usage.degraded("codex"), "an error keeps Codex's last reading");
        }

        function test_helperFailure_data() {
            return [
                { tag: "no python3", scenario: "no-python", message: "python3 was not found on the Plasma session's PATH." },
                { tag: "traceback", scenario: "traceback", message: "The usage helper exited with code 1: KeyError: 'weekly'" }
            ];
        }

        function test_helperFailure(data) {
            start("ok");
            poll(data.scenario);
            compare(usage.helperError, data.message);
            compare(usage.entry("claude").lastError, data.message);
            compare(usage.entry("claude").weekly.percent, 52, "the last reading stays");
            verify(usage.degraded("codex"));
            compare(JSON.parse(config.usageStatus).helperError, data.message);
            compare(JSON.parse(config.usageStatus).claude.status, "ok", "the providers keep their last status");

            poll("ok");
            compare(usage.helperError, "");
            verify(!usage.degraded("claude"));
        }

        function test_failureWords_data() {
            return [
                { tag: "crashed", failure: { reason: "crashed", code: 11, detail: "" },
                  message: "The usage helper stopped unexpectedly." },
                { tag: "unreadable", failure: { reason: "unreadable", code: 0, detail: "" },
                  message: "The usage helper's output couldn't be read." },
                { tag: "exited", failure: { reason: "exited", code: 2, detail: "" },
                  message: "The usage helper exited with code 2." }
            ];
        }

        function test_failureWords(data) {
            make("ok", []);
            compare(usage.failureText(data.failure), data.message);
        }

        function test_presentNotifiesOnlyWhenItFlips() {
            make("ok", ["claude", "codex"]);
            const claude = spy("claudePresentChanged");
            const codex = spy("codexPresentChanged");
            spy("entriesChanged").wait(10000);
            compare(claude.count, 1);
            poll("ok");
            poll("failed");
            poll("ok");
            compare(claude.count, 1, "polls that keep Claude shown don't notify");
            compare(codex.count, 1);
            poll("signed-out");
            compare(claude.count, 2);
            compare(codex.count, 1, "Codex keeps its reading");
        }

        function test_configWrittenOnlyOnChange() {
            start("ok");
            compare(config.knownLimitsWrites, 1);
            compare(config.usageStatusWrites, 1);
            poll("ok");
            compare(config.knownLimitsWrites, 1);
            compare(config.usageStatusWrites, 1);

            // A picked limit that isn't reported stays on offer, marked.
            config.claudeInnerLimit = "Haiku";
            compare(config.knownLimitsWrites, 2);
            compare(JSON.parse(config.knownLimits).claude[1], { id: "Haiku", label: "Haiku", reported: false });
            config.claudeInnerLimit = "";
            compare(config.knownLimitsWrites, 3);
            config.codexInnerLimit = "none";
            compare(config.knownLimitsWrites, 3, "no change to what is on offer");

            poll("failed");
            compare(config.usageStatusWrites, 2);
            poll("failed");
            compare(config.usageStatusWrites, 2);
            compare(config.knownLimitsWrites, 3, "a failed poll keeps the limits on offer");

            poll("reset");
            compare(config.knownLimitsWrites, 4);
            compare(JSON.parse(config.knownLimits).claude.map(l => l.id), ["Fable", "Sonnet"]);
        }

        function test_resetsArriveBeforeTheReadings() {
            start("ok");
            const seen = [];
            const listener = events => seen.push({ events: events, percent: usage.entry("claude").weekly.percent });
            usage.resetsDetected.connect(listener);
            poll("reset");
            usage.resetsDetected.disconnect(listener);
            compare(seen.length, 1);
            compare(seen[0].percent, 52, "sent while the old reading is still there");
            compare(seen[0].events, { "claude.weekly": { from: 52, early: true },
                                      "claude.scoped.Fable": { from: 78, early: true } });
            compare(usage.entry("claude").weekly.percent, 3);
        }

        function test_noProvidersPollsNothing() {
            make("ok", []);
            verify(timers().every(t => !t.running));
            compare(usage.command, "");
            wait(1500);
            compare(usage.entries, {});
            compare(config.knownLimitsWrites + config.usageStatusWrites, 0);

            const landed = spy("entriesChanged");
            usage.providers = ["codex"];
            landed.wait(10000);
            compare(Object.keys(usage.entries), ["codex"]);
            verify(!usage.claudePresent && usage.codexPresent);
        }

        function test_droppedProvidersGoAtOnce() {
            start("ok");
            usage.providers = ["claude"];
            compare(Object.keys(usage.entries), ["claude"]);
            verify(!usage.codexPresent);
            compare(Object.keys(JSON.parse(config.usageStatus)), ["claude", "helperError"]);
            spy("entriesChanged").wait(10000);
            compare(Object.keys(usage.entries), ["claude"], "the next report adds nothing unasked");
        }

        function test_commandQuotesThePathAndKnownIds() {
            make("ok", []);
            usage.helperPath = "/nonexistent/it's/usage.py";
            compare(usage.command, "");
            usage.providers = ["codex", "cpu", "claude", "bogus"];
            compare(usage.command, "python3 -B '/nonexistent/it'\\''s/usage.py' --providers claude,codex");
            // python3 can't open it; the helper failure says so.
            tryVerify(() => usage.helperError.startsWith("The usage helper exited with code 2"), 10000, usage.helperError);
        }
    }

    TestCase {
        id: cells
        name: "UsageCell"
        when: windowShown

        property var monitor: null
        property var made: []

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            monitor = monitorComponent.createObject(cells);
        }

        // The cells go first, so their bindings never see the monitor gone.
        function cleanup() {
            made.forEach(c => c.destroy());
            made = [];
            wait(0);
            monitor.destroy();
        }

        function cell(item, properties) {
            const c = cellComponent.createObject(root, Object.assign({ monitor: monitor, item: item }, properties));
            made.push(c);
            waitForRendering(c);
            return c;
        }

        // A line of the readout beside the ring: "first", the weekly
        // percentage, or "second", the time to the reset.
        function line(cell, name) {
            return root.find(cell, i => i.objectName === name);
        }

        // The Claude or Codex mark inside the ring.
        function mark(cell) {
            return root.find(cell.children[0], i => i.markName !== undefined);
        }

        // Claude at `percent` with no model limit, resetting in `left` seconds.
        function claudeAt(percent, left) {
            const usage = monitor.usage;
            usage.entries = { claude: { status: "ok", fetchedAt: usage.createdAt,
                                        weekly: usage.window(percent, left ?? 2 * usage.day, []), scoped: [] } };
        }

        // Five hours before the reset, where every reading under 100 % lasts
        // the week, so only the percentage sets the level.
        readonly property int lastHours: 5 * 3600

        function test_texts_data() {
            return [{ tag: "claude", percent: "52%", left: "2d" },
                    { tag: "codex", percent: "24%", left: "5d" }];
        }

        // The mark names the item in the ring, and the percentage moves out
        // of it to stand over the time to the reset.
        function test_texts(data) {
            const c = cell(data.tag);
            const gauge = c.children[0];
            compare(root.texts(c), [data.percent, data.left].map(root.localized));
            compare(line(c, "first").text, root.localized(data.percent));
            compare(line(c, "second").text, root.localized(data.left));
            verify(line(c, "second").y >= line(c, "first").y + line(c, "first").height, "the time sits under the percentage");
            compare(gauge.text, "", "no percentage inside the ring");
            const m = mark(c);
            verify(m.visible, "the mark shows");
            compare(m.markName, data.tag);
            verify(m.width > 0 && m.width <= gauge.centreWidth, m.width + " in " + gauge.centreWidth);
        }

        // A thin panel puts the readings on one line and leaves the ring
        // unnamed; with the text off, the ring keeps its mark alone.
        function test_oneLineAndRingOnly() {
            const thin = cell("claude", { twoLines: false });
            compare(root.texts(thin), ["52%", "·", "2d"].map(root.localized));
            compare(line(thin, "second").y, line(thin, "first").y, "one line");
            verify(line(thin, "second").x > line(thin, "first").x);
            verify(!mark(thin).visible, "no mark beside one line");
            const bare = cell("claude", { textShown: false });
            compare(root.texts(bare), []);
            compare(bare.implicitWidth, 34, "the ring alone");
            verify(mark(bare).visible, "the ring keeps its mark");
            verify(bare.accessibleDescription !== "", "the tooltip still has the words");
        }

        function test_countdownKeepsItsRoom_data() {
            return [{ tag: "two lines", twoLines: true }, { tag: "one line", twoLines: false }];
        }

        // The countdown shows its largest unit alone and keeps one room
        // whatever it reads, from a new week down to the last minutes and a
        // passed reset, so the cell keeps its width; every reading fits its
        // box and starts where the last one did.
        function test_countdownKeepsItsRoom(data) {
            claudeAt(40, 6 * 86400 + 23 * 3600);
            const c = cell("claude", { twoLines: data.twoLines });
            const readout = root.find(c, i => i.textWidth !== undefined);
            const width = c.implicitWidth;
            const room = readout.rooms[1];
            const starts = ["first", "second"].map(name => line(c, name).mapToItem(c, Qt.point(0, 0)).x);
            const shown = [];
            for (const percent of [0, 5, 100, NaN]) {
                for (const left of [6 * 86400 + 23 * 3600, 86400 + 11 * 3600, 23 * 3600 + 59 * 60, 10 * 3600 + 10 * 60,
                                    3600, 59 * 60, 5 * 60, 30, -600]) {
                    claudeAt(percent, left);
                    waitForRendering(c);
                    const texts = [line(c, "first").text, line(c, "second").text];
                    const what = texts.join(" ") + " at " + percent + "% with " + left + " s left";
                    verify(!texts[1].includes(" "), what + ": one unit");
                    ["first", "second"].forEach((name, i) => {
                        const text = line(c, name);
                        verify(text.contentWidth <= text.width, text.text + " overflows its room: " + what);
                        compare(text.mapToItem(c, Qt.point(0, 0)).x, starts[i], what + ": " + name + " stays put");
                    });
                    compare(readout.rooms[1], room, what + ": the countdown's room");
                    compare(c.implicitWidth, width, what + ": the cell's width");
                    shown.push(texts[1]);
                }
            }
            for (const text of ["6d", "1d", "23h", "10h", "1h", "59m", "5m", "–"]) {
                verify(shown.includes(root.localized(text)), text + " among " + JSON.stringify(shown));
            }
            compare(line(c, "first").text, "–", "no percentage, a dash");
            compare(line(c, "second").text, "–", "a passed reset shows a dash until the next poll");
        }

        function test_levelColours_data() {
            return [{ tag: "74", percent: 74, tone: "text" }, { tag: "75", percent: 75, tone: "neutral" },
                    { tag: "89", percent: 89, tone: "neutral" }, { tag: "90", percent: 90, tone: "negative" }];
        }

        // The percentage takes the ring's colour; the time stays dim, so
        // only the reading that reached a level shows it.
        function test_levelColours(data) {
            claudeAt(data.percent, lastHours);
            const c = cell("claude");
            const expected = data.tone === "negative" ? Kirigami.Theme.negativeTextColor
                           : data.tone === "neutral" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
            compare(c.children[0].outerTone, expected);
            compare(line(c, "first").color, c.children[0].outerTone, "the percentage follows the ring");
            // Text keeps 8-bit colours, so they compare as drawn.
            compare(String(line(c, "second").color), String(Style.dim(Kirigami.Theme.textColor)), "the time stays dim");
        }

        function test_countdownRedAtTheLimit_data() {
            return [{ tag: "99", percent: 99, left: 2 * 86400, shows: "2d", tone: "dim" },
                    { tag: "100", percent: 100, left: 2 * 86400, shows: "2d", tone: "negative" },
                    { tag: "100 last minutes", percent: 100, left: 10 * 60, shows: "10m", tone: "negative" },
                    { tag: "100 reset passed", percent: 100, left: -600, shows: "–", tone: "dim" }];
        }

        // At the limit the countdown says how long the lock-out lasts, and
        // turns red with the percentage, as the popup's does. A reset that
        // has passed shows a dim dash until the next check. On one line the
        // dot between them stays dim.
        function test_countdownRedAtTheLimit(data) {
            claudeAt(data.percent, data.left);
            const dim = String(Style.dim(Kirigami.Theme.textColor));
            for (const twoLines of [true, false]) {
                const c = cell("claude", { twoLines: twoLines });
                compare(line(c, "second").text, root.localized(data.shows));
                compare(String(line(c, "second").color), data.tone === "dim" ? dim : String(Kirigami.Theme.negativeTextColor));
                compare(line(c, "first").color, c.children[0].outerTone, "the percentage follows the ring");
                const dot = root.find(c, i => i.visible && i.text === "·");
                compare(dot ? String(dot.color) : dim, dim, "the dot");
            }
        }

        function test_pulse_data() {
            return [{ tag: "89", percent: 89, pulsing: false }, { tag: "90", percent: 90, pulsing: true },
                    { tag: "99", percent: 99, pulsing: true }, { tag: "100", percent: 100, pulsing: false }];
        }

        function test_pulse(data) {
            claudeAt(data.percent, lastHours);
            compare(cell("claude").children[0].pulsing, data.pulsing);
        }

        // Weekly and model readings as [percent, seconds to the reset],
        // read `polledAgo` seconds before now, and the tones they give the
        // ring, the inner ring and the percentage. Only the reading sets the
        // tone, amber from 75 % and red from 90 %, whatever the pace: a limit
        // on course to run out early says so in the popup's sentence alone.
        function test_paceNeverRaisesTheLevel_data() {
            const day = 86400;
            return [
                { tag: "lasts", weekly: [52, 2 * day + 21 * 3600], outer: "text" },
                { tag: "runs out", weekly: [70, 3 * day], outer: "text" },
                { tag: "runs out at 39", weekly: [39, 5 * day], outer: "text" },
                { tag: "amber runs out", weekly: [80, 2 * day], outer: "neutral" },
                { tag: "amber lasts", weekly: [80, 5 * 3600], outer: "neutral" },
                { tag: "red from 90", weekly: [92, 2 * day + 21 * 3600], outer: "negative" },
                { tag: "runaway first day", weekly: [70, 7 * day - 18 * 3600], outer: "text" },
                { tag: "quiet first day", weekly: [5, 7 * day - 3 * 3600], outer: "text" },
                { tag: "reset passed", weekly: [70, -600], outer: "text" },
                { tag: "used up", weekly: [100, 2 * day], outer: "negative" },
                { tag: "from its poll", weekly: [50, 3 * day], polledAgo: day, outer: "text" },
                { tag: "model runs out", weekly: [52, 2 * day + 21 * 3600], inner: [78, 2 * day + 21 * 3600],
                  outer: "text", innerTone: "neutral" },
                { tag: "model lasts", weekly: [52, 5 * 3600], inner: [78, 5 * 3600], outer: "text", innerTone: "neutral" },
                { tag: "model quiet", weekly: [70, 3 * day], inner: [30, 2 * day + 21 * 3600],
                  outer: "text", innerTone: "text" },
                { tag: "model red from 90", weekly: [52, 2 * day + 21 * 3600], inner: [95, 2 * day + 21 * 3600],
                  outer: "text", innerTone: "negative" }
            ];
        }

        function test_paceNeverRaisesTheLevel(data) {
            const usage = monitor.usage;
            const scoped = data.inner ? [Object.assign({ id: "Fable", label: "Fable" }, usage.window(data.inner[0], data.inner[1], []))] : [];
            usage.entries = { claude: { status: "ok", fetchedAt: usage.createdAt - (data.polledAgo ?? 0),
                                        weekly: usage.window(data.weekly[0], data.weekly[1], []), scoped: scoped } };
            const tone = name => name === "negative" ? Kirigami.Theme.negativeTextColor
                               : name === "neutral" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
            const c = cell("claude");
            const gauge = c.children[0];
            compare(gauge.outerTone, tone(data.outer), "the ring");
            compare(outerArc(c).color, tone(data.outer), "the ring as drawn");
            compare(line(c, "first").color, gauge.outerTone, "the percentage follows the ring");
            if (data.weekly[0] < 100) {
                compare(String(line(c, "second").color), String(Style.dim(Kirigami.Theme.textColor)), "the time stays dim");
            }
            compare(gauge.inner, data.inner !== undefined);
            if (data.inner) {
                compare(gauge.innerTone, tone(data.innerTone), "the inner ring");
                compare(innerArc(c).color, Qt.alpha(tone(data.innerTone), 0.55 * Kirigami.Theme.textColor.a), "the inner ring as drawn");
            }
            compare(cell("claude", { textShown: false }).children[0].outerTone, gauge.outerTone, "the ring alone keeps its level");
        }

        // The rings of thin panels too: a strip 18 to 24 px thick has rings
        // of 15 to 20 px.
        function test_failedCheckShowsADot_data() {
            return [{ tag: "34", ring: 34 }, { tag: "22", ring: 22 }, { tag: "52", ring: 52 },
                    { tag: "34 mirrored", ring: 34, mirrored: true }, { tag: "15", ring: 15 }, { tag: "16", ring: 16 },
                    { tag: "18", ring: 18 }, { tag: "20", ring: 20 }, { tag: "16 mirrored", ring: 16, mirrored: true }];
        }

        // A failed check keeps the last reading and puts a small dot in the
        // ring's corner above the readings, clear of the arc and still while
        // the ring breathes; on a small ring it sits out from the corner as
        // far as that takes. The words say when the check failed.
        function test_failedCheckShowsADot(data) {
            claudeAt(95, lastHours);
            const c = cell("claude", { ring: data.ring });
            c.LayoutMirroring.enabled = data.mirrored ?? false;
            c.LayoutMirroring.childrenInherit = true;
            const gauge = c.children[0];
            const dot = Array.from(c.children).find(i => i.border !== undefined);
            verify(!dot.visible, "no dot while the checks succeed");
            const reading = [line(c, "first").text, line(c, "second").text, gauge.outerTone];

            const entries = monitor.usage.entries;
            monitor.usage.entries = Object.assign({}, entries, {
                claude: Object.assign({}, entries.claude, { lastError: "HTTP Error 500", lastErrorAt: monitor.usage.createdAt })
            });
            waitForRendering(c);
            verify(dot.visible, "a dot");
            compare([line(c, "first").text, line(c, "second").text, gauge.outerTone], reading, "the last reading stays");
            compare(c.opacity, 1, "no fade");
            compare(gauge.opacity, 1);
            compare(dot.color, Kirigami.Theme.neutralTextColor);
            compare([dot.border.width, dot.border.color], [1, Kirigami.Theme.backgroundColor]);
            compare(dot.width, Math.max(4, Math.round(data.ring / 6)));
            compare(dot.height, dot.width);
            compare(dot.radius, dot.width / 2);
            verify(dot.Accessible.ignored);
            verify(gauge.pulsing && dot.parent === c, "outside the breathing face");

            const at = dot.mapToItem(gauge, Qt.point(0, 0));
            const outset = -at.y;
            verify(outset >= 0 && outset < 1, "at the top, or just above it: " + outset);
            if (data.ring >= 22) {
                compare(outset, 0, "in the corner");
            }
            compare(at.x, data.mirrored ? -outset : gauge.width - dot.width + outset,
                    data.mirrored ? "at the left, above the readings" : "at the right");
            verify(data.mirrored ? line(c, "first").mapToItem(gauge, Qt.point(0, 0)).x < 0
                                 : line(c, "first").mapToItem(gauge, Qt.point(0, 0)).x > gauge.width, "the readings on its side");
            const r = dot.width / 2;
            const clear = Math.hypot(at.x + r - gauge.width / 2, at.y + r - gauge.height / 2) - r;
            const arc = outerArc(c);
            verify(clear >= arc.radius + arc.strokeWidth / 2 - 1e-9, "clear of the arc: " + clear + " from the centre, the arc to "
                   + (arc.radius + arc.strokeWidth / 2));
            verify(c.accessibleDescription.indexOf(". Last check failed at ") > 0, c.accessibleDescription);

            monitor.usage.entries = entries;
            verify(!dot.visible, "gone with the next good check");
        }

        // The percentages in the locale's digits; the stand-in i18ncp
        // leaves the days and hours as they are given.
        function test_descriptions() {
            const p = root.localized;
            compare(cell("claude").accessibleDescription, p("52%") + " used, Fable " + p("78%") + ", resets in 2 days 21 hours");
            compare(cell("codex").accessibleDescription, p("24%") + " used, resets in 5 days 4 hours");
            monitor.usage.innerChoices = { claude: "none", codex: "" };
            compare(cell("claude").accessibleDescription, p("52%") + " used, resets in 2 days 21 hours");
            claudeAt(40, 3600);
            compare(cell("claude").accessibleDescription, p("40%") + " used, resets in 1 hour");
            monitor.usage.entries = { claude: { status: "signed_out" } };
            compare(cell("claude").accessibleDescription, "Signed out");
        }

        function arcs(cell) {
            const found = [];
            const collect = i => {
                if (i.animating !== undefined) {
                    found.push(i);
                }
                i.children.forEach(collect);
            };
            collect(cell.children[0]);
            return found;
        }

        // Only the item's own windows play, and a model's only while its
        // limit is the one on the inner ring.
        function test_playsItsResets() {
            const claude = cell("claude");
            const codex = cell("codex");
            monitor.usage.resetsDetected({ "claude.weekly": { from: 80, early: false },
                                           "claude.scoped.Fable": { from: 95, early: true } });
            compare(arcs(claude).map(a => a.animating), [true, true]);
            verify(arcs(codex).every(a => !a.animating));
            tryVerify(() => arcs(claude).every(a => !a.animating), 5000);

            monitor.usage.innerChoices = { claude: "none", codex: "" };
            monitor.usage.resetsDetected({ "claude.scoped.Fable": { from: 95, early: false } });
            verify(arcs(claude).every(a => !a.animating), "no inner ring, nothing to play");
        }

        function setEntry(id, entry) {
            const entries = Object.assign({}, monitor.usage.entries);
            entries[id] = entry;
            monitor.usage.entries = entries;
        }

        // The weekly arc is the outer of the two, the chosen limit's the inner.
        function outerArc(cell) {
            return arcs(cell).reduce((a, b) => a.radius > b.radius ? a : b);
        }

        function innerArc(cell) {
            return arcs(cell).reduce((a, b) => a.radius < b.radius ? a : b);
        }

        // The inner ring follows the chosen limit; the readout beside it keeps
        // the weekly share and the time to its reset whichever limit shows.
        function test_innerLimitFollowsSettings() {
            const claude = cell("claude");
            const codex = cell("codex");
            compare(claude.innerLimit.id, "Fable", "The only limit shows by default");
            compare(claude.children[0].inner, true);
            compare(claude.children[0].innerValue, 78);
            compare(root.texts(claude), ["52%", "2d"].map(root.localized));
            compare(codex.innerLimit, null, "No scoped limit, no inner ring");
            compare(codex.children[0].inner, false);
            compare(root.texts(codex), ["24%", "5d"].map(root.localized));

            setEntry("codex", { status: "ok", weekly: { percent: 24 },
                                scoped: [{ id: "codex_spark", label: "GPT-5.3-Codex-Spark", percent: 5 }] });
            compare(codex.innerLimit.id, "codex_spark", "A new limit is picked up");
            compare(codex.children[0].inner, true);
            compare(codex.children[0].innerValue, 5);
            compare(root.texts(codex), ["24%", "–"].map(root.localized));

            const fable = { id: "Fable", label: "Fable", percent: 78 };
            const sonnet = { id: "Sonnet", label: "Sonnet", percent: 9 };
            setEntry("claude", { status: "ok", weekly: { percent: 62 }, scoped: [fable, sonnet] });
            compare(claude.innerLimit, null, "Several and none picked: all models only");
            compare(claude.children[0].inner, false);
            compare(root.texts(claude), ["62%", "–"].map(root.localized));
            monitor.usage.innerChoices = { claude: "Sonnet", codex: "" };
            compare(claude.innerLimit.id, "Sonnet");
            compare(claude.children[0].inner, true);
            compare(claude.children[0].innerValue, 9);
            compare(root.texts(claude), ["62%", "–"].map(root.localized));
            monitor.usage.innerChoices = { claude: "none", codex: "" };
            compare(claude.innerLimit, null);
            compare(claude.children[0].inner, false);
            compare(root.texts(claude), ["62%", "–"].map(root.localized));
            monitor.usage.innerChoices = { claude: "Sonnet", codex: "" };
            setEntry("claude", { status: "ok", weekly: { percent: 62 }, scoped: [fable] });
            compare(claude.innerLimit, null, "A picked limit that goes away leaves one circle");
            compare(claude.children[0].inner, false);

            // A reading without a weekly window yet, after a failed first poll.
            setEntry("codex", { status: "error", lastError: "timed out", lastErrorAt: 1 });
            compare(root.texts(codex), ["–", "–"]);
            verify(!Number.isFinite(codex.children[0].value));
        }

        function test_resetsReachOnlyTheShownLimit() {
            const fable = { id: "Fable", label: "Fable", percent: 78 };
            const sonnet = { id: "Sonnet", label: "Sonnet", percent: 9 };
            setEntry("claude", { status: "ok", weekly: { percent: 62 }, scoped: [fable, sonnet] });
            monitor.usage.innerChoices = { claude: "Fable", codex: "" };
            const claude = cell("claude");
            const codex = cell("codex");
            const inner = innerArc(claude);
            monitor.usage.resetsDetected({ "claude.scoped.Sonnet": { from: 92, early: true } });
            compare(inner.animating, false, "A limit that is not shown plays nothing");
            monitor.usage.resetsDetected({ "claude.scoped.Fable": { from: 92, early: true } });
            verify(inner.animating, "The shown limit plays its reset");
            tryCompare(inner, "animating", false);
            // Events are handed over once, so changing the pick replays nothing.
            monitor.usage.innerChoices = { claude: "Sonnet", codex: "" };
            monitor.usage.innerChoices = { claude: "Fable", codex: "" };
            compare(inner.animating, false);
            compare(inner.head, 78);
            monitor.usage.innerChoices = { claude: "none", codex: "" };
            monitor.usage.resetsDetected({ "claude.scoped.Fable": { from: 92, early: true } });
            compare(inner.animating, false, "No reset plays on a hidden arc");
            // The weekly arc plays its own, and only on its own item.
            monitor.usage.resetsDetected({ "codex.weekly": { from: 97, early: false } });
            verify(outerArc(codex).animating);
            compare(outerArc(claude).animating, false);
            tryCompare(outerArc(codex), "animating", false, 5000);
        }
    }

    TestCase {
        id: popups
        name: "UsagePopup"
        when: windowShown

        property var monitor: null
        property var loaders: []

        Component {
            id: mirroredHost
            Loader {
                LayoutMirroring.enabled: true
                LayoutMirroring.childrenInherit: true
            }
        }

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            monitor = monitorComponent.createObject(popups);
        }

        function cleanup() {
            loaders.forEach(l => l.destroy());
            loaders = [];
            wait(0);
            monitor.destroy();
        }

        function load(item, mirrored) {
            const loader = (mirrored ? mirroredHost : host).createObject(root) as Loader;
            loaders.push(loader);
            loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/UsagePopup.qml"), { monitor: monitor, item: item });
            compare(loader.status, Loader.Ready);
            const page = loader.item as Item;
            waitForRendering(page);
            verify(page.implicitWidth > 0 && page.implicitHeight > 0);
            return page;
        }

        function graph(popup) {
            return root.find(popup, i => i.mainPoints !== undefined);
        }

        function header(popup) {
            return root.find(popup, i => i.partsShown !== undefined);
        }

        function ring(popup) {
            return root.find(popup, i => i.outerTone !== undefined);
        }

        // The countdown's visible Readings, in the order of the parts.
        function countdown(popup) {
            const found = [];
            const collect = i => {
                if (i.numberWidth !== undefined) {
                    if (i.visible && i.accessibleIgnored) {
                        found.push(i);
                    }
                    return;
                }
                i.children.forEach(collect);
            };
            collect(header(popup));
            return found;
        }

        function caption(popup) {
            return root.find(header(popup), i => i.text === "until reset");
        }

        // Each limit's delegate, in order: its bar and the pace sentence.
        function rows(popup) {
            const found = [];
            const collect = i => {
                if (i.resets !== undefined && i.level !== undefined) {
                    found.push(i);
                    return;
                }
                i.children.forEach(collect);
            };
            collect(popup);
            return found;
        }

        function sentence(row) {
            return row.children.find(c => c.wrapMode === Text.Wrap) ?? null;
        }

        function bars(row) {
            return row.children.find(c => c.wrapMode === undefined);
        }

        // The filled part of a row's bar.
        function fill(row) {
            return root.find(bars(row), i => i.radius !== undefined && i.parent.radius !== undefined);
        }

        function rowText(row, text) {
            return root.find(row, i => i.text === text);
        }

        function setClaude(changes) {
            const entries = monitor.usage.entries;
            monitor.usage.entries = Object.assign({}, entries, { claude: Object.assign({}, entries.claude, changes) });
        }

        function test_innerLimit() {
            const popup = load("claude");
            const shown = root.texts(popup);
            for (const text of ["Claude", "Weekly limits", "until reset", "All models", "Fable", root.localized("52%"), root.localized("78%"),
                                "— All models", "- - Fable"]) {
                verify(shown.includes(text), text + " in " + JSON.stringify(shown));
            }
            verify(shown.some(t => /^THIS WEEK · resets .+ EDT$/.test(t)), JSON.stringify(shown));
            verify(!shown.some(t => t.startsWith("resets in")), "Fable resets with the week");
            verify(!shown.includes("Open System Monitor"), "the footer has the gear alone");
            compare(countdown(popup).map(r => [r.value, r.unit]), [[root.localized("2"), "d"], [root.localized("21"), "h"]]);
            compare(graph(popup).mainPoints.length, 17);
            compare(graph(popup).secondPoints.length, 17);
            compare(graph(popup).pollAt, monitor.usage.createdAt);
        }

        // A limit's percentage is set like the other popups' numbers. The
        // header ring's centre, which says the same, is the panel ring's.
        function test_percentInSans() {
            const found = [];
            const collect = i => {
                if (i.outerTone !== undefined) {
                    return;
                }
                if (i.text === root.localized("52%") && i.font !== undefined) {
                    found.push(i);
                }
                i.children.forEach(collect);
            };
            collect(load("claude"));
            compare(found.length, 1);
            const percent = found[0];
            compare(percent.font.family, Kirigami.Theme.defaultFont.family);
            compare(percent.font.features.tnum, 1);
        }

        // The countdown is a Reading per part, stepped in place as time
        // passes; the row is spoken as one, caption included.
        function test_countdownKeepsItsReadings() {
            const popup = load("claude");
            const before = countdown(popup);
            const row = before[0].parent;
            compare(row.Accessible.name, "2 days 21 hours until reset");
            verify(caption(popup).Accessible.ignored);
            verify(before.every(r => r.accessibleIgnored));
            before.forEach(r => {
                const texts = r.children.filter(c => typeof c.text === "string");
                compare(texts.length, 2);
                verify(texts.every(t => t.Accessible.ignored), r.value + r.unit + " is not spoken on its own");
            });
            popup.nowMs += 3600 * 1000;
            const after = countdown(popup);
            compare(after.map(r => r.value + r.unit), ["2d", "20h"].map(root.localized));
            verify(after[0] === before[0] && after[1] === before[1], "the same Readings, not new ones");
            compare(row.Accessible.name, "2 days 20 hours until reset");
            popup.nowMs = (monitor.usage.entries.claude.weekly.resetsAt - 300) * 1000;
            compare(countdown(popup).map(r => r.value + r.unit), [root.localized("5m")]);
            popup.nowMs = (monitor.usage.entries.claude.weekly.resetsAt + 60) * 1000;
            compare(countdown(popup).length, 0);
            verify(root.texts(header(popup)).includes("–"), "a passed reset reads as a dash");
            verify(!root.texts(header(popup)).includes("until reset"));
        }

        // Each unit sits against its number, "5d 18h" and not "5 d 18 h":
        // the gap inside a pair is under half a space at the unit's size,
        // and the pairs stand at least a space apart.
        function test_countdownUnitsAreTight() {
            const usage = monitor.usage;
            setClaude({ weekly: usage.window(30, 5 * usage.day + 18 * 3600 + 30, []) });
            const [days, hours] = countdown(load("claude"));
            compare([days.value + days.unit, hours.value + hours.unit], ["5d", "18h"].map(root.localized));
            for (const r of [days, hours]) {
                const [number, unit] = r.children.filter(c => typeof c.text === "string");
                spaceProbe.font = unit.font;
                const gap = unit.mapToItem(r, Qt.point(0, 0)).x - number.mapToItem(r, Qt.point(number.width, 0)).x;
                verify(gap >= 0 && gap < spaceProbe.advanceWidth / 2, r.value + r.unit + ": " + gap + " px against a space of "
                       + spaceProbe.advanceWidth);
            }
            const between = hours.mapToItem(days.parent, Qt.point(0, 0)).x - days.mapToItem(days.parent, Qt.point(days.width, 0)).x;
            verify(between >= spaceProbe.advanceWidth, "the pairs " + between + " px apart");
        }

        // The pairs follow the popup's direction, the largest unit first in
        // reading order; each number stays before its unit, and the caption
        // lines up with the row's outer edge.
        function test_countdownMirrors_data() {
            return [{ tag: "plain", mirrored: false }, { tag: "mirrored", mirrored: true }];
        }

        function test_countdownMirrors(data) {
            const popup = load("claude", data.mirrored);
            const [days, hours] = countdown(popup);
            const x = r => r.mapToItem(popup, Qt.point(0, 0)).x;
            verify(data.mirrored ? x(days) > x(hours) : x(days) < x(hours), x(days) + " " + x(hours));
            verify(!days.LayoutMirroring.enabled && !hours.LayoutMirroring.enabled);
            const row = days.parent;
            const label = caption(popup);
            const rowLeft = row.mapToItem(popup, Qt.point(0, 0)).x;
            const labelLeft = label.mapToItem(popup, Qt.point(0, 0)).x;
            if (data.mirrored) {
                fuzzyCompare(labelLeft, rowLeft, 1);
            } else {
                fuzzyCompare(labelLeft + label.width, rowLeft + row.width, 1);
            }
        }

        // The ring and the bars carry the level; the countdown turns red only
        // once the limit is used up, when it is the time the lock-out lasts.
        function test_countdownRedOnlyAtTheLimit_data() {
            return [{ tag: "52", percent: 52, red: false }, { tag: "91", percent: 91, red: false },
                    { tag: "100", percent: 100, red: true }];
        }

        function test_countdownRedOnlyAtTheLimit(data) {
            const usage = monitor.usage;
            setClaude({ weekly: usage.window(data.percent, 2 * usage.day + 21 * 3600, []) });
            const readings = countdown(load("claude"));
            compare(readings.length, 2);
            const expected = String(data.red ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor);
            readings.forEach(r => compare(String(r.color), expected));
        }

        // Once the reset has passed with the reading still at 100 %, no
        // lock-out is left to count down: the dash stays plain, as in the
        // panel, until the next check brings the new week.
        function test_dashAfterTheResetIsNotRed() {
            const usage = monitor.usage;
            setClaude({ weekly: usage.window(100, -600, []) });
            const popup = load("claude");
            verify(!header(popup).partsShown);
            const dash = root.find(header(popup), i => i.numberWidth !== undefined && i.visible);
            compare(dash.value, "–");
            compare(String(dash.color), String(Kirigami.Theme.textColor));
        }

        // After the reset the dash has no caption, yet sits where the
        // countdown did, level with the title, and the header keeps its
        // height.
        function test_dashSitsWhereTheCountdownDid() {
            const place = () => {
                const h = header(load("claude"));
                const digits = root.find(h, i => i.numberWidth !== undefined && i.visible);
                return { height: h.height, baseline: digits.mapToItem(h, Qt.point(0, digits.baselineOffset)).y };
            };
            const countdown = place();
            setClaude({ weekly: monitor.usage.window(40, -600, []) });
            const dash = place();
            compare(dash.baseline, countdown.baseline, "the headline's baseline");
            compare(dash.height, countdown.height, "the header's height");
        }

        function test_codex() {
            const popup = load("codex");
            const shown = root.texts(popup);
            verify(shown.includes("Codex") && shown.includes("Weekly limit"), JSON.stringify(shown));
            compare(countdown(popup).map(r => r.value + r.unit), ["5d", "4h"].map(root.localized));
            verify(!shown.some(t => t.startsWith("- - ")), "no dashed series without an inner ring");
        }

        // One limit has no bars: the header's ring says the same number, and
        // "All models" contrasts with nothing. The subtitle is singular.
        function test_oneLimitHasNoBars() {
            const popup = load("codex");
            const shown = root.texts(popup);
            verify(!shown.includes("All models"), JSON.stringify(shown));
            const only = rows(popup);
            compare(only.length, 1);
            verify(!bars(only[0]).visible);
            verify(sentence(only[0]).visible, "the pace sentence takes the bars' place");
            verify(shown.includes("Weekly limit") && !shown.includes("Weekly limits"));
            const claude = root.texts(load("claude"));
            verify(claude.includes("Weekly limits") && !claude.includes("Weekly limit"), JSON.stringify(claude));
        }

        // With one limit and nothing to say about its pace, the graph's tile
        // follows the header directly.
        function test_oneQuietLimitShowsNoColumn() {
            const usage = monitor.usage;
            setClaude({ weekly: usage.window(5, 7 * usage.day - 3 * 3600, [[0.1, 2], [0, 5]]), scoped: [] });
            const popup = load("claude");
            const only = rows(popup);
            compare(only.length, 1);
            verify(!only[0].parent.visible, "no bars and no sentence");
        }

        // A tile reads as apart from the last bar: more room under the bars
        // than between them.
        function test_barsBottomMargin() {
            const [all, fable] = rows(load("claude"));
            const column = all.parent;
            const siblings = Array.from(column.parent.children);
            const tiles = siblings.slice(siblings.indexOf(column) + 1).find(i => i.visible);
            const gap = tiles.y - (column.y + column.height);
            compare(gap, Math.round(Kirigami.Units.largeSpacing * 1.75));
            verify(gap > fable.y - (all.y + all.height));
        }

        // One limit with nothing to say has no bars, and its tile then sits
        // as far under the ring as the CPU popup's first tile does.
        function test_tileUnderTheHeader() {
            const usage = monitor.usage;
            setClaude({ weekly: usage.window(5, 7 * usage.day - 3 * 3600, [[0.1, 2], [0, 5]]), scoped: [] });
            const popup = load("claude");
            verify(rows(popup).every(r => !r.parent.visible), "no bars and no sentence");
            const loader = host.createObject(root) as Loader;
            loaders.push(loader);
            loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/CpuPopup.qml"), { monitor: monitor });
            compare(loader.status, Loader.Ready);
            const cpu = loader.item as Item;
            waitForRendering(cpu);
            const gap = page => {
                const r = ring(page);
                const tile = root.find(page, i => i.visible && i.graphNote !== undefined);
                return tile.mapToItem(page, Qt.point(0, 0)).y - r.mapToItem(page, Qt.point(0, r.height)).y;
            };
            verify(gap(cpu) > 0);
            compare(gap(popup), gap(cpu));
        }

        // The countdown's caption shares the subtitle's baseline, plain and
        // mirrored, and the graph's tile spans the content's edges.
        function test_captionBaselineAndTileEdges_data() {
            return [{ tag: "plain", mirrored: false }, { tag: "mirrored", mirrored: true }];
        }

        function test_captionBaselineAndTileEdges(data) {
            const popup = load("claude", data.mirrored);
            const h = header(popup);
            const subtitle = root.find(h, i => i.visible && i.text === h.subtitle);
            verify(subtitle);
            const baseline = t => t.mapToItem(popup, Qt.point(0, t.baselineOffset)).y;
            fuzzyCompare(baseline(caption(popup)), baseline(subtitle), 1);
            const edge = Math.round(Kirigami.Units.largeSpacing * 2);
            const tile = root.find(popup, i => i.visible && i.graphNote !== undefined);
            const left = tile.mapToItem(popup, Qt.point(0, 0)).x;
            compare(left, edge);
            compare(left + tile.width, popup.width - edge);
        }

        // The week's tile ends on its legend's baseline with a model limit,
        // on the graph's floor without one; either sits as far from the
        // tile's bottom as the caption's capitals from its top.
        function test_weekTilePadding_data() {
            return [{ tag: "legend", item: "claude", legend: true }, { tag: "graph", item: "codex", legend: false }];
        }
        function test_weekTilePadding(data) {
            const popup = load(data.item);
            const tile = root.find(popup, i => i.visible && i.graphNote !== undefined);
            compare(tile.foot !== null, data.legend);
            const caption = root.find(tile, i => i.label !== undefined && i.detail !== undefined);
            const capTop = caption.mapToItem(tile, Qt.point(0, caption.baselineOffset)).y - tile.capHeight;
            const graph = root.find(tile, i => i.mainPoints !== undefined);
            const foot = data.legend ? tile.height - tile.foot.mapToItem(tile, Qt.point(0, tile.foot.baselineOffset)).y
                                     : tile.height - graph.mapToItem(tile, Qt.point(0, graph.height)).y;
            fuzzyCompare(foot, capTop, 1, "the foot's ink " + foot + " from the bottom, the capitals " + capTop + " from the top");
        }

        // A new reading keeps the limit's row: its bar moves to the reading
        // and the percentage counts with it, each frame in the colour of
        // the bar as drawn, so Fable turns red as its bar passes 90 %.
        function test_barsFollowTheirReadings() {
            const popup = load("claude");
            const row = rows(popup)[1];
            const bar = fill(row);
            const percent = rowText(row, root.localized("78%"));
            verify(percent, "78% beside Fable's bar");
            compare(bar.width, bar.parent.width * 0.78);
            const seen = [];
            bar.widthChanged.connect(() => seen.push([bar.width / bar.parent.width, row.level]));
            setClaude({ scoped: [Object.assign({}, monitor.usage.entries.claude.scoped[0], { percent: 95 })] });
            compare(rows(popup)[1], row, "the same row");
            compare(bar.width, bar.parent.width * 0.78, "starting from where it was");
            tryCompare(bar, "width", bar.parent.width * 0.95, 2000);
            compare(percent.text, root.localized("95%"));
            compare(String(bar.color), String(Kirigami.Theme.negativeTextColor));
            verify(seen.some(([drawn]) => drawn < 0.89) && seen.some(([drawn]) => drawn > 0.91), JSON.stringify(seen));
            verify(seen.every(([drawn, level]) => drawn < 0.895 ? level === 1 : drawn > 0.905 ? level === 2 : true),
                   "amber below 90 %, red from it, as drawn: " + JSON.stringify(seen));
        }

        // Every model's limit gets a row, whichever the ring shows.
        function test_severalLimits() {
            const usage = monitor.usage;
            setClaude({ scoped: [Object.assign({ id: "Fable", label: "Fable" }, usage.window(78, 2 * usage.day + 21 * 3600, [])),
                                 Object.assign({ id: "Sonnet", label: "Sonnet" }, usage.window(12, 4 * usage.day, []))] });
            const shown = root.texts(load("claude"));
            for (const text of ["All models", "Fable", "Sonnet", "78%", "12%", "resets in 4d 0h"].map(root.localized)) {
                verify(shown.includes(text), text + " in " + JSON.stringify(shown));
            }
            verify(!shown.some(t => t.startsWith("- - ")), "two limits and no choice: no inner ring");
        }

        // The one thing worth saying about the pace, under the bar it is
        // about, in the text colour. `row` is the limit it sits under; times
        // are rounded as the sentence rounds them.
        function test_paceSentence_data() {
            const day = 86400;
            const window = (percent, left, points) => ({ percent: percent, left: left, points: points });
            return [
                { tag: "modelOut", row: 1, expect: u => {
                    // Fable: 78 % four days and three hours in.
                    const w = u.entries.claude.scoped[0];
                    const start = w.resetsAt - w.windowSeconds;
                    return "Fable is on pace to run out " + wallClock(u, start + (u.createdAt - start) * 100 / 78, 600);
                } },
                { tag: "allOutFirst", row: 0,
                  weekly: window(60, 4 * day, [[3, 0], [2, 20], [1, 40], [0, 60]]),
                  scoped: [{ id: "Fable", label: "Fable", w: window(30, 4 * day, [[3, 0], [0, 30]]) }],
                  expect: u => "All models are on pace to run out " + wallClock(u, u.createdAt + 2 * day, 600) },
                // With both limits on course to run out, the sooner one is said.
                { tag: "bothOutModelSooner", row: 1,
                  weekly: window(60, 4 * day, [[3, 0], [0, 60]]),
                  scoped: [{ id: "Fable", label: "Fable", w: window(90, 4 * day, [[3, 0], [0, 90]]) }],
                  expect: u => "Fable is on pace to run out " + wallClock(u, u.createdAt - 3 * day + 3 * day * 100 / 90, 600) },
                { tag: "bothOutWeekSooner", row: 0,
                  weekly: window(85, 4 * day, [[3, 0], [0, 85]]),
                  scoped: [{ id: "Fable", label: "Fable", w: window(60, 4 * day, [[3, 0], [0, 60]]) }],
                  expect: u => "All models are on pace to run out " + wallClock(u, u.createdAt - 3 * day + 3 * day * 100 / 85, 600) },
                // A run-out still ahead outranks a model's limit already reached.
                { tag: "outBeforeModelReached", row: 0,
                  weekly: window(60, 4 * day, [[3, 0], [0, 60]]),
                  scoped: [{ id: "Fable", label: "Fable", w: window(100, 4 * day, [[3, 0], [1, 100], [0, 100]]) }],
                  expect: u => "All models are on pace to run out " + wallClock(u, u.createdAt + 2 * day, 600) },
                { tag: "oneLimitOut", row: 0,
                  weekly: window(60, 4 * day, [[3, 0], [2, 20], [1, 40], [0, 60]]), scoped: [],
                  expect: u => "The weekly limit is on pace to run out " + wallClock(u, u.createdAt + 2 * day, 600) },
                { tag: "lasts", row: 0,
                  weekly: window(30, 4 * day, [[3, 0], [0, 30]]), scoped: [],
                  expect: u => root.localized("On pace to use 70% by the reset") },
                { tag: "everyModelLockedOut", row: 0,
                  weekly: window(100, 2 * day, [[3, 50], [2, 100], [0, 100]]),
                  expect: u => "Limit reached " + wallClock(u, u.createdAt - 2 * day, 60) },
                { tag: "reachedAtAnUnknownTime", row: 0,
                  weekly: window(100, 2 * day, []), scoped: [],
                  expect: u => "Limit reached" },
                { tag: "modelReached", row: 1,
                  scoped: [{ id: "Fable", label: "Fable", w: window(100, 2 * day + 21 * 3600, [[1, 90], [0.5, 100], [0, 100]]) }],
                  expect: u => "Fable limit reached " + wallClock(u, u.createdAt - day / 2, 60) },
                // A runaway first day already warns.
                { tag: "runawayFirstDay", row: 0,
                  weekly: window(70, 7 * day - 18 * 3600, [[0.75, 0], [0, 70]]), scoped: [],
                  expect: u => "The weekly limit is on pace to run out "
                      + wallClock(u, u.createdAt - 18 * 3600 + day * 100 / 70, 600) },
                // A quiet one has nothing to say, and never says it is too early.
                { tag: "quietFirstDay", row: -1,
                  weekly: window(5, 7 * day - 3 * 3600, [[0.1, 2], [0, 5]]), scoped: [], expect: u => "" },
                { tag: "resetPassed", row: -1,
                  weekly: window(40, -60, [[3, 10], [0, 40]]), scoped: [], expect: u => "" },
                // Projected from a reading two days old, the run-out has
                // already passed: it may have happened, not still to come.
                { tag: "staleRunOutPast", row: 0, ago: 2 * day,
                  weekly: window(60, 3 * day, [[4, 0], [2, 60]]), scoped: [],
                  expect: u => "The weekly limit may already have run out "
                      + wallClock(u, u.createdAt - 4 * day + 2 * day * 100 / 60, 600) },
                { tag: "staleModelRunOutPast", row: 1, ago: 2 * day,
                  weekly: window(20, 3 * day, [[4, 0], [2, 20]]),
                  scoped: [{ id: "Fable", label: "Fable", w: window(60, 3 * day, [[4, 0], [2, 60]]) }],
                  expect: u => "Fable may already have run out "
                      + wallClock(u, u.createdAt - 4 * day + 2 * day * 100 / 60, 600) },
                { tag: "staleAllRunOutPast", row: 0, ago: 2 * day,
                  weekly: window(60, 3 * day, [[4, 0], [2, 60]]),
                  scoped: [{ id: "Fable", label: "Fable", w: window(20, 3 * day, [[4, 0], [2, 20]]) }],
                  expect: u => "All models may already have run out "
                      + wallClock(u, u.createdAt - 4 * day + 2 * day * 100 / 60, 600) }
            ];
        }

        function wallClock(usage, epoch, step) {
            return words.weekdayTime(Math.round(epoch / step) * step, usage.entries.claude.weekly);
        }

        function test_paceSentence(data) {
            const usage = monitor.usage;
            const changes = {};
            if (data.weekly) {
                changes.weekly = usage.window(data.weekly.percent, data.weekly.left, data.weekly.points);
            }
            if (data.scoped) {
                changes.scoped = data.scoped.map(s => Object.assign({ id: s.id, label: s.label },
                                                                    usage.window(s.w.percent, s.w.left, s.w.points)));
            }
            if (data.ago !== undefined) {
                Object.assign(changes, { fetchedAt: usage.createdAt - data.ago, lastError: "HTTP Error 500",
                                         lastErrorAt: usage.createdAt - 600 });
            }
            setClaude(changes);
            const popup = load("claude");
            const all = rows(popup);
            const said = all.map(r => sentence(r)).filter(s => s.visible);
            const expected = data.expect(usage);
            verify(!root.texts(popup).some(t => /early/i.test(t)), JSON.stringify(root.texts(popup)));
            if (data.row < 0) {
                compare(said.length, 0);
                return;
            }
            compare(said.length, 1);
            const text = sentence(all[data.row]);
            compare(text.text, expected);
            compare(String(text.color), String(Kirigami.Theme.textColor));
            compare(text.textFormat, Text.PlainText);
            if (all.length > 1) {
                const bar = bars(all[data.row]);
                verify(bar.visible);
                verify(text.mapToItem(popup, Qt.point(0, 0)).y >= bar.mapToItem(popup, Qt.point(0, bar.height)).y,
                       "the sentence sits under its bar");
                if (data.row + 1 < all.length) {
                    verify(text.mapToItem(popup, Qt.point(0, text.height)).y <= all[data.row + 1].mapToItem(popup, Qt.point(0, 0)).y,
                           "and above the next limit");
                }
            }
        }

        // A run-out is said to ten minutes, but never at or after the reset
        // it comes before: one that would round up past the reset, or into
        // its last minute, rounds down.
        function test_runOutBeforeTheReset_data() {
            // The reset is `past` seconds after a ten-minute mark two days
            // out, and the week runs out `before` seconds ahead of it.
            return [{ tag: "rounds up past the reset", past: 420, before: 90, said: 0 },
                    { tag: "rounds up into its last minute", past: 30, before: 70, said: -600 },
                    { tag: "rounds down", past: 420, before: 200, said: 0 },
                    { tag: "rounds up", past: 900, before: 590, said: 600 }];
        }

        function test_runOutBeforeTheReset(data) {
            const usage = monitor.usage;
            const mark = Math.ceil(usage.createdAt / 600) * 600 + 2 * usage.day;
            const weekly = Object.assign(usage.window(50, 0, []), { resetsAt: mark + data.past });
            // At 50 %, polled as long after the week began as the run-out
            // falls before its end.
            const start = weekly.resetsAt - weekly.windowSeconds;
            setClaude({ weekly: weekly, scoped: [], fetchedAt: start + (weekly.windowSeconds - data.before) / 2 });
            const popup = load("claude");
            compare(popup.paces[0].state, "out");
            compare(popup.paces[0].runOut, weekly.resetsAt - data.before);
            const said = mark + data.said;
            verify(said <= weekly.resetsAt - 60);
            compare(sentence(rows(popup)[0]).text, "The weekly limit is on pace to run out " + words.weekdayTime(said, weekly));
        }

        // Ten minutes on the clock the time is shown in: in a zone a quarter
        // hour off the hour, such as Nepal's, a run-out on the UTC grid would
        // always read as five past.
        function test_runOutRoundsOnTheWallClock() {
            const usage = monitor.usage;
            const weekly = usage.window(60, 4 * usage.day, [[3, 0], [0, 60]]);
            const systemOffset = -new Date(weekly.resetsAt * 1000).getTimezoneOffset() * 60;
            const offset = systemOffset === 20700 ? 31500 : 20700;
            weekly.clockZone = { offset: offset, abbreviation: "NPT" };
            setClaude({ weekly: weekly, scoped: [] });
            const popup = load("claude");
            const p = popup.paces[0];
            compare(p.state, "out");
            const said = Math.round((p.runOut + offset) / 600) * 600 - offset;
            compare(sentence(rows(popup)[0]).text, "The weekly limit is on pace to run out " + words.weekdayTime(said, weekly));
        }

        // Only a limit's reading sets its colour, amber from 75 % and red from
        // 90 %: a run-out before the reset leaves the row's percentage and
        // bar and the header's ring at their own level, and says so in the
        // pace sentence alone.
        function test_paceNeverRaisesTheLevel() {
            const red = String(Kirigami.Theme.negativeTextColor);
            const amber = String(Kirigami.Theme.neutralTextColor);
            const plain = String(Kirigami.Theme.textColor);
            let popup = load("claude");
            let [all, fable] = rows(popup);
            compare(popup.paces[1].state, "out", "Fable on course to run out");
            compare(fable.level, 1);
            compare(String(rowText(fable, root.localized("78%")).color), amber);
            compare(String(fill(fable).color), amber);
            compare(all.level, 0);
            compare(String(rowText(all, root.localized("52%")).color), plain);
            compare(String(fill(all).color), plain);
            compare(String(ring(popup).outerTone), plain);

            const usage = monitor.usage;
            setClaude({ weekly: usage.window(39, 5 * usage.day, [[2, 0], [0, 39]]) });
            popup = load("claude");
            [all, fable] = rows(popup);
            compare(popup.paces[0].state, "out", "the week on course to run out at 39 %");
            compare(all.level, 0);
            compare(String(rowText(all, root.localized("39%")).color), plain);
            compare(String(ring(popup).outerTone), plain);

            // 91 % is red, whatever the pace.
            setClaude({ weekly: usage.window(91, 3600, [[6.9, 0], [0, 91]]), scoped: [] });
            popup = load("claude");
            compare(String(ring(popup).outerTone), red);
        }

        function test_signedOut() {
            monitor.usage.entries = { claude: { status: "signed_out" } };
            const shown = root.texts(load("claude"));
            verify(shown.includes("Run claude in a terminal to sign in."), JSON.stringify(shown));
            verify(!shown.includes("All models") && !shown.includes("until reset"), JSON.stringify(shown));
            verify(!shown.some(t => /on pace|run out|by the reset/i.test(t)), JSON.stringify(shown));
            monitor.usage.entries = {};
            monitor.usage.helperError = "python3 was not found on the Plasma session's PATH.";
            verify(root.texts(load("codex")).includes(monitor.usage.helperError));
        }

        // An error is shown as written, never as markup.
        function test_failedPoll() {
            setClaude({ lastError: "<b>HTTP Error 500</b>", lastErrorAt: monitor.usage.createdAt });
            const popup = load("claude");
            const note = root.find(popup, i => typeof i.text === "string" && i.text.startsWith("Last check failed at "));
            verify(note !== null);
            verify(note.text.endsWith(": <b>HTTP Error 500</b>"), note.text);
            compare(note.textFormat, Text.PlainText);
            verify(root.texts(popup).includes(root.localized("52%")), "the last reading stays");
        }

        // The pace is measured to the poll the reading came from, so a
        // reading hours old doesn't understate the rate.
        function test_paceFromThePoll() {
            const usage = monitor.usage;
            setClaude({ fetchedAt: usage.createdAt - 6 * 3600 });
            const popup = load("claude");
            compare(popup.pollAt, usage.createdAt - 6 * 3600);
            verify(graph(popup).stale, "a reading six hours old is marked");
            setClaude({ fetchedAt: undefined });
            compare(popup.pollAt, usage.entries.claude.weekly.history[usage.entries.claude.weekly.history.length - 1][0]);
        }

        // The graph draws the run-out the pace sentence names and no other.
        // With the week and Fable both on course to run out, it is the
        // sooner one the sentence gives; when that is a model limit the
        // graph has no line for, it draws none. Each week began four days
        // and three hours ago.
        function test_graphDrawsTheRunOutSaid_data() {
            return [{ tag: "modelSooner", weekly: 62, scoped: [["Fable", 78]], said: 1, drawn: true },
                    { tag: "weekSooner", weekly: 85, scoped: [["Fable", 60]], said: 0, drawn: true },
                    { tag: "offTheRing", weekly: 30, scoped: [["Fable", 90], ["Opus", 70]], inner: "Opus", said: 1, drawn: false }];
        }

        function test_graphDrawsTheRunOutSaid(data) {
            const usage = monitor.usage;
            const left = 2 * usage.day + 21 * 3600;
            usage.innerChoices = { claude: data.inner ?? "", codex: "" };
            setClaude({ weekly: usage.window(data.weekly, left, [[4.125, 0], [0, data.weekly]]),
                        scoped: data.scoped.map(([id, percent]) => Object.assign({ id: id, label: id },
                                                                                 usage.window(percent, left, [[4.125, 0], [0, percent]]))) });
            const popup = load("claude");
            verify(popup.paces.every(p => p.state === "out" || p.state === "lasts"), JSON.stringify(popup.paces));
            compare(popup.paceEvent.index, data.said);
            verify(sentence(rows(popup)[data.said]).visible);
            const g = graph(popup);
            const red = String(Kirigami.Theme.negativeTextColor);
            const ends = g.children.filter(i => i.visible && i.radius > 0 && String(i.color) === red);
            if (!data.drawn) {
                compare(ends.length, 0, "no run-out drawn");
                return;
            }
            compare(ends.length, 1, "one run-out drawn");
            fuzzyCompare(ends[0].x + ends[0].width / 2, g.xAt(popup.paces[data.said].runOut), 1e-6);
        }

        function test_emptyHistory() {
            const usage = monitor.usage;
            setClaude({ weekly: usage.window(0, 6 * usage.day, []), scoped: [] });
            const g = graph(load("claude"));
            verify(g.placed);
            compare(g.mainPoints.length, 0);
            verify(!g.stale);
            compare(g.projection.length, 0);
        }

        function test_fullWeek() {
            const usage = monitor.usage;
            const history = [];
            for (let days = 6.95; days >= 0; days -= 0.25) {
                history.push([days, Math.round((7 - days) / 7 * 88)]);
            }
            setClaude({ weekly: usage.window(88, 3600, history), scoped: [] });
            const popup = load("claude");
            const g = graph(popup);
            compare(g.mainPoints.length, history.length);
            verify(g.mainPoints[0].x >= 0 && g.mainPoints[g.mainPoints.length - 1].x <= g.width);
            compare(countdown(popup).map(r => r.value + r.unit), ["1h", "0m"].map(root.localized));
        }
    }

    Words {
        id: words
        monitor: null
    }

    // Expectations follow the running locale's digits and names, so these
    // pass under any locale.
    TestCase {
        name: "UsageWords"

        readonly property real nowMs: 1000000 * 1000
        // 11:00 UTC on Sunday 27 September 2026: 7:00 AM in New York.
        readonly property real sunday: Date.UTC(2026, 8, 27, 11, 0, 0) / 1000

        function local(text) {
            const zero = Qt.locale().zeroDigit.codePointAt(0);
            return text.replace(/[0-9]/g, c => String.fromCodePoint(zero + Number(c)));
        }

        function test_countdown_data() {
            return [
                { tag: "days", left: 2 * 86400 + 21 * 3600 + 12 * 60, expected: "2d 21h" },
                { tag: "hours", left: 5 * 3600 + 12 * 60, expected: "5h 12m" },
                { tag: "minutes", left: 12 * 60, expected: "12m" },
                { tag: "passed", left: -60, expected: "" }
            ];
        }
        function test_countdown(data) {
            compare(words.countdown(nowMs / 1000 + data.left, nowMs), local(data.expected));
        }

        function test_countdownParts_data() {
            return [
                { tag: "days", left: 5 * 86400 + 18 * 3600 + 7 * 60, expected: [["5", "d"], ["18", "h"]] },
                { tag: "daysLeadingOnly", left: 5 * 86400 + 18 * 3600 + 7 * 60, leadingOnly: true, expected: [["5", "d"]] },
                { tag: "oneDayLeadingOnly", left: 86400 + 30 * 60, leadingOnly: true, expected: [["1", "d"]] },
                { tag: "lastDayLeadingOnly", left: 23 * 3600 + 5 * 60, leadingOnly: true, expected: [["23", "h"]] },
                { tag: "hours", left: 5 * 3600 + 12 * 60, expected: [["5", "h"], ["12", "m"]] },
                { tag: "hoursLeadingOnly", left: 3600 + 2 * 60, leadingOnly: true, expected: [["1", "h"]] },
                { tag: "minutes", left: 12 * 60, leadingOnly: true, expected: [["12", "m"]] },
                { tag: "lastMinutesLeadingOnly", left: 59 * 60, leadingOnly: true, expected: [["59", "m"]] },
                { tag: "passedLeadingOnly", left: -60, leadingOnly: true, expected: [] },
                { tag: "passed", left: -60, expected: [] },
                { tag: "noReset", left: NaN, expected: [] }
            ];
        }
        function test_countdownParts(data) {
            const parts = words.countdownParts(nowMs / 1000 + data.left, nowMs, data.leadingOnly ?? false);
            compare(parts.length, data.expected.length);
            data.expected.forEach((pair, i) => {
                compare(parts[i].value, local(pair[0]), data.tag + " " + i);
                compare(parts[i].unit, pair[1], data.tag + " " + i);
            });
            // countdown() spells out the same parts.
            if (!data.leadingOnly) {
                compare(words.countdown(nowMs / 1000 + data.left, nowMs), parts.map(p => p.value + p.unit).join(" "));
            }
        }

        function test_weekdayTime() {
            const locale = Qt.locale();
            const spelled = date => locale.dayName(date.getDay(), Locale.ShortFormat) + " " + words.shortTime(date);
            // 7:30 UTC on Friday 25 September 2026, two days before the reset.
            const friday = Date.UTC(2026, 8, 25, 7, 30) / 1000;
            const systemOffset = -new Date(sunday * 1000).getTimezoneOffset() * 60;

            // A clock zone three hours east of UTC, or five when that is
            // system time, reads as its own wall clock and names no zone.
            const east = systemOffset === 3 * 3600 ? 5 : 3;
            const elsewhere = { resetsAt: sunday, clockZone: { offset: east * 3600, abbreviation: "XYZ" } };
            compare(words.weekdayTime(friday, elsewhere), spelled(new Date(2026, 8, 25, 7 + east, 30)));

            // A clock zone that matches system time at the reset, and no zone
            // at all, read in system time.
            const here = { resetsAt: sunday, clockZone: { offset: systemOffset, abbreviation: "XYZ" } };
            compare(words.weekdayTime(friday, here), spelled(new Date(friday * 1000)));
            compare(words.weekdayTime(friday, { resetsAt: sunday }), spelled(new Date(friday * 1000)));
            compare(words.weekdayTime(friday, null), spelled(new Date(friday * 1000)));

            compare(words.weekdayTime(NaN, elsewhere), "");
        }

        function test_duration_data() {
            return [
                { tag: "daysAndHours", left: 2 * 86400 + 21 * 3600, expected: "2 days 21 hours" },
                { tag: "oneDay", left: 86400 + 20 * 60, expected: "1 day" },
                { tag: "hoursAndMinutes", left: 3600 + 5 * 60, expected: "1 hour 5 minutes" },
                { tag: "minutes", left: 60, expected: "1 minute" }
            ];
        }
        function test_duration(data) {
            compare(words.duration(nowMs / 1000 + data.left, nowMs), data.expected);
        }

        function test_resetDateInTheClockZone() {
            const time = words.shortTime(new Date(2026, 8, 27, 7, 0));
            compare(words.resetDate({ resetsAt: sunday, clockZone: { offset: -4 * 3600, abbreviation: "EDT" } }),
                    Qt.locale().dayName(0, Locale.ShortFormat) + " " + time + " EDT");
            // Claude reports its reset a second before the hour.
            compare(words.resetDate({ resetsAt: sunday - 1, clockZone: { offset: -4 * 3600, abbreviation: "EDT" } }),
                    Qt.locale().dayName(0, Locale.ShortFormat) + " " + time + " EDT");
        }

        function test_resetDateInSystemTime() {
            const date = new Date(sunday * 1000);
            compare(words.resetDate({ resetsAt: sunday }),
                    Qt.locale().dayName(date.getDay(), Locale.ShortFormat) + " " + words.shortTime(date));
            compare(words.resetDate({ resetsAt: null }), "");
        }

        function test_timeOfDay() {
            const noon = new Date(2026, 8, 27, 12, 0).getTime();
            const earlier = new Date(2026, 8, 27, 9, 15);
            compare(words.timeOfDay(earlier.getTime() / 1000, noon), words.shortTime(earlier));
            const yesterday = new Date(2026, 8, 26, 9, 15);
            const shortDate = yesterday.toLocaleDateString(Qt.locale(), Locale.ShortFormat);
            verify(words.timeOfDay(yesterday.getTime() / 1000, noon).includes(shortDate), "another day gives the date");
        }

        // Times read to the minute in every locale, as they are rounded to
        // it or coarser: Qt 6.6's C locale gives its short time with seconds,
        // which the floor's tests run in. Where the locale's short time has
        // no seconds, it is the one shown.
        function test_timesHaveNoSeconds() {
            const digits = new RegExp("[0-9" + [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map(d => Format.whole(d)).join("") + "]+", "g");
            const numbers = text => (text.match(digits) ?? []).length;
            const at = new Date(2026, 8, 27, 9, 15, 42);
            const epoch = at.getTime() / 1000;
            compare(numbers(words.resetDate({ resetsAt: epoch })), 2, words.resetDate({ resetsAt: epoch }));
            compare(numbers(words.weekdayTime(epoch, null)), 2, words.weekdayTime(epoch, null));
            compare(numbers(words.timeOfDay(epoch, at.getTime())), 2, words.timeOfDay(epoch, at.getTime()));
            const nextDay = new Date(2026, 8, 28, 12, 0).getTime();
            verify(!words.timeOfDay(epoch, nextDay).includes(Format.whole(42)), words.timeOfDay(epoch, nextDay));
            const locale = Qt.locale();
            if (!/s/.test(locale.timeFormat(Locale.ShortFormat))) {
                compare(words.shortTime(at), at.toLocaleTimeString(locale, Locale.ShortFormat));
            }
        }
    }

    // The short readings by a ring, for every item, from FakeMonitor's
    // readings or the ones a row sets. Expectations follow the running
    // locale's digits, as in UsageWords.
    TestCase {
        id: readouts
        name: "Readout"

        property var monitor: null

        Words {
            id: readoutWords
            monitor: readouts.monitor
        }

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            monitor = createTemporaryObject(monitorComponent, readouts);
        }

        function local(text) {
            const zero = Qt.locale().zeroDigit.codePointAt(0);
            return text.replace(/[0-9]/g, c => String.fromCodePoint(zero + Number(c))).replace(".", Qt.locale().decimalPoint);
        }

        function apply(target, values) {
            for (const key in values) {
                target[key] = values[key];
            }
        }

        // `set`, `outer` and `inner` override the monitor's and its GPUs'
        // readings; `weekly` is [percent, seconds left] for the row's item.
        function test_readout_data() {
            return [
                { tag: "cpu", item: "cpu", first: "23%", second: "61°" },
                { tag: "cpu warm", item: "cpu", set: { cpuUsage: 75, cpuTemperature: 75 },
                  first: "75%", level: 1, second: "75°", heat: 1 },
                { tag: "cpu hot", item: "cpu", set: { cpuUsage: 90, cpuTemperature: 90 },
                  first: "90%", level: 2, second: "90°", heat: 2 },
                { tag: "cpu in fahrenheit", item: "cpu", set: { fahrenheit: true }, first: "23%", second: "142°" },
                { tag: "cpu unread", item: "cpu", set: { cpuUsage: NaN, cpuTemperature: NaN }, first: "–", second: "–" },
                // The integrated GPU's temperature stays in the tooltip.
                { tag: "two gpus", item: "gpu", first: "12%", second: "48°" },
                { tag: "gpu hot", item: "gpu", outer: { usage: 95, temperature: 92 },
                  first: "95%", level: 2, second: "92°", heat: 2 },
                { tag: "gpu resting", item: "gpu", outer: { phase: "resting" }, inner: { present: false },
                  first: "0%", second: "48°" },
                { tag: "intel gpu", item: "gpu", outer: { reportsTemperature: false }, inner: { present: false },
                  first: "12%", second: "" },
                { tag: "integrated gpu awake alone", item: "gpu", outer: { phase: "asleep" }, first: "3%", second: "41°" },
                { tag: "only gpu asleep", item: "gpu", outer: { phase: "asleep" }, inner: { present: false },
                  first: "off", off: true, second: "" },
                { tag: "both gpus asleep", item: "gpu", outer: { phase: "asleep" }, inner: { phase: "asleep" },
                  first: "off", off: true, second: "" },
                { tag: "memory", item: "memory", first: "42%", second: "13.4G" },
                { tag: "memory in MiB", item: "memory", set: { memoryUsed: 900 * 1048576 }, first: "3%", second: "900M" },
                { tag: "memory full", item: "memory", set: { memoryUsed: 29 * 1073741824 },
                  first: "91%", level: 2, second: "29.0G" },
                { tag: "memory unread", item: "memory", set: { memoryUsed: NaN }, first: "–", second: "–" },
                { tag: "claude", item: "claude", first: "52%", second: "2d" },
                { tag: "codex", item: "codex", first: "24%", second: "5d" },
                { tag: "claude a day out", item: "claude", weekly: [40, 86400 + 30 * 60], first: "40%", second: "1d" },
                { tag: "claude last day", item: "claude", weekly: [40, 23 * 3600 + 5 * 60], first: "40%", second: "23h" },
                { tag: "claude at its limit", item: "claude", weekly: [90, 3600], first: "90%", level: 2, second: "1h" },
                { tag: "claude last hour", item: "claude", weekly: [40, 59 * 60], first: "40%", second: "59m" },
                { tag: "claude amber", item: "claude", weekly: [75, 12 * 60], first: "75%", level: 1, second: "12m" },
                { tag: "claude used up", item: "claude", weekly: [100, 2 * 86400], first: "100%", level: 2, second: "2d", heat: 2 },
                { tag: "used up, reset passed", item: "claude", weekly: [100, -600], first: "100%", level: 2, second: "–" },
                { tag: "reset passed", item: "claude", weekly: [40, -600], first: "40%", second: "–" },
                // On pace to run out before the reset, the percentage keeps
                // its own reading's colour.
                { tag: "claude runs out", item: "claude", weekly: [70, 3 * 86400], first: "70%", second: "3d" },
                { tag: "claude runaway first day", item: "claude", weekly: [70, 6 * 86400 + 6 * 3600], first: "70%", second: "6d" },
                { tag: "claude quiet first day", item: "claude", weekly: [5, 6 * 86400 + 21 * 3600], first: "5%", second: "6d" },
                { tag: "runs out, reset passed", item: "claude", weekly: [70, -600], first: "70%", second: "–" },
                { tag: "signed out", item: "claude", entries: { claude: { status: "signed_out" } }, first: "–", second: "–" },
                { tag: "not checked yet", item: "codex", entries: {}, first: "–", second: "–" }
            ];
        }

        // Readout reads a missing level or heat as none, and only a true
        // `off` as asleep. A countdown keeps to its largest unit.
        function test_readout(data) {
            const usage = monitor.usage;
            apply(monitor, data.set ?? {});
            apply(monitor.gpuOuter, data.outer ?? {});
            apply(monitor.gpuInner, data.inner ?? {});
            if (data.entries !== undefined) {
                usage.entries = data.entries;
            }
            if (data.weekly !== undefined) {
                usage.entries = { [data.item]: { status: "ok", fetchedAt: usage.createdAt,
                                                 weekly: usage.window(data.weekly[0], data.weekly[1], []), scoped: [] } };
            }
            const r = readoutWords.readout(data.item, usage.createdAt * 1000);
            compare({ first: r.first, level: r.level ?? 0, off: r.off === true, second: r.second, heat: r.heat ?? 0 },
                    { first: local(data.first), level: data.level ?? 0, off: data.off ?? false,
                      second: local(data.second), heat: data.heat ?? 0 });
        }
    }

    TestCase {
        name: "WeekGraph"
        when: windowShown

        readonly property real start: 1000000
        readonly property real day: 86400
        readonly property real week: 7 * day

        Component {
            id: mirroredGraph
            Item {
                width: 700
                height: 100
                LayoutMirroring.enabled: true
                LayoutMirroring.childrenInherit: true
                WeekGraph {
                    anchors.fill: parent
                }
            }
        }

        // A week from `start` read at `at` (epoch seconds) with `percent`
        // and `history`, seen at `now`, drawing the run-out of the series
        // `projected` names.
        function make(history, options) {
            const o = options ?? {};
            return createTemporaryObject(graphComponent, root, {
                window: { resetsAt: start + week, windowSeconds: week, percent: o.percent ?? NaN, history: history },
                projected: o.projected ?? "",
                pollAt: o.at ?? NaN,
                nowMs: (o.now ?? o.at ?? start + day) * 1000
            });
        }

        function rule(g) {
            return root.find(g, i => i.limitY !== undefined);
        }

        // Where a percentage lands: 100 % on the rule, 0 % half a stroke
        // above the bottom.
        function yOf(g, percent) {
            const top = rule(g).limitY;
            return top + (1 - percent / 100) * (g.height - 0.75 - top);
        }

        // The graph's own Rectangles, outside the rule.
        function rectangles(g) {
            return g.children.filter(i => i.radius !== undefined && i.visible);
        }

        function test_pointsSpanTheWindow() {
            const g = make([[start - 10, 5], [start, 0], [start + week / 2, 50], [start + week, 100], [start + week + 10, 7]]);
            compare(g.mainPoints.map(p => p.x), [0, 350, 700]);
            fuzzyCompare(g.mainPoints[0].y, g.height - 0.75, 1e-9);
            fuzzyCompare(g.mainPoints[1].y, yOf(g, 50), 1e-9);
            fuzzyCompare(g.mainPoints[2].y, rule(g).limitY, 1e-9);
            verify(rule(g).limitY >= Kirigami.Units.smallSpacing, "100 % is on the rule, under its label's room");
        }

        function test_secondSeriesSharesTheAxis() {
            const g = make([]);
            g.secondWindow = { resetsAt: start + 3 * day, windowSeconds: week, history: [[start + day, 20]] };
            compare(g.secondPoints.length, 1);
            compare(g.secondPoints[0].x, 100);
            fuzzyCompare(g.secondPoints[0].y, yOf(g, 20), 1e-9);
        }

        function test_noResetTimeDrawsNothing() {
            const g = make([[start, 10]]);
            g.window = { resetsAt: null, windowSeconds: week, history: [[start, 10]] };
            verify(!g.placed);
            compare(g.mainPoints.length, 0);
            verify(!rule(g).visible);
            // The dot of the reading that was there fades out.
            tryVerify(() => rectangles(g).length === 0, 1000, "no floor, tick, marker or dot");
        }

        // A faint floor across the whole width and a short tick at the
        // reset, in the rule's colour.
        function test_baselineAndResetTick() {
            const g = make([[start, 0], [start + day, 9]], { percent: 9, at: start + day });
            const r = rule(g);
            const floor = rectangles(g).find(i => i.height === 1);
            verify(floor);
            compare(floor.x, 0);
            compare(floor.y, g.height - 1);
            compare(floor.width, g.width);
            compare(String(floor.color), String(r.lineColor));
            const tick = rectangles(g).find(i => i.width === 1 && i.height > 1);
            verify(tick);
            compare(tick.x, g.width - 1);
            compare(tick.y + tick.height, g.height);
            verify(tick.height <= Kirigami.Units.smallSpacing + 1, tick.height);
            compare(String(tick.color), String(r.lineColor));
        }

        // Round dots from the last point to 100 % at the run-out, ending in a
        // dot on the rule, only for a limit on course to run out before the
        // reset, in the red of a limit running out: a projection, not more
        // readings. It joins the rule's series, so the "100%" label keeps
        // clear of it.
        function test_projectionOnlyWhenOut_data() {
            return [
                { tag: "out", percent: 60, at: start + 3 * day, runOut: start + 5 * day },
                { tag: "lasts", percent: 30, at: start + 3 * day },
                { tag: "reached", percent: 100, at: start + 3 * day },
                { tag: "tooEarlyToTell", percent: 5, at: start + 3 * 3600 },
                { tag: "resetPassed", percent: 60, at: start + 3 * day, now: start + week + 60 }
            ];
        }

        // The run-outs' Shape and its one path.
        function runOutPath(g) {
            const shape = g.children.find(i => i.data !== undefined
                && Array.from(i.data).some(p => p.capStyle === ShapePath.RoundCap));
            return shape ? { shape: shape, path: Array.from(shape.data).find(p => p.capStyle !== undefined) } : null;
        }

        // A run-out's end: a dot centred on 100 % where it runs out.
        function endDot(g, end) {
            return rectangles(g).find(i => i.radius > 0 && Math.abs(i.x + i.width / 2 - end.x) < 1e-9
                                         && Math.abs(i.y + i.height / 2 - end.y) < 1e-9);
        }

        function test_projectionOnlyWhenOut(data) {
            const g = make([[start, 0], [data.at, data.percent]], Object.assign({ projected: "main" }, data));
            const dotted = runOutPath(g);
            verify(dotted);
            const red = String(Kirigami.Theme.negativeTextColor);
            compare(String(dotted.path.strokeColor), red);
            compare(dotted.path.strokeStyle, ShapePath.DashLine);
            verify(dotted.path.dashPattern[0] < 0.1 && dotted.path.dashPattern[1] >= 2.5,
                   "round caps on dashes this short are dots, apart: " + dotted.path.dashPattern);
            if (data.runOut === undefined) {
                compare(g.projection.length, 0);
                verify(!dotted.shape.visible);
                verify(!rectangles(g).some(i => i.radius > 0), "no end dot");
                return;
            }
            verify(dotted.shape.visible);
            const end = endDot(g, g.projection[1]);
            verify(end, "a dot where it runs out");
            compare(String(end.color), red);
            compare(g.projection.length, 2);
            const last = g.mainPoints[g.mainPoints.length - 1];
            compare([g.projection[0].x, g.projection[0].y], [last.x, last.y]);
            fuzzyCompare(g.projection[1].x, (data.runOut - start) / week * g.width, 1e-9);
            fuzzyCompare(g.projection[1].y, rule(g).limitY, 1e-9);
            verify(rule(g).series.some(s => s.length === 2 && s[1].x === g.projection[1].x && s[1].y === g.projection[1].y),
                   "the run-out is among the rule's series");
        }

        // With both limits on course to run out, only the named one's run-out
        // is drawn, from its own line; naming neither draws none.
        function test_onlyTheNamedRunOut_data() {
            return [{ tag: "main", runOut: start + 3 * day * 100 / 60 },
                    { tag: "second", runOut: start + 3 * day * 100 / 70 },
                    { tag: "none" }];
        }

        function test_onlyTheNamedRunOut(data) {
            const at = start + 3 * day;
            const g = make([[start, 0], [at, 60]], { percent: 60, at: at, projected: data.runOut ? data.tag : "" });
            g.secondWindow = { resetsAt: start + week, windowSeconds: week, percent: 70, history: [[start, 0], [at, 70]] };
            // A run-out the model's window brings fades in.
            tryCompare(g, "runOutOpacity", data.runOut === undefined ? 0 : 1, 1000);
            const ends = rectangles(g).filter(i => i.radius > 0);
            if (data.runOut === undefined) {
                compare(g.projection.length, 0);
                verify(!runOutPath(g).shape.visible);
                compare(ends.length, 0, "no end dot");
                return;
            }
            const series = data.tag === "main" ? g.mainPoints : g.secondPoints;
            const last = series[series.length - 1];
            compare(g.projection.length, 2);
            compare([g.projection[0].x, g.projection[0].y], [last.x, last.y]);
            fuzzyCompare(g.projection[1].x, (data.runOut - start) / week * g.width, 1e-9);
            verify(runOutPath(g).shape.visible);
            compare(ends.length, 1, "one end dot");
            verify(endDot(g, g.projection[1]), "where the named limit runs out");
        }

        // The label sits at the right end, where the week is still to come,
        // and moves left when a run-out ends under it there.
        function test_labelAvoidsTheRunOut() {
            const at = start + 3 * day;
            const lasting = make([[start, 0], [at, 40]], { percent: 40, at: at });
            verify(!rule(lasting).atStart);
            const late = 3 * day * 100 / (week - 2 * 3600);
            const running = make([[start, 0], [at, late]], { percent: late, at: at, projected: "main" });
            compare(running.projection.length, 2);
            verify(rule(running).atStart);
        }

        function test_singleReadingIsADot() {
            const g = make([[start + day, 20]], { percent: 20, at: start + day });
            compare(g.mainPoints.length, 1);
            const dot = rectangles(g).find(i => i.radius > 0);
            verify(dot);
            const p = g.mainPoints[0];
            fuzzyCompare(dot.x + dot.width / 2, p.x, 1e-9);
            fuzzyCompare(dot.y + dot.height / 2, p.y, 1e-9);
            // A week that lasts, so no run-out ends in a dot either.
            const line = make([[start, 0], [start + day, 10]], { percent: 10, at: start + day, projected: "second" });
            verify(!rectangles(line).some(i => i.radius > 0), "a line has no dot");

            // The same for the model's limit, in its dashed line's colour.
            line.secondWindow = { resetsAt: start + week, windowSeconds: week, percent: 10, history: [[start + day, 10]] };
            compare(line.projection.length, 0);
            compare(line.secondPoints.length, 1);
            tryVerify(() => rectangles(line).some(i => i.radius > 0 && i.opacity === 1), 1000, "the model's single reading is a dot");
            const second = rectangles(line).find(i => i.radius > 0);
            const q = line.secondPoints[0];
            fuzzyCompare(second.x + second.width / 2, q.x, 1e-9);
            fuzzyCompare(second.y + second.height / 2, q.y, 1e-9);
            fuzzyCompare(second.color.a, 0.55 * line.color.a, 0.01);
        }

        // Within two hours the line's end shows now; past that a marker does.
        // Once the reset has passed with an old reading, the marker stays
        // inside the graph at its end.
        function test_staleMarker_data() {
            return [{ tag: "fresh", now: start + 3 * day, age: 1.5 * 3600, stale: false },
                    { tag: "stale", now: start + 3 * day, age: 2.5 * 3600, stale: true, x: g => Math.round(3 * day / week * g.width) },
                    { tag: "pastReset", now: start + week + 3 * 3600, age: 6 * 3600, stale: true, x: g => g.width - 1 }];
        }

        function test_staleMarker(data) {
            const now = data.now;
            const g = make([[start, 0], [now - data.age, 20]], { percent: 20, at: now - data.age, now: now });
            compare(g.stale, data.stale);
            const marker = rectangles(g).find(i => i.width === 1 && i.y === rule(g).ruleY);
            compare(marker !== undefined, data.stale);
            if (data.stale) {
                compare(marker.x, data.x(g));
                compare(marker.y + marker.height, g.height);
            }
            verify(!make([], { percent: 0, at: now - data.age, now: now }).stale, "no line, nothing to mark");
        }

        // Late in the week the marker for now falls where the "100%" label
        // sits, at the right end; the label moves to the start rather than
        // have the line run through its digits.
        function test_labelAvoidsTheStaleMarker() {
            const now = start + week - 5 * 3600;
            const fresh = make([[start, 0], [now - 3600, 40]], { percent: 40, at: now - 3600, now: now });
            verify(!rule(fresh).atStart, "a fresh reading leaves the label at the end");
            const old = make([[start, 0], [now - 6 * 3600, 40]], { percent: 40, at: now - 6 * 3600, now: now });
            verify(old.stale);
            const marker = rectangles(old).find(i => i.width === 1 && i.y === rule(old).ruleY);
            verify(marker.x > old.width - rule(old).span, "the marker is under the label's place at the end");
            verify(rule(old).atStart, "the label moves to the start");
        }

        // Time runs left to right in every language.
        function test_noMirroring() {
            const host = createTemporaryObject(mirroredGraph, root);
            const g = host.children[0];
            g.window = { resetsAt: start + week, windowSeconds: week, percent: 50,
                         history: [[start, 0], [start + week / 2, 50]] };
            verify(!g.LayoutMirroring.enabled);
            compare(g.mainPoints[0].x, 0);
            const label = root.find(rule(g), i => i.text === root.localized("100%"));
            compare(label.x, g.width - label.implicitWidth);
        }
    }
}
