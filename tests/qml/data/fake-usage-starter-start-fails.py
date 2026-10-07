# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# As fake-usage-starter.py, but --start fails with a traceback and no report.
import sys

from fake_usage import starter_scenario

if "--start" in sys.argv:
    print("Traceback (most recent call last):\n  File \"usage.py\"\nRuntimeError: boom\n", file=sys.stderr)
    sys.exit(1)
starter_scenario()
