// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// What UsageData shows when the helper itself fails, as opposed to one of
// the providers it polls.

// Why the helper gave no report, from the executable engine's "exit code",
// "exit status" (1 when the process crashed) and "stderr". KProcess starts
// python3 directly, or through /bin/sh when python3 is not on PATH, and sh
// exits 127 for a command it cannot find.
//
// Returns { reason, code, detail }: reason is "missing" (no python3),
// "crashed", "unreadable" (it exited cleanly with no report) or "exited";
// detail is the last line the helper wrote to stderr, which names the error
// in a traceback. UsageData puts it into words.
function helperFailure(data) {
    const code = data["exit code"];
    const reason = data["exit status"] === 1 ? "crashed"
                 : code === 127 ? "missing"
                 : code === 0 ? "unreadable"
                 : "exited";
    const detail = reason === "missing" ? "" : String(data.stderr ?? "").trim().split("\n").pop().trim();
    return { reason: reason, code: code, detail: detail };
}

// What a helper failure is, for the words and for "Try again": "missing"
// when python3 couldn't be found, "files" when it stopped on an error
// reading or writing its files, both of which would only happen again,
// else "helper".
function failureReason(failure) {
    if (failure.reason === "missing") {
        return "missing";
    }
    return /^(OSError|PermissionError|FileNotFoundError|FileExistsError|IsADirectoryError|NotADirectoryError)\b/
        .test(failure.detail) ? "files" : "helper";
}

// The entries with every shown one marked as failed at `at`, keeping its
// last reading, as UsageData.merge() marks a provider's failed check, with
// `reason` from failureReason(). A helper that failed set no hold, so the
// retry waits the five minutes the helper holds a failed provider back, or
// to the end of a longer hold the provider's last report gave, such as a
// rate limit, which the helper still keeps. Signed-out entries are left
// alone, and no entry is added: UsageData adds one first for a provider
// still loading.
function markFailed(entries, message, at, reason) {
    const marked = Object.assign({}, entries);
    for (const id in marked) {
        if (marked[id].status !== "signed_out") {
            const held = Number.isFinite(marked[id].retryAt) ? marked[id].retryAt : 0;
            marked[id] = Object.assign({}, marked[id], { lastError: message, lastErrorAt: at, reason: reason,
                                                         host: "", retryAt: Math.max(at + 300, held) });
        }
    }
    return marked;
}
