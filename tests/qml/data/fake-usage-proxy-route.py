# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import time

from fake_usage import DAY, ok, report, values, window


if "claude" in values("--direct-providers"):
    report(claude=ok(window(23, DAY)))
else:
    time.sleep(0.35)
    report(claude=ok(window(84, DAY), source="cliproxyapi"))
