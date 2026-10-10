# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Claude's check fails as a helper from before failures had reasons reports it.
from fake_usage import report

report(claude={"status": "error", "message": "HTTP Error 500: Internal Server Error"})
