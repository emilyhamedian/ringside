# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Claude at 52 %, reported as usage.py does while the desktop clock shows
# system time: with no clock zone on any time.
from fake_usage import DAY, ok, report, window

report(zoned=False, claude=ok(window(52, 2 * DAY + 21 * 3600, [(0, 52)])))
