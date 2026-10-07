// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Every state and reason of the session starter, for tst_usage's popup tests
// and the gallery's footers. Times are in seconds from now. `failed` says the
// status shows in full rather than dim; `only` names the one item a row is
// for. The Claude-only row comes last, so the gallery's Claude and Codex
// footers stay side by side.
var ROWS = [
    { label: "off", state: "off", enabled: false, failed: false },
    { label: "on, waiting", state: "waiting", enabled: true, failed: false, next: 133 * 60 },
    { label: "on, waiting, another day", state: "waiting", enabled: true, failed: false, next: 26 * 3600 },
    { label: "on, waiting, six days or more away", state: "waiting", enabled: true, failed: false, next: 6 * 86400 + 5 * 3600 },
    { label: "sent, confirming", state: "confirming", enabled: true, failed: false, at: -180, next: 120 },
    { label: "started, confirmed", state: "started", enabled: true, failed: false, at: -180, next: 297 * 60 },
    { label: "weekly limit reached", state: "weekly", enabled: true, failed: false, next: 3 * 86400 },
    { label: "failed: not installed", state: "failed", enabled: true, failed: true, reason: "not-installed" },
    { label: "failed: signed out", state: "failed", enabled: true, failed: true, reason: "signed-out" },
    { label: "failed: not responding, retrying", state: "failed", enabled: true, failed: true, reason: "not-responding", next: 300 },
    { label: "failed: couldn't check the limits, retrying", state: "failed", enabled: true, failed: true, reason: "unchecked", next: 900 },
    { label: "failed: the message never left, retrying", state: "failed", enabled: true, failed: true, reason: "not-sent", next: 300 },
    { label: "the helper failed to start one, retrying", state: "failed", enabled: true, failed: true, reason: "helper",
      at: -60, next: 240, error: "The usage helper exited with code 1: RuntimeError: boom" },
    { label: "the switch couldn't be turned off", state: "failed", enabled: false, failed: true, reason: "switch",
      error: "The usage helper exited with code 1: PermissionError: [Errno 13] Permission denied: 'starter.json'" },
    { label: "one send unconfirmed, retrying", state: "retrying", enabled: true, failed: true, at: -180, next: 120 },
    { label: "two unconfirmed, paused", state: "paused", enabled: true, failed: true, next: 302 * 60 },
    { label: "failed: not a subscription", state: "failed", enabled: true, failed: true, reason: "not-subscription", only: "claude" }
];

// A row as UsageData.starter() gives it, with `now` in epoch seconds.
function starter(row, now) {
    return { enabled: row.enabled, state: row.state, reason: row.reason ?? null, error: row.error ?? null,
             at: row.at !== undefined ? now + row.at : null, next: row.next !== undefined ? now + row.next : null };
}
