// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import "../../../package/contents/ui"

// The graphs' history store in a database whose table isn't the store's,
// so every read and write fails, as with a damaged file.
HistoryStore {
    name: "ringside-tests-broken"
}
