# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Claude's check fails; Codex is rate limited and asks for a retry in an hour.
from fake_usage import NOW, report

report(claude={"status": "error", "message": "HTTP Error 500: Internal Server Error", "reason": "server",
               "host": "api.anthropic.com", "retryAt": NOW + 300},
       codex={"status": "rate_limited", "retryAfter": 3600, "message": "HTTP Error 429: Too Many Requests",
              "reason": "rate-limited", "host": "", "retryAt": NOW + 3600})
