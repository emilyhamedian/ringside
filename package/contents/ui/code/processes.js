.pragma library

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
