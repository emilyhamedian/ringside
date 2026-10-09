# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Two runs at once, as when Codex is turned on while Claude's check runs:
# a run for Claude alone fails after a second, and one for both answers
# after three.
import sys
import time

from fake_usage import DAY, ok, report, window

if sys.argv[sys.argv.index("--providers") + 1] == "claude":
    time.sleep(1)
    print("boom", file=sys.stderr)
    sys.exit(3)
time.sleep(3)
report(claude=ok(window(52, 2 * DAY + 21 * 3600)), codex=ok(window(24, 5 * DAY + 4 * 3600)))
