# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# The readings of fake-usage-ok.py, a second late, as a check that takes a while.
import time

from fake_usage import DAY, ok, report, window

time.sleep(1)
report(claude=ok(window(52, 2 * DAY + 21 * 3600)), codex=ok(window(24, 5 * DAY + 4 * 3600)))
