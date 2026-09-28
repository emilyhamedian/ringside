# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# What sh reports when python3 isn't on PATH.
import sys

print("sh: 1: python3: not found", file=sys.stderr)
sys.exit(127)
