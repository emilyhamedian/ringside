# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Claude at 52 % with a Fable limit at 78 %, Codex at 24 %: Claude and Codex
# last to their resets at this rate, Fable runs out before its own.
from fake_usage import DAY, limit, ok, report, window

report(claude=ok(window(52, 2 * DAY + 21 * 3600, [(6, 8), (3, 37), (0, 52)]),
                 [limit("Fable", "Fable", window(78, 2 * DAY + 21 * 3600, [(5, 30), (0, 78)]))]),
       codex=ok(window(24, 5 * DAY + 4 * 3600, [(1, 10), (0, 24)])))
