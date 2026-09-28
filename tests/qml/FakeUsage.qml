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
    property var entries: ({
        claude: {
            status: "ok",
            fetchedAt: createdAt,
            weekly: window(62, 2 * day + 21 * 3600, [[6.9, 0], [6, 9], [5, 20], [4, 31], [3, 44], [2.2, 55], [0, 62]]),
            scoped: [Object.assign({ id: "Opus", label: "Opus" },
                                   window(78, 2 * day + 21 * 3600, [[6.9, 0], [5, 30], [3, 52], [0, 78]]))]
        },
        codex: {
            status: "ok",
            fetchedAt: createdAt,
            weekly: window(34, 5 * day + 4 * 3600, [[1.8, 0], [1, 14], [0, 34]]),
            scoped: []
        }
    })
    property string helperError: ""
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
}
