# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Readings as in fake-usage-ok.py, with a journal line at each level and
# two the widget must skip: one at a level it doesn't write, one without
# a message.
from fake_usage import DAY, ok, report, window

report(claude=ok(window(52, 2 * DAY)), codex=ok(window(24, 5 * DAY)),
       events=[{"level": "debug", "provider": "claude", "kind": "check", "message": "Claude: checked in 412 ms",
                "ms": 412},
               {"level": "info", "provider": "codex", "kind": "recovered",
                "message": "Codex: checked in 90 ms, working again after: the Codex CLI didn't answer in 20 s",
                "ms": 90},
               {"level": "warning", "provider": "claude", "kind": "failed",
                "message": "Claude: check failed after 3 ms: can't reach api.anthropic.com", "ms": 3},
               {"level": "critical", "provider": "claude", "kind": "check", "message": "not written"},
               {"level": "info", "provider": "claude", "kind": "check"}])
