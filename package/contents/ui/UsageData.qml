// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "code/items.js" as Items
import "code/limits.js" as Limits
import "code/report.js" as Report
import "code/reset.js" as Reset

// The Claude and Codex readings, from contents/code/usage.py run on a timer.
// Only the ids in `providers` are polled; with none, the helper never runs.
//
// A provider that answered or is signed out takes the new entry. One that
// failed keeps its last reading with lastError and lastErrorAt set, which
// marks its item with a dot; one that fails before its first reading gets
// no entry, so it stays hidden and the settings page says why from
// usageStatus.
//
// It also drives the opt-in session starter: the helper reports each
// provider's starter in every report, and the widget runs the helper with
// --start when one is due and with --starter-set when its switch is turned.
Item {
    id: usage

    // Plasmoid.configuration, or an object with the keys usageRefreshMinutes,
    // claudeInnerLimit, codexInnerLimit, knownLimits and usageStatus.
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

    // Known ids only, in a fixed order: the helper rejects an unknown one.
    readonly property var ids: Items.USAGE.filter(id => Array.from(usage.providers).includes(id))
    // Split by sh quoting rules, whether KProcess starts python3 itself or
    // hands the line to sh, so a quote in the install path is closed, escaped
    // and reopened. -B keeps Python from writing bytecode into the package.
    readonly property string command: helperCommand(ids, "")
    readonly property var innerChoices: ({ claude: config.claudeInnerLimit, codex: config.codexInnerLimit })
    // The last poll's status per id, as the settings page reads it.
    property var statuses: ({})
    // The session starter per id, as the last report gave it.
    property var starters: ({})
    // The switch positions asked for and not yet reported back, per id.
    property var starterWanted: ({})

    // Windows that just started over (see code/reset.js), sent before
    // `entries` changes so a ring can play the reset from its old reading.
    signal resetsDetected(var events)

    function entry(id) {
        return entries[id] ?? null;
    }

    function helperCommand(providerIds, args) {
        return providerIds.length > 0
            ? "python3 -B '" + helperPath.replace(/'/g, "'\\''") + "' --providers " + providerIds.join(",") + args : "";
    }

    function starter(id) {
        return starters[id] ?? null;
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
        writeStarter();
    }

    // One --starter-set at a time, so a quick on and off land in order.
    function writeStarter() {
        const id = Object.keys(starterWanted)[0];
        if (id !== undefined && !runner.connectedSources.some(s => s.includes(" --starter-set "))) {
            runner.connectSource(helperCommand(ids, " --starter-set " + id + "=" + (starterWanted[id] ? "on" : "off")));
        }
    }

    // Runs --start for the providers whose starter is due and whose switch
    // is on as the user last set it, never while one already runs (a send
    // can take minutes, and the helper holds its lock throughout) and never
    // while a switch change is being written, so a start the user just
    // turned off can't race the change. A change that lands calls this again.
    function startDue() {
        const busy = runner.connectedSources.some(s => s.endsWith(" --start") || s.includes(" --starter-set "));
        const now = Date.now() / 1000;
        const due = ids.filter(id => {
            const s = starters[id];
            return starterOn(id) && Number.isFinite(s?.next) && s.next <= now;
        });
        if (due.length > 0 && !busy) {
            runner.connectSource(helperCommand(due, " --start"));
        }
    }

    function present(id) {
        const e = entry(id);
        return e !== null && e.status !== "signed_out";
    }

    function degraded(id) {
        const e = entry(id);
        return e !== null && e.lastError !== undefined;
    }

    // The limit drawn inside the weekly ring, or null.
    function inner(id) {
        const e = entry(id);
        return e ? Limits.pick(e.scoped, config[id + "InnerLimit"]) : null;
    }

    function refresh() {
        if (command !== "" && !runner.connectedSources.includes(command)) {
            runner.connectSource(command);
        }
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
            latest[id] = { status: next.status, message: next.message ?? "" };
            if (next.status === "ok" || next.status === "signed_out") {
                merged[id] = next;
            } else if (was) {
                merged[id] = Object.assign({}, was, { lastError: next.message ?? next.status, lastErrorAt: at });
            }
        }
        const events = Reset.detect(entries, merged, at);
        if (Object.keys(events).length > 0) {
            resetsDetected(events);
        }
        entries = merged;
        statuses = latest;
        starters = starting;
        rememberLimits();
        writeStatus();
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
            // A switch change is settled by this run's report, or by its
            // failure, which leaves the switch where it was reported.
            const set = / --starter-set (\w+)=(on|off)$/.exec(source);
            const settled = set && usage.starterWanted[set[1]] === (set[2] === "on") ? set[1] : "";
            let report = null;
            try {
                report = JSON.parse(data.stdout);
            } catch (err) {
                report = null;
            }
            if (!report?.providers) {
                usage.helperError = usage.failureText(Report.helperFailure(data));
                usage.entries = Report.markFailed(usage.entries, usage.helperError, Math.floor(Date.now() / 1000));
                usage.writeStatus();
            } else {
                usage.helperError = "";
                usage.merge(report);
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
        interval: usage.config.usageRefreshMinutes * 60000
        running: usage.command !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: usage.refresh()
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
