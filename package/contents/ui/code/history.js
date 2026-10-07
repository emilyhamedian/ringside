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
