// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Which GPU the outer ring shows and which the inner one does. Automatic puts
// a discrete GPU outside and an integrated one inside; with a single GPU
// there is one ring. A choice is a ksystemstats id ("gpu0"), "none", or ""
// for automatic.
function assignGpus(gpus, outerChoice, innerChoice) {
    const list = (gpus || []).map((g, i) => ({ g, i }))
        .sort((a, b) => (a.g.kind === "integrated") - (b.g.kind === "integrated") || a.i - b.i)
        .map(e => e.g);
    const byId = id => list.find(g => g.id === id) || null;
    let outer = outerChoice === "none" ? null : outerChoice ? byId(outerChoice) : list[0] || null;
    // With the outer ring turned off, automatic still means the GPU that
    // would sit inside, not the one the user just took away.
    const taken = outerChoice === "none" ? list[0] : outer;
    let inner = innerChoice === "none" ? null
              : innerChoice ? byId(innerChoice) : list.find(g => g !== taken) || null;
    if (inner && outer && inner.id === outer.id) {
        inner = null;
    }
    if (!outer && inner) {
        outer = inner;
        inner = null;
    }
    return { outer: outer, inner: inner };
}

// "zram", "disk" or "zram + disk" for the swap tile's caption.
function swapLabel(kinds) {
    return (kinds || []).join(" + ");
}

// Free and cached memory from ksystemstats' physical-memory readings, such
// that used, cached and free add up to the total (Monitor.qml says why).
// Free is MemFree, never more than "used" leaves; cached is the rest. A
// missing buffer reading counts as none; any other gives NaN.
function memoryParts(total, used, application, cache, buffer) {
    const free = Math.max(0, Math.min(total - application - cache - (buffer || 0), total - used));
    return { free: free, cached: total - used - free };
}

// What the GPU item shows of the two ring readers: a GPU that is asleep drops
// out, and the one still awake is shown alone, as on a single-GPU machine.
// With both asleep, or one GPU asleep, the outer one is shown, as "off".
function gpuView(outer, inner) {
    const outerAsleep = outer.phase === "asleep";
    const innerAsleep = inner.present && inner.phase === "asleep";
    return {
        primary: inner.present && outerAsleep && !innerAsleep ? inner : outer,
        dual: inner.present && !outerAsleep && !innerAsleep
    };
}
