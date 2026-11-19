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
        scoped: [average(accounts.map(account => account.scoped[0]), 79)],
        accounts: accounts,
        affinity: { enabled: true, ttlSeconds: 3600 }
    };
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
    return entry;
}
