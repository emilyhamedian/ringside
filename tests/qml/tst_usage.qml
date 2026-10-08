// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/popups"
import "../../package/contents/ui/code/format.js" as Format
import "../../package/contents/ui/code/report.js" as Report
import "../../package/contents/ui/code/style.js" as Style
import "starterstates.js" as StarterStates

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
    function i18nc(context, text, ...args) { return substitute(translations[text] ?? text, args); }
    // Stand-in translations a test can set, by the English text.
    property var translations: ({})
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

        // A provider's earlier failure gives way to the helper's own, host
        // and all, and "Try again" waits five minutes.
        function test_markFailedMarksOnlyShownEntries() {
            const before = { claude: { status: "ok", weekly: { percent: 40 }, lastError: "x", reason: "offline", host: "a.test" },
                             codex: { status: "signed_out" } };
            const after = Report.markFailed(before, "boom", 1000, "files");
            compare(after.claude.weekly.percent, 40);
            compare([after.claude.lastError, after.claude.lastErrorAt, after.claude.reason, after.claude.host, after.claude.retryAt],
                    ["boom", 1000, "files", "", 1300]);
            compare(after.codex, before.codex);
            compare(before.claude.lastError, "x", "the input is not modified");
        }

        function test_markFailedAddsNoEntry() {
            compare(Object.keys(Report.markFailed({}, "boom", 1000, "helper")).length, 0);
            compare(Object.keys(Report.markFailed({ codex: { status: "ok" } }, "boom", 1000, "helper")), ["codex"]);
        }

        // An error on the helper's own files would only happen again.
        function test_failureReason_data() {
            return [
                { tag: "permission", detail: "PermissionError: [Errno 13] Permission denied: '/x/usage.json'", reason: "files" },
                { tag: "disk full", detail: "OSError: [Errno 28] No space left on device", reason: "files" },
                { tag: "not a folder", detail: "NotADirectoryError: [Errno 20] Not a directory: '/x'", reason: "files" },
                { tag: "missing", detail: "FileNotFoundError: [Errno 2] No such file or directory: '/x'", reason: "files" },
                { tag: "key error", detail: "KeyError: 'weekly'", reason: "helper" },
                { tag: "named in passing", detail: "RuntimeError: not an OSError", reason: "helper" },
                { tag: "no detail", detail: "", reason: "helper" }
            ];
        }

        function test_failureReason(data) {
            compare(Report.failureReason({ reason: "exited", code: 1, detail: data.detail }), data.reason);
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
            // The helper's reason, host and end of its hold come through.
            const claude = usage.entry("claude");
            compare([claude.reason, claude.host], ["server", "api.anthropic.com"]);
            verify(Math.abs(claude.retryAt - (Date.now() / 1000 + 300)) < 60, claude.retryAt);
            compare([usage.entry("codex").reason, usage.entry("codex").host], ["rate-limited", ""]);
            verify(Math.abs(usage.entry("codex").retryAt - (Date.now() / 1000 + 3600)) < 60);
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
            compare(usage.entry("claude").reason, undefined, "recovery leaves nothing of the failure");
        }

        // A report from a helper that gives no reason holds nothing back.
        function test_failureWithoutAReason() {
            start("ok");
            poll("old");
            const claude = usage.entry("claude");
            compare([claude.reason, claude.host, claude.retryAt], ["other", "", claude.lastErrorAt]);
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
                { tag: "no python3", scenario: "no-python", message: "python3 was not found on the Plasma session's PATH.",
                  reason: "helper" },
                { tag: "traceback", scenario: "traceback", message: "The usage helper exited with code 1: KeyError: 'weekly'",
                  reason: "helper" },
                { tag: "files", scenario: "files", reason: "files",
                  message: "The usage helper exited with code 1: PermissionError: [Errno 13] Permission denied: '/home/user/.cache/ringside/usage.json'" }
            ];
        }

        function test_helperFailure(data) {
            start("ok");
            poll(data.scenario);
            compare(usage.helperError, data.message);
            compare(usage.entry("claude").lastError, data.message);
            const claude = usage.entry("claude");
            compare([claude.reason, claude.host, claude.retryAt], [data.reason, "", claude.lastErrorAt + 300]);
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

        // A check runs from the tick to its report, and the tick is when
        // the next interval counts from.
        function test_checkingWhileTheHelperRuns() {
            const before = Date.now() / 1000;
            start("ok");
            verify(!usage.checking);
            verify(usage.lastRun >= before - 1 && usage.lastRun <= Date.now() / 1000, usage.lastRun);
            const landed = spy("entriesChanged");
            usage.refresh();
            verify(usage.checking);
            landed.wait(10000);
            verify(!usage.checking);
        }

        // "Try again" checks at once and counts the next interval from then,
        // so the next tick doesn't follow straight after.
        function test_checkNowRestartsTheInterval() {
            start("ok");
            const first = usage.lastRun;
            wait(1100);
            const landed = spy("entriesChanged");
            usage.checkNow();
            verify(usage.checking);
            tryVerify(() => usage.lastRun > first + 1, 2000, "the interval starts over");
            landed.wait(10000);
            verify(!usage.checking);
            compare(timers().filter(t => t.running).map(t => t.interval), [5 * 60000]);
        }

        // The first tick once the helper's hold is over; a hold set by the
        // check a tick ran is over by the tick one interval on.
        function test_nextCheck_data() {
            return [
                { tag: "no hold", minutes: 5, retryAt: undefined, next: 300 },
                { tag: "the tick's own hold", minutes: 5, retryAt: 302, next: 300 },
                { tag: "on a tick", minutes: 5, retryAt: 3000, next: 3000 },
                { tag: "between ticks", minutes: 5, retryAt: 3100, next: 3300 },
                { tag: "longer interval", minutes: 15, retryAt: 302, next: 900 },
                { tag: "rate limit past a long tick", minutes: 15, retryAt: 1000, next: 1800 },
                { tag: "hold long over", minutes: 15, retryAt: -5000, next: 900 }
            ];
        }

        function test_nextCheck(data) {
            make("ok", []);
            config.usageRefreshMinutes = data.minutes;
            usage.lastRun = 10000;
            usage.entries = { claude: { status: "ok", lastError: "x", lastErrorAt: 10000,
                                        retryAt: data.retryAt === undefined ? undefined : 10000 + data.retryAt } };
            compare(usage.nextCheck("claude"), 10000 + data.next);
        }

        // Only when a check would really ask: the hold is over, none runs,
        // the next tick is over a minute away, and the helper can read its
        // files. At the default five minutes the hold ends with the tick.
        function test_canRetry_data() {
            return [
                { tag: "hold over", ran: 400, retryAt: -100, can: true },
                { tag: "held", ran: 400, retryAt: 100, can: false },
                { tag: "rate limited", ran: 400, retryAt: 3000, reason: "rate-limited", can: false },
                { tag: "files", ran: 400, retryAt: -100, reason: "files", can: false },
                { tag: "helper", ran: 400, retryAt: -100, reason: "helper", can: true },
                { tag: "checking", ran: 400, retryAt: -100, checking: true, can: false },
                { tag: "tick within a minute", ran: 850, retryAt: -100, can: false },
                { tag: "tick a minute and more away", ran: 830, retryAt: -100, can: true },
                { tag: "not failed", ran: 400, retryAt: -100, ok: true, can: false },
                { tag: "five minutes", minutes: 5, ran: 60, retryAt: 240, can: false }
            ];
        }

        function test_canRetry(data) {
            make("ok", []);
            const now = Date.now() / 1000;
            config.usageRefreshMinutes = data.minutes ?? 15;
            usage.lastRun = now - data.ran;
            usage.checking = data.checking ?? false;
            const entry = { status: "ok", retryAt: now + data.retryAt, reason: data.reason ?? "offline" };
            usage.entries = { claude: data.ok ? entry : Object.assign(entry, { lastError: "x", lastErrorAt: now - data.ran }) };
            compare(usage.canRetry("claude", now * 1000), data.can);
            compare(usage.canRetry("codex", now * 1000), false, "no entry, nothing to retry");
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

        function runner() {
            return usage.resources.find(r => r.engine === "executable");
        }

        // The helper commands run from now on, in order.
        function commands() {
            return createTemporaryObject(spyComponent, data, { target: runner(), signalName: "sourceConnected" });
        }

        function ran(spy, suffix) {
            return spy.signalArguments.map(a => a[0]).filter(c => c.endsWith(suffix));
        }

        function starterTick() {
            return timers().find(t => t.interval === 30000);
        }

        function test_startersFromEveryReport() {
            start("starter");
            compare(usage.starter("claude").state, "waiting");
            verify(usage.starterOn("claude"));
            compare(usage.starter("codex"), { enabled: false, state: "off", at: null, next: null, reason: null });
            verify(!usage.starterOn("codex"));
            // A failed or rate-limited check keeps the last reading but
            // still takes the starter it reports.
            usage.starters = Object.assign({}, usage.starters, { codex: { enabled: true, state: "started", at: null, next: null, reason: null } });
            poll("failed");
            compare(usage.starter("claude").state, "off");
            verify(usage.degraded("claude"));
            compare(usage.entry("codex").status, "ok", "the reading before the rate limit");
            compare(usage.starter("codex").state, "off");
        }

        function test_starterTickOnlyWhileOneIsOn() {
            start("ok");
            verify(!starterTick().running, "every starter is off");
            poll("starter");
            verify(starterTick().running);
        }

        // --start runs once the starter's time has come, not before, and
        // never twice at once.
        function test_startRunsOnceWhenDue() {
            start("starter");
            const run = commands();
            starterTick().triggered();
            compare(ran(run, " --start"), [], "not due yet");
            const due = usage.starter("claude").next;
            tryVerify(() => Date.now() / 1000 >= due, 5000);
            starterTick().triggered();
            // Codex comes due too while Claude's start runs: it waits for
            // the next tick rather than starting beside it.
            usage.starters = Object.assign({}, usage.starters, { codex: { enabled: true, state: "waiting", at: null, next: due, reason: null } });
            starterTick().triggered();
            compare(ran(run, " --start"), [usage.helperCommand(["claude"], " --start")]);
            tryVerify(() => usage.starter("claude").state === "confirming", 10000);
            starterTick().triggered();
            compare(ran(run, " --start"), [usage.helperCommand(["claude"], " --start"), usage.helperCommand(["codex"], " --start")],
                    "Claude's confirmation isn't due yet; Codex is");
            tryVerify(() => runner().connectedSources.length === 0, 10000);
        }

        // A switch turned off while its starter is due starts nothing, even
        // before the helper has written the change.
        function test_switchedOffStartsNothing() {
            start("starter-slow-set");
            const run = commands();
            const due = usage.starter("claude").next;
            tryVerify(() => Date.now() / 1000 >= due, 5000);
            usage.setStarter("claude", false);
            starterTick().triggered();
            compare(ran(run, " --start"), [], "the switch is off");
            tryVerify(() => Object.keys(usage.starterWanted).length === 0, 10000);
            starterTick().triggered();
            compare(ran(run, " --start"), [], "the helper reports it off");
        }

        // A due start waits for a switch change being written, so the two
        // never run at once, and runs as soon as it lands, with the starter
        // just switched on, which is due at once.
        function test_startWaitsForASwitchChange() {
            start("starter-slow-set");
            const run = commands();
            const due = usage.starter("claude").next;
            tryVerify(() => Date.now() / 1000 >= due, 5000);
            usage.setStarter("codex", true);
            starterTick().triggered();
            compare(ran(run, " --start"), [], "a switch change is being written");
            tryVerify(() => ran(run, " --start").length === 1, 10000);
            compare(ran(run, " --start"), [usage.helperCommand(["claude", "codex"], " --start")]);
            verify(!runner().connectedSources.some(c => c.includes("--starter-set")));
            tryVerify(() => runner().connectedSources.length === 0, 10000);
        }

        // A --start that fails leaves the readings alone and says so only in
        // the starter's status. It runs again five minutes later, then ten,
        // twenty and so on up to five hours, not on every tick, and a report
        // that moves the starter on ends it.
        function test_failedStartBacksOff() {
            start("starter-start-fails");
            const run = commands();
            const due = usage.starter("claude").next;
            tryVerify(() => Date.now() / 1000 >= due, 5000);
            starterTick().triggered();
            compare(ran(run, " --start").length, 1);
            tryVerify(() => usage.starter("claude").state === "failed", 10000);
            const failed = usage.starter("claude");
            compare(failed.reason, "helper");
            compare(failed.error, "The usage helper exited with code 1: RuntimeError: boom");
            compare(failed.next - failed.at, 300);
            verify(!usage.degraded("claude") && !usage.degraded("codex"), "the readings carry no failure");
            compare(usage.helperError, "");
            compare(usage.starter("codex").state, "off");
            starterTick().triggered();
            compare(ran(run, " --start").length, 1, "not before the retry");

            const retry = count => {
                const before = count ?? usage.startFailures.claude.count;
                usage.startFailures = { claude: Object.assign({}, usage.startFailures.claude,
                                                              { retryAt: Date.now() / 1000 - 1, count: before }) };
                const runs = ran(run, " --start").length;
                starterTick().triggered();
                compare(ran(run, " --start").length, runs + 1, "the retry is due");
                tryVerify(() => usage.startFailures.claude.count === before + 1, 10000);
                return usage.starter("claude").next - usage.starter("claude").at;
            };
            compare(retry(), 600);
            compare(retry(), 1200);
            compare(retry(6), 5 * 3600);
            compare(retry(), 5 * 3600);

            poll("starter");
            compare(usage.starter("claude").reason, "helper", "still waiting, before the retry");
            usage.startFailures = { claude: Object.assign({}, usage.startFailures.claude, { retryAt: Date.now() / 1000 - 1 }) };
            starterTick().triggered();
            tryVerify(() => usage.starter("claude").state === "confirming", 10000);
            compare(usage.startFailures, {});
        }

        // A --start that reports but leaves the starter due, or leaves it
        // out, backs off as a failed one does rather than running on every
        // tick. The readings it brings are taken.
        function test_startLeftDueBacksOff() {
            start("starter");
            const due = usage.starter("claude").next;
            tryVerify(() => Date.now() / 1000 >= due, 5000);
            const command = usage.helperCommand(["claude"], " --start");
            const answer = providers => runner().newData(command, { "exit code": 0, "exit status": 0, stderr: "",
                                                                    stdout: JSON.stringify({ fetchedAt: due, providers: providers }) });
            const stuck = { enabled: true, state: "waiting", at: null, next: due, reason: null };
            answer({ claude: Object.assign({}, usage.entry("claude"), { starter: stuck }) });
            const failed = usage.starter("claude");
            compare([failed.state, failed.reason, failed.error], ["failed", "helper", ""]);
            compare(failed.next - failed.at, 300);
            verify(!usage.degraded("claude"));
            compare(usage.helperError, "");
            const run = commands();
            starterTick().triggered();
            compare(ran(run, " --start"), [], "not before the retry");

            answer({});
            compare(usage.starter("claude").next - usage.starter("claude").at, 600, "left out, it backs off further");
            answer({ claude: Object.assign({}, usage.entry("claude"), {
                starter: { enabled: true, state: "confirming", at: due, next: due + 300, reason: null } }) });
            compare(usage.starter("claude").state, "confirming", "a report that moves it on ends the back-off");
        }

        // A --start that dies after the helper claimed the step leaves the
        // starter in its state with next five minutes on. The polls that
        // report that claim keep the back-off, which still doubles; one
        // that reports a new state, or a next past the retry, ends it.
        function test_startBackOffOutlastsTheHelpersClaim() {
            start("starter");
            const due = usage.starter("claude").next;
            tryVerify(() => Date.now() / 1000 >= due, 5000);
            const crash = () => runner().newData(usage.helperCommand(["claude"], " --start"), {
                "exit code": 1, "exit status": 0, stdout: "", stderr: "Traceback (most recent call last):\nOSError: boom\n" });
            const poll = (state, next) => {
                const starter = { enabled: true, state: state, at: null, next: next, reason: null };
                runner().newData(usage.command, { "exit code": 0, "exit status": 0, stderr: "", stdout: JSON.stringify({
                    fetchedAt: due, providers: { claude: Object.assign({}, usage.entry("claude"), { starter: starter }) } }) });
            };
            const claimed = Math.floor(Date.now() / 1000) + 300;
            crash();
            poll("waiting", claimed);
            const failed = usage.starter("claude");
            compare([failed.state, failed.reason, failed.error], ["failed", "helper", "The usage helper exited with code 1: OSError: boom"]);
            compare(failed.next - failed.at, 300);
            usage.startFailures = { claude: Object.assign({}, usage.startFailures.claude, { retryAt: Date.now() / 1000 - 1 }) };
            crash();
            compare(usage.starter("claude").next - usage.starter("claude").at, 600, "the next crash doubles it");
            poll("waiting", claimed);
            compare(usage.startFailures.claude.count, 2);

            poll("confirming", claimed);
            compare(usage.startFailures, {}, "a new state ends it");
            crash();
            poll("confirming", usage.startFailures.claude.retryAt + 1);
            compare(usage.startFailures, {}, "so does a next past the retry");
        }

        // A helper that can't save its state reports a switched-on starter
        // due at once, on every poll as after every --start. Those polls
        // keep the back-off, which doubles with each --start, and the
        // status gives the reason the helper printed.
        function test_startBackOffOutlastsPollsThatSayDue() {
            start("starter");
            const due = usage.starter("claude").next;
            tryVerify(() => Date.now() / 1000 >= due, 5000);
            const answer = (command, stderr) => {
                const now = Math.floor(Date.now() / 1000);
                const stuck = { enabled: true, state: "waiting", at: null, next: now, reason: null };
                runner().newData(command, { "exit code": 0, "exit status": 0, stderr: stderr, stdout: JSON.stringify({
                    fetchedAt: now, providers: { claude: Object.assign({}, usage.entry("claude"), { starter: stuck }) } }) });
            };
            const run = commands();
            for (const delay of [300, 600, 1200]) {
                answer(usage.helperCommand(["claude"], " --start"), "[Errno 28] No space left on device\n");
                const failed = usage.starter("claude");
                compare([failed.state, failed.reason, failed.error], ["failed", "helper", "[Errno 28] No space left on device"]);
                compare(failed.next - failed.at, delay);
                wait(1100);
                answer(usage.command, "");
                compare(usage.starter("claude").reason, "helper", "a poll that says due keeps it");
                starterTick().triggered();
                compare(ran(run, " --start"), [], "not before the retry");
            }
        }

        function test_setStarterRunsTheHelper() {
            start("starter");
            const run = commands();
            const landed = spy("startersChanged");
            usage.setStarter("codex", true);
            verify(usage.starterOn("codex"), "the switch shows the change at once");
            compare(ran(run, "=on"), [usage.helperCommand(["claude", "codex"], " --starter-set codex=on")]);
            landed.wait(10000);
            verify(usage.starter("codex").enabled);
            verify(usage.starterOn("codex"));
            compare(usage.starterWanted, {});
        }

        // A change the helper couldn't write comes back in a report that
        // shows the switch unchanged, with the reason on stderr. The switch
        // snaps back and says why under it, and one the user turned off
        // starts nothing until it is turned again.
        function test_refusedChangeSnapsBack() {
            start("starter-stuck");
            const status = config.usageStatus;
            const refused = "[Errno 13] Permission denied: '/home/user/.config/ringside/.starter.kvt5gezx.tmp'";
            const landed = spy("startersChanged");
            usage.setStarter("codex", true);
            verify(usage.starterOn("codex"));
            landed.wait(10000);
            verify(!usage.starterOn("codex"), "the helper kept it off");
            compare(usage.starterWanted, {});
            compare(usage.starter("codex"), { enabled: false, state: "failed", reason: "switch", at: null, next: null, error: refused });
            verify(!usage.degraded("claude") && !usage.degraded("codex"), "the readings carry no failure");
            compare(usage.helperError, "");
            compare(config.usageStatus, status);
            tryVerify(() => runner().connectedSources.length === 0, 10000);

            const run = commands();
            usage.setStarter("claude", false);
            tryVerify(() => Object.keys(usage.starterWanted).length === 0, 10000);
            verify(usage.starterOn("claude"), "the helper kept it on");
            compare([usage.starter("claude").reason, usage.starter("claude").error], ["switch", refused]);
            const due = usage.starter("claude").next;
            tryVerify(() => Date.now() / 1000 >= due, 5000);
            starterTick().triggered();
            compare(ran(run, " --start"), [], "the user turned it off");

            usage.setStarter("claude", true);
            tryVerify(() => Object.keys(usage.starterWanted).length === 0, 10000);
            verify(usage.starter("claude").reason !== "switch", "turned again, the failure is gone");
            const next = usage.starter("claude").next;
            tryVerify(() => Date.now() / 1000 >= next, 5000);
            starterTick().triggered();
            compare(ran(run, " --start").length, 1);
            tryVerify(() => runner().connectedSources.length === 0, 10000);
        }

        // Only the change last asked for can fail, and a report that shows
        // another widget's change, with no reason on stderr, is no failure.
        function test_refusedChangeOnlyWhenAskedAndSaid() {
            start("starter");
            const command = usage.helperCommand(usage.ids, " --starter-set codex=on");
            const answer = stderr => runner().newData(command, { "exit code": 0, "exit status": 0, stderr: stderr,
                                                                 stdout: JSON.stringify({ fetchedAt: usage.entry("codex").fetchedAt,
                                                                                          providers: { codex: usage.entry("codex") } }) });
            usage.starterWanted = { codex: true };
            answer("");
            compare(usage.switchFailures, {}, "another widget's change");
            usage.starterWanted = { codex: false };
            answer("[Errno 13] Permission denied\n");
            compare(usage.switchFailures, {}, "turned again since");
            verify(usage.starter("codex").reason !== "switch");
            compare(usage.starterWanted, { codex: false }, "the newer change still runs");
            tryVerify(() => runner().connectedSources.length === 0, 10000);
            compare(usage.switchFailures, {});
        }

        function test_failedChangeSnapsBack() {
            start("starter");
            poll("traceback");
            usage.setStarter("codex", true);
            verify(usage.starterOn("codex"));
            tryVerify(() => !usage.starterOn("codex"), 10000);
            compare(usage.starter("codex").enabled, false);
        }

        // A switch change that gives no report leaves the readings and the
        // settings page alone. The switch snaps back and says why under it
        // until it is turned again.
        function test_unwrittenChangeSaysSoUnderTheSwitch() {
            start("starter");
            const status = config.usageStatus;
            usage.starterWanted = { codex: true };
            runner().newData(usage.helperCommand(usage.ids, " --starter-set codex=on"),
                             { "exit code": 1, "exit status": 0, stdout: "",
                               stderr: "Traceback (most recent call last):\nPermissionError: [Errno 13] Permission denied: 'starter.json'\n" });
            verify(!usage.starterOn("codex"), "snapped back");
            compare(usage.starterWanted, {});
            verify(!usage.degraded("claude") && !usage.degraded("codex"), "the readings carry no failure");
            compare(usage.helperError, "");
            compare(config.usageStatus, status);
            compare(usage.starter("codex"), { enabled: false, state: "failed", reason: "switch", at: null, next: null,
                                              error: "The usage helper exited with code 1: PermissionError: [Errno 13] Permission denied: 'starter.json'" });
            compare(usage.starter("claude").state, "waiting", "the other switch is untouched");
            // Another widget's change, once reported, ends it.
            const reported = usage.starters;
            usage.starters = Object.assign({}, reported, { codex: { enabled: true, state: "started", at: null, next: null, reason: null } });
            compare(usage.starter("codex").state, "started");
            usage.starters = reported;
            compare(usage.starter("codex").reason, "switch");

            usage.setStarter("codex", true);
            compare(usage.starter("codex").state, "off", "turned again, the failure is gone");
            tryVerify(() => usage.starter("codex").enabled, 10000);
            verify(usage.starter("codex").reason !== "switch");
            tryVerify(() => runner().connectedSources.length === 0, 10000);

            // A change that fails after the switch was turned again is no
            // longer the one asked for, so it records nothing.
            usage.starterWanted = { codex: false };
            runner().newData(usage.helperCommand(usage.ids, " --starter-set codex=on"),
                             { "exit code": 1, "exit status": 0, stdout: "", stderr: "PermissionError: [Errno 13] Permission denied\n" });
            compare(usage.switchFailures, {});
            tryVerify(() => runner().connectedSources.length === 0, 10000);
            compare(usage.switchFailures, {});
            verify(usage.starter("codex").reason !== "switch");
            verify(!usage.starterOn("codex"));
        }

        // A quick on and off run one after the other, so the last one wins.
        function test_changesRunInOrder() {
            start("starter");
            const run = commands();
            usage.setStarter("codex", true);
            usage.setStarter("codex", false);
            verify(!usage.starterOn("codex"));
            compare(runner().connectedSources.filter(c => c.includes("--starter-set")).length, 1);
            tryVerify(() => Object.keys(usage.starterWanted).length === 0, 10000);
            compare(ran(run, "=on").length + ran(run, "=off").length, 2);
            verify(run.signalArguments.findIndex(a => a[0].endsWith("=on")) < run.signalArguments.findIndex(a => a[0].endsWith("=off")));
            compare(usage.starter("codex").state, "off");
        }

        // Its failures go too, so none shows again should it come back.
        function test_droppedProviderDropsItsStarter() {
            start("starter");
            usage.setStarter("codex", true);
            usage.startFailures = { codex: { count: 1, at: 0, retryAt: 300, error: "boom", state: "waiting" } };
            usage.switchFailures = { codex: { on: true, error: "boom" } };
            usage.providers = ["claude"];
            compare(Object.keys(usage.starters), ["claude"]);
            compare(usage.starterWanted, {});
            compare(usage.startFailures, {});
            compare(usage.switchFailures, {});
            usage.setStarter("codex", true);
            compare(usage.starterWanted, {}, "an unpolled provider has no switch");
            tryVerify(() => runner().connectedSources.length === 0, 10000);
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

        // What merge() adds to an entry whose check failed, with the reading
        // taken `age` seconds before now.
        function failure(age) {
            const now = Date.now() / 1000;
            return { fetchedAt: now - age, lastError: "can't reach api.anthropic.com: Name or service not known",
                     lastErrorAt: Math.floor(now), reason: "offline", host: "api.anthropic.com", retryAt: Math.floor(now) + 300 };
        }

        // Claude near its limit, with Fable on the inner ring.
        function hotClaude() {
            const usage = monitor.usage;
            setEntry("claude", Object.assign({}, usage.entries.claude, { weekly: usage.window(95, lastHours, []) }));
            return usage.entries.claude;
        }

        // The ring's middle, which holds the mark, and the stroke.
        function middle(cell) {
            const face = outerArc(cell).parent;
            let item = mark(cell);
            while (item.parent !== face) {
                item = item.parent;
            }
            return item;
        }

        function strike(cell) {
            return root.find(cell.children[0], i => i.lineWidth !== undefined);
        }

        function strikePath(cell) {
            return Array.from(strike(cell).data).find(o => o.strokeColor !== undefined);
        }

        // The rings of thin panels too: a strip 18 to 24 px thick has rings
        // of 15 to 20 px.
        function test_failedCheckStrikesTheRing_data() {
            return [{ tag: "34", ring: 34 }, { tag: "22", ring: 22 }, { tag: "52", ring: 52 },
                    { tag: "34 mirrored", ring: 34, mirrored: true }, { tag: "15", ring: 15 }, { tag: "16", ring: 16 },
                    { tag: "18", ring: 18 }, { tag: "20", ring: 20 }, { tag: "16 mirrored", ring: 16, mirrored: true }];
        }

        // A reading two check intervals old that couldn't be renewed is
        // gone: the arcs unwind, the inner ring goes, the mark greys, a
        // stroke in the track's own colour crosses the ring from its bottom
        // left to its top right, inside it, in every direction of writing,
        // and the readings go to dim dashes. Nothing breathes. The words say
        // when and why it failed, the last reading and the next check. The
        // next good check puts it all back.
        function test_failedCheckStrikesTheRing(data) {
            const ok = hotClaude();
            const c = cell("claude", { ring: data.ring });
            c.LayoutMirroring.enabled = data.mirrored ?? false;
            c.LayoutMirroring.childrenInherit = true;
            const gauge = c.children[0];
            const arc = outerArc(c);
            const face = arc.parent;
            verify(!strike(c).visible, "no stroke while the checks succeed");
            verify(gauge.pulsing);

            setEntry("claude", Object.assign({}, ok, failure(600)));
            tryCompare(gauge, "struck", 1, 3000);
            tryCompare(arc, "percent", 0, 3000);
            tryCompare(gauge, "innerShown", 0, 3000);
            verify(gauge.cancelled && !gauge.stale);
            compare([line(c, "first").text, line(c, "second").text], ["––%", "–d"]);
            const dim = String(Style.dim(Kirigami.Theme.textColor));
            compare([String(line(c, "first").color), String(line(c, "second").color)], [dim, dim]);
            fuzzyCompare(middle(c).opacity, 0.4, 1e-6);

            const s = strike(c);
            const path = strikePath(c);
            verify(s.visible);
            compare(s.opacity, 1);
            compare(path.strokeColor, arc.trackColor, "the track's own colour");
            compare(arc.trackColor, Qt.alpha(Kirigami.Theme.textColor, 0.16 * Kirigami.Theme.textColor.a));
            const end = path.pathElements[0];
            const mid = gauge.width / 2;
            verify(path.startX < mid && path.startY > mid, "from the bottom left");
            fuzzyCompare(end.x, gauge.width - path.startX, 1e-6);
            fuzzyCompare(end.y, gauge.height - path.startY, 1e-6);
            verify(end.x - path.startX >= 2 * s.lineWidth, "long enough to read as a stroke at " + data.ring + " px");
            const tip = Math.hypot(path.startX - mid, path.startY - mid) + s.lineWidth / 2;
            const inside = arc.radius - arc.strokeWidth / 2;
            fuzzyCompare(tip, inside, 1e-6, "its caps end on the track's inner edge");

            // A breath under way ends, and no other starts.
            tryCompare(face, "opacity", 1, 2500);
            wait(1200);
            compare(face.opacity, 1, "no breathing");
            verify(gauge.Accessible.ignored);
            const lines = c.accessibleDescription.split("\n");
            compare(lines.length, 3, c.accessibleDescription);
            verify(/^Last check failed at .+\. Can't reach api\.anthropic\.com\.$/.test(lines[0]), lines[0]);
            verify(lines[1].startsWith("Last reading at ") && lines[1].endsWith(": " + root.localized("95%") + " used, Fable "
                                                                                 + root.localized("78%") + ", resets in 5 hours."), lines[1]);
            verify(/^Next check at .+\.$/.test(lines[2]), lines[2]);

            setEntry("claude", ok);
            tryCompare(gauge, "struck", 0, 3000);
            tryCompare(arc, "percent", 95, 3000);
            verify(!strike(c).visible);
            compare([line(c, "first").text, line(c, "second").text], ["95%", "5h"].map(root.localized));
            fuzzyCompare(middle(c).opacity, 1, 1e-6);
            compare(c.accessibleDescription, root.localized("95%") + " used, Fable " + root.localized("78%") + ", resets in 5 hours");
        }

        // Until the reading is two check intervals old, and while its week
        // runs, a failed check keeps it in grey: the arcs and readings stay
        // where they were, with no amber, red or breathing, and no stroke.
        function test_failedCheckGreysFirst_data() {
            return [{ tag: "first failure", age: 60, interval: 5, grey: true },
                    { tag: "under two intervals", age: 570, interval: 5, grey: true },
                    { tag: "two intervals", age: 600, interval: 5, grey: false },
                    { tag: "under two longer intervals", age: 1770, interval: 15, grey: true },
                    { tag: "two longer intervals", age: 1800, interval: 15, grey: false },
                    { tag: "the week has reset", age: 60, interval: 5, grey: false, reset: true }];
        }

        function test_failedCheckGreysFirst(data) {
            const usage = monitor.usage;
            usage.refreshMinutes = data.interval;
            const ok = hotClaude();
            const c = cell("claude");
            const gauge = c.children[0];
            const arc = outerArc(c);
            const changes = failure(data.age);
            if (data.reset) {
                changes.weekly = usage.window(95, -600, []);
            }
            setEntry("claude", Object.assign({}, ok, changes));
            compare(gauge.stale, data.grey);
            compare(gauge.cancelled, !data.grey);
            if (!data.grey) {
                tryCompare(gauge, "struck", 1, 3000);
                return;
            }
            tryCompare(gauge, "greyed", 1, 3000);
            wait(2 * Kirigami.Units.longDuration);
            compare(gauge.struck, 0, "no stroke");
            verify(!strike(c).visible);
            compare(arc.percent, 95, "the arc stays");
            compare(innerArc(c).percent, 78);
            compare([line(c, "first").text, line(c, "second").text], ["95%", "5h"].map(root.localized));
            const dim = String(Style.dim(Kirigami.Theme.textColor));
            compare([String(line(c, "first").color), String(line(c, "second").color)], [dim, dim]);
            compare(arc.color, Qt.alpha(Kirigami.Theme.textColor, 0.42 * Kirigami.Theme.textColor.a), "grey, not red");
            compare(innerArc(c).color, Qt.alpha(Kirigami.Theme.textColor, 0.55 * Kirigami.Theme.textColor.a), "grey, not amber");
            fuzzyCompare(middle(c).opacity, 0.4, 1e-6);
            tryCompare(arc.parent, "opacity", 1, 2500);
            wait(1200);
            compare(arc.parent.opacity, 1, "no breathing");
            verify(c.accessibleDescription.startsWith("Last check failed at "), c.accessibleDescription);

            // The check that finds it two intervals old strikes it.
            setEntry("claude", Object.assign({}, ok, failure(2 * data.interval * 60)));
            verify(gauge.cancelled && !gauge.stale);
            tryCompare(gauge, "struck", 1, 3000);
            compare(line(c, "first").text, "––%");
        }

        // At Plasma's Instant speed the arcs, the stroke and the dashes
        // change together, in one frame each way.
        function test_strikeAtInstant() {
            const ok = hotClaude();
            const c = cell("claude");
            const gauge = c.children[0];
            gauge.settle = 0;
            setEntry("claude", Object.assign({}, ok, failure(600)));
            compare(outerArc(c).percent, 0, "the arc at once");
            compare([gauge.struck, line(c, "first").text], [0, root.localized("95%")], "neither the stroke nor the dashes yet");
            wait(0);
            compare([gauge.struck, line(c, "first").text, line(c, "second").text], [1, "––%", "–d"], "both");
            setEntry("claude", ok);
            wait(0);
            compare([gauge.struck, outerArc(c).percent, line(c, "first").text], [0, 95, root.localized("95%")]);
        }

        // The words of a failed check, from the reason the helper gives.
        function test_failureWords_data() {
            return [
                { tag: "offline", entry: { reason: "offline", host: "api.anthropic.com" }, text: "Can't reach api.anthropic.com." },
                { tag: "timeout", entry: { reason: "timeout", host: "api.anthropic.com" },
                  text: "api.anthropic.com didn't answer in time." },
                { tag: "codex timeout", item: "codex", entry: { reason: "timeout", host: "" }, text: "Codex didn't answer in time." },
                { tag: "server", entry: { reason: "server", host: "api.anthropic.com" }, text: "api.anthropic.com answered with an error." },
                { tag: "rate limit", entry: { reason: "rate-limited", retryAt: Date.now() / 1000 + 3000 }, text: /^Anthropic asked Ringside to wait until .+\.$/ },
                { tag: "codex rate limit", item: "codex", entry: { reason: "rate-limited", retryAt: Date.now() / 1000 + 3000 }, text: /^OpenAI asked Ringside to wait until .+\.$/ },
                { tag: "files", entry: { reason: "files" }, text: "The usage helper couldn't read or write its files." },
                { tag: "helper", entry: { reason: "helper" }, text: "The usage helper stopped with an error." },
                { tag: "other", entry: { reason: "other", lastError: "codex CLI not found" }, text: "Codex CLI not found." },
                { tag: "no reason", entry: { lastError: "Claude Code's credentials can't be read" },
                  text: "Claude Code's credentials can't be read." },
                { tag: "a sentence", entry: { reason: "other", lastError: "Stopped!" }, text: "Stopped!" },
                { tag: "offline, no host", entry: { reason: "offline", host: "", lastError: "can't reach it" }, text: "Can't reach it." }
            ];
        }

        function test_failureWords(data) {
            const c = cell(data.item ?? "claude");
            const words = Array.from(c.data).find(o => o.failureReason !== undefined);
            const text = words.failureReason(data.item ?? "claude", Object.assign({ lastError: "x" }, data.entry), Date.now());
            if (typeof data.text === "string") {
                compare(text, data.text);
            } else {
                verify(data.text.test(text), text);
            }
        }

        // The next check, or that one is running.
        function test_failedWordsNameTheNextCheck() {
            const ok = hotClaude();
            const c = cell("claude");
            setEntry("claude", Object.assign({}, ok, failure(60)));
            verify(/\nNext check at .+\.$/.test(c.accessibleDescription), c.accessibleDescription);
            monitor.usage.checking = true;
            verify(c.accessibleDescription.endsWith("\nChecking now."), c.accessibleDescription);
            setEntry("claude", Object.assign({}, ok, failure(60), { weekly: monitor.usage.window(95, -600, []) }));
            verify(/\nThe week reset at .+, with no reading since\.\n/.test(c.accessibleDescription), c.accessibleDescription);
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
                const tile = root.find(page, i => i.visible && i.graphTop !== undefined);
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
            const tile = root.find(popup, i => i.visible && i.graphTop !== undefined);
            const left = tile.mapToItem(popup, Qt.point(0, 0)).x;
            compare(left, edge);
            compare(left + tile.width, popup.width - edge);
        }

        // "100%" names each percentage graph's top, and a temperature graph
        // names its peak, at the far end of its tile's caption line, over the
        // end of the rule, and nothing
        // is written in the graph above its floor, where a line could run
        // through it. Mirrored, the caption line reads from the right and
        // "100%" ends it at the left.
        function test_scaleOnTheCaptionLine_data() {
            const rows = [];
            for (const popup of ["claude", "codex", "CpuPopup", "GpuPopup", "MemoryPopup"]) {
                rows.push({ tag: popup, popup: popup, mirrored: false });
                rows.push({ tag: popup + " mirrored", popup: popup, mirrored: true });
            }
            return rows;
        }

        function test_scaleOnTheCaptionLine(data) {
            let page;
            if (data.popup === "claude" || data.popup === "codex") {
                page = load(data.popup, data.mirrored);
            } else {
                const loader = (data.mirrored ? mirroredHost : host).createObject(root) as Loader;
                loaders.push(loader);
                loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/" + data.popup + ".qml"), { monitor: monitor });
                compare(loader.status, Loader.Ready);
                page = loader.item as Item;
                waitForRendering(page);
            }
            const rules = [];
            const collect = i => {
                if (i.visible && i.lineColor !== undefined && i.limitY !== undefined) {
                    rules.push(i);
                }
                i.children.forEach(collect);
            };
            collect(page);
            verify(rules.length > 0, "a percentage graph");
            for (const rule of rules) {
                const g = rule.parent;
                let tile = g;
                while (tile.graphTop === undefined) {
                    tile = tile.parent;
                }
                const left = i => i.mapToItem(page, Qt.point(0, 0)).x;
                const top = i => i.mapToItem(page, Qt.point(0, 0)).y;
                const plotBottom = top(g) + (g.plotHeight ?? g.height);
                const written = [];
                const look = i => {
                    if (i.visible && i.font !== undefined && typeof i.text === "string" && i.text !== "" && top(i) < plotBottom) {
                        written.push(i.text);
                    }
                    i.children.forEach(look);
                };
                look(g);
                compare(written, [], "nothing written in the graph");

                const lineParts = [];
                const part = i => {
                    if (i.label !== undefined && i.detail !== undefined) {
                        lineParts.push(i);
                    }
                    i.children.forEach(part);
                };
                part(tile);
                const [caption, scale] = lineParts;
                if (g.plot !== undefined) {
                    verify(scale.text.startsWith(root.localized("peak ")), scale.text);
                } else {
                    compare(scale.text, root.localized("100%"));
                }
                verify(scale.visible && !scale.truncated);
                verify(top(scale) + scale.height <= top(g), "on the caption line, over the graph");
                verify(caption.visible && caption.text !== "");
                fuzzyCompare(top(scale) + scale.baselineOffset, top(caption) + caption.baselineOffset, 0.5);
                // The text's box at the graph's far end; its ink is right-aligned in it.
                if (data.mirrored) {
                    compare(left(scale), left(g));
                    verify(left(caption) >= left(scale) + scale.width, "the caption after it");
                } else {
                    compare(left(scale) + scale.width, left(g) + g.width);
                    verify(left(caption) + caption.width <= left(scale), "the caption before it");
                }
                compare(left(rule), left(g));
                compare(rule.width, g.width, "the rule spans the graph, under the scale's end");
            }
        }

        // A week the helper gives no reset time draws no rule, so its
        // caption line names no scale.
        function test_noScaleWithoutAReset() {
            setClaude({ weekly: Object.assign(monitor.usage.window(0, 6 * monitor.usage.day, []), { resetsAt: null }) });
            const popup = load("claude");
            const tile = root.find(popup, i => i.visible && i.graphTop !== undefined);
            verify(!graph(popup).placed);
            compare(tile.graphTop, "");
            verify(!root.find(tile, i => i.visible && i.text === root.localized("100%")), "no 100% on the caption line");
        }

        // The week's tile ends on its legend's baseline with a model limit,
        // without one on the run-out's time under the graph while it shows,
        // else on the graph's floor; each sits as far from the tile's bottom
        // as the caption's capitals from its top.
        function test_weekTilePadding_data() {
            return [{ tag: "legend", item: "claude", legend: true },
                    { tag: "graph", item: "codex", legend: false },
                    { tag: "runOut", item: "claude", legend: false, runOut: true }];
        }
        function test_weekTilePadding(data) {
            if (data.runOut) {
                const usage = monitor.usage;
                setClaude({ weekly: usage.window(60, 4 * usage.day, [[3, 0], [0, 60]]), scoped: [] });
            }
            const popup = load(data.item);
            const tile = root.find(popup, i => i.visible && i.graphTop !== undefined);
            const week = root.find(tile, i => i.mainPoints !== undefined);
            compare(tile.foot !== null, data.legend || data.runOut === true);
            if (data.runOut) {
                verify(week.timeShown);
                compare(tile.foot, week.runOutTime);
            } else if (!data.legend) {
                verify(!week.timeShown);
            }
            const caption = root.find(tile, i => i.label !== undefined && i.detail !== undefined);
            const capTop = caption.mapToItem(tile, Qt.point(0, caption.baselineOffset)).y - tile.capHeight;
            const graph = root.find(tile, i => i.mainPoints !== undefined);
            const foot = tile.foot ? tile.height - tile.foot.mapToItem(tile, Qt.point(0, tile.foot.baselineOffset)).y
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

        function starterSwitch(popup) {
            return root.find(popup, i => i.visualPosition !== undefined);
        }

        function starterStatus(popup) {
            return root.find(popup, i => i.maximumLineCount === 2 && i.elide === Text.ElideRight);
        }

        function configureButton(popup) {
            return root.find(popup, i => i.icon !== undefined && i.icon.name === "configure");
        }

        function setStarter(item, starter) {
            monitor.usage.starters = Object.assign({}, monitor.usage.starters, { [item]: Object.assign({ at: null, next: null, reason: null }, starter) });
        }

        function starterFor(row) {
            return StarterStates.starter(row, monitor.usage.createdAt);
        }

        function test_starterSwitch_data() {
            return [{ tag: "claude", item: "claude", label: "Start a new session when one ends" },
                    { tag: "codex", item: "codex", label: "Start a new week when one ends" }];
        }

        // The switch sits in the footer, left of the configure button, its
        // label the same in every state and its status under it: dim while
        // the starter holds as planned, full when something went wrong.
        function test_starterSwitch(data) {
            const popup = load(data.item);
            const toggle = starterSwitch(popup);
            const status = starterStatus(popup);
            verify(toggle && status);
            const button = configureButton(popup);
            verify(toggle.mapToItem(popup, Qt.point(0, 0)).y > popup.height / 2, "in the footer");
            // The rest of the footer's width, up to a gap before the button.
            fuzzyCompare(toggle.mapToItem(popup, Qt.point(toggle.width, 0)).x,
                         button.mapToItem(popup, Qt.point(0, 0)).x - Kirigami.Units.largeSpacing - Kirigami.Units.smallSpacing, 0.5);
            compare(toggle.mapToItem(popup, Qt.point(0, 0)).x, Math.round(Kirigami.Units.largeSpacing * 2), "on the readings' edge");
            compare(button.mapToItem(popup, Qt.point(button.width - button.rightPadding, 0)).x,
                    popup.width - Math.round(Kirigami.Units.largeSpacing * 2), "the icon on the readings' far edge");
            verify(status.mapToItem(popup, Qt.point(0, 0)).y >= toggle.mapToItem(popup, Qt.point(0, toggle.height)).y, "under the label");
            // The last line's baseline two large spacings above the popup's
            // edge, as the label's capitals are below the footer's rule.
            const lastBaseline = status.mapToItem(popup, Qt.point(0, status.height)).y - (status.height / 2 - status.baselineOffset);
            fuzzyCompare(popup.height - lastBaseline, Math.round(Kirigami.Units.largeSpacing * 2), 1);
            const texts = toggle.parent.texts;
            StarterStates.ROWS.filter(row => (row.only ?? data.item) === data.item).forEach(row => {
                const starter = starterFor(row);
                setStarter(data.item, starter);
                compare(toggle.text, data.label, row.state);
                compare(toggle.checked, row.enabled, row.state);
                compare(status.text, texts.starterStatus(data.item, starter, popup.nowMs), row.state);
                verify(status.text !== "", row.state);
                compare(String(status.color), String(row.failed ? Kirigami.Theme.textColor : Style.dim(Kirigami.Theme.textColor)), row.state);
                compare(toggle.Accessible.name, data.label, row.state);
                compare(toggle.Accessible.description, status.text, row.state);
                verify(status.Accessible.ignored, "read once, from the switch");
            });
        }

        function test_starterToggle_data() {
            return [{ tag: "sticks", sticks: true }, { tag: "refused", sticks: false }];
        }

        // A click asks the helper for the change and shows it at once; the
        // helper's report then decides, and a refused change snaps back.
        function test_starterToggle(data) {
            const usage = monitor.usage;
            usage.starterSticks = data.sticks;
            const popup = load("codex");
            const toggle = starterSwitch(popup);
            mouseClick(toggle);
            compare(usage.starterRequests, [["codex", true]]);
            verify(toggle.checked, "shown as asked while the helper runs");
            usage.answerStarter();
            compare(toggle.checked, data.sticks);
            compare(usage.starter("codex").enabled, data.sticks);
            // The switch still follows the reports after a click.
            setStarter("codex", { enabled: true, state: "waiting", next: usage.createdAt + 3600 });
            verify(toggle.checked);
            setStarter("codex", { enabled: false, state: "off" });
            verify(!toggle.checked);
            compare(usage.starterRequests.length, 1, "a report runs nothing");
        }

        // Tab reaches the switch, then the configure button; Space and Return
        // turn it.
        function test_starterKeyboard() {
            const popup = load("claude");
            const toggle = starterSwitch(popup);
            const button = configureButton(popup);
            verify(toggle.activeFocusOnTab && button.activeFocusOnTab);
            compare(toggle.nextItemInFocusChain(true), button);
            compare(button.nextItemInFocusChain(false), toggle);
            toggle.forceActiveFocus();
            keyClick(Qt.Key_Space);
            keyClick(Qt.Key_Return);
            compare(monitor.usage.starterRequests, [["claude", true], ["claude", false]]);
        }

        // The status takes the lines it says, with no room kept for a line
        // it doesn't have: in every state its last baseline sits as far from
        // the popup's edge as the switch's label is from the footer's rule,
        // and the switch stays where it is.
        function test_starterFooterIsEven_data() {
            return [{ tag: "claude", item: "claude" }, { tag: "codex", item: "codex" }];
        }

        function test_starterFooterIsEven(data) {
            const popup = load(data.item);
            const status = starterStatus(popup);
            const toggle = starterSwitch(popup);
            const switchY = toggle.mapToItem(popup, 0, 0).y;
            const heights = {};
            let lineHeight = NaN;
            // An unknown state says nothing, the shortest status there is.
            StarterStates.ROWS.concat([{ state: "later", enabled: true }]).forEach(row => {
                setStarter(data.item, starterFor(row));
                waitForRendering(popup);
                const tag = row.state + " " + (row.reason ?? "");
                verify(status.contentHeight <= status.height + 0.5, status.text);
                verify(status.height <= status.contentHeight + 0.5, "no empty line under the status: " + tag);
                lineHeight = status.contentHeight / status.lineCount;
                const lastBaseline = status.mapToItem(popup, 0, 0).y + status.baselineOffset + (status.lineCount - 1) * lineHeight;
                verify(Math.abs(popup.implicitHeight - lastBaseline - Math.round(Kirigami.Units.largeSpacing * 2)) <= 1,
                       tag + ": last baseline " + (popup.implicitHeight - lastBaseline) + " px from the edge");
                compare(toggle.mapToItem(popup, 0, 0).y, switchY, tag);
                heights[status.lineCount] = popup.implicitHeight;
            });
            verify(heights[1] !== undefined && heights[2] !== undefined, "statuses of one line and of two: " + Object.keys(heights));
            verify(Math.abs(heights[2] - heights[1] - lineHeight) <= 1,
                   "a second line adds one line: " + (heights[2] - heights[1]));
        }

        // A status too long for its two lines, such as one with a long
        // error, reads in full from a tool tip while the pointer is on the
        // status or the switch, or the switch has keyboard focus.
        function test_starterLongStatusHasAToolTip() {
            const popup = load("claude");
            const toggle = starterSwitch(popup);
            const status = starterStatus(popup);
            const tip = status.resources.find(r => r.delay !== undefined && r.text !== undefined);
            verify(tip);
            setStarter("claude", { enabled: true, state: "failed", reason: "not-installed" });
            waitForRendering(popup);
            verify(!status.truncated);
            mouseMove(status, 2, 2);
            wait(tip.delay + 200);
            verify(!tip.visible, "a status that fits needs none");

            const error = "The usage helper exited with code 1: PermissionError: [Errno 13] Permission denied: "
                        + "'/home/someone/.local/state/ringside/.starter.kvt5gezx.tmp'";
            setStarter("claude", { enabled: true, state: "failed", reason: "switch", error: error });
            waitForRendering(popup);
            verify(status.truncated);
            const full = toggle.parent.texts.starterStatus("claude", monitor.usage.starter("claude"), popup.nowMs);
            verify(full.endsWith(error));
            mouseMove(status, 3, 3);
            tryVerify(() => tip.visible, 5000);
            compare(tip.text, full);
            mouseMove(popup, 1, 1);
            tryVerify(() => !tip.visible, 5000);
            mouseMove(toggle, toggle.width / 2, toggle.height / 2);
            tryVerify(() => tip.visible, 5000);
            mouseMove(popup, 1, 1);
            tryVerify(() => !tip.visible, 5000);
            toggle.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => tip.visible, 5000);
        }

        function test_starterMirrors() {
            const popup = load("claude", true);
            const toggle = starterSwitch(popup);
            const status = starterStatus(popup);
            const right = i => i.mapToItem(popup, Qt.point(i.width, 0)).x;
            compare(right(toggle), popup.width - Math.round(Kirigami.Units.largeSpacing * 2), "on the readings' edge");
            verify(configureButton(popup).mapToItem(popup, Qt.point(0, 0)).x < toggle.mapToItem(popup, Qt.point(0, 0)).x);
            fuzzyCompare(right(status), right(toggle) - (toggle.leftPadding + toggle.indicator.width + toggle.spacing), 0.5);
            compare(status.effectiveHorizontalAlignment, Text.AlignRight);
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
            if (!data.drawn) {
                verify(!Number.isFinite(g.runOutAt));
                compare(g.runOutOpacity, 0, "no run-out drawn");
                verify(!g.timeShown);
                return;
            }
            compare(g.runOutOpacity, 1, "a run-out drawn");
            const said = popup.paces[data.said];
            compare(g.runOutX, Math.round(g.xAt(said.runOut)));
            compare(g.shownRunOutLevel, rows(popup)[data.said].level, "in its limit's level");
            const when = popup.runOutWhen(popup.limits[data.said], said);
            compare(g.runOutTime.text, when);
            verify(g.runOutTime.visible);
            verify(sentence(rows(popup)[data.said]).text.endsWith(" " + when), "the time the sentence gives");
        }

        function test_emptyHistory() {
            const usage = monitor.usage;
            setClaude({ weekly: usage.window(0, 6 * usage.day, []), scoped: [] });
            const g = graph(load("claude"));
            verify(g.placed);
            compare(g.mainPoints.length, 0);
            verify(!g.stale);
            verify(!Number.isFinite(g.runOutAt));
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

        // The session starter's status for each state, Claude and Codex, with
        // a time today and on another day. Times are on the clock the helper
        // gives the starter, New York's here: it is Tuesday 6 October 2026,
        // 10 PM there. Day -1 is 29 September.
        function test_starterStatus_data() {
            const T = (h, m) => ({ day: 6, h: h, m: m });
            const W = (h, m) => ({ day: 7, h: h, m: m });
            const F = (h, m) => ({ day: 9, h: h, m: m });
            const rows = (item, list) => list.map(r => ({ tag: item + ":" + r[0], item: item, starter: r[1], expected: r[2] }));
            const off = { enabled: false, state: "off" };
            return rows("claude", [
                ["off", off, ["When a session ends, Ringside sends Claude a one-word message to start the next one."]],
                ["waiting", { state: "waiting", next: T(23, 40) }, ["The next session starts at %1.", T(23, 40)]],
                ["waitingTomorrow", { state: "waiting", next: W(1, 46) }, ["The next session starts %1.", W(1, 46)]],
                ["confirming", { state: "confirming", at: T(23, 30), next: T(23, 35) },
                 ["Started a session at %1. Confirming at %2.", T(23, 30), T(23, 35)]],
                ["started", { state: "started", at: T(23, 30), next: W(4, 30) },
                 ["Started a session at %1. The next one starts %2.", T(23, 30), W(4, 30)]],
                // Claude's reset comes a second early; it reads to the minute.
                ["weekly", { state: "weekly", next: F(20, 33), early: 1 },
                 ["Weekly limit reached. The next session starts %1, when the limit resets.", F(20, 33)]],
                ["weeklyNextWeek", { state: "weekly", next: { day: 12, h: 23, m: 0 } },
                 ["Weekly limit reached. The next session starts %1, when the limit resets.", { day: 12, h: 23, m: 0 }]],
                ["notInstalled", { state: "failed", reason: "not-installed" }, ["Can't start a session: Claude Code isn't installed."]],
                ["signedOut", { state: "failed", reason: "signed-out" },
                 ["Can't start a session: Claude Code is signed out. Run claude in a terminal to sign in."]],
                ["notSubscription", { state: "failed", reason: "not-subscription" },
                 ["Can't start a session: Claude Code isn't signed in with a Claude subscription."]],
                ["notResponding", { state: "failed", reason: "not-responding", next: T(22, 5) },
                 ["Can't start a session: Claude Code isn't responding. Trying again at %1.", T(22, 5)]],
                ["notRespondingTomorrow", { state: "failed", reason: "not-responding", next: W(0, 0) },
                 ["Can't start a session: Claude Code isn't responding. Trying again %1.", W(0, 0)]],
                ["unchecked", { state: "failed", reason: "unchecked", next: T(22, 5) },
                 ["Couldn't check the limits. Trying again at %1.", T(22, 5)]],
                ["uncheckedTomorrow", { state: "failed", reason: "unchecked", next: W(0, 0) },
                 ["Couldn't check the limits. Trying again %1.", W(0, 0)]],
                ["notSent", { state: "failed", reason: "not-sent", next: T(22, 15) },
                 ["Couldn't start a session. Trying again at %1.", T(22, 15)]],
                ["retrying", { state: "retrying", at: T(23, 30), next: T(23, 35) },
                 ["Couldn't confirm the session started at %1. Trying once more at %2.", T(23, 30), T(23, 35)]],
                ["paused", { state: "paused", next: W(4, 35) }, ["Couldn't confirm two sessions in a row. Paused until %1.", W(4, 35)]],
                // The helper itself failed to run the start; the widget retries.
                ["startFailed", { state: "failed", reason: "helper", at: T(23, 30), next: T(23, 35), error: "The usage helper exited with code 1: boom" },
                 ["Couldn't start a session. Trying again at %1. The usage helper exited with code 1: boom", T(23, 35)]],
                ["startFailedTomorrow", { state: "failed", reason: "helper", at: T(23, 30), next: W(4, 35), error: "" },
                 ["Couldn't start a session. Trying again %1.", W(4, 35)]],
                ["pausedToday", { state: "paused", next: T(23, 55) }, ["Couldn't confirm two sessions in a row. Paused until %1.", T(23, 55)]],
                ["switchFailed", { state: "failed", reason: "switch", error: "The usage helper exited with code 1: boom" },
                 ["Couldn't change the switch: The usage helper exited with code 1: boom"]]
            ]).concat(rows("codex", [
                ["off", off, ["When a week ends, Ringside sends Codex a one-word message to start the next one."]],
                ["waiting", { state: "waiting", next: { day: 12, h: 3, m: 33 } }, ["The next week starts %1.", { day: 12, h: 3, m: 33 }]],
                // Six days or more away, the weekday comes with the date, as
                // it could be today's.
                ["waitingNextWeek", { state: "waiting", next: { day: 13, h: 3, m: 33 } }, ["The next week starts %1.", { day: 13, h: 3, m: 33 }]],
                ["startedLastWeek", { state: "started", at: { day: -1, h: 23, m: 30 } }, ["Started this week %1.", { day: -1, h: 23, m: 30 }]],
                ["waitingToday", { state: "waiting", next: T(23, 40) }, ["The next week starts at %1.", T(23, 40)]],
                ["confirming", { state: "confirming", at: T(23, 30), next: T(23, 35) },
                 ["Started a week at %1. Confirming at %2.", T(23, 30), T(23, 35)]],
                // The next start is the week's end, which the reset line gives.
                ["started", { state: "started", at: T(23, 30), next: { day: 13, h: 23, m: 30 } }, ["Started this week at %1.", T(23, 30)]],
                ["startedYesterday", { state: "started", at: { day: 5, h: 23, m: 30 } }, ["Started this week %1.", { day: 5, h: 23, m: 30 }]],
                ["weekly", { state: "weekly", next: F(2, 33) }, ["Weekly limit reached. The next week starts %1, when the limit resets.", F(2, 33)]],
                ["notInstalled", { state: "failed", reason: "not-installed" }, ["Can't start a week: Codex isn't installed."]],
                ["signedOut", { state: "failed", reason: "signed-out" },
                 ["Can't start a week: Codex is signed out. Run codex in a terminal to sign in."]],
                ["notResponding", { state: "failed", reason: "not-responding", next: T(22, 5) },
                 ["Can't start a week: Codex isn't responding. Trying again at %1.", T(22, 5)]],
                ["notRespondingTomorrow", { state: "failed", reason: "not-responding", next: W(0, 0) },
                 ["Can't start a week: Codex isn't responding. Trying again %1.", W(0, 0)]],
                ["unchecked", { state: "failed", reason: "unchecked", next: T(22, 5) },
                 ["Couldn't check the limits. Trying again at %1.", T(22, 5)]],
                ["uncheckedTomorrow", { state: "failed", reason: "unchecked", next: W(1, 0) },
                 ["Couldn't check the limits. Trying again %1.", W(1, 0)]],
                ["notSentTomorrow", { state: "failed", reason: "not-sent", next: W(0, 15) },
                 ["Couldn't start a week. Trying again %1.", W(0, 15)]],
                ["retrying", { state: "retrying", at: T(23, 30), next: W(0, 5) },
                 ["Couldn't confirm the week started at %1. Trying once more %2.", T(23, 30), W(0, 5)]],
                ["paused", { state: "paused", next: W(4, 35) }, ["Couldn't confirm two weeks in a row. Paused until %1.", W(4, 35)]],
                ["startFailed", { state: "failed", reason: "helper", at: T(23, 30), next: T(23, 35), error: "The usage helper exited with code 1: boom" },
                 ["Couldn't start a week. Trying again at %1. The usage helper exited with code 1: boom", T(23, 35)]],
                ["pausedToday", { state: "paused", next: T(23, 55) }, ["Couldn't confirm two weeks in a row. Paused until %1.", T(23, 55)]],
                ["switchFailed", { state: "failed", reason: "switch", error: "The usage helper exited with code 1: boom" },
                 ["Couldn't change the switch: The usage helper exited with code 1: boom"]]
            ]));
        }

        function test_starterStatus(data) {
            // New York's wall clock in October, four hours behind UTC.
            const epoch = t => Date.UTC(2026, 9, t.day, t.h + 4, t.m) / 1000;
            const now = epoch({ day: 6, h: 22, m: 0 });
            const starter = { enabled: data.starter.state !== "off", state: data.starter.state, reason: data.starter.reason ?? null,
                              error: data.starter.error ?? null, clockZone: { offset: -4 * 3600, abbreviation: "EDT" },
                              at: data.starter.at ? epoch(data.starter.at) : null,
                              next: data.starter.next ? epoch(data.starter.next) - (data.starter.early ?? 0) : null };
            // The expected time as the locale writes it: its time, after its
            // short day name on another day, and that after its short date
            // six days or more away.
            const spelled = t => {
                const date = new Date(2026, 9, t.day, t.h, t.m);
                const time = words.shortTime(date);
                const day = Qt.locale().dayName(date.getDay(), Locale.ShortFormat);
                return t.day === 6 ? time
                     : Math.abs(epoch(t) - now) < 6 * 86400 ? day + " " + time
                     : day + " " + date.toLocaleDateString(Qt.locale(), Locale.ShortFormat) + " " + time;
            };
            const [text, ...times] = data.expected;
            compare(words.starterStatus(data.item, starter, now * 1000), root.substitute(text, times.map(spelled)));
        }

        // Times and today are the starter's clock zone's, not system time's:
        // in a zone twelve hours from system time, the two disagree on which
        // day it is. Without a zone, they are system time's.
        function test_starterStatusOnTheStartersClock() {
            const base = Date.UTC(2026, 9, 6, 12, 0) / 1000;
            const systemOffset = -new Date(base * 1000).getTimezoneOffset() * 60;
            const zone = { offset: systemOffset + (systemOffset <= 0 ? 12 : -12) * 3600, abbreviation: "XYZ" };
            // An epoch whose wall clock in the zone reads October `day`, h:m.
            const at = (day, h, m) => Date.UTC(2026, 9, day, h, m) / 1000 - zone.offset;
            const time = (day, h, m) => words.shortTime(new Date(2026, 9, day, h, m));
            compare(words.starterStatus("claude", { state: "waiting", next: at(6, 23, 30), clockZone: zone }, at(6, 0, 30) * 1000),
                    "The next session starts at " + time(6, 23, 30) + ".");
            compare(words.starterStatus("claude", { state: "waiting", next: at(7, 0, 30), clockZone: zone }, at(6, 23, 30) * 1000),
                    "The next session starts " + Qt.locale().dayName(3, Locale.ShortFormat) + " " + time(7, 0, 30) + ".");
            const system = new Date(2026, 9, 6, 23, 30);
            compare(words.starterStatus("claude", { state: "waiting", next: system.getTime() / 1000 }, new Date(2026, 9, 6, 9, 0).getTime()),
                    "The next session starts at " + words.shortTime(system) + ".");
            // A week started on one side of a daylight saving change and
            // ending on the other: the start is shown in the zone at the start.
            const summer = { offset: zone.offset + 3600, abbreviation: "XYD" };
            const started = Date.UTC(2026, 9, 6, 9, 0) / 1000 - summer.offset;
            compare(words.starterStatus("codex", { state: "started", at: started, next: started + 7 * 86400 + 3601,
                                                   clockZone: zone, atClockZone: summer }, (started + 3600) * 1000),
                    "Started this week at " + time(6, 9, 0) + ".");
        }

        // Each status sentence has its own string for a time today and for
        // one on another day, with the weekday and time apart, so a language
        // can word the two its own way.
        function test_starterStatusTranslatesEachDay() {
            const now = new Date(2026, 9, 6, 22, 0);
            const today = new Date(2026, 9, 6, 23, 40);
            const wednesday = new Date(2026, 9, 7, 1, 46);
            root.translations = {
                "The next session starts at %1.": "Die nächste Sitzung beginnt um %1.",
                "The next session starts %1 %2.": "Die nächste Sitzung beginnt am %1 um %2."
            };
            try {
                compare(words.starterStatus("claude", { state: "waiting", next: today.getTime() / 1000 }, now.getTime()),
                        "Die nächste Sitzung beginnt um " + words.shortTime(today) + ".");
                compare(words.starterStatus("claude", { state: "waiting", next: wednesday.getTime() / 1000 }, now.getTime()),
                        "Die nächste Sitzung beginnt am " + Qt.locale().dayName(3, Locale.ShortFormat) + " um "
                        + words.shortTime(wednesday) + ".");
            } finally {
                root.translations = {};
            }
        }

        function test_starterStatusOfAnUnknownState() {
            compare(words.starterStatus("claude", { enabled: true, state: "failed", reason: "elsewhere" }, 0), "");
            compare(words.starterStatus("codex", { enabled: true, state: "failed", reason: "not-subscription" }, 0), "");
            compare(words.starterStatus("claude", { enabled: true, state: "later" }, 0), "");
            compare(words.starterStatus("claude", null, 0),
                    "When a session ends, Ringside sends Claude a one-word message to start the next one.");
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
                runOutText: o.runOutText ?? "",
                pollAt: o.at ?? NaN,
                nowMs: (o.now ?? o.at ?? start + day) * 1000
            });
        }

        function rule(g) {
            return root.find(g, i => i.limitY !== undefined);
        }

        // Where a percentage lands: 100 % on the rule, 0 % half a stroke
        // above the plot's bottom.
        function yOf(g, percent) {
            const top = rule(g).limitY;
            return top + (1 - percent / 100) * (g.plotHeight - 0.75 - top);
        }

        // The graph's own Rectangles, outside the rule.
        function rectangles(g) {
            return g.children.filter(i => i.radius !== undefined && i.visible);
        }

        function test_pointsSpanTheWindow() {
            const g = make([[start - 10, 5], [start, 0], [start + week / 2, 50], [start + week, 100], [start + week + 10, 7]]);
            compare(g.mainPoints.map(p => p.x), [0, 350, 700]);
            fuzzyCompare(g.mainPoints[0].y, g.plotHeight - 0.75, 1e-9);
            fuzzyCompare(g.mainPoints[1].y, yOf(g, 50), 1e-9);
            fuzzyCompare(g.mainPoints[2].y, rule(g).limitY, 1e-9);
            verify(rule(g).limitY >= 1.5, "room over 100 % for a line's stroke");
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

        // The frame, in the rule's colour: a floor across the whole width, a
        // short tick rising from it at each midnight on the clock the
        // popup's times are told in, and an edge at the reset from the rule
        // down to the floor, the lines meeting without overlapping.
        function test_frame_data() {
            return [{ tag: "systemTime", zoned: false }, { tag: "desktopClock", zoned: true }];
        }

        function test_frame(data) {
            const g = make([[start, 0], [start + day, 9]], { percent: 9, at: start + day });
            let offset = -new Date((start + week) * 1000).getTimezoneOffset() * 60;
            if (data.zoned) {
                // A zone a quarter hour off the hour, unlike system time's.
                offset = offset === 20700 ? 31500 : 20700;
                g.window = Object.assign({}, g.window, { clockZone: { offset: offset, abbreviation: "NPT" } });
            }
            const r = rule(g);
            const lines = rectangles(g).filter(i => String(i.color) === String(r.lineColor));
            const floor = lines.find(i => i.height === 1);
            verify(floor);
            compare([floor.x, floor.y, floor.width], [0, g.plotHeight - 1, g.width]);
            compare(floor.y, g.floorY);
            const edge = lines.find(i => i.width === 1 && i.x === g.width - 1);
            verify(edge);
            compare(edge.y, r.ruleY + 1);
            compare(edge.y + edge.height, floor.y);
            const ticks = lines.filter(i => i.width === 1 && i !== edge).sort((a, b) => a.x - b.x);
            const midnights = [];
            for (let t = (Math.floor((start + offset) / day) + 1) * day - offset; t < start + week; t += day) {
                midnights.push(Math.round((t - start) / week * g.width));
            }
            compare(midnights.length, 7);
            compare(ticks.map(t => t.x), midnights);
            ticks.forEach(t => {
                compare(t.y + t.height, floor.y);
                compare(t.height, Math.round(Kirigami.Units.smallSpacing / 2));
            });
        }

        // The run-out as drawn: the graph's own, not the last week's.
        function runOutOf(g) {
            return g.children.find(i => i.level !== undefined && i.label !== undefined);
        }

        function dashes(runOut) {
            return runOut.children.filter(i => i.radius !== undefined).sort((a, b) => a.y - b.y);
        }

        // Only for a limit on course to run out before the reset: a dashed
        // line from the rule to the floor at the moment it runs out, and the
        // pace sentence's time centred under the floor, inside the graph. It
        // takes its limit's level, as the limit's bar and ring do: the text
        // colour with the time dim below 75 %, amber from 75 and red from 90.
        function test_runOutOnlyWhenOut_data() {
            return [
                { tag: "out", percent: 60, at: start + 3 * day, runOut: start + 5 * day, level: 0 },
                { tag: "outAmber", percent: 80, at: start + 3 * day, runOut: start + 3 * day * 100 / 80, level: 1 },
                { tag: "outRed", percent: 95, at: start + 3 * day, runOut: start + 3 * day * 100 / 95, level: 2 },
                { tag: "nearTheReset", percent: 97, at: start + 6.75 * day, runOut: start + 6.75 * day * 100 / 97, level: 2, atTheEnd: true },
                { tag: "lasts", percent: 30, at: start + 3 * day },
                { tag: "reached", percent: 100, at: start + 3 * day },
                { tag: "tooEarlyToTell", percent: 5, at: start + 3 * 3600 },
                { tag: "resetPassed", percent: 60, at: start + 3 * day, now: start + week + 60 }
            ];
        }

        function test_runOutOnlyWhenOut(data) {
            const g = make([[start, 0], [data.at, data.percent]], Object.assign({ projected: "main", runOutText: "Fri 7:20 AM" }, data));
            const r = runOutOf(g);
            verify(r);
            if (data.runOut === undefined) {
                verify(!Number.isFinite(g.runOutAt));
                compare(g.runOutOpacity, 0);
                verify(!r.visible);
                verify(!g.timeShown);
                compare(g.foot, null);
                compare(g.implicitHeight, g.plotHeight, "no room kept for a time");
                return;
            }
            verify(r.visible);
            compare(g.runOutOpacity, 1);
            const x = Math.round((data.runOut - start) / week * g.width);
            compare(g.runOutX, x);
            const d = dashes(r);
            verify(d.length > 5, d.length + " dashes");
            d.forEach(i => fuzzyCompare(i.x + i.width / 2, x + 0.5, 1e-9));
            compare(d[0].y, rule(g).ruleY);
            const bottom = d[d.length - 1].y + d[d.length - 1].height;
            verify(bottom <= g.floorY && bottom > g.floorY - 3, "down to the floor: " + bottom);
            verify(d.every((i, n) => n === 0 || i.y > d[n - 1].y + d[n - 1].height), "dashed");
            const colour = [Kirigami.Theme.textColor, Kirigami.Theme.neutralTextColor, Kirigami.Theme.negativeTextColor][data.level];
            compare(g.shownRunOutLevel, data.level);
            d.forEach(i => compare(String(i.color), String(Qt.alpha(colour, 0.6 * colour.a))));
            const time = r.label;
            verify(time.visible);
            compare(time.text, "Fri 7:20 AM");
            compare(String(time.color), String(data.level === 0 ? Style.dim(Kirigami.Theme.textColor) : colour));
            verify(time.y >= g.floorY + 1, "under the floor");
            if (data.atTheEnd) {
                compare(time.x + time.implicitWidth, g.width, "kept inside the graph");
            } else {
                fuzzyCompare(time.x + time.implicitWidth / 2, x + 0.5, 0.5);
            }
            compare(g.foot, time);
            compare(g.implicitHeight, time.y + time.implicitHeight);
        }

        // With both limits on course to run out, only the named one's run-out
        // is drawn, in its own level; naming neither draws none.
        function test_onlyTheNamedRunOut_data() {
            return [{ tag: "main", runOut: start + 3 * day * 100 / 60, level: 0 },
                    { tag: "second", runOut: start + 3 * day * 100 / 80, level: 1 },
                    { tag: "none" }];
        }

        function test_onlyTheNamedRunOut(data) {
            const at = start + 3 * day;
            const g = make([[start, 0], [at, 60]], { percent: 60, at: at, projected: data.runOut ? data.tag : "" });
            g.secondWindow = { resetsAt: start + week, windowSeconds: week, percent: 80, history: [[start, 0], [at, 80]] };
            // A run-out the model's window brings fades in.
            tryCompare(g, "runOutOpacity", data.runOut === undefined ? 0 : 1, 1000);
            if (data.runOut === undefined) {
                verify(!Number.isFinite(g.runOutAt));
                verify(!runOutOf(g).visible);
                return;
            }
            verify(runOutOf(g).visible);
            compare(g.runOutX, Math.round((data.runOut - start) / week * g.width));
            compare(g.shownRunOutLevel, data.level);
        }

        function test_singleReadingIsADot() {
            const g = make([[start + day, 20]], { percent: 20, at: start + day });
            compare(g.mainPoints.length, 1);
            const dot = rectangles(g).find(i => i.radius > 0);
            verify(dot);
            const p = g.mainPoints[0];
            fuzzyCompare(dot.x + dot.width / 2, p.x, 1e-9);
            fuzzyCompare(dot.y + dot.height / 2, p.y, 1e-9);
            // A week that lasts, so no run-out either.
            const line = make([[start, 0], [start + day, 10]], { percent: 10, at: start + day, projected: "second" });
            verify(!rectangles(line).some(i => i.radius > 0), "a line has no dot");

            // The same for the model's limit, in its dashed line's colour.
            line.secondWindow = { resetsAt: start + week, windowSeconds: week, percent: 10, history: [[start + day, 10]] };
            verify(!Number.isFinite(line.runOutAt));
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
            const marker = rectangles(g).find(i => i.width === 1 && String(i.color) === String(Qt.alpha(g.color, 0.45 * g.color.a)));
            compare(marker !== undefined, data.stale);
            if (data.stale) {
                compare(marker.x, data.x(g));
                compare(marker.y, rule(g).ruleY + 1);
                compare(marker.y + marker.height, g.floorY);
            }
            verify(!make([], { percent: 0, at: now - data.age, now: now }).stale, "no line, nothing to mark");
        }

        // Time runs left to right in every language.
        function test_noMirroring() {
            const host = createTemporaryObject(mirroredGraph, root);
            const g = host.children[0];
            g.window = { resetsAt: start + week, windowSeconds: week, percent: 50,
                         history: [[start, 0], [start + week / 2, 50]] };
            verify(!g.LayoutMirroring.enabled);
            compare(g.mainPoints[0].x, 0);
        }
    }

    // A graph's span, "1 day", has its 1 in the locale's digits. It is
    // here as this suite runs in German and Egyptian Arabic too.
    TestCase {
        name: "SpanDigits"
        when: windowShown

        Component {
            id: spanComponent
            SpanButton {
                monitor: QtObject {
                    property string graphSpan: "day"
                }
            }
        }

        function test_theOneIsInTheLocalesDigits() {
            const span = createTemporaryObject(spanComponent, root);
            const one = Number(1).toLocaleString(Qt.locale(), "f", 0);
            compare(span.text, one + " day");
            compare(span.labels.minute, one + " min");
            compare(span.labels.hour, one + " h");
            compare(span.Accessible.name, "Graph span: " + one + " day");
            compare([span.names.minute, span.names.hour], [one + " minute", one + " hour"]);
        }
    }
}
