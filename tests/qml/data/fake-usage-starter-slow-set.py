# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# As fake-usage-starter.py, but --starter-set is delayed, so a tick
# can come while the switch change is still being written.
import sys
import time

import fake_usage

if "--starter-set" in sys.argv:
    time.sleep(0.2)
    # Keep Claude's two-second deadline due when the switch write finishes.
    fake_usage.NOW -= 2
fake_usage.starter_scenario()
