// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import "../../package/contents/ui/code/limits.js" as Limits

// Fixed Claude and Codex readings in the shape of UsageData.qml, for the
// tests and the preview gallery: every property, signal and function the
// views read. Times are relative to when it was created, so the countdowns
// read the same on every run.
QtObject {
    id: usage

    readonly property real createdAt: Math.floor(Date.now() / 1000)
    readonly property int day: 86400

    // Entries as the helper reports them (see code/usage.py), after merging.
    // Each window's history starts when the window did: days of use with
    // quiet nights between them. At these rates Claude's week and Codex's
    // last to their resets and the Fable limit runs out before its own.
    property var entries: ({
        claude: {
            status: "ok",
            fetchedAt: createdAt,
            weekly: window(52, 2 * day + 21 * 3600, [[4.1, 0], [3.9, 4], [3.7, 9], [3.4, 10], [3, 10], [2.9, 16],
                                                     [2.7, 22], [2.4, 23], [2, 23], [1.9, 28], [1.7, 34], [1.4, 36],
                                                     [1, 36], [0.9, 42], [0.6, 48], [0.3, 50], [0, 52]]),
            scoped: [Object.assign({ id: "Fable", label: "Fable" },
                                   window(78, 2 * day + 21 * 3600, [[4.1, 0], [3.9, 7], [3.7, 14], [3.4, 15], [3, 15],
                                                                    [2.9, 24], [2.7, 33], [2.4, 34], [2, 34], [1.9, 42],
                                                                    [1.7, 52], [1.4, 55], [1, 55], [0.9, 64], [0.6, 73],
                                                                    [0.3, 76], [0, 78]]))]
        },
        codex: {
            status: "ok",
            fetchedAt: createdAt,
            weekly: window(24, 5 * day + 4 * 3600, [[1.8, 0], [1.5, 4], [1.2, 10], [0.9, 11], [0.5, 16], [0.2, 22], [0, 24]]),
            scoped: []
        }
    })
    property string helperError: ""
    // The last check's status per provider, as UsageData keeps them.
    property var statuses: ({ claude: { status: "ok", message: "" }, codex: { status: "ok", message: "" } })
    // Stands in for claudeInnerLimit and codexInnerLimit.
    property var innerChoices: ({ claude: "", codex: "" })
    // The session starter per provider, as the helper reports it.
    property var starters: ({
        claude: { enabled: false, state: "off", at: null, next: null, reason: null },
        codex: { enabled: false, state: "off", at: null, next: null, reason: null }
    })
    property var starterWanted: ({})
    // Whether answerStarter() reports the switch changes asked for, or
    // the switch positions as they were.
    property bool starterSticks: true
    // Every setStarter() call, as [id, on].
    property var starterRequests: []
    // Ids with no report yet, which show as loading until they have an
    // entry, as UsageData's do until their first report.
    property var pending: []

    readonly property bool claudePresent: present("claude")
    readonly property bool codexPresent: present("codex")
    property int refreshMinutes: 5
    property bool checking: false
    // The timer's last tick, a minute before creation.
    property real lastRun: createdAt - 60
    // Every checkNow() call.
    property int checks: 0

    signal resetsDetected(var events)

    // A weekly window resetting `left` seconds after creation, with history
    // points given as [days before creation, percent].
    function window(percent, left, points) {
        return {
            percent: percent,
            resetsAt: createdAt + left,
            windowSeconds: 7 * day,
            clockZone: { offset: -4 * 3600, abbreviation: "EDT" },
            history: points.map(p => [createdAt - Math.round(p[0] * day), p[1]])
        };
    }

    function entry(id) {
        return entries[id] ?? null;
    }

    function loading(id) {
        return pending.includes(id) && entry(id) === null;
    }

    function present(id) {
        const e = entry(id);
        return loading(id) || e !== null && e.status !== "signed_out";
    }

    function degraded(id) {
        const e = entry(id);
        return e !== null && e.lastError !== undefined;
    }

    // As UsageData's.
    function struck(id, nowMs) {
        const e = entry(id);
        const now = nowMs / 1000;
        return degraded(id) && !(e.weekly && e.weekly.resetsAt > now && now - e.fetchedAt < 2 * refreshMinutes * 60);
    }

    function inner(id) {
        const e = entry(id);
        return e ? Limits.pick(e.scoped, innerChoices[id] ?? "") : null;
    }

    function refresh() {
    }

    // As UsageData's.
    function nextCheck(id) {
        const e = entry(id);
        const step = refreshMinutes * 60;
        const hold = e && Number.isFinite(e.retryAt) ? e.retryAt : lastRun + step;
        return lastRun + Math.max(1, Math.ceil((hold - lastRun - 10) / step)) * step;
    }

    function canRetry(id, nowMs) {
        const e = entry(id);
        const now = nowMs / 1000;
        return e !== null && e.lastError !== undefined && !["files", "missing", "not-installed", "program", "busy"].includes(e.reason)
            && !checking && now >= e.retryAt && nextCheck(id) - now > 60;
    }

    function checkNow() {
        ++checks;
        checking = true;
    }

    function starter(id) {
        return starters[id] ?? null;
    }

    function starterOn(id) {
        return starterWanted[id] ?? starter(id)?.enabled === true;
    }

    function setStarter(id, on) {
        starterRequests = starterRequests.concat([[id, on]]);
        starterWanted = Object.assign({}, starterWanted, { [id]: on });
    }

    // Stands in for the helper's report after --starter-set: a starter just
    // switched on is due at once.
    function answerStarter() {
        const next = Object.assign({}, starters);
        if (starterSticks) {
            for (const id in starterWanted) {
                next[id] = { enabled: starterWanted[id], state: starterWanted[id] ? "waiting" : "off",
                             at: null, next: starterWanted[id] ? Math.floor(Date.now() / 1000) : null, reason: null };
            }
        }
        starters = next;
        starterWanted = {};
    }
}
