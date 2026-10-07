# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Both session starters on and failing: Claude Code isn't installed and
# Codex is signed out. Each checks again in five minutes.
from fake_usage import DAY, ok, report, starter, window

report(claude=ok(window(52, 2 * DAY + 21 * 3600, [(0, 52)]), session=None,
                 starter=starter("failed", next=300, reason="not-installed")),
       codex=ok(window(24, 5 * DAY, [(0, 24)]), starter=starter("failed", next=300, reason="signed-out")))
