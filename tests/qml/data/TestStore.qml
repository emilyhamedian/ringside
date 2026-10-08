// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import "../../../package/contents/ui"

// The graphs' history store in a database of the tests' own, so a test run
// never touches what a widget kept.
HistoryStore {
    name: "ringside-tests"
}
