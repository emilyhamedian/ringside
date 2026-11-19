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
if fake_usage.values("--proxy-url") and "--starter-switch-only" not in sys.argv:
    direct = ",".join(fake_usage.values("--direct-providers")).split(",")
    entries = {
        "claude": fake_usage.ok(fake_usage.window(52, fake_usage.DAY), session=None),
        "codex": fake_usage.ok(fake_usage.window(24, fake_usage.DAY), session=fake_usage.session(12, 3600)),
    }
    for name, entry in entries.items():
        if name not in direct:
            entry["source"] = "cliproxyapi"
    fake_usage.report(**entries)
else:
    fake_usage.starter_scenario()
