# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# As fake-usage-starter.py, but --starter-set takes three seconds, so a tick
# can come while the switch change is still being written.
import sys
import time

from fake_usage import starter_scenario

if "--starter-set" in sys.argv:
    time.sleep(3)
starter_scenario()
