// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Which weekly windows started over between two sets of entries, as
// "<provider>.weekly" or "<provider>.scoped.<id>" -> { from, early }.
//
// A window has started over when the provider moved its reset time out by
// more than MOVED_BY seconds, or when its percent fell by CLEARED_BY points or
// more: usage only climbs inside a window and polls are minutes apart, so a
// drop that size is a reset. A new window moves the reset by days; a reset
// time that jitters by a second or so between reports is the same window. The
// early flag picks the animation: it is set when the old reset time had not
// passed yet, meaning the provider cleared the allowance ahead of schedule.
// Scoped windows are matched by id, so a limit that appears, disappears or
// moves in the list never counts as a reset.
const CLEARED_BY = 20;
const MOVED_BY = 3600;

function detect(before, after, now) {
    const events = {};
    function compare(key, was, is) {
        if (!was || !is) {
            return;
        }
        if (is.resetsAt > was.resetsAt + MOVED_BY || is.percent <= was.percent - CLEARED_BY) {
            events[key] = { from: was.percent, early: was.resetsAt > now };
        }
    }
    for (const id of ["claude", "codex"]) {
        compare(id + ".weekly", before[id]?.weekly, after[id]?.weekly);
        const previous = before[id]?.scoped ?? [];
        for (const limit of after[id]?.scoped ?? []) {
            compare(id + ".scoped." + limit.id, previous.find(old => old.id === limit.id), limit);
        }
    }
    return events;
}
