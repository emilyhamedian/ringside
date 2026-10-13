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

// The attributes an NVIDIA GPU's list asks for: each process's GPU usage, its
// video memory and which GPU it is on, from libksysguard's gpu plugin, which
// reads them with nvidia-smi. Before libksysguard 6.4 the plugin didn't say
// which GPU, so without all three the list is left out.
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
        const group = groups.get(row.name) || { name: row.name, usage: 0, memory: 0, count: 0, counted: 0 };
        group.usage += Number.isFinite(row.usage) ? row.usage : 0;
        group.counted += Number.isFinite(row.usage) ? 1 : 0;
        group.memory += Number.isFinite(row.memory) ? row.memory : 0;
        group.count += 1;
        groups.set(row.name, group);
    }
    // A group none of whose processes has a usage has none either.
    return Array.from(groups.values(), g => ({ name: g.name, usage: g.counted > 0 ? g.usage : NaN, memory: g.memory, count: g.count }));
}

// The heaviest processes by `key` ("usage" or "memory").
function top(rows, key, count) {
    return grouped(rows)
        .filter(g => g[key] > 0)
        .sort((a, b) => b[key] - a[key] || a.name.localeCompare(b.name))
        .slice(0, count);
}

// Percentage points of a GPU's usage its counted processes may leave
// unexplained, given the moment between the GPU's reading and theirs.
const UNCOUNTED_SHARE = 10;

// The processes using the GPU `gpu` names, busiest first. A process holding
// video memory while idle still counts, after the busy ones. So does one
// whose usage isn't counted, as for ROCm compute, unless the GPU is `busy`
// (its usage in percent) well beyond what the counted ones add up to: the
// uncounted ones are then doing that work, and come first.
function topOnGpu(rows, gpu, count, busy) {
    const groups = grouped(rows.filter(row => row.gpu === gpu)).filter(g => g.usage > 0 || g.memory > 0);
    const counted = groups.reduce((sum, g) => sum + (Number.isFinite(g.usage) ? g.usage : 0), 0);
    const uncountedFirst = busy - counted > UNCOUNTED_SHARE;
    const rank = g => !Number.isFinite(g.usage) && uncountedFirst ? 0 : 1;
    return groups
        .sort((a, b) => rank(a) - rank(b) || (b.usage || 0) - (a.usage || 0) || b.memory - a.memory || a.name.localeCompare(b.name))
        .slice(0, count);
}

// A run of the helper's "gpuprocs": when it began, in seconds since boot,
// and each process's use of each GPU, keyed "PID BDF": its name, the video
// memory its DRM clients and ROCm hold, and each engine's busy nanoseconds
// so far, added up over its clients.
function gpuScan(text) {
    const scan = { time: NaN, uses: {} };
    const useOf = (pid, gpu, name) => {
        const key = pid + " " + gpu;
        scan.uses[key] = scan.uses[key] || { name: name, gpu: gpu, drm: 0, rocm: 0, engines: {}, counted: false };
        return scan.uses[key];
    };
    for (const line of String(text).split("\n")) {
        const f = line.split(" ");
        if (f[0] === "t") {
            scan.time = Number(f[1]);
        } else if (f[0] === "drm" && f.length >= 7) {
            const use = useOf(f[1], f[2], f.slice(6).join(" "));
            use.drm += (Number(f[4]) || 0) * 1024;
            if (f[5] !== "-") {
                for (const pair of f[5].split(",")) {
                    const [engine, ns] = pair.split(":");
                    use.engines[engine] = (use.engines[engine] || 0) + (Number(ns) || 0);
                    use.counted = true;
                }
            }
        } else if (f[0] === "kfd" && f.length >= 5) {
            useOf(f[1], f[2], f.slice(4).join(" ")).rocm += Number(f[3]) || 0;
        }
    }
    return scan;
}

// The processes as of `after`, with their usage since `before`: the busiest
// engine's share of the time between the two scans. It is NaN without an
// earlier reading of the process, or where the kernel counts no engine
// time, as for ROCm compute. ROCm's memory is mostly the same as DRM's, so
// the larger stands for both.
function gpuProcesses(before, after) {
    const seconds = before ? after.time - before.time : NaN;
    return Object.keys(after.uses).map(key => {
        const use = after.uses[key];
        const was = before ? before.uses[key] : undefined;
        let usage = NaN;
        if (use.counted && was && seconds > 0) {
            usage = 0;
            for (const engine of Object.keys(use.engines)) {
                const ns = use.engines[engine] - (was.engines[engine] || 0);
                usage = Math.max(usage, ns / (seconds * 1e9) * 100);
            }
            usage = Math.min(100, usage);
        }
        return { name: use.name, usage: usage, memory: Math.max(use.drm, use.rocm), gpu: use.gpu };
    });
}
