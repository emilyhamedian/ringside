# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# As fake-usage-starter.py, but a switch toggled with --starter-set doesn't
# stick, as when the switch file can't be written.
from fake_usage import DAY, ok, report, starter, window

report(sticks=False,
       claude=ok(window(52, 2 * DAY + 21 * 3600, [(0, 52)]), session=None,
                 starter=starter("waiting", next=0)),
       codex=ok(window(24, 5 * DAY, [(0, 24)]), starter=starter("started", at=-2 * DAY)))
