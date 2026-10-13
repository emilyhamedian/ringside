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

// The attributes the GPU list asks for: each process's GPU usage, its video
// memory and which GPU it is on, from libksysguard's gpu plugin. Before
// libksysguard 6.4 the plugin read only NVIDIA GPUs and didn't say which,
// so without all three the list is left out.
function gpuAttributes(available) {
    const wanted = ["name", "gpu_usage", "gpu_memory", "gpu_module"];
    return wanted.every(id => available.includes(id)) ? wanted : [];
}

// One process's use of a GPU, as reading() does for the CPU. The GPU is
// named as ksystemstats names it.
function gpuReading(columns, values) {
    const value = id => values[columns.indexOf(id)];
    return {
        name: value("name"),
        usage: Number(value("gpu_usage")),
        memory: Number(value("gpu_memory")) * 1024,
        gpu: String(value("gpu_module") ?? "")
    };
}

// Processes sharing a name (a browser's content processes, a compiler's
// jobs) added up to one.
function grouped(rows) {
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
    return Array.from(groups.values());
}

// The heaviest processes by `key` ("usage" or "memory").
function top(rows, key, count) {
    return grouped(rows)
        .filter(g => g[key] > 0)
        .sort((a, b) => b[key] - a[key] || a.name.localeCompare(b.name))
        .slice(0, count);
}

// The processes using the GPU named `gpu`, busiest first. A process holding
// video memory while idle still counts, after the busy ones.
function topOnGpu(rows, gpu, count) {
    return grouped(rows.filter(row => row.gpu === gpu))
        .filter(g => g.usage > 0 || g.memory > 0)
        .sort((a, b) => b.usage - a.usage || b.memory - a.memory || a.name.localeCompare(b.name))
        .slice(0, count);
}
