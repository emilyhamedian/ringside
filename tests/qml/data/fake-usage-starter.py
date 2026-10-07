# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Readings as in fake-usage-ok.py with no Claude session running. Claude's
# session starter is on and due in two seconds, so --start moves it to
# confirming; Codex's is off.
from fake_usage import starter_scenario

starter_scenario()
