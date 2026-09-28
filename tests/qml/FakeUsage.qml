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
    // quiet nights between them.
    property var entries: ({
        claude: {
            status: "ok",
            fetchedAt: createdAt,
            weekly: window(62, 2 * day + 21 * 3600, [[4.1, 0], [3.9, 5], [3.7, 11], [3.4, 12], [3, 12], [2.9, 19],
                                                     [2.7, 26], [2.4, 27], [2, 27], [1.9, 33], [1.7, 41], [1.4, 43],
                                                     [1, 43], [0.9, 50], [0.6, 57], [0.3, 60], [0, 62]]),
            scoped: [Object.assign({ id: "Opus", label: "Opus" },
                                   window(78, 2 * day + 21 * 3600, [[4.1, 0], [3.9, 7], [3.7, 14], [3.4, 15], [3, 15],
                                                                    [2.9, 24], [2.7, 33], [2.4, 34], [2, 34], [1.9, 42],
                                                                    [1.7, 52], [1.4, 55], [1, 55], [0.9, 64], [0.6, 73],
                                                                    [0.3, 76], [0, 78]]))]
        },
        codex: {
            status: "ok",
            fetchedAt: createdAt,
            weekly: window(34, 5 * day + 4 * 3600, [[1.8, 0], [1.5, 6], [1.2, 14], [0.9, 15], [0.5, 22], [0.2, 31], [0, 34]]),
            scoped: []
        }
    })
    property string helperError: ""
    // The last check's status per provider, as UsageData keeps them.
    property var statuses: ({ claude: { status: "ok", message: "" }, codex: { status: "ok", message: "" } })
    // Stands in for claudeInnerLimit and codexInnerLimit.
    property var innerChoices: ({ claude: "", codex: "" })

    readonly property bool claudePresent: present("claude")
    readonly property bool codexPresent: present("codex")

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

    function present(id) {
        const e = entry(id);
        return e !== null && e.status !== "signed_out";
    }

    function degraded(id) {
        const e = entry(id);
        return e !== null && e.lastError !== undefined;
    }

    function inner(id) {
        const e = entry(id);
        return e ? Limits.pick(e.scoped, innerChoices[id] ?? "") : null;
    }

    function refresh() {
    }
}
