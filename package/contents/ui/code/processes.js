// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// The attributes to ask libksysguard's process model for, given the ones it
// offers. Its "memory" arrived in libksysguard 6.3; before that the list asks
// for the values it is picked from. The model drops an attribute it lacks but
// then lists it as offered, so the choice is made before asking.
function attributes(available) {
    const memory = available.includes("memory") ? ["memory"] : ["vmPSS", "vmURSS", "vmRSS"];
    return ["name", "usage"].concat(memory).filter(id => available.includes(id));
}

// One process from a row of the model's values, `columns` naming each by its
// attribute (the model's enabledAttributes, in column order). Memory arrives
// in KiB and leaves in bytes. Without "memory", it is picked the way
// libksysguard 6.3 picks it: proportional memory where readable, else
// private, else resident.
function reading(columns, values) {
    const value = id => Number(values[columns.indexOf(id)]);
    const memory = ["memory", "vmPSS", "vmURSS", "vmRSS"].map(value).find(kib => kib > 0) || 0;
    return { name: values[columns.indexOf("name")], usage: value("usage"), memory: memory * 1024 };
}

// The heaviest processes by `key` ("usage" or "memory"). Processes sharing a
// name (a browser's content processes, a compiler's jobs) add up to one row.
function top(rows, key, count) {
    const groups = new Map();
    for (const row of rows) {
        if (!row.name) {
            continue;
        }
        const group = groups.get(row.name) || { name: row.name, usage: 0, memory: 0, count: 0 };
        group.usage += Number.isFinite(row.usage) ? row.usage : 0;
        group.memory += Number.isFinite(row.memory) ? row.memory : 0;
        group.count += 1;
        groups.set(row.name, group);
    }
    return Array.from(groups.values())
        .filter(g => g[key] > 0)
        .sort((a, b) => b[key] - a[key] || a.name.localeCompare(b.name))
        .slice(0, count);
}
