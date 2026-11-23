// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

function example(now, provider = "claude") {
    const day = 86400;
    const weekly = (percent, left) => ({ percent: percent, resetsAt: now + left, period: "week", windowSeconds: 7 * day });
    const fable = (percent, left) => Object.assign(weekly(percent, left), { id: "Fable", label: "Fable" });
    const average = (windows, percent) => Object.assign({}, windows[0], { percent: percent, resetsAt: null,
        accountAverage: true, resetTimes: windows.map(window => window.resetsAt) });
    const first = 2 * day + 21 * 3600 + 60;
    const second = 4 * day + 5 * 3600 + 60;
    const accounts = [
        { state: "ok", weekly: weekly(82, first), scoped: [fable(100, first)],
          session: { period: "session", percent: 100, windowSeconds: 18000, resetsAt: now + 47 * 60 },
          bankedResets: { count: 2, expires: [now + 2 * day + 60, now + 12 * day + 60] },
          credits: { status: "ok", balance: { amount: 18.42, currency: "USD", precision: 2 }, fetchedAt: now } },
        { state: "ok", weekly: weekly(35, second), scoped: [fable(58, second)] }
    ];
    const entry = {
        source: "cliproxyapi",
        pool: "demo",
        status: "ok",
        proxyStatus: "connected",
        fetchedAt: now,
        weekly: average(accounts.map(account => account.weekly), 58.5),
        session: average([accounts[0].session], 50),
        scoped: [average(accounts.map(account => account.scoped[0]), 79)],
        accounts: accounts,
        affinity: { enabled: true, ttlSeconds: 3600 }
    };
    const history = [
        [7, 29, 41], [6, 40, 56], [5, 52, 68], [4.15, 74, 90], [4.125, 31, 39],
        [3.5, 39, 53], [2.82, 60, 77], [2.8, 20, 27], [2, 31, 36], [1, 46, 55], [0, 58.5, 79]
    ];
    entry.weekly.history = history.map(([days, used]) => [now - Math.round(days * day), used]);
    entry.scoped[0].history = history.map(([days, used, fable]) => [now - Math.round(days * day), fable]);
    if (provider === "codex") {
        const monthly = { period: "month", percent: 24, windowSeconds: 30 * day, resetsAt: now + 9 * day };
        entry.otherPeriods = [average([monthly], 24)];
        entry.scoped = [];
        for (const account of accounts) {
            account.scoped = [];
        }
        accounts[0].credits.balance = { amount: 1250.5, currency: "", precision: 2 };
        accounts[1].otherPeriods = [monthly];
    }
    if (provider === "antigravity") {
        const gemA = Object.assign(weekly(42, first), { label: "Gemini" });
        const gemB = Object.assign(weekly(18, second), { label: "Gemini" });
        const tpA = Object.assign(weekly(86, first), { id: "3p-weekly", label: "Claude & GPT" });
        const tpB = Object.assign(weekly(34, second), { id: "3p-weekly", label: "Claude & GPT" });
        const agAccounts = [
            { state: "ok", weekly: gemA, scoped: [tpA],
              session: { period: "session", percent: 24, windowSeconds: 18000, resetsAt: now + 3 * 3600 + 12 * 60 },
              credits: { status: "ok", balance: { amount: 1250, currency: "", precision: 0 }, fetchedAt: now } },
            { state: "ok", weekly: gemB, scoped: [tpB],
              credits: { status: "ok", balance: { amount: 500, currency: "", precision: 0 }, fetchedAt: now } }
        ];
        const agEntry = {
            source: "cliproxyapi",
            pool: "demo-ag",
            status: "ok",
            proxyStatus: "connected",
            fetchedAt: now,
            weekly: average([gemA, gemB], 30),
            session: average([agAccounts[0].session], 12),
            scoped: [average([tpA, tpB], 60)],
            accounts: agAccounts,
            affinity: { enabled: true, ttlSeconds: 3600 }
        };
        agEntry.weekly.history = history.map(([days, used]) => [now - Math.round(days * day), Math.round(used * 0.5)]);
        agEntry.scoped[0].history = history.map(([days, , tp]) => [now - Math.round(days * day), Math.round(tp * 0.75)]);
        return agEntry;
    }
    return entry;
}
