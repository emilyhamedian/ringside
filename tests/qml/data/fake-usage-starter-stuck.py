# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# As fake-usage-starter.py, but a switch toggled with --starter-set doesn't
# stick, as when the switch file can't be written.
from fake_usage import starter_scenario

starter_scenario(sticks=False)
