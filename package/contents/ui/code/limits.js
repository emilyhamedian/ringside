// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library
.import "items.js" as Items

const POOL_PROVIDERS = ["claude", "codex", "kimi"];

// Model-specific weekly limits: which one a Claude or Codex ring draws inside
// its weekly arc, and what the settings page offers to choose from.
//
// A choice is "" for automatic, "none" for no inner ring, or a limit's id.

// The scoped limit a ring draws, or null for the all-models ring alone.
// Automatic shows the only limit a provider reports; with several, none until
// one is picked. A picked limit that is not reported shows none.
function pick(scoped, choice, preferFable = false) {
    if (!scoped || choice === "none") {
        return null;
    }
    const list = Array.from(scoped);
    if (!choice) {
        return (preferFable ? list.find(limit => limit.id.toLowerCase() === "fable") : null)
            ?? (list.length === 1 ? list[0] : null);
    }
    return list.find(limit => limit.id === choice)
        ?? (preferFable && choice.toLowerCase() === "fable 5" ? list.find(limit => limit.id === "Fable") : null)
        ?? null;
}

function pooled(entry) {
    return entry?.source === "cliproxyapi";
}

function allStale(entry) {
    const accounts = entry?.accounts ?? [];
    return pooled(entry) && accounts.some(account => account.state === "stale") && !accounts.some(account => account.state === "ok");
}

// A pool has separate reset clocks. Include the upcoming clocks of idle
// accounts as well, and never substitute the reset of a different period.
function nextReset(window, nowMs) {
    return Array.from(window?.resetTimes ?? []).reduce((next, at) =>
        Number.isFinite(at) && at > nowMs / 1000 && (!Number.isFinite(next) || at < next) ? at : next, NaN);
}

// Limits for the settings page, per provider: those in the latest good
// reading, plus a picked one that is no longer reported, so the page can
// still name it. A provider without a reading keeps what was stored.
function known(providers, stored, choices) {
    const result = {};
    for (const id of Items.USAGE) {
        const before = stored?.[id] ?? [];
        if (!providers?.[id]?.scoped) {
            result[id] = before;
            continue;
        }
        const scoped = Array.from(providers[id].scoped);
        const choice = choices?.[id] ?? "";
        const pinned = choice ? pick(scoped, choice, id === "claude" && pooled(providers[id])) : null;
        result[id] = scoped.map(limit => ({ id: pinned === limit ? choice : limit.id, label: limit.label, reported: true }));
        if (choice !== "" && choice !== "none" && !pinned) {
            const kept = before.find(limit => limit.id === choice);
            result[id].push({ id: choice, label: kept?.label ?? choice, reported: false });
        }
    }
    return result;
}
