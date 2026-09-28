# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Claude at 62 % with an Opus limit at 78 %, Codex at 34 %.
from fake_usage import DAY, limit, ok, report, window

report(claude=ok(window(62, 2 * DAY + 21 * 3600, [(6, 9), (3, 44), (0, 62)]),
                 [limit("Opus", "Opus", window(78, 2 * DAY + 21 * 3600, [(5, 30), (0, 78)]))]),
       codex=ok(window(34, 5 * DAY + 4 * 3600, [(1, 14), (0, 34)])))
