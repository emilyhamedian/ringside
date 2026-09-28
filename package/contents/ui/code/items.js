// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// The items a widget can show and which of them are switched on.
//
// Claude and Codex are opt-in: they are on only while the stored order lists
// them and the hidden list doesn't. An order saved before they existed, or
// never saved at all, leaves them off, whatever the hidden list says. The
// settings page writes both lists whenever it saves either, so switching one
// on stores it in the order.

var KNOWN = ["cpu", "gpu", "memory", "network", "disk", "claude", "codex"];
var SYSTEM = ["cpu", "gpu", "memory", "network", "disk"];
var USAGE = ["claude", "codex"];

function isUsage(item) {
    return USAGE.includes(item);
}

function isRing(item) {
    return item === "cpu" || item === "gpu" || item === "memory" || isUsage(item);
}

// Every known item once, in the stored order, the rest after it.
function order(stored) {
    const list = Array.from(stored || []).filter((k, i, all) => KNOWN.includes(k) && all.indexOf(k) === i);
    return list.concat(KNOWN.filter(k => !list.includes(k)));
}

// The hidden list as it applies, with any opt-in item the order leaves out.
function hidden(storedOrder, storedHidden) {
    const listed = Array.from(storedOrder || []);
    const list = Array.from(storedHidden || []).filter((k, i, all) => KNOWN.includes(k) && all.indexOf(k) === i);
    return list.concat(USAGE.filter(k => !listed.includes(k) && !list.includes(k)));
}

// The items switched on, in order. Whether each has something to show (a
// GPU, a signed-in CLI) is the caller's to check.
function enabled(storedOrder, storedHidden) {
    const off = hidden(storedOrder, storedHidden);
    return order(storedOrder).filter(k => !off.includes(k));
}
