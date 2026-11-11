// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Whether a Claude or Codex ring is draining, which is when it pulses: its
// weekly percentage climbed, or its credit balance fell, between the last two
// checks. Each check that reports on a provider gives { at, weekly, credit },
// at being when it reported, in epoch seconds.

// A check's finding stands until the next check is due: one interval later,
// with a minute's grace. A check later than that, as after a suspend, says
// nothing about what is being spent now, and nor does the one before it.
function recent(at, refreshMinutes, now) {
    return Number.isFinite(at) && at <= now && now - at <= refreshMinutes * 60 + 60;
}

// The drain after a check, from the one before it (`last`, undefined for the
// first) and the readings either side: the entries and the credit records as
// UsageData keeps them. A first check, one after a failed check and one after
// a suspend have nothing to compare with. A check answered from the helper's
// five-minute cache brings the same reading back, and keeps what the check
// that took it found.
function step(last, before, after, creditBefore, creditAfter, refreshMinutes, now) {
    const paired = last !== undefined && recent(last.at, refreshMinutes, now);
    const read = e => e?.status === "ok" && e.lastError === undefined;
    return {
        at: now,
        weekly: paired && read(before) && read(after)
            && (after.fetchedAt === before.fetchedAt ? last.weekly === true : climbed(before.weekly, after.weekly)),
        credit: paired && creditBefore?.status === "ok" && creditAfter?.status === "ok"
            && (creditAfter.fetchedAt === creditBefore.fetchedAt ? last.credit === true
                                                                 : fell(creditBefore.balance, creditAfter.balance))
    };
}

// Whether the provider's `kind` ("weekly" or "credit") drained by the last
// check, while that check is recent.
function active(drain, kind, refreshMinutes, now) {
    return drain?.[kind] === true && recent(drain.at, refreshMinutes, now);
}

// The weekly percentage rose in the same window. Percentages are whole and
// coarse, so use that leaves the whole number where it was, as when it rounds
// down to it, counts as none. A reset moved out by over an hour is a new
// window, as code/reset.js reads it.
function climbed(before, after) {
    return Number.isFinite(before?.percent) && Number.isFinite(after?.percent) && after.percent > before.percent
        && !(after.resetsAt > before.resetsAt + 3600);
}

// The balance fell in the same currency and scale. A top-up, or a balance
// given in other units, is no sign of use.
function fell(before, after) {
    const valid = b => typeof b?.amount === "number" && Number.isFinite(b.amount) && b.amount > 0;
    return valid(before) && valid(after) && after.currency === before.currency && after.precision === before.precision
        && after.amount < before.amount;
}
