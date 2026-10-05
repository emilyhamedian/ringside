// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Where a weekly limit is heading at the rate it has been used so far, for
// the panel's colours and the popup's pace sentence. Times are epoch seconds;
// the words are the popup's, since a .pragma library file can't translate.

// The projection of `percent`, read at `at`, in a window from `start` to
// `end`; `history` is the window's [epoch seconds, percent] points, oldest
// first. The state is one of:
//   "none"     nothing to say: no window or reading, or too early to tell
//   "reached"  the limit is used up; reachedAt is when, or NaN if unknown
//   "out"      at this rate the limit runs out at runOut, before the reset
//   "lasts"    it lasts to the reset, where it reaches atReset percent
function project(percent, start, end, at, history) {
    const result = { state: "none", runOut: NaN, atReset: NaN, reachedAt: NaN };
    if (!(end > start) || !Number.isFinite(percent) || !Number.isFinite(at)) {
        return result;
    }
    if (percent >= 100) {
        const first = Array.from(history ?? []).find(p => p[0] >= start && p[1] >= 100);
        result.state = "reached";
        result.reachedAt = first ? first[0] : NaN;
        return result;
    }
    const elapsed = Math.max(start, Math.min(end, at)) - start;
    // Under a day, or a seventh of a shorter window, a day and a night haven't
    // been averaged yet. The rate is taken over at least that long, so a
    // runaway first day still warns while a quiet one says nothing.
    const threshold = Math.min(86400, (end - start) / 7);
    const runOut = percent > 0 ? start + Math.max(elapsed, threshold) * 100 / percent : Infinity;
    // A run-out within a minute of the reset is the reset.
    if (runOut < end - 60) {
        result.state = "out";
        result.runOut = runOut;
    } else if (elapsed >= threshold) {
        result.state = "lasts";
        result.atReset = percent * (end - start) / elapsed;
    }
    return result;
}

// When an entry's percentages were read: its poll (a cached reading keeps its
// own), else the newest point in its week's history, else `now`. Projecting
// from the poll rather than from now keeps a stale reading from understating
// the rate.
function pollTime(entry, now) {
    if (entry && Number.isFinite(entry.fetchedAt)) {
        return entry.fetchedAt;
    }
    const history = entry && entry.weekly && entry.weekly.history ? Array.from(entry.weekly.history) : [];
    return history.length > 0 ? history[history.length - 1][0] : now;
}

// project() for a usage window read at `at`. Once its reset has passed by
// `now` the reading belongs to a week that is over, so there is nothing to say.
function ofWindow(window, at, now) {
    if (!window || !(window.resetsAt > now)) {
        return project(NaN, 0, 0, at, []);
    }
    return project(window.percent, window.resetsAt - window.windowSeconds, window.resetsAt, at, window.history);
}

// A projection's alert level, as Format.level() counts them: red when the
// limit is used up or on course to run out before the reset.
function alarm(p) {
    return p.state === "out" || p.state === "reached" ? 2 : 0;
}

// A level raised by the projection, never lowered by it.
function level(base, p) {
    return Math.max(base, alarm(p));
}
