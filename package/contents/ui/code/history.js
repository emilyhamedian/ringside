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
// edge, so a history that hasn't filled yet grows in from the right.
function points(samples, length, width, height, max) {
    const slots = Math.max(2, length);
    const step = width / (slots - 1);
    const top = max > 0 ? max : 1;
    const first = slots - samples.length;
    return samples.map((v, i) => ({
        x: (first + i) * step,
        y: height - Math.max(0, Math.min(1, v / top)) * height
    }));
}

// Upper bound for graphs without a natural maximum (throughput): the peak
// in view rounded up to 1, 2 or 5 times a power of ten, and never below floor.
function niceMax(samples, floor) {
    const peak = samples.reduce((m, v) => Math.max(m, v), floor);
    const magnitude = 10 ** Math.floor(Math.log10(peak));
    for (const f of [1, 2, 5, 10]) {
        if (peak <= f * magnitude) {
            return f * magnitude;
        }
    }
    return 10 * magnitude;
}
