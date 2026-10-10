# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# A quiet poll as usage.py reports it: readings as in fake-usage-ok.py, one
# polled and one from the cache, each with its debug line.
from fake_usage import DAY, ok, report, window

report(claude=ok(window(52, 2 * DAY)), codex=ok(window(24, 5 * DAY)),
       events=[{"level": "debug", "provider": "claude", "kind": "check", "message": "Claude: checked in 412 ms",
                "ms": 412},
               {"level": "debug", "provider": "codex", "kind": "cached",
                "message": "Codex: the reading taken 60 s ago still stands"}])
