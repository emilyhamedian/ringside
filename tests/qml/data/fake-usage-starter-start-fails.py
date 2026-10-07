# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# As fake-usage-starter.py, but --start fails with a traceback and no report.
import sys

from fake_usage import DAY, ok, report, starter, window

if "--start" in sys.argv:
    print("Traceback (most recent call last):\n  File \"usage.py\"\nRuntimeError: boom\n", file=sys.stderr)
    sys.exit(1)
report(claude=ok(window(52, 2 * DAY + 21 * 3600, [(0, 52)]), session=None, starter=starter("waiting", next=2)),
       codex=ok(window(24, 5 * DAY + 4 * 3600, [(0, 24)])))
