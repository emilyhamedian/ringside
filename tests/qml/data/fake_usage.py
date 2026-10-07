# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Stands in for contents/code/usage.py in tst_usage.qml.

Each fake-usage-*.py script beside this one is a scenario: it calls report()
with the entries the helper would give and this prints them as usage.py
does, filtered to the ids after --providers. Times are relative to now, so
countdowns read the same on every run. Nothing is read from the machine and
nothing goes over the network.

Every entry carries a session starter, off unless the scenario gives one.
--starter-set <id>=on|off switches it in the report printed (on reads as
waiting and due now) unless the scenario passes sticks=False, and --start
moves each switched-on starter that is due to confirming, as a send would.
Nothing is remembered between runs.
"""

import json
import sys
import time

NOW = int(time.time())
DAY = 86400
WEEK = 7 * DAY
SESSION = 5 * 3600


def window(percent, left, history=()):
    """A week resetting `left` seconds from now; history as (days ago, percent)."""
    return {"percent": percent, "resetsAt": NOW + left, "windowSeconds": WEEK,
            "clockZone": {"offset": -4 * 3600, "abbreviation": "EDT"},
            "history": [[NOW - round(days * DAY), percent] for days, percent in history]}


def limit(limit_id, label, week):
    return dict(week, id=limit_id, label=label)


def session(percent, left):
    """Claude's five-hour window, resetting `left` seconds from now."""
    return {"percent": percent, "resetsAt": NOW + left, "windowSeconds": SESSION}


def starter(state="off", at=None, next=None, reason=None):
    """A session starter as usage.py reports it; at and next are seconds from now."""
    return {"enabled": state != "off", "state": state, "at": None if at is None else NOW + at,
            "next": None if next is None else NOW + next, "reason": reason}


def ok(weekly, scoped=(), **extra):
    """An ok entry; extra may give Claude's "session" and a "starter"."""
    return {"status": "ok", "fetchedAt": NOW, "weekly": weekly, "scoped": list(scoped), **extra}


def values(flag):
    return [sys.argv[i + 1] for i, arg in enumerate(sys.argv[:-1]) if arg == flag]


def report(sticks=True, **entries):
    requested = sys.argv[sys.argv.index("--providers") + 1].split(",")
    providers = {k: v for k, v in entries.items() if k in requested}
    for entry in providers.values():
        entry.setdefault("starter", starter())
    for change in values("--starter-set"):
        name, _, value = change.partition("=")
        if sticks and name in providers:
            providers[name]["starter"] = starter("waiting", next=0) if value == "on" else starter()
    if "--start" in sys.argv:
        for entry in providers.values():
            due = entry["starter"]
            if due["enabled"] and due["next"] is not None and due["next"] <= NOW and due["state"] != "failed":
                entry["starter"] = starter("confirming", at=0, next=300)
    print(json.dumps({"fetchedAt": NOW, "providers": providers}))
