# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Claude is signed out; the codex CLI isn't installed.
from fake_usage import report

report(claude={"status": "signed_out"},
       codex={"status": "error", "message": "codex CLI not found", "reason": "not-installed", "host": ""})
