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
waiting and due now) unless the scenario passes sticks=False, which says
why on stderr as usage.py does when it can't write the switch. --start
reports each listed starter but a failed one as confirming, as a send would:
the widget runs --start only for starters that are switched on and due, so
the fake checks neither. Nothing is remembered between runs.
"""

import json
import sys
import time

NOW = int(time.time())
DAY = 86400
WEEK = 7 * DAY
SESSION = 5 * 3600
# What usage.py prints on stderr when it can't write the switch file.
SWITCH_REFUSED = "[Errno 13] Permission denied: '/home/user/.config/ringside/.starter.kvt5gezx.tmp'"
# The desktop clock's zone, as usage.py adds it to every time it reports.
ZONE = {"offset": -4 * 3600, "abbreviation": "EDT"}


def window(percent, left, history=()):
    """A week resetting `left` seconds from now; history as (days ago, percent)."""
    return {"percent": percent, "resetsAt": NOW + left, "windowSeconds": WEEK,
            "clockZone": ZONE,
            "history": [[NOW - round(days * DAY), percent] for days, percent in history]}


def limit(limit_id, label, week):
    return dict(week, id=limit_id, label=label)


def session(percent, left):
    """Claude's five-hour window, resetting `left` seconds from now."""
    return {"percent": percent, "resetsAt": NOW + left, "windowSeconds": SESSION, "clockZone": ZONE}


def starter(state="off", at=None, next=None, reason=None):
    """A session starter as usage.py reports it; at and next are seconds from now."""
    report = {"enabled": state != "off", "state": state, "at": None if at is None else NOW + at,
              "next": None if next is None else NOW + next, "reason": reason}
    return dict(report, clockZone=ZONE) if at is not None or next is not None else report


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
    if not sticks and values("--starter-set"):
        print(SWITCH_REFUSED, file=sys.stderr)
    for change in values("--starter-set"):
        name, _, value = change.partition("=")
        if sticks and name in providers:
            providers[name]["starter"] = starter("waiting", next=0) if value == "on" else starter()
    if "--start" in sys.argv:
        for entry in providers.values():
            if entry["starter"]["state"] != "failed":
                entry["starter"] = starter("confirming", at=0, next=300)
    print(json.dumps({"fetchedAt": NOW, "providers": providers}))


def starter_scenario(sticks=True):
    """fake-usage-starter.py's report: readings as in fake-usage-ok.py with
    no Claude session running, Claude's starter on and due in two seconds,
    Codex's off."""
    report(sticks=sticks,
           claude=ok(window(52, 2 * DAY + 21 * 3600, [(0, 52)]), session=None, starter=starter("waiting", next=2)),
           codex=ok(window(24, 5 * DAY + 4 * 3600, [(0, 24)])))
