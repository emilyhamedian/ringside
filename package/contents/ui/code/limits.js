// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Model-specific weekly limits: which one a Claude or Codex ring draws inside
// its weekly arc, and what the settings page offers to choose from.
//
// A choice is "" for automatic, "none" for no inner ring, or a limit's id.

const PROVIDERS = ["claude", "codex"];

// The scoped limit a ring draws, or null for the all-models ring alone.
// Automatic shows the only limit a provider reports; with several, none until
// one is picked. A picked limit that is not reported shows none.
function pick(scoped, choice) {
    if (!scoped || choice === "none") {
        return null;
    }
    const list = Array.from(scoped);
    if (!choice) {
        return list.length === 1 ? list[0] : null;
    }
    return list.find(limit => limit.id === choice) ?? null;
}

// Limits for the settings page, per provider: those in the latest good
// reading, plus a picked one that is no longer reported, so the page can
// still name it. A provider without a reading keeps what was stored.
function known(providers, stored, choices) {
    const result = {};
    for (const id of PROVIDERS) {
        const before = stored?.[id] ?? [];
        if (!providers?.[id]?.scoped) {
            result[id] = before;
            continue;
        }
        const scoped = Array.from(providers[id].scoped);
        result[id] = scoped.map(limit => ({ id: limit.id, label: limit.label, reported: true }));
        const choice = choices?.[id] ?? "";
        if (choice !== "" && choice !== "none" && !scoped.some(limit => limit.id === choice)) {
            const kept = before.find(limit => limit.id === choice);
            result[id].push({ id: choice, label: kept?.label ?? choice, reported: false });
        }
    }
    return result;
}
