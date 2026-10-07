# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Both session starters on: Claude's is due now with no session running, so
# --start moves it to confirming; Codex started this week two days ago.
from fake_usage import DAY, ok, report, starter, window

report(claude=ok(window(52, 2 * DAY + 21 * 3600, [(0, 52)]), session=None,
                 starter=starter("waiting", next=0)),
       codex=ok(window(24, 5 * DAY, [(0, 24)]), starter=starter("started", at=-2 * DAY)))
