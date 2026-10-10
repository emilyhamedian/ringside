// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "code/items.js" as Items
import "code/limits.js" as Limits
import "code/log.js" as Log
import "code/report.js" as Report
import "code/reset.js" as Reset

// The Claude and Codex readings, from contents/code/usage.py run on a timer.
// Only the ids in `providers` are polled; with none, the helper never runs.
//
// A provider that answered or is signed out takes the new entry. One that
// failed keeps its last reading with lastError, lastErrorAt, reason, host
// and retryAt set (see usage.py), which greys its item and then strikes it
// through. Until its first report a polled provider is loading, and shows
// as waiting; if that first check fails it gets an entry with the failure
// and no readings, so its item stays, struck. A provider stored as signed
// out skips the loading look, and like one that is never answered stays
// hidden, the settings page saying why from usageStatus.
//
// It also drives the opt-in session starter: the helper reports each
// provider's starter in every report, and the widget runs the helper with
// --start when one is due and with --starter-set when its switch is turned.
//
// Each run's report carries the helper's lines for the journal, which go
// there under ringside.usage, as does a helper run that gave no report.
Item {
    id: usage

    // Plasmoid.configuration, or an object with the keys usageRefreshMinutes,
    // claudeInnerLimit, codexInnerLimit, knownLimits and usageStatus, and
    // optionally claudeProgram and codexProgram.
    required property var config
    // Ids to poll, e.g. ["claude", "codex"].
    property var providers: []
    // The helper; the tests swap in a stub.
    property string helperPath: decodeURIComponent(Qt.resolvedUrl("../code/usage.py").toString()
                                                   .replace(/^file:\/\//, ""))
    // The merged entry per polled id, in the helper's shape (see usage.py).
    property var entries: ({})
    // Why the helper itself gave no report; empty once one arrives.
    property string helperError: ""
    // Bound to a bool, so they notify only when they flip, not on every poll.
    readonly property bool claudePresent: present("claude")
    readonly property bool codexPresent: present("codex")
    // Minutes between checks.
    readonly property int refreshMinutes: config.usageRefreshMinutes
    // A check is running, and when the timer's current interval started:
    // its last tick, or a change of interval, which starts it over. In
    // epoch seconds.
    property bool checking: false
    property real lastRun: NaN

    // Known ids only, in a fixed order: the helper rejects an unknown one.
    readonly property var ids: Items.USAGE.filter(id => Array.from(usage.providers).includes(id))
    // Split by sh quoting rules, whether KProcess starts python3 itself or
    // hands the line to sh, so the install path and each chosen program are
    // quoted (see quoted()). -B keeps Python from writing bytecode into the
    // package.
    readonly property string command: helperCommand(ids, "")
    // The claude and codex programs chosen in the settings; empty finds
    // them. Every run passes them, so choosing one checks it at once.
    readonly property var programs: ({ claude: String(config.claudeProgram ?? ""), codex: String(config.codexProgram ?? "") })
    readonly property var innerChoices: ({ claude: config.claudeInnerLimit, codex: config.codexInnerLimit })
    // The last poll's status per id, as the settings page reads it.
    property var statuses: ({})
    // The polled ids with a report, or a failure of a helper run that
    // polled them, since the widget started or they were turned on.
    property var answered: []
    // The session starter per id, as the last report gave it.
    property var starters: ({})
    // The switch positions asked for and not yet reported back, per id.
    property var starterWanted: ({})
    // Per id, the --start runs in a row that gave no report or left the
    // starter due: { count, at, retryAt, error, state }, state being the
    // starter's when it failed. Kept while reports show the starter on and
    // due, or in that state with next no later than the retry.
    property var startFailures: ({})
    // Per id, the switch change that didn't take: { on, error }. Shown
    // until the switch is turned again or reported where it was asked.
    property var switchFailures: ({})
    // The helper's own failure last written to the journal, so a failure
    // that repeats on every check is written once, and its end once.
    property string helperTrouble: ""

    LoggingCategory {
        id: journal
        name: "ringside.usage"
        defaultLogLevel: LoggingCategory.Info
    }

    // Windows that just started over (see code/reset.js), sent before
    // `entries` changes so a ring can play the reset from its old reading.
    signal resetsDetected(var events)

    function entry(id) {
        return entries[id] ?? null;
    }

    // Text as one sh word: in single quotes, where nothing is special, with
    // each quote in it closed, escaped and reopened.
    function quoted(text) {
        return "'" + text.replace(/'/g, "'\\''") + "'";
    }

    // The chosen programs come before --providers, so the patterns that
    // read a run's ids and mode from its end never meet a path.
    function helperCommand(providerIds, args) {
        return providerIds.length > 0
            ? "python3 -B " + quoted(helperPath)
              + providerIds.filter(id => programs[id]).map(id => " --program " + quoted(id + "=" + programs[id])).join("")
              + " --providers " + providerIds.join(",") + args : "";
    }

    // As reported; after a switch change the helper couldn't write, "failed"
    // with reason "switch" and its error; after a --start that failed or
    // left the starter due, "failed" with reason "helper", the error, and
    // next at the retry.
    function starter(id) {
        const s = starters[id] ?? null;
        const w = switchFailures[id];
        const f = startFailures[id];
        return s && w && s.enabled !== w.on ? Object.assign({}, s, { state: "failed", reason: "switch", error: w.error })
             : s && f ? Object.assign({}, s, { state: "failed", reason: "helper", at: f.at, next: f.retryAt, error: f.error })
             : s;
    }

    // Where the switch stands: as asked while the helper writes it, then as
    // reported, so a change that didn't stick snaps back.
    function starterOn(id) {
        return starterWanted[id] ?? starter(id)?.enabled === true;
    }

    function setStarter(id, on) {
        if (!ids.includes(id)) {
            return;
        }
        starterWanted = Object.assign({}, starterWanted, { [id]: on });
        if (switchFailures[id]) {
            const failures = Object.assign({}, switchFailures);
            delete failures[id];
            switchFailures = failures;
        }
        writeStarter();
    }

    // One --starter-set at a time, so a quick on and off land in order.
    function writeStarter() {
        const id = Object.keys(starterWanted)[0];
        if (id !== undefined && !runner.connectedSources.some(s => / --starter-set \w+=(on|off)$/.test(s))) {
            runner.connectSource(helperCommand(ids, " --starter-set " + id + "=" + (starterWanted[id] ? "on" : "off")));
        }
    }

    // Runs --start for the providers whose starter is due and whose switch
    // is on as the user last set it, never while one already runs (a send
    // can take minutes, and the helper holds its lock throughout) and never
    // while a switch change is being written, so a start the user just
    // turned off can't race the change. A change that lands calls this again.
    // A switch turned off while a --start runs is the helper's to catch: it
    // reads the switch again just before it sends.
    function startDue() {
        const busy = runner.connectedSources.some(s => s.endsWith(" --start") || / --starter-set \w+=(on|off)$/.test(s));
        const now = Date.now() / 1000;
        // A switch the user turned off and the helper couldn't write starts
        // nothing either, until it is turned again.
        const due = ids.filter(id => {
            const s = starter(id);
            return starterOn(id) && s?.reason !== "switch" && Number.isFinite(s?.next) && s.next <= now;
        });
        if (due.length > 0 && !busy) {
            runner.connectSource(helperCommand(due, " --start"));
        }
    }

    // A --start that gave no report retries after 5 minutes, doubling up to
    // the 5-hour session window, rather than on every tick: the failure may
    // repeat, and a helper that dies after sending would send again. The
    // readings it left untouched keep no failure.
    function startFailed(failedIds, error) {
        const now = Math.floor(Date.now() / 1000);
        const failures = Object.assign({}, startFailures);
        failedIds.forEach(id => {
            const count = (failures[id]?.count ?? 0) + 1;
            failures[id] = { count: count, at: now, retryAt: now + Math.min(300 * 2 ** (count - 1), 5 * 3600), error: error,
                             state: starters[id]?.state ?? null };
        });
        startFailures = failures;
    }

    // A --start that reported but left a starter due, or didn't report it,
    // would run again on every tick, so it backs off as a failed one does,
    // with what the helper said on stderr as the error.
    function startLeftDue(startedIds, error) {
        const now = Date.now() / 1000;
        const due = startedIds.filter(id => {
            const s = starters[id];
            return s?.enabled === true && Number.isFinite(s.next) && s.next <= now;
        });
        if (due.length > 0) {
            startFailed(due, error);
        }
    }

    function switchRefused(id, on, error) {
        switchFailures = Object.assign({}, switchFailures, { [id]: { on: on, error: error } });
    }

    // Polled, with no report yet, and not signed out when last stored.
    function loading(id) {
        if (!ids.includes(id) || answered.includes(id)) {
            return false;
        }
        try {
            return JSON.parse(config.usageStatus || "{}")[id]?.status !== "signed_out";
        } catch (err) {
            return true;
        }
    }

    function present(id) {
        const e = entry(id);
        return loading(id) || e !== null && e.status !== "signed_out";
    }

    function degraded(id) {
        const e = entry(id);
        return e !== null && e.lastError !== undefined;
    }

    // A failed check keeps the last reading, in grey, while it is under two
    // check intervals old and its week runs; after that the item is struck
    // through, and shows no reading until a check succeeds.
    function struck(id, nowMs) {
        const e = entry(id);
        const now = nowMs / 1000;
        return degraded(id) && !(e.weekly && e.weekly.resetsAt > now && now - e.fetchedAt < 2 * refreshMinutes * 60);
    }

    // The limit drawn inside the weekly ring, or null.
    function inner(id) {
        const e = entry(id);
        return e ? Limits.pick(e.scoped, config[id + "InnerLimit"]) : null;
    }

    function refresh() {
        if (command !== "" && !runner.connectedSources.includes(command)) {
            // Set first: a source the engine still holds answers at once.
            checking = true;
            runner.connectSource(command);
        }
    }

    // When the timer next runs the helper for a provider whose check
    // failed: the first tick once the helper's hold on it is over, since
    // the ticks before that only replay the failure. A hold set by the
    // check a tick ran ends a moment after the tick one hold later, and
    // counts as over by then. In epoch seconds.
    function nextCheck(id) {
        const e = entry(id);
        const step = refreshMinutes * 60;
        const hold = e && Number.isFinite(e.retryAt) ? e.retryAt : lastRun + step;
        return lastRun + Math.max(1, Math.ceil((hold - lastRun - 10) / step)) * step;
    }

    // Whether a failed check is worth trying again now: only once the
    // helper's hold is over, so it would really ask; not while a check
    // runs or with the next tick under a minute away; and never for a
    // helper that can't read its files or can't be started, or a Codex CLI
    // that isn't installed or a chosen one that can't run, which would only
    // fail again until the user acts, or one that found another check
    // holding its lock, which a click would only queue behind.
    function canRetry(id, nowMs) {
        const e = entry(id);
        const now = nowMs / 1000;
        return e !== null && e.lastError !== undefined && !["files", "missing", "not-installed", "program", "busy"].includes(e.reason)
            && !checking && now >= e.retryAt && nextCheck(id) - now > 60;
    }

    // Checks now, and counts the next interval from here: the timer's
    // start runs the check.
    function checkNow() {
        poller.restart();
    }

    // Forgets the ids no longer polled, and with none left the helper's
    // failure too.
    function forgetUnpolled() {
        const only = map => {
            const kept = {};
            ids.filter(id => map[id] !== undefined).forEach(id => { kept[id] = map[id]; });
            return kept;
        };
        if (Object.keys(entries).some(id => !ids.includes(id))) {
            entries = only(entries);
        }
        if (Object.keys(starters).some(id => !ids.includes(id))) {
            starters = only(starters);
        }
        if (Object.keys(starterWanted).some(id => !ids.includes(id))) {
            starterWanted = only(starterWanted);
        }
        if (Object.keys(startFailures).some(id => !ids.includes(id))) {
            startFailures = only(startFailures);
        }
        if (Object.keys(switchFailures).some(id => !ids.includes(id))) {
            switchFailures = only(switchFailures);
        }
        if (answered.some(id => !ids.includes(id))) {
            answered = answered.filter(id => ids.includes(id));
        }
        if (Object.keys(statuses).some(id => !ids.includes(id)) || ids.length === 0 && helperError !== "") {
            statuses = only(statuses);
            if (ids.length === 0) {
                helperError = "";
            }
            writeStatus();
        }
    }

    function merge(report) {
        const at = report.fetchedAt ?? Math.floor(Date.now() / 1000);
        const merged = {};
        const latest = {};
        const starting = Object.assign({}, starters);
        for (const id of ids) {
            const was = entries[id];
            const next = report.providers[id];
            if (next?.starter) {
                starting[id] = next.starter;
            }
            if (!next) {
                if (was) {
                    merged[id] = was;
                }
                if (statuses[id]) {
                    latest[id] = statuses[id];
                }
                continue;
            }
            // What the settings page needs of this check: whether the
            // program was found or can run, and whether the starter is
            // on, which is when Claude's program is needed.
            latest[id] = { status: next.status, message: next.message ?? "", program: next.program,
                           starter: next.starter?.enabled === true };
            if (next.status === "ok" || next.status === "signed_out") {
                merged[id] = next;
            } else if (was || loading(id)) {
                merged[id] = Object.assign({}, was ?? { status: next.status },
                                           { lastError: next.message ?? next.status, lastErrorAt: at,
                                             reason: next.reason ?? "other", host: next.host ?? "",
                                             retryAt: next.retryAt ?? at });
            }
        }
        const reported = ids.filter(id => report.providers[id] && !answered.includes(id));
        const events = Reset.detect(entries, merged, at);
        if (Object.keys(events).length > 0) {
            resetsDetected(events);
        }
        entries = merged;
        statuses = latest;
        if (reported.length > 0) {
            answered = answered.concat(reported);
        }
        // A failed start ends once the starter is off, moves to another
        // state or comes due after the retry. A starter still due, even at
        // a later time, as when the helper can't save its state and reports
        // every starter due at once, keeps its back-off. So does one the
        // helper claimed five minutes for before the --start died, which
        // reports its old state with that claim as next.
        const now = Date.now() / 1000;
        const failures = {};
        for (const id in startFailures) {
            const s = starting[id];
            const f = startFailures[id];
            if (s?.enabled && Number.isFinite(s.next) && (s.next <= now || s.state === f.state && s.next <= f.retryAt)) {
                failures[id] = f;
            }
        }
        starters = starting;
        startFailures = failures;
        rememberLimits();
        writeStatus();
    }

    // The helper's lines, as usage.py's event() made them.
    function writeEvents(events) {
        for (const e of Array.isArray(events) ? events : []) {
            if (["debug", "info", "warning"].includes(e?.level) && typeof e.message === "string") {
                Log.write(journal, e.level, e.message);
            }
        }
    }

    // A helper failure for the journal: what failed and, from the last
    // line of a traceback, only the error's name, since its message may
    // name anything the helper was handling.
    function troubleText(failure) {
        const error = /^([A-Za-z_][\w.]*)(?::|$)/.exec(failure.detail)?.[1];
        const text = failure.reason === "missing" ? "python3 was not found on the Plasma session's PATH"
                   : failure.reason === "crashed" ? "the usage helper crashed"
                   : failure.reason === "unreadable" ? "the usage helper's output couldn't be read"
                   : "the usage helper exited with code " + failure.code;
        return error ? text + " (" + error + ")" : text;
    }

    // A failed check run, written as a warning when it starts or changes,
    // and as debug while it repeats.
    function noteTrouble(text) {
        Log.write(journal, text === helperTrouble ? "debug" : "warning", text);
        helperTrouble = text;
    }

    function failureText(failure) {
        switch (failure.reason) {
        case "missing":
            return i18nc("@info", "python3 was not found on the Plasma session's PATH.");
        case "crashed":
            return failure.detail
                ? i18nc("@info %1 is the error the usage helper printed", "The usage helper stopped unexpectedly: %1", failure.detail)
                : i18nc("@info", "The usage helper stopped unexpectedly.");
        case "unreadable":
            return failure.detail
                ? i18nc("@info %1 is the error the usage helper printed", "The usage helper's output couldn't be read: %1", failure.detail)
                : i18nc("@info", "The usage helper's output couldn't be read.");
        }
        return failure.detail
            ? i18nc("@info %1 is an exit code, %2 the error the usage helper printed", "The usage helper exited with code %1: %2",
                    failure.code, failure.detail)
            : i18nc("@info %1 is an exit code", "The usage helper exited with code %1.", failure.code);
    }

    // What the settings page offers for the inner rings: refreshed with each
    // report and each change of choice, and written only when it changes.
    function rememberLimits() {
        let stored = {};
        try {
            stored = JSON.parse(config.knownLimits || "{}");
        } catch (err) {
            stored = {};
        }
        const known = JSON.stringify(Limits.known(entries, stored, innerChoices));
        if (config.knownLimits !== known) {
            config.knownLimits = known;
        }
    }

    function writeStatus() {
        const status = JSON.stringify(Object.assign({}, statuses, { helperError: helperError }));
        if (config.usageStatus !== status) {
            config.usageStatus = status;
        }
    }

    // Also sent while the widget starts; a choice made before any reading
    // has nothing to add to what is stored.
    onInnerChoicesChanged: {
        if (Object.keys(entries).length > 0) {
            rememberLimits();
        }
    }

    // A changed list polls at once; ids no longer polled go straight away.
    onCommandChanged: {
        forgetUnpolled();
        if (command !== "") {
            Qt.callLater(refresh);
        }
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            // The source may still be listed until this handler returns.
            usage.checking = connectedSources.some(s => s !== source && / --providers [\w,]+$/.test(s));
            // A switch change is settled by this run's report, or by its
            // failure, which leaves the switch where it was reported and,
            // like a failed --start, says so only under the switch. So does
            // a report that shows the switch unchanged with the reason the
            // helper couldn't write it on stderr; without one, another
            // widget's change came first, and that is no failure.
            const set = / --starter-set (\w+)=(on|off)$/.exec(source);
            const started = / --providers ([\w,]+) --start$/.exec(source);
            const settled = set && usage.starterWanted[set[1]] === (set[2] === "on") ? set[1] : "";
            let report = null;
            try {
                report = JSON.parse(data.stdout);
            } catch (err) {
                report = null;
            }
            usage.writeEvents(report?.events);
            if (!report?.providers && started) {
                const failure = Report.helperFailure(data);
                Log.write(journal, "warning", "the session starter run for " + started[1] + " failed: "
                          + usage.troubleText(failure));
                usage.startFailed(started[1].split(","), usage.failureText(failure));
            } else if (!report?.providers && set) {
                const failure = Report.helperFailure(data);
                Log.write(journal, "warning", "the " + set[1] + " session starter switch wasn't saved: "
                          + usage.troubleText(failure));
                if (settled) {
                    usage.switchRefused(settled, set[2] === "on", usage.failureText(failure));
                }
            } else if (!report?.providers) {
                const failure = Report.helperFailure(data);
                usage.noteTrouble(usage.troubleText(failure));
                usage.helperError = usage.failureText(failure);
                // A provider still loading that this run polled fails with
                // the rest; one that only another run polls waits for it.
                const polled = (/ --providers ([\w,]+)$/.exec(source)?.[1] ?? "").split(",");
                const first = usage.ids.filter(id => polled.includes(id) && usage.loading(id));
                const loaded = Object.assign({}, usage.entries);
                first.forEach(id => { loaded[id] = { status: "error" }; });
                usage.entries = Report.markFailed(loaded, usage.helperError, Math.floor(Date.now() / 1000),
                                                  Report.failureReason(failure));
                usage.answered = usage.answered.concat(first);
                usage.writeStatus();
            } else {
                if (usage.helperTrouble !== "") {
                    Log.write(journal, "info", "the usage helper reports again, after: " + usage.helperTrouble);
                    usage.helperTrouble = "";
                }
                usage.helperError = "";
                usage.merge(report);
                const reason = Report.helperFailure(data).detail;
                if (started) {
                    usage.startLeftDue(started[1].split(","), reason);
                }
                if (settled && reason !== "" && report.providers[settled]?.starter
                    && report.providers[settled].starter.enabled !== (set[2] === "on")) {
                    usage.switchRefused(settled, set[2] === "on", reason);
                }
            }
            if (settled) {
                const wanted = Object.assign({}, usage.starterWanted);
                delete wanted[settled];
                usage.starterWanted = wanted;
            }
            if (set) {
                usage.writeStarter();
                usage.startDue();
            }
        }
    }

    Timer {
        id: poller
        interval: usage.refreshMinutes * 60000
        running: usage.command !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            usage.lastRun = Date.now() / 1000;
            usage.refresh();
        }
        onIntervalChanged: usage.lastRun = Date.now() / 1000
    }

    // The poller counts time the machine is awake, so after a suspend its
    // tick is late by the wall clock that nextCheck() and canRetry() go by,
    // and the next check they give would lie in the past. While a check has
    // failed, and they are shown, a tick over a minute overdue runs at once
    // and the interval counts from there. It is the check that came due
    // during the suspend, so nothing is asked sooner than the interval
    // allows.
    Timer {
        interval: 60000
        running: usage.ids.some(id => usage.degraded(id))
        repeat: true
        onTriggered: {
            if (Date.now() / 1000 - usage.lastRun > usage.refreshMinutes * 60 + 60) {
                poller.restart();
            }
        }
    }

    // Due times are compared with the wall clock, so after a suspend the
    // next tick, at most 30 s after waking, starts what came due meanwhile.
    Timer {
        interval: 30000
        running: usage.ids.some(id => usage.starters[id]?.enabled === true && Number.isFinite(usage.starters[id].next))
        repeat: true
        onTriggered: usage.startDue()
    }
}
