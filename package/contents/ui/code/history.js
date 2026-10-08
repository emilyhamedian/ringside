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

// Like push(), but a missing reading stays NaN, which a temperature graph
// leaves as a gap: a sleeping GPU has no temperature, and 0 would read as one.
function record(samples, value, length) {
    const keep = Math.max(0, length - 1);
    const next = samples.length > keep ? samples.slice(samples.length - keep) : samples.slice();
    next.push(typeof value === "number" && Number.isFinite(value) ? value : NaN);
    return next;
}

// Points for a graph of `length` slots. The newest sample sits at the right
// edge, so a history that hasn't filled yet grows in from the right. `max`
// maps to `top` pixels down and `min`, 0 unless given, to 0.75 px above the
// bottom, half a 1.5 px stroke each, so a line along either edge isn't half
// clipped. A missing sample's point has a NaN y.
function points(samples, length, width, height, max, top, min) {
    const slots = Math.max(2, length);
    const step = width / (slots - 1);
    const bottom = min ?? 0;
    const scale = max - bottom > 0 ? max - bottom : 1;
    const inset = top ?? 0.75;
    const first = slots - samples.length;
    return samples.map((v, i) => ({
        x: (first + i) * step,
        y: inset + (1 - Math.max(0, Math.min(1, (v - bottom) / scale))) * (height - inset - 0.75)
    }));
}

// The unbroken stretches of a line, as arrays of `points` (see points()):
// a missing sample ends one.
function runs(samples, points) {
    const out = [];
    let current = null;
    samples.forEach((v, i) => {
        if (!Number.isFinite(v)) {
            current = null;
        } else if (current === null) {
            current = [points[i]];
            out.push(current);
        } else {
            current.push(points[i]);
        }
    });
    return out;
}

// A temperature graph's scale, { low, high }, in the samples' unit. The top
// is the hot threshold, so the line's height says how near hot it runs, or
// a round five over the peak when the line runs hotter, so it is never cut
// off. The floor is a round ten at least `margin` under the coolest reading
// rather than zero: from zero a steady 45 °C would sit halfway up, where a
// change of a degree or two hardly shows. Round ends keep the scale, and the
// caption naming it, still while the readings wander.
function temperatureScale(samples, hot, margin) {
    const readings = samples.filter(v => Number.isFinite(v));
    const coolest = readings.reduce((a, b) => Math.min(a, b), hot);
    const peak = readings.reduce((a, b) => Math.max(a, b), -Infinity);
    return { low: Math.floor((coolest - margin) / 10) * 10, high: peak > hot ? Math.ceil(peak / 5) * 5 : hot };
}

// A temperature line cut where it crosses the warm and hot thresholds, so
// each piece takes one colour: [{ level, points }], level 0 under warm, 1
// from warm and 2 from hot, as Format.heat() has it. A crossing between two
// samples is placed where the line between them meets the threshold, and a
// missing sample ends a piece.
function pieces(samples, points, warm, hot) {
    const thresholds = [warm, hot];
    const level = v => v >= hot ? 2 : v >= warm ? 1 : 0;
    const out = [];
    let current = null;
    samples.forEach((v, i) => {
        if (!Number.isFinite(v)) {
            current = null;
            return;
        }
        if (current === null) {
            current = { level: level(v), points: [points[i]] };
            out.push(current);
            return;
        }
        const u = samples[i - 1];
        const from = points[i - 1];
        const to = points[i];
        for (let l = level(u), step = Math.sign(level(v) - l); l !== level(v); l += step) {
            const f = (thresholds[step > 0 ? l : l - 1] - u) / (v - u);
            const at = { x: from.x + f * (to.x - from.x), y: from.y + f * (to.y - from.y) };
            current.points.push(at);
            current = { level: l + step, points: [at] };
            out.push(current);
        }
        current.points.push(to);
    });
    return out;
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
