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
// a missing sample ends one. Given `half`, a reading alone between gaps
// becomes a level stroke `half` either side of it (see spread()).
function runs(samples, points, half) {
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
    return half > 0 ? out.map(run => run.length > 1 ? run : spread(run[0], half)) : out;
}

// A lone point as a short level line, so an hour's or a day's bucket with
// gaps either side, a GPU awake for ten minutes say, reads as a mark rather
// than a speck.
function spread(point, half) {
    return [{ x: point.x - half, y: point.y }, { x: point.x + half, y: point.y }];
}

// How far either side of a lone point spread() draws it on a graph of
// `length` slots across `width`: its slot, and never less than 3 px across.
function loneHalf(length, width) {
    return Math.max(1.5, width / Math.max(1, length - 1) / 2);
}

// The faint band from a line up to the highest reading behind each of its
// points: an outline per unbroken stretch, along the highs and back along
// the line. `low` and `high` are the points of `values` and `highs`.
function bands(values, highs, low, high, half) {
    const out = [];
    let run = null;
    values.forEach((v, i) => {
        if (!Number.isFinite(v) || !Number.isFinite(highs[i])) {
            run = null;
        } else if (run === null) {
            run = [i];
            out.push(run);
        } else {
            run.push(i);
        }
    });
    return out.map(run => {
        if (run.length === 1) {
            const [top, bottom] = [high[run[0]], low[run[0]]];
            return [{ x: top.x - half, y: top.y }, { x: top.x + half, y: top.y },
                    { x: bottom.x + half, y: bottom.y }, { x: bottom.x - half, y: bottom.y }];
        }
        return run.map(i => high[i]).concat(run.slice().reverse().map(i => low[i]));
    });
}

// A temperature graph's floor: a round ten at least `margin` under the
// coolest reading rather than zero, since from zero a steady 45 °C would sit
// halfway up, where a change of a degree or two hardly shows. Given the
// floor it had, it keeps it while the coolest reading stays at least
// `margin` over it and under ten and two margins over it, so a reading that
// dips across a round number moves the line once rather than again as it
// leaves the graph's span. NaN with no reading.
function temperatureFloor(samples, margin, previous) {
    const coolest = samples.reduce((a, v) => Number.isFinite(v) ? Math.min(a, v) : a, Infinity);
    if (coolest === Infinity) {
        return NaN;
    }
    if (coolest >= previous + margin && coolest < previous + 10 + 2 * margin) {
        return previous;
    }
    return Math.floor((coolest - margin) / 10) * 10;
}

// A temperature graph's top: the hot threshold, so the line's height says
// how near hot it runs, or, when a reading runs hotter, the hottest rounded
// up to a five, so a new peak moves the top only once it passes the next
// five. With no threshold, -Infinity, it is the hottest rounded up.
function temperatureTop(samples, hot) {
    const hottest = samples.reduce((a, v) => Number.isFinite(v) ? Math.max(a, v) : a, -Infinity);
    return hottest > hot ? Math.ceil(hottest / 5) * 5 : hot;
}

// A temperature line cut where it crosses the warm and hot thresholds, so
// each piece takes one colour: [{ level, points }], level 0 under warm, 1
// from warm and 2 from hot, as Format.heat() has it. A crossing between two
// samples is placed where the line between them meets the threshold, and a
// missing sample ends a piece. Given `half`, a lone reading is spread as
// runs() spreads one.
function pieces(samples, points, warm, hot, half) {
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
    if (half > 0) {
        out.forEach(piece => {
            if (piece.points.length === 1) {
                piece.points = spread(piece.points[0], half);
            }
        });
    }
    return out;
}

// What a graph's top stands for: the highest reading behind each point
// where it has them, at an hour or a day, or else the points themselves.
function tops(values, highs) {
    return highs.length > 0 ? highs : values;
}

// The newest of the largest samples as { index, value }, or null when there
// are none. Gaps don't count.
function peak(samples) {
    let best = null;
    samples.forEach((v, i) => {
        if (Number.isFinite(v) && (best === null || v >= best.value)) {
            best = { index: i, value: v };
        }
    });
    return best;
}

// The spans a graph can show: the last minute reading by reading, and the
// last hour and day in buckets that follow the wall clock, 120 of 30
// seconds and 144 of 10 minutes, so each reads at about the minute's
// density. Every series records all three whichever is shown.
const SPANS = ["minute", "hour", "day"];
const TIERS = {
    hour: { period: 30, length: 120 },
    day: { period: 600, length: 144 }
};

// A series' record: the minute's readings, as push() or record() keep them,
// and a tier (see tier()) for the hour and one for the day.
function series() {
    return { minute: [], hour: tier("hour"), day: tier("day") };
}

// The hour's or the day's buckets: the average of each bucket's readings
// and the highest of them, oldest first and NaN for a bucket with none, and
// the open bucket's running sum, count and highest. `at` is the open
// bucket's number, the wall clock's seconds over the period, -1 before the
// first reading.
function tier(name) {
    const t = TIERS[name];
    return { period: t.period, length: t.length, at: -1, sum: 0, count: 0, high: -Infinity, means: [], highs: [] };
}

// Adds a reading taken at `nowMs` on the wall clock; a missing one only
// moves the clock on. The open bucket isn't drawn: it closes when a reading
// falls in a later one, and every bucket passed over meanwhile, while the
// machine slept, say, or the sample timer stopped, becomes a gap. A clock
// set back a little leaves the reading in the open bucket; set back
// further, the buckets now in its future go. Returns the bucket that
// closed as { at, mean, high }, or null.
function add(t, value, nowMs) {
    const at = Math.floor(nowMs / 1000 / t.period);
    let closed = null;
    if (t.at >= 0 && at > t.at) {
        closed = { at: t.at, mean: t.count > 0 ? t.sum / t.count : NaN, high: t.count > 0 ? t.high : NaN };
        const gap = Array(Math.min(at - t.at - 1, t.length)).fill(NaN);
        t.means = t.means.concat([closed.mean], gap).slice(-t.length);
        t.highs = t.highs.concat([closed.high], gap).slice(-t.length);
    } else if (t.at >= 0 && at < t.at - 1) {
        const keep = Math.max(0, t.means.length - (t.at - at));
        t.means = t.means.slice(0, keep);
        t.highs = t.highs.slice(0, keep);
    }
    if (t.at < 0 || at > t.at || at < t.at - 1) {
        t.at = at;
        t.sum = 0;
        t.count = 0;
        t.high = -Infinity;
    }
    if (typeof value === "number" && Number.isFinite(value)) {
        t.sum += value;
        t.count += 1;
        t.high = Math.max(t.high, value);
    }
    return closed;
}

// Fills an empty tier from saved buckets, [{ at, mean, high }], keeping
// those of the last `length` buckets before `nowMs`'s and leaving gaps
// where none was saved.
function restore(t, buckets, nowMs) {
    if (t.at >= 0) {
        return;
    }
    const now = Math.floor(nowMs / 1000 / t.period);
    const kept = buckets.filter(b => b.at >= now - t.length && b.at < now);
    t.at = now;
    if (kept.length === 0) {
        return;
    }
    const first = kept.reduce((a, b) => Math.min(a, b.at), now);
    t.means = Array(now - first).fill(NaN);
    t.highs = Array(now - first).fill(NaN);
    for (const b of kept) {
        t.means[b.at - first] = typeof b.mean === "number" ? b.mean : NaN;
        t.highs[b.at - first] = typeof b.high === "number" ? b.high : NaN;
    }
}

// An extent, [coolest, hottest] or [], taking in one more reading.
function widen(extent, v) {
    if (!Number.isFinite(v)) {
        return extent;
    }
    return extent.length === 0 ? [v, v] : [Math.min(extent[0], v), Math.max(extent[1], v)];
}

// The coolest and hottest readings a series keeps across the three spans,
// as [coolest, hottest], or [] with none: a temperature graph sets its
// scale from these, so it holds still when the span changes.
function extent(s) {
    let low = Infinity;
    let high = -Infinity;
    for (const list of [s.minute, s.hour.means, s.hour.highs, s.day.means, s.day.highs]) {
        for (const v of list) {
            if (Number.isFinite(v)) {
                low = Math.min(low, v);
                high = Math.max(high, v);
            }
        }
    }
    return low <= high ? [low, high] : [];
}
