# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Readings as in fake-usage-ok.py with no Claude session running. Claude's
# session starter is on and due in two seconds, so --start moves it to
# confirming; Codex's is off.
from fake_usage import DAY, ok, report, starter, window

report(claude=ok(window(52, 2 * DAY + 21 * 3600, [(0, 52)]), session=None, starter=starter("waiting", next=2)),
       codex=ok(window(24, 5 * DAY + 4 * 3600, [(0, 24)])))
