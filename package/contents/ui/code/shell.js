// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// What it takes to run the helper scripts through the executable engine.

// A local file URL as a path: "file:///opt/my%20tools" as "/opt/my tools".
function path(url) {
    return decodeURIComponent(String(url).replace(/^file:\/\//, ""));
}

// Text as one sh word: in single quotes, where nothing is special, with
// each quote in it closed, escaped and reopened.
function quoted(text) {
    return "'" + text.replace(/'/g, "'\\''") + "'";
}
