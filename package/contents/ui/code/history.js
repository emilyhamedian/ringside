// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Sample histories are plain arrays, oldest first. Each change makes a new
// array so bindings on it re-evaluate.

function push(samples, value, length) {
    const keep = Math.max(0, length - 1);
    const next = samples.length > keep ? samples.slice(samples.length - keep) : samples.slice();
    next.push(typeof value === "number" && Number.isFinite(value) ? value : 0);
    return next;
}

// Points for a graph of `length` slots. The newest sample sits at the right
// edge, so a history that hasn't filled yet grows in from the right. `max`
// maps to `top` pixels down and 0 to 0.75 px above the bottom, half a 1.5 px
// stroke each, so a line along either edge isn't half clipped.
function points(samples, length, width, height, max, top) {
    const slots = Math.max(2, length);
    const step = width / (slots - 1);
    const scale = max > 0 ? max : 1;
    const inset = top ?? 0.75;
    const first = slots - samples.length;
    return samples.map((v, i) => ({
        x: (first + i) * step,
        y: inset + (1 - Math.max(0, Math.min(1, v / scale))) * (height - inset - 0.75)
    }));
}

// Whether `after` is `before` with one sample pushed, as push() makes it:
// { dropped } with the sample that fell off the left, undefined while the
// history grows in, or null for any other change.
function arrival(before, after, length) {
    const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
    if (!before || !after || before.length === 0) {
        return null;
    }
    if (after.length === before.length + 1 && same(after.slice(0, -1), before)) {
        return { dropped: undefined };
    }
    if (after.length === before.length && before.length >= Math.max(1, length) && same(after.slice(0, -1), before.slice(1))) {
        return { dropped: before[0] };
    }
    return null;
}

// The newest of the largest samples as { index, value }, or null when there
// are none.
function peak(samples) {
    let best = null;
    samples.forEach((v, i) => {
        if (best === null || v >= best.value) {
            best = { index: i, value: v };
        }
    });
    return best;
}
