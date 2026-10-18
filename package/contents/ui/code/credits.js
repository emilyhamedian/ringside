// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// A falling balance is evidence since the previous check, not live activity.
// Only exact exhausted flags from the provider count; a rounded 100% does not.
function used(entry, credit, refreshMinutes, nowMs) {
    const now = nowMs / 1000;
    const age = 2 * Math.max(5, refreshMinutes) * 60;
    const fresh = at => typeof at === "number" && Number.isFinite(at) && at > 0 && at <= now && now - at <= age;
    if (!entry?.weekly || entry.status !== "ok" || entry.lastError !== undefined || !fresh(entry.fetchedAt)
        || credit?.status !== "ok" || credit.spent !== true || !fresh(credit.fetchedAt)
        || typeof credit.balance?.amount !== "number" || !Number.isFinite(credit.balance.amount) || credit.balance.amount <= 0) {
        return false;
    }
    const exhausted = window => window?.exhausted === true && Number.isFinite(window.percent)
        && Number.isFinite(window.resetsAt) && window.resetsAt > now;
    return exhausted(entry.weekly) || exhausted(entry.session)
        || (Array.isArray(entry.scoped) && entry.scoped.some(exhausted));
}
