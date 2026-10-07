# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# As fake-usage-starter.py, but --starter-set takes three seconds, so a tick
# can come while the switch change is still being written.
import sys
import time

from fake_usage import DAY, ok, report, starter, window

if "--starter-set" in sys.argv:
    time.sleep(3)
report(claude=ok(window(52, 2 * DAY + 21 * 3600, [(0, 52)]), session=None, starter=starter("waiting", next=2)),
       codex=ok(window(24, 5 * DAY + 4 * 3600, [(0, 24)])))
