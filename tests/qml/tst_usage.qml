// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/popups"
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

        function test_markFailedDimsOnlyShownEntries() {
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
            compare(usage.entry("claude").weekly.percent, 62);
            compare(usage.entry("codex").weekly.percent, 34);
            verify(usage.claudePresent && usage.codexPresent);
            verify(!usage.degraded("claude") && !usage.degraded("codex"));
            compare(usage.inner("claude").id, "Opus");
            compare(usage.inner("codex"), null);
            compare(usage.helperError, "");
            compare(JSON.parse(config.knownLimits),
                    { claude: [{ id: "Opus", label: "Opus", reported: true }], codex: [] });
            compare(JSON.parse(config.usageStatus), { claude: { status: "ok", message: "" },
                                                      codex: { status: "ok", message: "" }, helperError: "" });
        }

        function test_innerFollowsTheChoice() {
            start("ok");
            config.claudeInnerLimit = "none";
            compare(usage.inner("claude"), null);
            config.claudeInnerLimit = "Opus";
            compare(usage.inner("claude").percent, 78);
            config.claudeInnerLimit = "Sonnet";
            compare(usage.inner("claude"), null, "a picked limit that isn't reported shows none");
        }

        function test_failedPollKeepsTheLastReading() {
            start("ok");
            poll("failed");
            compare(usage.entry("claude").weekly.percent, 62);
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
            compare(usage.entry("claude").weekly.percent, 62, "the last reading stays");
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
            compare(JSON.parse(config.knownLimits).claude.map(l => l.id), ["Opus", "Sonnet"]);
        }

        function test_resetsArriveBeforeTheReadings() {
            start("ok");
            const seen = [];
            const listener = events => seen.push({ events: events, percent: usage.entry("claude").weekly.percent });
            usage.resetsDetected.connect(listener);
            poll("reset");
            usage.resetsDetected.disconnect(listener);
            compare(seen.length, 1);
            compare(seen[0].percent, 62, "sent while the old reading is still there");
            compare(seen[0].events, { "claude.weekly": { from: 62, early: true },
                                      "claude.scoped.Opus": { from: 78, early: true } });
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
            return root.find(cell.children[0], i => i.isMask !== undefined);
        }

        // Claude at `percent` with no model limit, resetting in `left` seconds.
        function claudeAt(percent, left) {
            const usage = monitor.usage;
            usage.entries = { claude: { status: "ok", fetchedAt: usage.createdAt,
                                        weekly: usage.window(percent, left ?? 2 * usage.day, []), scoped: [] } };
        }

        function test_texts_data() {
            return [{ tag: "claude", percent: "62%", left: "2d 21h", mark: "/icons/claude.svg" },
                    { tag: "codex", percent: "34%", left: "5d 4h", mark: "/icons/openai.svg" }];
        }

        // The mark names the item in the ring, and the percentage moves out
        // of it to stand over the time to the reset.
        function test_texts(data) {
            const c = cell(data.tag);
            const gauge = c.children[0];
            compare(root.texts(c), [data.percent, data.left]);
            compare(line(c, "first").text, data.percent);
            compare(line(c, "second").text, data.left);
            verify(line(c, "second").y >= line(c, "first").y + line(c, "first").height, "the time sits under the percentage");
            compare(gauge.text, "", "no percentage inside the ring");
            const m = mark(c);
            verify(m.visible, "the mark shows");
            verify(m.source.toString().endsWith(data.mark), m.source);
            verify(m.width > 0 && m.width <= gauge.centreWidth, m.width + " in " + gauge.centreWidth);
        }

        // A thin panel puts the readings on one line and leaves the ring
        // unnamed; with the text off, the ring keeps its mark alone.
        function test_oneLineAndRingOnly() {
            const thin = cell("claude", { twoLines: false });
            compare(root.texts(thin), ["62%", "·", "2d 21h"]);
            compare(line(thin, "second").y, line(thin, "first").y, "one line");
            verify(line(thin, "second").x > line(thin, "first").x);
            verify(!mark(thin).visible, "no mark beside one line");
            const bare = cell("claude", { textShown: false });
            compare(root.texts(bare), []);
            compare(bare.implicitWidth, 34, "the ring alone");
            verify(mark(bare).visible, "the ring keeps its mark");
            verify(bare.accessibleDescription !== "", "the tooltip still has the words");
        }

        function test_widthHoldsAsTheCountdownRuns_data() {
            return [{ tag: "two lines", twoLines: true }, { tag: "one line", twoLines: false }];
        }

        function test_widthHoldsAsTheCountdownRuns(data) {
            claudeAt(40, 6 * 86400 + 23 * 3600);
            const c = cell("claude", { twoLines: data.twoLines });
            const width = c.implicitWidth;
            for (const percent of [5, 100, NaN]) {
                for (const left of [23 * 3600 + 59 * 60, 10 * 3600 + 10 * 60, 5 * 60, 30, -600]) {
                    claudeAt(percent, left);
                    waitForRendering(c);
                    compare(c.implicitWidth, width, percent + "% with " + left + " s left");
                    for (const name of ["first", "second"]) {
                        verify(line(c, name).contentWidth <= line(c, name).width,
                               line(c, name).text + " overflows its room at " + percent + "% with " + left + " s left");
                    }
                }
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
            claudeAt(data.percent);
            const c = cell("claude");
            const expected = data.tone === "negative" ? Kirigami.Theme.negativeTextColor
                           : data.tone === "neutral" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
            compare(c.children[0].outerTone, expected);
            compare(line(c, "first").color, c.children[0].outerTone, "the percentage follows the ring");
            // Text keeps 8-bit colours, so they compare as drawn.
            compare(String(line(c, "second").color), String(Style.dim(Kirigami.Theme.textColor)), "the time stays dim");
        }

        function test_pulse_data() {
            return [{ tag: "89", percent: 89, pulsing: false }, { tag: "90", percent: 90, pulsing: true },
                    { tag: "99", percent: 99, pulsing: true }, { tag: "100", percent: 100, pulsing: false }];
        }

        function test_pulse(data) {
            claudeAt(data.percent);
            compare(cell("claude").children[0].pulsing, data.pulsing);
        }

        function test_degradedDims() {
            const c = cell("claude");
            compare(c.opacity, 1);
            const entries = monitor.usage.entries;
            monitor.usage.entries = Object.assign({}, entries, {
                claude: Object.assign({}, entries.claude, { lastError: "HTTP Error 500", lastErrorAt: monitor.usage.createdAt })
            });
            compare(c.opacity, 0.55);
            verify(c.accessibleDescription.indexOf(". Last check failed at ") > 0, c.accessibleDescription);
        }

        function test_descriptions() {
            compare(cell("claude").accessibleDescription, "62% used, Opus 78%, resets in 2 days 21 hours");
            compare(cell("codex").accessibleDescription, "34% used, resets in 5 days 4 hours");
            monitor.usage.innerChoices = { claude: "none", codex: "" };
            compare(cell("claude").accessibleDescription, "62% used, resets in 2 days 21 hours");
            claudeAt(40, 3600);
            compare(cell("claude").accessibleDescription, "40% used, resets in 1 hour");
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
                                           "claude.scoped.Opus": { from: 95, early: true } });
            compare(arcs(claude).map(a => a.animating), [true, true]);
            verify(arcs(codex).every(a => !a.animating));
            tryVerify(() => arcs(claude).every(a => !a.animating), 5000);

            monitor.usage.innerChoices = { claude: "none", codex: "" };
            monitor.usage.resetsDetected({ "claude.scoped.Opus": { from: 95, early: false } });
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
            compare(claude.innerLimit.id, "Opus", "The only limit shows by default");
            compare(claude.children[0].inner, true);
            compare(claude.children[0].innerValue, 78);
            compare(root.texts(claude), ["62%", "2d 21h"]);
            compare(codex.innerLimit, null, "No scoped limit, no inner ring");
            compare(codex.children[0].inner, false);
            compare(root.texts(codex), ["34%", "5d 4h"]);

            setEntry("codex", { status: "ok", weekly: { percent: 34 },
                                scoped: [{ id: "codex_spark", label: "GPT-5.3-Codex-Spark", percent: 5 }] });
            compare(codex.innerLimit.id, "codex_spark", "A new limit is picked up");
            compare(codex.children[0].inner, true);
            compare(codex.children[0].innerValue, 5);
            compare(root.texts(codex), ["34%", "–"]);

            const fable = { id: "Fable", label: "Fable", percent: 78 };
            const opus = { id: "Opus", label: "Opus", percent: 9 };
            setEntry("claude", { status: "ok", weekly: { percent: 62 }, scoped: [fable, opus] });
            compare(claude.innerLimit, null, "Several and none picked: all models only");
            compare(claude.children[0].inner, false);
            compare(root.texts(claude), ["62%", "–"]);
            monitor.usage.innerChoices = { claude: "Opus", codex: "" };
            compare(claude.innerLimit.id, "Opus");
            compare(claude.children[0].inner, true);
            compare(claude.children[0].innerValue, 9);
            compare(root.texts(claude), ["62%", "–"]);
            monitor.usage.innerChoices = { claude: "none", codex: "" };
            compare(claude.innerLimit, null);
            compare(claude.children[0].inner, false);
            compare(root.texts(claude), ["62%", "–"]);
            monitor.usage.innerChoices = { claude: "Opus", codex: "" };
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
            const opus = { id: "Opus", label: "Opus", percent: 9 };
            setEntry("claude", { status: "ok", weekly: { percent: 62 }, scoped: [fable, opus] });
            monitor.usage.innerChoices = { claude: "Fable", codex: "" };
            const claude = cell("claude");
            const codex = cell("codex");
            const inner = innerArc(claude);
            monitor.usage.resetsDetected({ "claude.scoped.Opus": { from: 92, early: true } });
            compare(inner.animating, false, "A limit that is not shown plays nothing");
            monitor.usage.resetsDetected({ "claude.scoped.Fable": { from: 92, early: true } });
            verify(inner.animating, "The shown limit plays its reset");
            tryCompare(inner, "animating", false);
            // Events are handed over once, so changing the pick replays nothing.
            monitor.usage.innerChoices = { claude: "Opus", codex: "" };
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

        function load(item) {
            const loader = host.createObject(root) as Loader;
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

        function setClaude(changes) {
            const entries = monitor.usage.entries;
            monitor.usage.entries = Object.assign({}, entries, { claude: Object.assign({}, entries.claude, changes) });
        }

        function test_innerLimit() {
            const popup = load("claude");
            const shown = root.texts(popup);
            for (const text of ["Claude", "Weekly limits", "2d 21h", "until reset", "All models", "Opus", "62%", "78%",
                                "— All models", "- - Opus"]) {
                verify(shown.includes(text), text + " in " + JSON.stringify(shown));
            }
            verify(shown.some(t => /^THIS WEEK · resets .+ EDT$/.test(t)), JSON.stringify(shown));
            verify(!shown.some(t => t.startsWith("resets in")), "Opus resets with the week");
            verify(!shown.includes("Open System Monitor"), "the footer has the gear alone");
            compare(graph(popup).mainPoints.length, 17);
            compare(graph(popup).secondPoints.length, 17);
        }

        function test_codex() {
            const shown = root.texts(load("codex"));
            verify(shown.includes("Codex") && shown.includes("Weekly limits") && shown.includes("5d 4h"), JSON.stringify(shown));
            verify(!shown.some(t => t.startsWith("- - ")), "no dashed series without an inner ring");
        }

        // Every model's limit gets a row, whichever the ring shows.
        function test_severalLimits() {
            const usage = monitor.usage;
            setClaude({ scoped: [Object.assign({ id: "Opus", label: "Opus" }, usage.window(78, 2 * usage.day + 21 * 3600, [])),
                                 Object.assign({ id: "Sonnet", label: "Sonnet" }, usage.window(12, 4 * usage.day, []))] });
            const shown = root.texts(load("claude"));
            for (const text of ["All models", "Opus", "Sonnet", "78%", "12%", "resets in 4d 0h"]) {
                verify(shown.includes(text), text + " in " + JSON.stringify(shown));
            }
            verify(!shown.some(t => t.startsWith("- - ")), "two limits and no choice: no inner ring");
        }

        function test_signedOut() {
            monitor.usage.entries = { claude: { status: "signed_out" } };
            const shown = root.texts(load("claude"));
            verify(shown.includes("Run claude in a terminal to sign in."), JSON.stringify(shown));
            verify(!shown.includes("All models") && !shown.includes("until reset"), JSON.stringify(shown));
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
            verify(root.texts(popup).includes("62%"), "the last reading stays");
        }

        function test_emptyHistory() {
            const usage = monitor.usage;
            setClaude({ weekly: usage.window(0, 6 * usage.day, []), scoped: [] });
            const g = graph(load("claude"));
            verify(g.placed);
            compare(g.mainPoints.length, 0);
            compare(g.dayXs.length, 6);
            verify(Number.isFinite(g.nowX));
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
            verify(root.texts(popup).includes("1h 0m"), JSON.stringify(root.texts(popup)));
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

        function test_widestCountdown() {
            compare(words.widestCountdown(), local("00h 00m"));
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
            const time = new Date(2026, 8, 27, 7, 0).toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
            compare(words.resetDate({ resetsAt: sunday, clockZone: { offset: -4 * 3600, abbreviation: "EDT" } }),
                    Qt.locale().dayName(0, Locale.ShortFormat) + " " + time + " EDT");
            // Claude reports its reset a second before the hour.
            compare(words.resetDate({ resetsAt: sunday - 1, clockZone: { offset: -4 * 3600, abbreviation: "EDT" } }),
                    Qt.locale().dayName(0, Locale.ShortFormat) + " " + time + " EDT");
        }

        function test_resetDateInSystemTime() {
            const date = new Date(sunday * 1000);
            compare(words.resetDate({ resetsAt: sunday }),
                    Qt.locale().dayName(date.getDay(), Locale.ShortFormat) + " "
                    + date.toLocaleTimeString(Qt.locale(), Locale.ShortFormat));
            compare(words.resetDate({ resetsAt: null }), "");
        }

        function test_timeOfDay() {
            const noon = new Date(2026, 8, 27, 12, 0).getTime();
            const earlier = new Date(2026, 8, 27, 9, 15);
            compare(words.timeOfDay(earlier.getTime() / 1000, noon), earlier.toLocaleTimeString(Qt.locale(), Locale.ShortFormat));
            const yesterday = new Date(2026, 8, 26, 9, 15);
            compare(words.timeOfDay(yesterday.getTime() / 1000, noon), yesterday.toLocaleString(Qt.locale(), Locale.ShortFormat));
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

        ReadoutFont {
            id: readoutFace
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
                { tag: "claude", item: "claude", first: "62%", second: "2d 21h" },
                { tag: "codex", item: "codex", first: "34%", second: "5d 4h" },
                { tag: "claude at its limit", item: "claude", weekly: [90, 3600], first: "90%", level: 2, second: "1h 0m" },
                { tag: "claude amber", item: "claude", weekly: [75, 12 * 60], first: "75%", level: 1, second: "12m" },
                { tag: "claude used up", item: "claude", weekly: [100, 2 * 86400], first: "100%", level: 2, second: "2d 0h" },
                { tag: "reset passed", item: "claude", weekly: [40, -600], first: "40%", second: "–" },
                { tag: "signed out", item: "claude", entries: { claude: { status: "signed_out" } }, first: "–", second: "–" },
                { tag: "not checked yet", item: "codex", entries: {}, first: "–", second: "–" }
            ];
        }

        // Readout reads a missing level or heat as none, and only a true
        // `off` as asleep.
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

            // Each line fits the room its widest text keeps.
            const widest = readoutWords.widestReadout(data.item);
            const firstRoom = readoutFace.room(readoutFace.strong, widest[0]);
            const secondRoom = readoutFace.room(readoutFace.plain, widest[1]);
            verify(firstRoom > 0 && secondRoom > 0, "measured");
            verify(readoutFace.room(readoutFace.strong, [r.first]) <= firstRoom, r.first + " in " + JSON.stringify(widest[0]));
            verify(readoutFace.room(readoutFace.plain, [r.second]) <= secondRoom, r.second + " in " + JSON.stringify(widest[1]));
        }

        function test_widestReadout_data() {
            return [
                { tag: "cpu", item: "cpu", widest: [["100%"], ["100°"]] },
                { tag: "gpu", item: "gpu", widest: [["100%", "off"], ["100°"]] },
                { tag: "memory", item: "memory", widest: [["100%"], ["1000M"]] },
                { tag: "claude", item: "claude", widest: [["100%"], ["00h 00m"]] },
                { tag: "codex", item: "codex", widest: [["100%"], ["00h 00m"]] }
            ];
        }

        function test_widestReadout(data) {
            compare(readoutWords.widestReadout(data.item), data.widest.map(texts => texts.map(local)));
        }
    }

    TestCase {
        name: "WeekGraph"
        when: windowShown

        readonly property real start: 1000000
        readonly property real week: 7 * 86400

        function make(history, nowMs) {
            return createTemporaryObject(graphComponent, root, {
                window: { resetsAt: start + week, windowSeconds: week, history: history },
                nowMs: nowMs ?? (start + 86400) * 1000
            });
        }

        function test_pointsSpanTheWindow() {
            const g = make([[start - 10, 5], [start, 0], [start + week / 2, 50], [start + week, 100], [start + week + 10, 7]]);
            compare(g.mainPoints.map(p => [p.x, p.y]), [[0, 100], [350, 50], [700, 0]]);
            compare(g.dayXs, [100, 200, 300, 400, 500, 600]);
            compare(g.nowX, 100);
        }

        function test_secondSeriesSharesTheAxis() {
            const g = make([]);
            g.secondWindow = { resetsAt: start + 3 * 86400, windowSeconds: week, history: [[start + 86400, 20]] };
            compare(g.secondPoints.map(p => [p.x, p.y]), [[100, 80]]);
        }

        function test_nowStaysInside() {
            compare(make([], (start - 3600) * 1000).nowX, 0);
            compare(make([], (start + week + 3600) * 1000).nowX, 700);
        }

        function test_noResetTimeDrawsNothing() {
            const g = make([[start, 10]]);
            g.window = { resetsAt: null, windowSeconds: week, history: [[start, 10]] };
            verify(!g.placed);
            compare(g.mainPoints.length, 0);
            compare(g.dayXs.length, 0);
            verify(isNaN(g.nowX));
        }
    }
}
