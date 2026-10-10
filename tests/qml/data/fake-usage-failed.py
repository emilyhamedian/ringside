# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Claude is rate limited and asks for a retry in an hour; Codex's check times out.
from fake_usage import NOW, report

report(claude={"status": "rate_limited", "retryAfter": 3600, "message": "rate limited, retrying in 3600 s",
               "reason": "rate-limited", "host": "api.anthropic.com", "retryAt": NOW + 3600},
       codex={"status": "error", "message": "no answer from codex app-server in 20 s", "reason": "timeout",
              "host": "", "retryAt": NOW + 300})
