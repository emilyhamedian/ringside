# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Stands in for contents/code/usage.py in tst_usage.qml.

Each fake-usage-*.py script beside this one is a scenario: it calls report()
with the entries the helper would give and this prints them as usage.py
does, filtered to the ids after --providers. Times are relative to now, so
countdowns read the same on every run. Nothing is read from the machine and
nothing goes over the network.
"""

import json
import sys
import time

NOW = int(time.time())
DAY = 86400
WEEK = 7 * DAY


def window(percent, left, history=()):
    """A week resetting `left` seconds from now; history as (days ago, percent)."""
    return {"percent": percent, "resetsAt": NOW + left, "windowSeconds": WEEK,
            "clockZone": {"offset": -4 * 3600, "abbreviation": "EDT"},
            "history": [[NOW - round(days * DAY), percent] for days, percent in history]}


def limit(limit_id, label, week):
    return dict(week, id=limit_id, label=label)


def ok(weekly, scoped=()):
    return {"status": "ok", "fetchedAt": NOW, "weekly": weekly, "scoped": list(scoped)}


def report(**entries):
    requested = sys.argv[sys.argv.index("--providers") + 1].split(",")
    print(json.dumps({"fetchedAt": NOW,
                      "providers": {k: v for k, v in entries.items() if k in requested}}))
