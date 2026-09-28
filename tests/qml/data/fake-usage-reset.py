# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Claude's week and its Opus limit started over, and a Sonnet limit appeared;
# Codex is as in fake-usage-ok.py.
from fake_usage import DAY, WEEK, limit, ok, report, window

report(claude=ok(window(3, WEEK, [(0, 3)]),
                 [limit("Opus", "Opus", window(1, WEEK, [(0, 1)])),
                  limit("Sonnet", "Sonnet", window(12, 4 * DAY, [(0, 12)]))]),
       codex=ok(window(34, 5 * DAY + 4 * 3600, [(1, 14), (0, 34)])))
