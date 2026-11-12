// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/popups"
import "starterstates.js" as StarterStates

// A section of Gallery.qml: Claude and Codex in the panel beside two system
// items, loading, failed and signed out among them, then their popups in
// each state, the session starter's footer in
// each of its states, then panels and popups under Breeze Light. The
// monitor's readings are FakeUsage's; the section's own come with made-up
// weeks of use.
ColumnLayout {
    id: section

    required property var monitor

    // A week's use so far, `days` long and ending at `percent`: busy
    // stretches with quiet nights between them, as [days ago, percent].
    function history(days, percent) {
        const steps = Math.round(days * 4);
        const weights = Array.from({ length: steps }, (_, i) => i % 4 === 1 || i % 4 === 2 ? 1 : 0.08);
        const sum = weights.reduce((a, b) => a + b, 0);
        const points = [[days, 0]];
        let total = 0;
        weights.forEach((weight, i) => {
            total += weight;
            points.push([Math.max(0, days - (i + 1) / 4), Math.round(total / sum * percent)]);
        });
        return points;
    }

    spacing: 2 * Kirigami.Units.gridUnit

    FakeMonitor {
        id: creditsMonitor
        usage: FakeUsage {
            id: creditUsage
            credits: ({
                claude: { status: "ok", balance: { amount: 18.42, currency: "USD", precision: 2 }, fetchedAt: creditUsage.createdAt },
                codex: { status: "ok", balance: { amount: 1250.5, currency: "", precision: 2 }, fetchedAt: creditUsage.createdAt }
            })
        }
    }

    FakeMonitor {
        id: cachedCredits
        usage: FakeUsage {
            id: cachedCreditUsage
            credits: ({ claude: { status: "error", balance: { amount: 18.42, currency: "USD", precision: 2 },
                                 fetchedAt: cachedCreditUsage.createdAt - 3600, reason: "offline" } })
        }
    }

    FakeMonitor {
        id: zeroCredits
        usage: FakeUsage {
            id: zeroCreditUsage
            credits: ({ codex: { status: "ok", balance: { amount: 0, currency: "", precision: 2 },
                                fetchedAt: zeroCreditUsage.createdAt } })
        }
    }

    component CreditViews: RowLayout {
        id: creditViews
        property bool flat: false
        spacing: 2 * Kirigami.Units.gridUnit

        GalleryFrame {
            label: "Claude · credits remaining"
            flat: creditViews.flat
            UsagePopup { monitor: creditsMonitor; item: "claude" }
        }
        GalleryFrame {
            label: "Codex · credits remaining"
            flat: creditViews.flat
            UsagePopup { monitor: creditsMonitor; item: "codex" }
        }
        GalleryFrame {
            label: "Claude · cached credits remaining"
            flat: creditViews.flat
            UsagePopup { monitor: cachedCredits; item: "claude" }
        }
        GalleryFrame {
            label: "Codex · zero credits (row hidden)"
            flat: creditViews.flat
            UsagePopup { monitor: zeroCredits; item: "codex" }
        }
    }

    CreditViews {}

    FakeMonitor {
        id: creditSpending
        usage: FakeUsage {
            id: spendingUsage
            entries: ({
                claude: { status: "ok", fetchedAt: spendingUsage.createdAt,
                          weekly: spendingUsage.window(100, 2 * spendingUsage.day, section.history(5, 100)),
                          scoped: [Object.assign({ id: "Fable", label: "Fable" }, spendingUsage.window(100, spendingUsage.day, []))] },
                codex: { status: "ok", fetchedAt: spendingUsage.createdAt,
                         weekly: spendingUsage.window(24, 5 * spendingUsage.day, section.history(2, 24)), scoped: [],
                         session: spendingUsage.window(100, 3600, []) }
            })
            credits: ({
                claude: { status: "ok", spent: true, balance: { amount: 18.42, currency: "USD", precision: 2 }, fetchedAt: spendingUsage.createdAt },
                codex: { status: "ok", spent: true, balance: { amount: 1250.5, currency: "", precision: 2 }, fetchedAt: spendingUsage.createdAt }
            })
        }
    }

    // Claude at 81 % is amber, and runs out before its reset at this pace;
    // Fable over 90 % and Codex at its limit are red. Codex has three banked
    // resets, the first expiring in two days.
    FakeMonitor {
        id: hot
        usage: FakeUsage {
            id: hotUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: hotUsage.createdAt,
                    weekly: hotUsage.window(81, 2 * hotUsage.day + 21 * 3600, section.history(4.1, 81)),
                    scoped: [Object.assign({ id: "Fable", label: "Fable" },
                                           hotUsage.window(93, 2 * hotUsage.day + 21 * 3600, section.history(4.1, 93)))]
                },
                codex: {
                    status: "ok",
                    fetchedAt: hotUsage.createdAt,
                    weekly: hotUsage.window(100, 14 * 3600 + 5 * 60, section.history(6.4, 100)),
                    scoped: [],
                    bankedResets: { count: 3, expires: [2, 12, 21].map(days => hotUsage.createdAt + days * hotUsage.day + 3600) }
                }
            })
        }
    }

    // Two model limits and no choice between them: no inner ring, a row each.
    // A day before the reset, Claude and Fable are amber and last to it.
    FakeMonitor {
        id: several
        usage: FakeUsage {
            id: severalUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: severalUsage.createdAt,
                    weekly: severalUsage.window(77, severalUsage.day, section.history(6, 77)),
                    scoped: [Object.assign({ id: "Fable", label: "Fable" },
                                           severalUsage.window(82, severalUsage.day, section.history(6, 82))),
                             Object.assign({ id: "Sonnet", label: "Sonnet" },
                                           severalUsage.window(12, 4 * severalUsage.day + 2 * 3600, section.history(3, 12)))]
                }
            })
        }
    }

    // Claude's week and Fable's started over early 3 h 10 min ago, from
    // 62 % and 81 %; Codex's in place 25 minutes ago, from 48 %.
    FakeMonitor {
        id: resetEarly
        usage: FakeUsage {
            id: resetEarlyUsage
            readonly property real at: createdAt - 3 * 3600 - 600
            function early(percent, from, at, history) {
                return Object.assign(window(percent, at + 7 * day - createdAt, history),
                                     { earlyReset: { at: at, from: from, until: at + day }, startedAt: at });
            }
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: resetEarlyUsage.createdAt,
                    weekly: resetEarlyUsage.early(3, 62, resetEarlyUsage.at, [[0.13, 0], [0.08, 1], [0, 3]]),
                    scoped: [Object.assign({ id: "Fable", label: "Fable" },
                                           resetEarlyUsage.early(5, 81, resetEarlyUsage.at, [[0.13, 0], [0.08, 2], [0, 5]]))]
                },
                codex: {
                    status: "ok",
                    fetchedAt: resetEarlyUsage.createdAt,
                    weekly: Object.assign(resetEarlyUsage.window(1, 2 * resetEarlyUsage.day + 4 * 3600, [[0.02, 0], [0, 1]]),
                                          { earlyReset: { at: resetEarlyUsage.createdAt - 1500, from: 48,
                                                          until: resetEarlyUsage.createdAt - 1500 + resetEarlyUsage.day },
                                            startedAt: resetEarlyUsage.createdAt - 1500 }),
                    scoped: []
                }
            })
        }
    }

    // Fable alone started over early, an hour ago.
    FakeMonitor {
        id: fableReset
        usage: FakeUsage {
            id: fableResetUsage
            readonly property real at: createdAt - 3600
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: fableResetUsage.createdAt,
                    weekly: fableResetUsage.window(55, 2 * fableResetUsage.day + 21 * 3600, section.history(4.1, 55)),
                    scoped: [Object.assign({ id: "Fable", label: "Fable" },
                                           fableResetUsage.window(2, 7 * fableResetUsage.day - 3600, [[0.04, 0], [0, 2]]),
                                           { earlyReset: { at: fableResetUsage.at, from: 81, until: fableResetUsage.at + fableResetUsage.day },
                                             startedAt: fableResetUsage.at })]
                }
            })
        }
    }

    // The last hour of a week that ran close to its limit.
    FakeMonitor {
        id: fullWeek
        usage: FakeUsage {
            id: fullWeekUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: fullWeekUsage.createdAt,
                    weekly: fullWeekUsage.window(91, 3600, section.history(6.95, 91)),
                    scoped: []
                }
            })
        }
    }

    // Checks have failed for an hour since the one that worked: the panel
    // strikes the ring, and the popup shows the status alone, its starter
    // switch held. The checks run every 15 minutes and the helper's hold is
    // over, so the popup offers to try again.
    FakeMonitor {
        id: failedMonitor
        usage: FakeUsage {
            id: failedUsage
            refreshMinutes: 15
            lastRun: createdAt - 400
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: failedUsage.createdAt - 3600,
                    weekly: failedUsage.window(48, 2 * failedUsage.day + 22 * 3600, section.history(4, 48)),
                    scoped: [Object.assign({ id: "Fable", label: "Fable" },
                                           failedUsage.window(52, 2 * failedUsage.day + 22 * 3600, section.history(4, 52)))],
                    lastError: "can't reach api.anthropic.com: Name or service not known",
                    lastErrorAt: failedUsage.createdAt - 400,
                    reason: "offline",
                    host: "api.anthropic.com",
                    retryAt: failedUsage.createdAt - 100
                }
            })
        }
    }

    // The first failed check, four minutes after one that found Claude
    // near its limit: grey, with no red and no breathing, until the reading
    // is two checks old.
    FakeMonitor {
        id: justFailed
        usage: FakeUsage {
            id: justFailedUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: justFailedUsage.createdAt - 240,
                    weekly: justFailedUsage.window(93, justFailedUsage.day + 6 * 3600, section.history(5.7, 93)),
                    scoped: [Object.assign({ id: "Fable", label: "Fable" },
                                           justFailedUsage.window(97, justFailedUsage.day + 6 * 3600, section.history(5.7, 97)))],
                    lastError: "rate limited, retrying in 3120 s",
                    lastErrorAt: justFailedUsage.createdAt - 60,
                    reason: "rate-limited",
                    host: "api.anthropic.com",
                    retryAt: justFailedUsage.createdAt + 3060
                }
            })
        }
    }

    // Checks failed through the week's reset: nothing is left of this week.
    FakeMonitor {
        id: failedPastReset
        usage: FakeUsage {
            id: failedPastResetUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: failedPastResetUsage.createdAt - 8 * 3600,
                    weekly: failedPastResetUsage.window(71, -2 * 3600, section.history(6.6, 71).map(p => [p[0] + 8 * 3600 / failedPastResetUsage.day, p[1]])),
                    scoped: [],
                    lastError: "The usage helper exited with code 1: KeyError: 'weekly'",
                    lastErrorAt: failedPastResetUsage.createdAt - 60,
                    reason: "helper",
                    host: "",
                    retryAt: failedPastResetUsage.createdAt + 240
                }
            })
        }
    }

    // Two days into the week, Claude at 25 % lasts it, while Fable at 55 %
    // runs out before the reset at this pace. The pace line says so;
    // neither is coloured, as a colour comes from the reading alone.
    FakeMonitor {
        id: fablePace
        usage: FakeUsage {
            id: fablePaceUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: fablePaceUsage.createdAt,
                    weekly: fablePaceUsage.window(25, 5 * fablePaceUsage.day, section.history(2, 25)),
                    scoped: [Object.assign({ id: "Fable", label: "Fable" },
                                           fablePaceUsage.window(55, 5 * fablePaceUsage.day, section.history(2, 55)))]
                }
            })
        }
    }

    // Codex's one limit at 40 % two days in, on pace to run out, with five
    // banked resets.
    FakeMonitor {
        id: codexPace
        usage: FakeUsage {
            id: codexPaceUsage
            entries: ({
                codex: {
                    status: "ok",
                    fetchedAt: codexPaceUsage.createdAt,
                    weekly: codexPaceUsage.window(40, 5 * codexPaceUsage.day, section.history(2, 40)),
                    scoped: [],
                    bankedResets: { count: 5, expires: [4, 9, 15, 20, 28].map(days => codexPaceUsage.createdAt + days * codexPaceUsage.day + 3600) }
                }
            })
        }
    }

    // The first check since the widget started, still running.
    FakeMonitor {
        id: loadingMonitor
        usage: FakeUsage {
            entries: ({})
            pending: ["claude", "codex"]
        }
    }

    // The first check since the widget started failed: offline for Claude,
    // no codex CLI for Codex. There is no reading to keep.
    FakeMonitor {
        id: firstFailed
        usage: FakeUsage {
            id: firstFailedUsage
            entries: ({
                claude: { status: "error", lastError: "can't reach api.anthropic.com: Name or service not known",
                          lastErrorAt: firstFailedUsage.createdAt - 30, reason: "offline", host: "api.anthropic.com",
                          retryAt: firstFailedUsage.createdAt + 270 },
                codex: { status: "error", lastError: "codex CLI not found", lastErrorAt: firstFailedUsage.createdAt - 30,
                         reason: "not-installed", host: "", retryAt: firstFailedUsage.createdAt + 270 }
            })
        }
    }

    FakeMonitor {
        id: signedOut
        usage: FakeUsage {
            entries: ({ codex: { status: "signed_out" } })
        }
    }

    // The session starter on, waiting for Claude's session to end, and
    // unable to start Codex's session or week while the CLI is signed out.
    FakeMonitor {
        id: starting
        usage: FakeUsage {
            id: startingUsage
            starters: ({
                claude: { enabled: true, on: ["session"], windows: ["session"], state: "waiting", at: null,
                          next: startingUsage.createdAt + 2 * 3600 + 13 * 60, reason: null },
                codex: { enabled: true, on: ["session"], windows: ["session", "week"], state: "failed", at: null, next: null,
                         reason: "signed-out", window: "session" }
            })
        }
    }

    // A Claude plan with no five-hour limit: nothing to start, so no footer.
    FakeMonitor {
        id: nothingToStart
        usage: FakeUsage {
            starters: ({ claude: { enabled: false, on: [], windows: [], state: "off", at: null, next: null, reason: null } })
        }
    }

    // Each of the starter's states for Claude and for Codex, but those for
    // one of them only, Codex's plan with a session and a week to start;
    // then Codex's off with only a week, and OpenCode Go's states that have
    // words of their own.
    readonly property var starterFooters: {
        const footers = [];
        StarterStates.ROWS.forEach(row => ["claude", "codex"].forEach(item => {
            if ((row.only ?? item) === item) {
                footers.push({ item: item, row: row, windows: item === "claude" ? ["session"] : ["session", "week"] });
            }
        }));
        footers.push({ item: "codex", row: StarterStates.ROWS[0], windows: ["week"] });
        StarterStates.ROWS.filter(row => (row.only ?? "opencode") === "opencode"
                                  && (["off", "weekly"].includes(row.state)
                                      || ["not-installed", "program", "signed-out", "not-responding", "no-model"].includes(row.reason)))
            .forEach(row => footers.push({ item: "opencode", row: row, windows: ["session"] }));
        return footers;
    }

    component Panel: GalleryPanel {
        monitor: section.monitor
        items: ["cpu", "memory", "claude", "codex"]
    }

    Panel {
        label: "Claude & Codex · credits used since the previous check · full blue rings, neutral weekly readings"
        thickness: 46
        monitor: creditSpending
    }

    Panel {
        label: "Claude & Codex · credits used · right to left"
        thickness: 46
        monitor: creditSpending
        mirrored: true
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · Claude 52 % with Fable 78 % inside (amber), Codex 24 %"
        thickness: 46
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · Claude 25 %, Fable 55 % (on pace to run out, not coloured)"
        thickness: 46
        monitor: fablePace
        items: ["cpu", "memory", "claude"]
    }

    Panel {
        label: "Claude & Codex · panel · 30 px"
        thickness: 30
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · Claude 81 % (amber) with Fable 93 % (red), Codex 100 % (red)"
        thickness: 46
        monitor: hot
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · Claude's checks failing for an hour (struck), Codex signed out (hidden)"
        thickness: 46
        monitor: failedMonitor
        items: ["cpu", "memory", "claude"]
    }

    Panel {
        label: "Claude & Codex · panel · 30 px · Claude's checks failing for an hour (struck)"
        thickness: 30
        monitor: failedMonitor
        items: ["cpu", "memory", "claude"]
    }

    Panel {
        label: "Claude · panel · 46 px · Claude's first failed check at 93 % (grey)"
        thickness: 46
        monitor: justFailed
        items: ["cpu", "memory", "claude"]
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · the first check running (still dots; a lit dot travels after 1 s)"
        thickness: 46
        monitor: loadingMonitor
    }

    Panel {
        label: "Claude & Codex · panel · 30 px · the first check running"
        thickness: 30
        monitor: loadingMonitor
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · the first check failed (struck, no reading)"
        thickness: 46
        monitor: firstFailed
    }

    // Kimi's month: 92 % used with 15 days left (red, on pace to run out),
    // with 34 % of its five-hour limit used; and 38 % with 12 days left
    // (lasts to the reset) on an older plan with a weekly limit; then its only
    // credential a Kimi Code sign-in that Kimi Code hasn't renewed.
    FakeMonitor {
        id: kimiMonitor
        usage: FakeUsage {
            id: kimiUsage
            function month(percent, left, history) {
                return Object.assign(window(percent, left, history), { windowSeconds: 30 * day });
            }
            ids: ["claude", "codex", "kimi"]
            entries: ({
                codex: { status: "ok", fetchedAt: kimiUsage.createdAt,
                         weekly: kimiUsage.window(24, 5 * kimiUsage.day, section.history(2, 24)), scoped: [] },
                kimi: { status: "ok", fetchedAt: kimiUsage.createdAt,
                        weekly: kimiUsage.month(92, 15 * kimiUsage.day + 6 * 3600, section.history(15, 92)), scoped: [],
                        session: { percent: 34, resetsAt: kimiUsage.createdAt + 3 * 3600 + 40 * 60, windowSeconds: 5 * 3600 } }
            })
        }
    }

    FakeMonitor {
        id: kimiCalm
        usage: FakeUsage {
            id: kimiCalmUsage
            ids: ["kimi"]
            entries: ({
                kimi: { status: "ok", fetchedAt: kimiCalmUsage.createdAt,
                        weekly: Object.assign(kimiCalmUsage.window(38, 12 * kimiCalmUsage.day + 2 * 3600,
                                                                   section.history(18, 38)),
                                              { windowSeconds: 30 * kimiCalmUsage.day }),
                        scoped: [],
                        session: { percent: 3, resetsAt: kimiCalmUsage.createdAt + 4 * 3600 + 10 * 60, windowSeconds: 5 * 3600 },
                        week: kimiCalmUsage.window(41, 2 * kimiCalmUsage.day + 9 * 3600, []) }
            })
        }
    }

    FakeMonitor {
        id: kimiExpired
        usage: FakeUsage {
            id: kimiExpiredUsage
            ids: ["kimi"]
            entries: ({
                kimi: { status: "ok", fetchedAt: kimiExpiredUsage.createdAt - 3 * 3600,
                        weekly: Object.assign(kimiExpiredUsage.window(38, 12 * kimiExpiredUsage.day,
                                                                      section.history(18, 38)),
                                              { windowSeconds: 30 * kimiExpiredUsage.day }),
                        scoped: [], lastError: "Kimi Code's sign-in has expired; open Kimi Code to renew it",
                        lastErrorAt: kimiExpiredUsage.createdAt - 3600, reason: "expired", host: "",
                        retryAt: kimiExpiredUsage.createdAt + 240 }
            })
        }
    }

    Panel {
        label: "Codex & Kimi · panel · 46 px · Codex 24 %, Kimi 92 % of its month (red)"
        thickness: 46
        monitor: kimiMonitor
        items: ["cpu", "memory", "codex", "kimi"]
    }

    Panel {
        label: "Kimi · panel · 30 px · 38 % of its month"
        thickness: 30
        monitor: kimiCalm
        items: ["cpu", "memory", "kimi"]
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        GalleryFrame {
            label: "Kimi · 92 % of its month, on pace to run out · 5-hour limit 34 %"
            UsagePopup { monitor: kimiMonitor; item: "kimi" }
        }

        GalleryFrame {
            label: "Kimi · 38 %, lasts to the reset · older plan: 5-hour limit 3 %, weekly limit 41 %"
            UsagePopup { monitor: kimiCalm; item: "kimi" }
        }

        GalleryFrame {
            label: "Kimi · Kimi Code's sign-in expired (struck)"
            UsagePopup { monitor: kimiExpired; item: "kimi" }
        }
    }

    // OpenCode Go's month: 55 % used with 13 days left, beside Kimi, with the
    // five-hour window idle and 30 % of the week used; then an OpenCode
    // account without Go, whose first check failed.
    FakeMonitor {
        id: goMonitor
        usage: FakeUsage {
            id: goUsage
            ids: ["kimi", "opencode"]
            entries: ({
                kimi: { status: "ok", fetchedAt: goUsage.createdAt,
                        weekly: Object.assign(goUsage.window(38, 12 * goUsage.day, section.history(18, 38)),
                                              { windowSeconds: 30 * goUsage.day }), scoped: [] },
                opencode: { status: "ok", fetchedAt: goUsage.createdAt,
                            weekly: Object.assign(goUsage.window(55, 13 * goUsage.day, section.history(18, 55)),
                                                  { windowSeconds: 31 * goUsage.day }), scoped: [],
                            session: { percent: 0, resetsAt: goUsage.createdAt + 5 * 3600, windowSeconds: 5 * 3600 },
                            week: goUsage.window(30, 4 * goUsage.day + 3 * 3600, []) }
            })
        }
    }

    FakeMonitor {
        id: goWithout
        usage: FakeUsage {
            id: goWithoutUsage
            ids: ["opencode"]
            entries: ({
                opencode: { status: "error", lastError: "the OpenCode account has no Go subscription",
                            lastErrorAt: goWithoutUsage.createdAt - 60, reason: "not-subscribed", host: "opencode.ai",
                            retryAt: goWithoutUsage.createdAt + 240 }
            })
        }
    }

    Panel {
        label: "Kimi & OpenCode Go · panel · 46 px · OpenCode Go 55 % of its month"
        thickness: 46
        monitor: goMonitor
        items: ["kimi", "opencode"]
    }

    Panel {
        label: "OpenCode Go · panel · 30 px · 55 % of its month"
        thickness: 30
        monitor: goMonitor
        items: ["cpu", "memory", "opencode"]
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        GalleryFrame {
            label: "OpenCode Go · 55 % of its month · 5-hour window idle, weekly limit 30 %"
            UsagePopup { monitor: goMonitor; item: "opencode" }
        }

        GalleryFrame {
            label: "OpenCode Go · an account without Go (struck)"
            UsagePopup { monitor: goWithout; item: "opencode" }
        }
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        GalleryFrame {
            label: "Claude · Fable on the inner ring, on pace to run out"
            UsagePopup { monitor: section.monitor; item: "claude" }
        }

        GalleryFrame {
            label: "Claude · as beside, with 64 % of a five-hour session that ends in 1h 25m"
            UsagePopup {
                item: "claude"
                monitor: FakeMonitor {
                    usage: FakeUsage {
                        id: sessionUsage
                        Component.onCompleted: entries = Object.assign({}, entries, { claude: Object.assign({}, entries.claude, {
                            session: { percent: 64, resetsAt: sessionUsage.createdAt + 85 * 60, windowSeconds: 5 * 3600 } }) })
                    }
                }
            }
        }

        GalleryFrame {
            label: "Codex · one limit, lasts to the reset"
            UsagePopup { monitor: section.monitor; item: "codex" }
        }

        GalleryFrame {
            label: "Claude · two model limits, none picked, amber, both last"
            UsagePopup { monitor: several; item: "claude" }
        }

        GalleryFrame {
            label: "Claude · 91 % (red), an hour left"
            UsagePopup { monitor: fullWeek; item: "claude" }
        }
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        GalleryFrame {
            label: "Claude · 81 % (amber, on pace to run out), Fable 93 % (red)"
            UsagePopup { monitor: hot; item: "claude" }
        }

        GalleryFrame {
            label: "Codex · at its limit, three banked resets, one expiring"
            UsagePopup { monitor: hot; item: "codex" }
        }

        GalleryFrame {
            label: "Claude · checks failing for an hour (struck), try again"
            UsagePopup { monitor: failedMonitor; item: "claude" }
        }

        GalleryFrame {
            label: "Codex · signed out"
            UsagePopup { monitor: signedOut; item: "codex" }
        }
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        GalleryFrame {
            label: "Claude · first failed check, rate limited, the reading in grey"
            UsagePopup { monitor: justFailed; item: "claude" }
        }

        GalleryFrame {
            label: "Claude · the helper failed through the week's reset"
            UsagePopup { monitor: failedPastReset; item: "claude" }
        }

        GalleryFrame {
            label: "Claude · the first check running"
            UsagePopup { monitor: loadingMonitor; item: "claude" }
        }

        GalleryFrame {
            label: "Codex · the first check failed, no CLI"
            UsagePopup { monitor: firstFailed; item: "codex" }
        }
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        GalleryFrame {
            label: "Claude · reset early 3h ago, from 62 % and Fable's 81 %"
            UsagePopup { monitor: resetEarly; item: "claude" }
        }

        GalleryFrame {
            label: "Codex · reset early in place 25m ago, from 48 %"
            UsagePopup { monitor: resetEarly; item: "codex" }
        }

        GalleryFrame {
            label: "Claude · Fable alone reset early an hour ago"
            UsagePopup { monitor: fableReset; item: "claude" }
        }
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        GalleryFrame {
            label: "Claude · 25 %, Fable 55 % (on pace to run out, not coloured)"
            UsagePopup { monitor: fablePace; item: "claude" }
        }

        GalleryFrame {
            label: "Codex · one limit at 40 %, on pace to run out, five banked resets"
            UsagePopup { monitor: codexPace; item: "codex" }
        }

        GalleryFrame {
            label: "Claude · session starter on, waiting"
            UsagePopup { monitor: starting; item: "claude" }
        }

        GalleryFrame {
            label: "Codex · session starter can't run: signed out (full text)"
            UsagePopup { monitor: starting; item: "codex" }
        }

        GalleryFrame {
            label: "Claude · plan with no five-hour limit: no starter"
            UsagePopup { monitor: nothingToStart; item: "claude" }
        }
    }

    // The footer alone, Claude's beside Codex's, in each starter state, then
    // OpenCode Go's own.
    GridLayout {
        columns: 4
        columnSpacing: 2 * Kirigami.Units.gridUnit
        rowSpacing: Kirigami.Units.gridUnit

        Repeater {
            model: section.starterFooters

            delegate: GalleryFrame {
                id: starterFrame

                required property var modelData
                readonly property string item: modelData.item
                readonly property FakeUsage fake: FakeUsage {
                    id: fake
                    starters: ({ [starterFrame.item]: StarterStates.starter(starterFrame.modelData.row, fake.createdAt,
                                                                            starterFrame.modelData.windows) })
                }

                label: ({ claude: "Claude", codex: "Codex", opencode: "OpenCode Go" })[item] + " · starter " + modelData.row.label
                       + (modelData.windows.length === 1 && item === "codex" ? " · week only" : "")

                PopupFooter {
                    width: Kirigami.Units.gridUnit * 20
                    monitor: section.monitor
                    systemMonitorShown: false
                    leading: StarterSwitch {
                        item: starterFrame.item
                        usage: starterFrame.fake
                        nowMs: starterFrame.fake.createdAt * 1000
                        texts: Words { monitor: section.monitor }
                    }
                }
            }
        }
    }

    GalleryLight {
        Panel {
            label: "Breeze Light · Claude & Codex · panel · 46 px · Claude 81 % (amber), Codex 100 % (red)"
            thickness: 46
            monitor: hot
        }

        CreditViews { flat: true }

        Panel {
            label: "Breeze Light · Claude & Codex · credits used since the previous check"
            thickness: 46
            monitor: creditSpending
        }

        Panel {
            label: "Breeze Light · Claude & Codex · credits used · right to left"
            thickness: 46
            monitor: creditSpending
            mirrored: true
        }

        Panel {
            label: "Breeze Light · Claude · panel · 46 px · Claude 77 % (amber), lasts to the reset"
            thickness: 46
            monitor: several
            items: ["cpu", "memory", "claude"]
        }

        Panel {
            label: "Breeze Light · Claude & Codex · panel · 46 px · the first check running"
            thickness: 46
            monitor: loadingMonitor
        }

        Panel {
            label: "Breeze Light · Claude & Codex · panel · 46 px · the first check failed (struck)"
            thickness: 46
            monitor: firstFailed
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            GalleryFrame {
                label: "Breeze Light · Claude · the pace line on Fable"
                flat: true
                UsagePopup { monitor: section.monitor; item: "claude" }
            }

            GalleryFrame {
                label: "Breeze Light · Codex · one limit, the pace line, five banked resets"
                flat: true
                UsagePopup { monitor: codexPace; item: "codex" }
            }

            GalleryFrame {
                label: "Breeze Light · Claude · session starter on, waiting (dim)"
                flat: true
                UsagePopup { monitor: starting; item: "claude" }
            }

            GalleryFrame {
                label: "Breeze Light · Codex · session starter signed out (full)"
                flat: true
                UsagePopup { monitor: starting; item: "codex" }
            }

            GalleryFrame {
                label: "Breeze Light · Claude · reset early 3h ago"
                flat: true
                UsagePopup { monitor: resetEarly; item: "claude" }
            }
        }
    }
}
