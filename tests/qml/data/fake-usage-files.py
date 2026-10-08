# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# The helper failing on its own files, with a traceback and no report.
import sys

print("Traceback (most recent call last):\n  File \"usage.py\"\n"
      "PermissionError: [Errno 13] Permission denied: '/home/user/.cache/ringside/usage.json'\n", file=sys.stderr)
sys.exit(1)
