#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Report the weekly usage windows of Claude Code and Codex as one JSON object.

Ringside runs this on a timer while a Claude or Codex item is switched on.
Each provider is queried on its own, so a failure on one side never hides the
other. Output shape:

    {"fetchedAt": <epoch seconds>,
     "providers": {
         "claude": {"status": "ok", "fetchedAt": ..., "weekly": {...}, "scoped": [...]},
         "codex":  {"status": "ok", "fetchedAt": ..., "weekly": {...}, "scoped": [...]}}}

--providers claude,codex names the providers to poll and report; both by
default. A window is {"percent": 0-100, "resetsAt": <epoch seconds>,
"windowSeconds": <its length>, "history": [[<epoch seconds>, <percent>], ...]}.
"weekly" is the all-models window; "scoped" lists the model-specific weekly
windows, each a window with an "id" that stays stable across polls and a
display "label". An ok entry's "fetchedAt" is when it was polled, which a
cached reading keeps. Status is one of "ok", "signed_out", "rate_limited"
(with "retryAfter", the seconds until the provider is polled again) or
"error", and the last two carry a "message" to show, a "reason" the widget
can put in its own words ("offline", "timeout", "server", "rate-limited",
"not-installed" when the Codex CLI isn't, "program" when the codex program
chosen with --program can't be run, "busy" when another run held the lock
too long, or "other"), the "host" that failed, or "" when none did, and
"retryAt", when the provider may be polled again (epoch seconds). Tokens
never reach stdout or stderr.

The report also carries "events", the lines this run has for Plasma's
journal (see event()), which the widget writes there and the cache never
holds.

When Plasma's digital clock shows a zone other than system time, every window
also carries "clockZone": {"offset": <seconds east of UTC>, "abbreviation":
"EDT"}, the zone's offset and abbreviation at that window's reset. Claude's
session does too, and so does each starter with a time, at its next time
or, without one, at its last; a starter with a last time also carries
"atClockZone", the zone at that time.

Every poll's result, a failure or a sign-out as much as a reading, is kept
in $XDG_CACHE_HOME/ringside for five minutes and served from there, so no
widget, reload or restart spends another call on Anthropic's tightly
rate-limited usage endpoint before then. A rate-limit reply is kept for as
long as it asked, if that is longer. A lock held for the whole run makes a
second widget that starts at the same time wait and then read this run's
result instead of polling again.

The APIs only report the current percentage, so each real poll also adds it to
the window's history in the same folder. A window's "history" holds the
points of its current span, oldest first.

Claude's entry also carries "session", its five-hour window, or null when
no session is running; it is left out when the reply doesn't say.

--program <provider>=<path> names the program to run for a provider, as the
user chose it in Ringside's settings; ~ stands for the home folder. Without
one, the program is found by itself (see find_cli()). Every entry carries
"program": {"path": <where it is, or "" when it isn't found>, "chosen":
bool, "problem": "" or what keeps a chosen path from running: "missing",
"not-executable" or "folder"}, looked up afresh on every run.

Every entry carries "starter", the session starter's state: {"enabled":
bool, "state": ..., "at": <epoch seconds> or null, "next": <epoch seconds>
or null, "reason": ... or null}. The states are "off"; "waiting" (next is
when the next window starts); "confirming" (at is the send, next the read
that confirms it); "started" (at is when the window started, next when the
next one starts, which the popup shows only for Claude); "weekly" (the
weekly limit is reached; next is its reset); "failed" (reason says why:
"not-installed", "program" for a chosen program that can't be run,
"signed-out", "not-subscription" for a CLI logged in other than with a
claude.ai subscription, "not-responding" for one whose
check before sending failed, "unchecked" for a failed read or a reading
that doesn't say when a reached weekly limit or a running week ends, or
"not-sent" for a send that never left; the last three back off, with next
the retry);
"retrying" (one send went unconfirmed; at is the send, next the retry) and
"paused" (two in a row; next is when the hold ends). The widget runs
--start once Date.now() reaches next, and --starter-set when its switch is
toggled.

Set RINGSIDE_USAGE_FAKE to a JSON report to print it instead of polling,
limited to the requested providers and with the clock zone added as on a live
run. --start and --starter-set change nothing then, and each "program" is
as the file gives it.
"""

import argparse
import contextlib
import errno
import fcntl
import json
import math
import os
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

VERSION = "0.3.0"

PROVIDERS = ("claude", "codex")

WEEK_MINUTES = 7 * 24 * 60
WEEK_SECONDS = WEEK_MINUTES * 60

# The CLIs' own config homes, which move with CLAUDE_CONFIG_DIR and CODEX_HOME.
CLAUDE_CREDENTIALS = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude") / ".credentials.json"
CLAUDE_USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
CLAUDE_TOKEN_URL = "https://platform.claude.com/v1/oauth/token"
# Public client id of the Claude Code CLI; the refresh grant needs it.
CLAUDE_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
CLAUDE_BETA_HEADER = "oauth-2025-04-20"
# Cloudflare in front of platform.claude.com rejects the stock urllib agent outright.
USER_AGENT = f"ringside/{VERSION}"
# Seconds before expiry to refresh the access token.
CLAUDE_EXPIRY_MARGIN = 60

CODEX_AUTH = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex") / "auth.json"

# How long a provider has to answer, Anthropic's servers or the Codex CLI
# alike: long enough for a lossy connection's retries to get through.
ANSWER_TIMEOUT = 20
# Seconds to wait after a 429 whose Retry-After is missing or unreadable.
RETRY_AFTER_DEFAULT = 60

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "ringside"
CACHE_FILE = CACHE_DIR / "usage.json"
HISTORY_FILE = CACHE_DIR / "usage-history.json"
LOCK_FILE = CACHE_DIR / "usage.lock"
CACHE_TTL = 5 * 60
# How long a run waits for another to finish before giving up. A poll takes
# at most about 70 s (Codex, then a token refresh and a poll); a starter
# send, which holds the lock throughout, about 130 s (a poll, a renewal,
# the preflight and the send).
LOCK_WAIT = 150
# The longest a refusal holds a provider back, whatever Retry-After says.
HOLD_MAX = 24 * 3600
# A week of polls five minutes apart is 2016 points; flat stretches collapse,
# so this is only reached by a series that changes on nearly every poll.
HISTORY_POINTS = 2100
# A fall of this many points means the provider cleared the window early.
HISTORY_CLEARED = 20

# The programs chosen with --program, by provider. A chosen program is the
# only one run for its provider: one that can't run is reported, never
# swapped for another the user didn't pick.
PROGRAMS = {}

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
APPLETSRC = CONFIG_HOME / "plasma-org.kde.plasma.desktop-appletsrc"
CLOCK_PLUGIN = "org.kde.plasma.digitalclock"

# The session starter's per-user switch, its runtime state, and the empty
# folder the CLIs run in, so no project's instructions or settings load.
STARTER_FILE = CONFIG_HOME / "ringside" / "starter.json"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state") / "ringside"
STARTER_STATE = STATE_DIR / "starter.json"
SWITCH_LOCK = STATE_DIR / "starter.lock"
WORK_DIR = STATE_DIR / "work"
SESSION_SECONDS = 5 * 3600
# A send is confirmed by a reading taken this long after it. One taken
# sooner than CONFIRM_SLACK after it can't confirm it: a week Codex started
# during a send of up to SEND_TIMEOUT must sit clear of ROLLING_SLACK.
CONFIRM_DELAY = 5 * 60
CONFIRM_SLACK = 4 * 60
# Failed reads and sends that never left wait 5, 15, then 60 minutes.
RETRY_DELAYS = (5 * 60, 15 * 60, 3600)
# Two unconfirmed sends in a row hold the starter this long.
PAUSE = 5 * 3600
# Codex reports an idle account's window as a week from the moment it is
# asked; a reset within this many seconds of that is no window at all.
ROLLING_SLACK = 120
# Renew Claude's login before a send if it expires within this many
# seconds, so the CLI has no reason to spend the refresh token itself.
CLI_TOKEN_MARGIN = 15 * 60
CLAUDE_MODEL = "haiku"
# Codex sends with the newest Luna model the CLI's own model list offers,
# at the lightest reasoning effort it lists; these when the list can't say.
CODEX_MODEL = "gpt-6-luna"
CODEX_EFFORT = "low"
# Reasoning efforts, lightest first.
EFFORTS = ("minimal", "low", "medium", "high", "xhigh", "max")
CODEX_MODEL_CACHE = CODEX_AUTH.parent / "models_cache.json"
PROMPT = "Hi"
PREFLIGHT_TIMEOUT = 20
SEND_TIMEOUT = 60


class SignedOut(Exception):
    pass


class Busy(RuntimeError):
    def __init__(self):
        super().__init__("another usage check is still running")


class RateLimited(Exception):
    def __init__(self, retry_after, host=""):
        super().__init__(f"rate limited, retrying in {retry_after} s")
        self.retry_after = retry_after
        self.host = host


class CheckFailed(RuntimeError):
    """A failed check whose cause is known: reason is "offline", "timeout",
    "server", "not-installed" or "program", host the server that failed, or
    "" for the Codex CLI, and status the HTTP status a server answered with."""

    def __init__(self, message, reason, host="", status=None):
        super().__init__(message)
        self.reason = reason
        self.host = host
        self.status = status


# --- journal ---------------------------------------------------------------

# The lines this run asks the widget to write to Plasma's journal, sent as
# the report's "events": [{"level": "debug", "info" or "warning",
# "provider", "kind", "message", "ms" where a check took time}]. Failures
# and changes are info or warning; each check, cached reading and step is
# debug. Messages are put together here from Ringside's own words and from
# fields whose values it knows: a reason, one of its own hosts, an HTTP
# status, a number. Never from an exception's text, a reply, a file or a
# token, so none of those can reach the journal.
EVENTS = []

NAMES = {"claude": "Claude", "codex": "Codex"}
# What signs a provider in, as the journal names it.
PRODUCTS = {"claude": "Claude Code", "codex": "the Codex CLI"}
# Who asks Ringside to wait, when the refusal names no host.
COMPANIES = {"claude": "Anthropic", "codex": "OpenAI"}
WINDOWS = {"claude": "session", "codex": "week"}

MESSAGES = {
    "check": "{name}: checked in {ms} ms",
    "cached": "{name}: the reading taken {age} s ago still stands",
    "held": "{name}: next check in {wait} s, after {why}",
    "failed": "{name}: check failed after {ms} ms: {why}",
    "failed-again": "{name}: check failed again after {ms} ms: {why}",
    "recovered": "{name}: checked in {ms} ms, working again after: {why}",
    "wait-over": "{name}: the wait {who} asked for is over",
    "busy": "{name}: no check: another usage check held the lock for over {wait} s",
    "cli": "{name}: asking {cli} app-server",
    "renewed": "{name}: renewed the Claude Code login",
    "starter-on": "{name} session starter switched on",
    "starter-off": "{name} session starter switched off",
    "starter-switch-failed": "{name} session starter switch not saved: {why}",
    "starter-sent": "{name} session starter sent its message; a reading in {wait} s confirms it",
    "starter-confirmed": "{name} session starter: the new {window} started",
    "starter-unconfirmed": "{name} session starter: no new {window} after its message; trying once more in {wait} s",
    "starter-paused": "{name} session starter paused for {hours} h: two messages in a row started no {window}",
    "starter-failed": "{name} session starter can't send: {why}; trying again in {wait} s",
    "starter-failed-again": "{name} session starter still can't send: {why}; trying again in {wait} s",
    "starter-switched-off": "{name} session starter was switched off before its message went out",
    "starter-next": "{name} session starter is {state}; next step at {at}",
    "starter-stopped": "{name} session starter didn't run: {why}",
}

# Why a session starter can't send, by its reason.
STARTER_WHY = {
    "not-installed": "the CLI isn't installed",
    "program": "the program set in Settings can't be run",
    "signed-out": "the CLI is signed out",
    "not-subscription": "the CLI isn't signed in with a subscription",
    "not-responding": "the CLI didn't answer its check before sending",
    "unchecked": "the limits couldn't be read",
    "not-sent": "the message couldn't be sent",
}


def event(level, provider, kind, ms=None, **fields):
    entry = {"level": level, "provider": provider, "kind": kind,
             "message": MESSAGES[kind].format(name=NAMES[provider], ms=ms, **fields)}
    if ms is not None:
        entry["ms"] = ms
    EVENTS.append(entry)


def own_host(host):
    """host if it is one Ringside asks, else "": a cache that was tampered
    with can't put anything else in the journal."""
    return host if host in (CLAUDE_USAGE_URL.split("/")[2], CLAUDE_TOKEN_URL.split("/")[2]) else ""


def failure_why(name, failure, asked=None, hold=None):
    """A failure, as the popup gives it, from its status, reason, host and
    HTTP status alone: a report from poll() or a cached hold."""
    host = own_host(failure.get("host"))
    reason = failure.get("reason")
    if failure.get("status") == "signed_out":
        return f"{PRODUCTS[name]} is signed out"
    if failure.get("status") == "rate_limited":
        why = f"{host or COMPANIES[name]} asked Ringside to wait"
        if type(asked) is int:
            why += f" {asked} s"
        return why + (f"; next check in {hold} s" if type(hold) is int else "")
    if reason == "offline":
        return f"can't reach {host or 'the server'}"
    if reason == "timeout":
        return f"{host} didn't answer in time" if host else f"the Codex CLI didn't answer in {ANSWER_TIMEOUT} s"
    if reason == "server":
        status = failure.get("httpStatus")
        return f"{host or 'the server'} answered with " + (f"HTTP {status}" if type(status) is int else "an error")
    if reason == "not-installed":
        return "the codex CLI isn't installed"
    if reason == "program":
        # A hold keeps the program it was for, which a recovery may have
        # moved on from.
        chosen = failure.get("program")
        return program_why(name, chosen if isinstance(chosen, str) else PROGRAMS.get(name, ""))
    return "an unexpected error, which the popup shows"


# What keeps a chosen program from running, by find_cli()'s problem.
PROGRAM_PROBLEMS = {"missing": "there is no file there", "not-executable": "it isn't marked executable",
                    "folder": "it is a folder"}


def program_why(name, chosen):
    """Why the program chosen for name can't run, naming it as the settings
    show it, with the home folder as ~. The path is the user's own setting."""
    path, problem = find_cli(name, chosen)
    why = f"the {name} program set in Settings, {shown_path(path)}, can't be run"
    return why + (f": {PROGRAM_PROBLEMS[problem]}" if problem in PROGRAM_PROBLEMS else "")


def os_why(err):
    """An OSError or Busy in the system's words, without the file name."""
    if isinstance(err, Busy):
        return str(err)
    return os.strerror(err.errno) if err.errno else "an unknown error"


def shown_path(path):
    """A path with the home folder as ~, so the journal doesn't name the user."""
    home = str(Path.home())
    return "~" + path[len(home):] if path.startswith(home + "/") else path


def note_check(name, report, previous, ms, entry):
    """The journal's line for a provider's poll: a failure when it starts or
    its reason changes, the first success after one, and anything else,
    each repeat of a failure among it, as debug. previous is the cache's
    entry from the poll before, entry the one this poll left there."""
    failed_before = isinstance(previous, dict) and previous.get("status") in ("error", "signed_out", "rate_limited")
    if failed_before and previous["status"] == "rate_limited" and report["status"] != "rate_limited":
        event("info", name, "wait-over", who=own_host(previous.get("host")) or COMPANIES[name])
    if report["status"] == "ok":
        if failed_before:
            event("info", name, "recovered", ms, why=failure_why(name, previous))
        else:
            event("debug", name, "check", ms)
        return
    why = failure_why(name, report, report.get("retryAfter"), entry.get("holdSeconds"))
    again = failed_before and (previous["status"], previous.get("reason"), own_host(previous.get("host"))) \
        == (report["status"], report.get("reason"), own_host(report.get("host")))
    level = "debug" if again else "info" if report["status"] == "signed_out" else "warning"
    event(level, name, "failed-again" if again else "failed", ms, why=why)


# --- Codex -----------------------------------------------------------------


def find_cli(name, chosen=""):
    """Where the name program is and what keeps it from running, as (path,
    problem).

    A chosen path, with ~ expanded, is the only place looked: it is a file
    that can be run, or problem says why not, "missing", "not-executable" or
    "folder". A relative path is missing, as it names no place. Without
    one, ~/.local/bin/<name> if executable, else name on PATH, which in a
    Plasma session may lack ~/.local/bin; path is "" when neither has it.
    """
    if chosen:
        path = os.path.expanduser(chosen)
        try:
            mode = os.stat(path).st_mode if os.path.isabs(path) else None
        except (OSError, ValueError):
            mode = None
        if mode is None:
            return path, "missing"
        if stat.S_ISDIR(mode):
            return path, "folder"
        if not stat.S_ISREG(mode) or not os.access(path, os.X_OK):
            return path, "not-executable"
        return path, ""
    wrapper = Path.home() / ".local" / "bin" / name
    if os.access(wrapper, os.X_OK):
        return str(wrapper), ""
    return shutil.which(name) or "", ""


def program(name):
    """The report's "program" for a provider."""
    chosen = PROGRAMS.get(name, "")
    path, problem = find_cli(name, chosen)
    return {"path": path, "chosen": chosen != "", "problem": problem}


def codex_rate_limits(binary):
    """Ask a fresh app-server for the account's rate limits.

    The server keeps running until told otherwise, so the response is read
    line by line and the server is stopped once the answer with id 2 arrives
    or the deadline passes. It runs in its own session so that stopping it
    also ends whatever it started there. A process started outside that
    session, such as one a wrapper hands to a container runtime, can keep
    stdout open after the kill, so reading stops at the deadline regardless.
    """
    proc = subprocess.Popen(
        [binary, "app-server", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.monotonic() + ANSWER_TIMEOUT
    try:
        for message in (
            {"id": 1, "method": "initialize",
             "params": {"clientInfo": {"name": "ringside", "title": "Ringside",
                                       "version": VERSION}}},
            {"method": "initialized"},
            {"id": 2, "method": "account/rateLimits/read"},
        ):
            proc.stdin.write((json.dumps(message) + "\n").encode())
        proc.stdin.flush()
        for line in lines_until(proc.stdout, deadline):
            try:
                reply = json.loads(line)
            except ValueError:
                continue
            if isinstance(reply, dict) and reply.get("id") == 2:
                if "error" in reply:
                    raise RuntimeError(str((reply["error"] or {}).get("message") or "app-server error"))
                return reply["result"]
        if time.monotonic() >= deadline:
            raise CheckFailed(f"no answer from codex app-server in {ANSWER_TIMEOUT} s", "timeout")
        raise RuntimeError("app-server closed without answering")
    finally:
        stop_session(proc)
        proc.stdout.close()
        with contextlib.suppress(subprocess.TimeoutExpired):
            proc.wait(timeout=5)


def lines_until(stream, deadline):
    """The lines of a pipe as they arrive, until it closes or the deadline
    (on time.monotonic()) passes."""
    fd = stream.fileno()
    pending = b""
    with selectors.DefaultSelector() as selector:
        selector.register(fd, selectors.EVENT_READ)
        while True:
            left = deadline - time.monotonic()
            if left <= 0 or not selector.select(left):
                return
            chunk = os.read(fd, 65536)
            if not chunk:
                return
            *lines, pending = (pending + chunk).split(b"\n")
            for line in lines:
                yield line.decode("utf-8", "replace")


def stop_session(proc):
    with contextlib.suppress(OSError):
        proc.stdin.close()
    with contextlib.suppress(ProcessLookupError):
        os.killpg(proc.pid, signal.SIGKILL)


def seven_day_window(limit):
    """The limit's window that spans exactly seven days; Codex may put it in either slot."""
    for window in (limit.get("primary"), limit.get("secondary")):
        if window and window.get("windowDurationMins") == WEEK_MINUTES:
            return window
    return None


def weekly_window(limit):
    """Pick the seven-day window, falling back to the longest window present."""
    windows = [w for w in (limit.get("primary"), limit.get("secondary")) if w]
    if not windows:
        return None
    return seven_day_window(limit) or max(windows, key=lambda w: w.get("windowDurationMins", 0))


def codex_window(window):
    """A Codex window, as long as it says it is; one that doesn't say counts as a week."""
    return window_from(window.get("usedPercent"), window.get("resetsAt"),
                       int(window.get("windowDurationMins") or WEEK_MINUTES) * 60)


def parse_codex(result):
    """Reduce an account/rateLimits/read result to its weekly windows.

    The account-wide "codex" limit gives the all-models window. Every other
    limit is model-specific and joins "scoped" when it has a seven-day window,
    keyed by its limit id. They are sorted by id: each poll starts a fresh
    app-server, so the order it lists them in is not guaranteed.
    """
    by_id = result.get("rateLimitsByLimitId") or {}
    limit = by_id.get("codex") or result.get("rateLimits")
    if not limit:
        raise RuntimeError("no rate limits in app-server reply")
    window = weekly_window(limit)
    if not window:
        raise RuntimeError("no usage window in app-server reply")
    # As for Claude: a missing share read as 0% could pass for an idle week.
    if type(window.get("usedPercent")) not in (int, float):
        raise RuntimeError("no usage share in app-server reply")
    scoped = []
    for limit_id, other in sorted(by_id.items()):
        weekly = seven_day_window(other) if limit_id != "codex" and other else None
        if weekly:
            scoped.append({"id": limit_id, "label": other.get("limitName") or limit_id,
                           **codex_window(weekly)})
    return {"weekly": codex_window(window), "scoped": scoped}


def codex_usage():
    if not CODEX_AUTH.exists():
        raise SignedOut()
    binary, problem = find_cli("codex", PROGRAMS.get("codex", ""))
    if problem:
        raise CheckFailed("the codex program set in Settings can't be run", "program")
    if not binary:
        raise CheckFailed("codex CLI not found", "not-installed")
    event("debug", "codex", "cli", cli=shown_path(binary))
    try:
        result = codex_rate_limits(binary)
    except RuntimeError as err:
        if re.search(r"auth|log ?in|logged", str(err), re.IGNORECASE):
            raise SignedOut() from err
        raise
    return parse_codex(result)


# --- Claude ----------------------------------------------------------------


def read_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def retry_seconds(value):
    """Seconds to wait from a Retry-After header, which holds either a delay
    or an HTTP date; at least one second."""
    if not value:
        return RETRY_AFTER_DEFAULT
    try:
        return max(1, int(value))
    except ValueError:
        pass
    try:
        at = parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return RETRY_AFTER_DEFAULT
    if at.tzinfo is None:
        at = at.replace(tzinfo=timezone.utc)
    return max(1, math.ceil(at.timestamp() - time.time()))


def http_json(url, headers, body=None):
    host = url.split("/")[2]
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, headers={"User-Agent": USER_AGENT, **headers},
                                     method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(request, timeout=ANSWER_TIMEOUT) as response:
            return json.load(response)
    except urllib.error.HTTPError as err:
        if err.code == 401:
            raise SignedOut() from err
        if err.code == 429:
            raise RateLimited(retry_seconds(err.headers.get("retry-after")), host) from err
        raise CheckFailed(f"HTTP {err.code} from {host}", "server", host, err.code) from err
    except urllib.error.URLError as err:
        # A socket error's str() leads with its errno, as in "[Errno -2] Name or
        # service not known"; strerror is the readable part.
        reason = getattr(err.reason, "strerror", None) or err.reason
        raise CheckFailed(f"can't reach {host}: {reason}",
                          "timeout" if isinstance(err.reason, TimeoutError) else "offline", host) from err
    except OSError as err:
        raise CheckFailed(f"can't reach {host}: {err.strerror or 'timed out'}",
                          "timeout" if isinstance(err, TimeoutError) else "offline", host) from err
    except ValueError as err:
        raise CheckFailed(f"unreadable reply from {host}", "server", host) from err


def usable(token):
    """A token that can go into a header as it is. One with whitespace or
    control characters would make http.client fail with the token in the
    error message, so it counts as no token at all."""
    return (isinstance(token, str) and token != "" and token.isascii() and token.isprintable()
            and not any(c.isspace() for c in token))


def read_oauth(path):
    """The claudeAiOauth record and the file's bytes. A record without a
    usable access token means signed out."""
    try:
        raw = path.read_bytes()
        data = json.loads(raw)
    except FileNotFoundError:
        raise SignedOut() from None
    except (OSError, ValueError):
        raise RuntimeError("Claude Code's credentials can't be read") from None
    oauth = data.get("claudeAiOauth") if isinstance(data, dict) else None
    if not isinstance(oauth, dict) or not usable(oauth.get("accessToken")):
        raise SignedOut()
    return oauth, raw


def generation(oauth):
    return oauth.get("accessToken"), oauth.get("refreshToken"), oauth.get("expiresAt")


def expired(oauth, margin=CLAUDE_EXPIRY_MARGIN):
    try:
        return float(oauth.get("expiresAt") or 0) / 1000 - time.time() <= margin
    except (TypeError, ValueError, OverflowError):
        return True


def seconds(value):
    """A non-negative number of seconds from a reply field, or None."""
    try:
        number = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return number if math.isfinite(number) and number >= 0 else None


def write_all(fd, data):
    """Write every byte of data or raise. write(2) takes only part of it when
    the disk is nearly full, and says so only in the count it returns."""
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        if not written:
            raise OSError(errno.ENOSPC, os.strerror(errno.ENOSPC))
        view = view[written:]


def check_writable(path):
    """Fail before a refresh token is spent if the renewed pair couldn't be
    saved: the folder and file must be writable, and the folder must take a
    file of about the same size. Random bytes, since zeros take no room on a
    compressing file system."""
    folder = path.parent
    reason = None
    if not os.access(folder, os.W_OK | os.X_OK) or not os.access(path, os.W_OK):
        reason = "the credentials file or its folder is not writable"
    else:
        try:
            fd, probe = tempfile.mkstemp(dir=folder, prefix=".credentials.", suffix=".probe")
            try:
                write_all(fd, os.urandom(os.stat(path).st_size + 4096))
                os.fsync(fd)
            finally:
                os.close(fd)
                os.unlink(probe)
        except OSError as err:
            reason = f"the credentials folder can't take a new file ({err.strerror})"
    if reason:
        raise RuntimeError(f"{reason}; leaving the expired login for Claude Code to renew")


def refresh_claude(oauth):
    """Exchange the refresh token the way the CLI does and return the fields
    that change.

    The old refresh token is spent once the POST succeeds, so after it
    nothing may fail but the write itself: every field of the reply is read
    leniently. Without expires_in the new access token counts as expired at
    once, so the next poll renews it again.
    """
    reply = http_json(
        CLAUDE_TOKEN_URL,
        {"Content-Type": "application/json"},
        {"grant_type": "refresh_token",
         "refresh_token": oauth["refreshToken"],
         "client_id": oauth.get("clientId") or CLAUDE_CLIENT_ID,
         "scope": " ".join(s for s in (oauth.get("scopes") or []) if isinstance(s, str))},
    )
    if not isinstance(reply, dict):
        reply = {}
    refresh = reply["refresh_token"] if usable(reply.get("refresh_token")) else oauth["refreshToken"]
    if not usable(reply.get("access_token")):
        # The old refresh token may be spent, so keep the new one; the stale
        # access token stays, expired, and the next poll renews again.
        return {"refreshToken": refresh, "expiresAt": 0}
    now_ms = int(time.time() * 1000)
    fresh = {"accessToken": reply["access_token"],
             "refreshToken": refresh,
             "expiresAt": now_ms + int((seconds(reply.get("expires_in")) or 0) * 1000)}
    refresh_left = seconds(reply.get("refresh_token_expires_in"))
    if refresh_left:
        fresh["refreshTokenExpiresAt"] = now_ms + int(refresh_left * 1000)
    if isinstance(reply.get("scope"), str) and reply["scope"].strip():
        fresh["scopes"] = reply["scope"].split()
    return fresh


def store_claude(path, spent, fresh):
    """Write a renewed pair back unless something else renewed first.

    Refresh tokens are single use, so whoever renewed last owns the valid
    pair. The file is re-read and only replaced while it still holds the
    token this run spent, and the bytes are compared again just before the
    write; other keys in the file and in the record are kept. A reader that
    catches another writer mid-way waits and tries again. The new file
    replaces the old in one step, and the folder is synced after, so a crash
    can't bring the spent token back. A file that can't be replaced (bind
    mounted, or in a sticky folder) is rewritten in place instead, and if
    that fails too the new file is left beside it rather than lost.
    """
    for attempt in range(5):
        if attempt:
            time.sleep(0.2)
        try:
            raw = path.read_bytes()
            current = json.loads(raw)
        except (OSError, ValueError):
            continue
        stored = current.get("claudeAiOauth") if isinstance(current, dict) else None
        if not isinstance(stored, dict) or stored.get("refreshToken") != spent:
            return False
        current["claudeAiOauth"] = {**stored, **fresh}
        data = json.dumps(current).encode()
        fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".credentials.", suffix=".tmp")
        kept = False
        try:
            try:
                os.fchmod(fd, 0o600)
                write_all(fd, data)
                os.fsync(fd)
            finally:
                os.close(fd)
            if path.read_bytes() != raw:
                continue
            try:
                os.replace(tmp, path)
                folder = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
                try:
                    os.fsync(folder)
                finally:
                    os.close(folder)
                return True
            except OSError:
                pass
            try:
                with open(path, "r+b") as fh:
                    if fh.read() != raw:
                        continue
                    fh.seek(0)
                    fh.write(data)
                    fh.truncate()
                    fh.flush()
                    os.fsync(fh.fileno())
                return True
            except OSError as err:
                kept = True
                raise RuntimeError(f"the renewed login couldn't be saved ({err.strerror}); "
                                   f"it is in {os.path.basename(tmp)} beside the credentials file") from None
        except OSError as err:
            raise RuntimeError(f"the renewed login couldn't be saved ({err.strerror})") from None
        finally:
            if not kept and os.path.exists(tmp):
                os.unlink(tmp)
    raise RuntimeError("Claude Code's credentials kept changing; the renewed login wasn't saved")


def claude_access_token(margin=CLAUDE_EXPIRY_MARGIN):
    """A usable access token, renewed first if it expires within margin
    seconds."""
    path = CLAUDE_CREDENTIALS
    if not path.exists():
        raise SignedOut()
    path = path.resolve()
    oauth, _ = read_oauth(path)
    if not expired(oauth, margin):
        return oauth["accessToken"]
    if not usable(oauth.get("refreshToken")):
        raise SignedOut()
    # Spending the CLI's single-use refresh token without saving the new pair
    # would sign Claude Code out, so check the write can happen first, then
    # read the file once more in case the CLI renewed it meanwhile.
    check_writable(path)
    current, _ = read_oauth(path)
    if generation(current) != generation(oauth):
        if not expired(current, margin):
            return current["accessToken"]
        if not usable(current.get("refreshToken")):
            raise SignedOut()
    try:
        fresh = refresh_claude(current)
    except Exception:
        latest, _ = read_oauth(path)
        if generation(latest) != generation(current) and not expired(latest, margin):
            return latest["accessToken"]
        raise
    store_claude(path, current["refreshToken"], fresh)
    event("debug", "claude", "renewed")
    if "accessToken" not in fresh:
        raise RuntimeError("the token refresh returned no usable access token")
    return fresh["accessToken"]


def parse_claude(usage):
    """Reduce an /api/oauth/usage body to its weekly windows.

    The all-models window is the top-level seven_day entry. Model-specific
    weekly windows arrive in the limits list as weekly_scoped entries and join
    "scoped" in the order listed. Each is keyed by the model's display name:
    the endpoint leaves the model id empty today, and staying on the name keeps
    a pinned choice valid if ids appear later. Entries scoped to something
    other than a model are skipped. "session" is the five-hour window, null
    while no session is running, and left out when the reply doesn't say.
    """
    weekly = usage.get("seven_day")
    if not weekly:
        raise RuntimeError("no weekly window in usage reply")
    # Read as 0%, a missing share would let the starter send past a reached
    # weekly limit.
    if type(weekly.get("utilization")) not in (int, float):
        raise RuntimeError("no weekly utilization in usage reply")
    scoped = []
    for limit in usage.get("limits") or []:
        name = ((limit.get("scope") or {}).get("model") or {}).get("display_name") or ""
        if limit.get("kind") == "weekly_scoped" and name and all(s["id"] != name for s in scoped):
            scoped.append({"id": name, "label": name,
                           **window_from(limit.get("percent"), limit.get("resets_at"), WEEK_SECONDS)})
    reading = {"weekly": window_from(weekly.get("utilization"), weekly.get("resets_at"), WEEK_SECONDS),
               "scoped": scoped}
    with contextlib.suppress(ValueError):
        reading["session"] = parse_session(usage)
    return reading


def parse_session(usage):
    """The five-hour window, or None when the reply says no session is
    running: five_hour null, or at 0% with no reset. A reply that leaves
    five_hour out or garbles it raises ValueError, since the starter would
    otherwise send into a session that runs."""
    if "five_hour" not in usage:
        raise ValueError("no five_hour in usage reply")
    session = usage["five_hour"]
    if session is None:
        return None
    if not isinstance(session, dict) or "resets_at" not in session:
        raise ValueError("five_hour is not a window")
    percent = session.get("utilization")
    if type(percent) not in (int, float):
        raise ValueError("five_hour has no utilization")
    reset = epoch_seconds(session["resets_at"])
    if reset is None and (session["resets_at"] is not None or percent != 0):
        raise ValueError("five_hour has no reset")
    return window_from(percent, reset, SESSION_SECONDS)


def claude_usage():
    token = claude_access_token()
    usage = http_json(CLAUDE_USAGE_URL, {
        "Authorization": f"Bearer {token}",
        "anthropic-beta": CLAUDE_BETA_HEADER,
        "Content-Type": "application/json",
    })
    return parse_claude(usage)


# --- shared ----------------------------------------------------------------


def clamp_percent(value):
    try:
        return max(0, min(100, round(float(value))))
    except (TypeError, ValueError):
        return 0


def epoch_seconds(value):
    """Accept epoch seconds or an ISO-8601 timestamp; None when unparseable."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value)
    try:
        stamp = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    return int(stamp.timestamp())


def window_from(percent, resets_at, seconds):
    return {"percent": clamp_percent(percent), "resetsAt": epoch_seconds(resets_at), "windowSeconds": seconds}


def windows(entry):
    """An entry's weekly window followed by its scoped ones."""
    if entry.get("weekly"):
        yield entry["weekly"]
    yield from entry.get("scoped") or []


def poll(fetch):
    try:
        report = fetch()
    except SignedOut:
        return {"status": "signed_out"}
    except RateLimited as err:
        return {"status": "rate_limited", "retryAfter": err.retry_after, "message": str(err),
                "reason": "rate-limited", "host": err.host}
    except RuntimeError as err:
        report = {"status": "error", "message": str(err) or "error",
                  "reason": getattr(err, "reason", "other"), "host": getattr(err, "host", "")}
        # For the journal only: hold() leaves it out of the cache.
        if getattr(err, "status", None) is not None:
            report["httpStatus"] = err.status
        return report
    except Exception as err:  # noqa: BLE001 - every failure becomes a status
        # Anything else could carry request details, a token among them, so
        # only its type is reported.
        return {"status": "error", "message": f"unexpected {err.__class__.__name__}", "reason": "other", "host": ""}
    report["status"] = "ok"
    return report


def locked():
    """Hold usage.lock until the block ends, waiting up to LOCK_WAIT seconds
    for another run to finish.

    Python opens the descriptor non-inheritable, so a process the Codex CLI
    leaves behind cannot keep holding the lock after this run exits.
    """
    CACHE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    return flocked(LOCK_FILE, LOCK_WAIT)


@contextlib.contextmanager
def flocked(path, wait):
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        deadline = time.monotonic() + wait
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise Busy() from None
                time.sleep(0.2)
        yield
    finally:
        os.close(fd)


def write_private(path, data):
    """Replace path with data as JSON in one step, readable only by the user."""
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.stem}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def read_cache():
    try:
        data = read_json(CACHE_FILE)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def well_formed(window, scoped=False):
    return (isinstance(window, dict) and type(window.get("percent")) is int
            and (window.get("resetsAt") is None or type(window.get("resetsAt")) is int)
            and type(window.get("windowSeconds", 0)) is int
            and (not scoped or isinstance(window.get("id"), str)))


def fresh(entry, now):
    """A cached reading young enough to report again. Anything malformed in
    the cache reads as no reading."""
    return (isinstance(entry, dict) and entry.get("status") == "ok"
            and type(entry.get("fetchedAt")) is int and 0 <= now - entry["fetchedAt"] < CACHE_TTL
            and well_formed(entry.get("weekly")) and isinstance(entry.get("scoped", []), list)
            and (entry.get("session") is None or well_formed(entry["session"]))
            and all(well_formed(w, scoped=True) for w in entry.get("scoped", [])))


# Failures that depend on which program was run.
PROGRAM_REASONS = ("not-installed", "program")


def held(entry, now, chosen):
    """Seconds left before a provider whose last poll failed is polled again,
    or 0. Never more than the hold's own length, should the clock have stepped
    back. A program that couldn't be found or run holds back only the
    program chosen then (chosen being the one chosen now), so choosing
    another checks it at once. Anything malformed in the cache reads as no
    hold."""
    if not (isinstance(entry, dict) and entry.get("status") in ("error", "signed_out", "rate_limited")
            and type(entry.get("heldUntil")) is int and type(entry.get("holdSeconds")) is int
            and (entry["status"] != "error" or isinstance(entry.get("message"), str))):
        return 0
    if entry.get("reason") in PROGRAM_REASONS and entry.get("program", "") != chosen:
        return 0
    return max(0, min(entry["heldUntil"] - now, entry["holdSeconds"], HOLD_MAX))


def hold(report, now, chosen):
    """The cache entry that stands in for a failed poll: five minutes, or as
    long as a rate-limit reply asked if that is longer, up to HOLD_MAX. A
    failure of the program keeps the one chosen, for held()."""
    length = CACHE_TTL
    if report["status"] == "rate_limited":
        length = min(max(CACHE_TTL, report["retryAfter"]), HOLD_MAX)
    entry = {"status": report["status"], "heldUntil": now + length, "holdSeconds": length}
    if report["status"] == "error":
        entry["message"] = report["message"]
    if report["status"] != "signed_out":
        entry["reason"], entry["host"] = report["reason"], report["host"]
    if entry.get("reason") in PROGRAM_REASONS:
        entry["program"] = chosen
    return entry


def replay(entry, wait, now):
    """What a held entry reports at now with wait seconds of its hold left.
    A hold cached before failures carried a reason has none to give."""
    if entry["status"] == "signed_out":
        return {"status": "signed_out"}
    reason = entry.get("reason") if isinstance(entry.get("reason"), str) else "other"
    host = entry.get("host") if isinstance(entry.get("host"), str) else ""
    failure = {"reason": reason, "host": host, "retryAt": now + wait}
    if entry["status"] == "rate_limited":
        return {"status": "rate_limited", "retryAfter": wait, "message": str(RateLimited(wait)), **failure}
    return {"status": "error", "message": entry["message"], **failure}


def collect(fetchers, now=None):
    """Poll each provider unless its last poll is recent enough to report
    again.

    Every poll's result is cached, so no run from any widget polls a provider
    twice within CACHE_TTL: a reading is served until it is that old, and a
    failure or a sign-out is reported again as it was. A rate-limit reply
    holds the provider back for as long as Retry-After asked, if that is
    longer, and reports the seconds left. A hold with more left than its own
    length means the clock stepped back; it is cut to that length so it
    still ends on time. A reading taken after now means the same, and it
    counts as taken now, so it is served for CACHE_TTL more rather than
    polled again at once. The cache is shared with runs that ask for other
    providers, so their entries stay as they were. The lock covers everything
    from reading the cache to writing it and the history, so a run that
    waited for another finds its result fresh; the time is taken once the
    lock is held, since a reading from a run that started later would
    otherwise look like one from the future.
    """
    with locked():
        now = int(time.time()) if now is None else now
        providers, history = collect_locked(fetchers, now)
    attach_history(providers, history, now)
    return providers


def collect_locked(fetchers, now):
    """collect's work, for a caller already holding the lock: the entries
    and the history, which isn't attached yet."""
    cache = read_cache()
    providers, polled = {}, {}
    stepped = False
    for name, fetch in fetchers.items():
        entry = cache.get(name)
        if isinstance(entry, dict) and type(entry.get("fetchedAt")) is int and entry["fetchedAt"] > now:
            entry["fetchedAt"] = now
            stepped = True
        if fresh(entry, now):
            providers[name] = entry
            event("debug", name, "cached", age=now - entry["fetchedAt"])
            continue
        wait = held(entry, now, PROGRAMS.get(name, ""))
        if wait:
            if entry["heldUntil"] - now > wait:
                entry["heldUntil"] = now + wait
                stepped = True
            providers[name] = replay(entry, wait, now)
            event("debug", name, "held", wait=wait, why=failure_why(name, entry))
            continue
        started = time.monotonic()
        report = poll(fetch)
        ms = round((time.monotonic() - started) * 1000)
        if report["status"] == "ok":
            report["fetchedAt"] = now
            cache[name] = providers[name] = report
        else:
            cache[name] = hold(report, now, PROGRAMS.get(name, ""))
            providers[name] = replay(cache[name], cache[name]["holdSeconds"], now)
        note_check(name, report, entry, ms, cache[name])
        polled[name] = report
    history = read_history()
    if polled or stepped:
        write_private(CACHE_FILE, cache)
    if polled:
        updated = record_history(history, polled, now)
        if updated != history:
            write_private(HISTORY_FILE, updated)
            history = updated
    return providers, history


# --- history ---------------------------------------------------------------


def points(series):
    """The well-formed [time, percent] pairs of a stored series."""
    if not isinstance(series, list):
        return []
    return [[point[0], point[1]] for point in series
            if isinstance(point, list) and len(point) == 2 and all(type(v) is int for v in point)]


def read_history():
    """The stored series as {provider: {"weekly": [...], "scoped": {id: [...]}}}.

    An unreadable file reads as empty, and any malformed part of a readable
    one is left out, so a damaged file costs history but never a report.
    """
    try:
        data = read_json(HISTORY_FILE)
    except (OSError, ValueError):
        return {}
    history = {}
    for name, series in (data.items() if isinstance(data, dict) else ()):
        if isinstance(series, dict):
            scoped = series.get("scoped")
            history[name] = {"weekly": points(series.get("weekly")),
                             "scoped": ({key: points(value) for key, value in scoped.items()}
                                        if isinstance(scoped, dict) else {})}
    return history


def within(series, window, now):
    """The points of a series inside the window's current span.

    The span starts windowSeconds before the reset, so when a reset moves
    resetsAt a week out the old week's points fall away. Nothing older than a
    week is kept either way.
    """
    start = now - WEEK_SECONDS
    if window.get("resetsAt") is not None:
        start = max(start, window["resetsAt"] - window.get("windowSeconds", WEEK_SECONDS))
    return [point for point in series if start <= point[0] <= now]


def extend_series(series, window, now):
    """The series with this poll's percent added.

    A fall of HISTORY_CLEARED points or more means the provider cleared the
    window, so the series starts over. A flat stretch keeps only its first and
    last sample: when the last two points match the new percent, the last one
    moves to now instead.
    """
    kept = within(series, window, now)
    percent = window["percent"]
    if kept and kept[-1][1] - percent >= HISTORY_CLEARED:
        kept = []
    if len(kept) >= 2 and kept[-2][1] == kept[-1][1] == percent:
        kept[-1] = [now, percent]
    else:
        kept.append([now, percent])
    return kept[-HISTORY_POINTS:]


def record_history(history, polled, now):
    """The history with this run's real polls added.

    A provider loses the series of limits it no longer reports. A failed
    poll, or one that finds the CLI signed out, leaves them as they were:
    the week's span drops what no longer belongs to it.
    """
    updated = dict(history)
    for name, entry in polled.items():
        if entry["status"] == "ok":
            old = history.get(name) or {"weekly": [], "scoped": {}}
            updated[name] = {
                "weekly": extend_series(old["weekly"], entry["weekly"], now),
                "scoped": {window["id"]: extend_series(old["scoped"].get(window["id"], []), window, now)
                           for window in entry["scoped"]}}
    return updated


def waiting(ids, message):
    """What a run that couldn't get the lock reports: what the cache would
    serve, read without the lock since the cache is only ever replaced whole,
    and the message for the rest."""
    now = int(time.time())
    cache = read_cache()
    providers = {}
    for name in ids:
        entry = cache.get(name)
        wait = held(entry, now, PROGRAMS.get(name, ""))
        if fresh(entry, now):
            providers[name] = entry
            event("debug", name, "cached", age=now - entry["fetchedAt"])
        elif wait:
            providers[name] = replay(entry, wait, now)
            event("debug", name, "held", wait=wait, why=failure_why(name, entry))
        else:
            providers[name] = {"status": "error", "message": message, "reason": "busy", "host": "", "retryAt": now}
            event("warning", name, "busy", wait=LOCK_WAIT)
    attach_history(providers, read_history(), now)
    return providers


def attach_history(providers, history, now):
    for name, entry in providers.items():
        if entry.get("status") != "ok":
            continue
        series = history.get(name) or {"weekly": [], "scoped": {}}
        entry["weekly"]["history"] = within(series["weekly"], entry["weekly"], now)
        for window in entry.get("scoped") or []:
            window["history"] = within(series["scoped"].get(window["id"], []), window, now)


# --- session starter -------------------------------------------------------


class NotSent(Exception):
    """A send that never reached the provider; it is tried again later and
    doesn't count as unconfirmed. The starter shows as failed meanwhile,
    with the reason or "not-sent"."""

    def __init__(self, reason=None):
        super().__init__(reason)
        self.reason = reason


class Failed(Exception):
    """The starter can't send until the user acts; reason is "not-installed",
    "program", "signed-out" or "not-subscription"."""

    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


class SwitchedOff(Exception):
    """The user switched the starter off while its step ran, before the
    message went out."""


class Unreadable(Exception):
    """The limits couldn't be read; the next try waits at least `wait`
    seconds, as long as the provider asked."""

    def __init__(self, wait=0):
        super().__init__()
        self.wait = wait


class Defer(Exception):
    """The cache holds a reading too old to decide on and too young to
    replace; the step runs again once it is stale."""

    def __init__(self, until):
        super().__init__()
        self.until = until


STATES = ("waiting", "confirming", "started", "weekly", "failed", "retrying", "paused")
REASONS = ("not-installed", "program", "signed-out", "not-subscription", "not-responding", "unchecked", "not-sent")


def blank_record():
    """A provider's starter state. Besides what the report shows: sentAt, the
    last send not yet confirmed; pending, a send under way, written before
    it starts so a run that dies mid-send still confirms it; uncertain,
    unconfirmed sends in a row; failures, failed reads or sends in a row;
    steppedAt, when a step last ran."""
    return {"state": "waiting", "at": None, "next": None, "reason": None,
            "sentAt": None, "pending": None, "uncertain": 0, "failures": 0, "steppedAt": None}


def record_from(raw):
    """A stored record with anything malformed replaced by its default.
    Losing a record costs at most one extra send."""
    record = blank_record()
    if not isinstance(raw, dict):
        return record
    for key in ("at", "next", "sentAt", "pending", "steppedAt"):
        if type(raw.get(key)) is int:
            record[key] = raw[key]
    for key in ("uncertain", "failures"):
        if type(raw.get(key)) is int and raw[key] >= 0:
            record[key] = raw[key]
    if raw.get("reason") in REASONS:
        record["reason"] = raw["reason"]
    state = raw.get("state")
    if (state in STATES and (state != "failed" or record["reason"])
            and (state not in ("confirming", "retrying") or record["sentAt"] is not None)):
        record["state"] = state
    return record


def unstep(record, now):
    """Move the times the last step set back with the clock, if it has
    stepped back since that step ran, as before NTP corrects a clock that
    was fast: each wait is then as long from now as it was when set, and a
    send no later than now. True when it moved them."""
    if record["steppedAt"] is None or now >= record["steppedAt"]:
        return False
    shift = record["steppedAt"] - now
    for key in ("next", "sentAt", "pending"):
        if record[key] is not None:
            record[key] -= shift
    # Only these states' at is a send; a started window's comes from the provider.
    if record["state"] in ("confirming", "retrying") and record["at"] is not None:
        record["at"] -= shift
    record["steppedAt"] = now
    return True


def read_starter_states():
    try:
        data = read_json(STARTER_STATE)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    return {name: record_from(data[name]) for name in PROVIDERS if name in data}


def read_switches():
    """The providers whose starter the user switched on; anything unreadable
    is off."""
    try:
        data = read_json(STARTER_FILE)
    except (OSError, ValueError):
        return set()
    return {name for name in PROVIDERS if isinstance(data, dict) and data.get(name) is True}


def private_state_dir():
    STATE_DIR.parent.mkdir(parents=True, exist_ok=True)
    STATE_DIR.mkdir(mode=0o700, exist_ok=True)


def set_switches(changes):
    """Apply changes, {provider: bool}, to the switch file. A lock of its
    own keeps two widgets from losing each other's change without waiting
    for a send. Each switch that turns goes to the journal."""
    private_state_dir()
    with flocked(SWITCH_LOCK, LOCK_WAIT):
        try:
            data = read_json(STARTER_FILE)
        except (OSError, ValueError):
            data = {}
        if not isinstance(data, dict):
            data = {}
        turned = [name for name, on in changes.items() if (data.get(name) is True) != on]
        data.update(changes)
        STARTER_FILE.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        write_private(STARTER_FILE, data)
    for name in turned:
        event("info", name, "starter-on" if changes[name] else "starter-off")


class Starter:
    """One provider's session starter, run when its next time comes.

    It reads the limits and holds while a window runs (until its reset and a
    second) or while the weekly limit is reached (until that resets, or
    as after a failed read when the reading doesn't say when).
    Otherwise it sends one word, and five minutes later reads again: a
    running window confirms the send. An unconfirmed send is tried once
    more after another five minutes; two in a row pause the starter for
    five hours. Reads go through the cache, so they keep its five-minute
    floor, and failed reads and sends that never left back off 5, 15, then
    60 minutes.

    read(not_before) returns the provider's reading, or raises Defer when
    the cached one was taken before not_before, Failed or Unreadable.
    check() returns the CLI or raises Failed; send(binary) raises Failed,
    NotSent or SwitchedOff when nothing went out. running(reading, now) is
    the window running now or None, or raises Unreadable when the reading
    can't tell, and period a window's length. The caller holds usage.lock
    throughout. name is the provider's, for the journal.
    """

    def __init__(self, name, record, *, read, check, send, running, period, persist, clock):
        self.name, self.record, self.read, self.check, self.send = name, record, read, check, send
        self.running, self.period, self.persist, self.clock = running, period, persist, clock

    def set(self, state, at=None, next_=None, reason=None):
        """Moves to a state. A failure goes to the journal as it starts or
        its reason changes, and as debug while it repeats."""
        rec = self.record
        if state == "failed":
            again = rec["state"] == "failed" and rec["reason"] == reason
            event("debug" if again else "warning", self.name, "starter-failed-again" if again else "starter-failed",
                  why=STARTER_WHY.get(reason, "an unknown reason"), wait=next_ - self.clock())
        rec.update(state=state, at=at, next=next_, reason=reason)
        self.persist()

    def back_off(self, at_least=0, reason="unchecked"):
        rec = self.record
        rec["failures"] += 1
        wait = max(RETRY_DELAYS[min(rec["failures"], len(RETRY_DELAYS)) - 1], at_least)
        # A failed read while a send awaits its confirmation or its retry
        # leaves that to the next try.
        if reason == "unchecked" and rec["state"] in ("confirming", "retrying"):
            self.set(rec["state"], rec["at"], self.clock() + wait)
        else:
            self.set("failed", next_=self.clock() + wait, reason=reason)

    def unconfirmed(self, now):
        """Count the send being confirmed as unconfirmed. The second in a
        row pauses the starter, and returns True."""
        rec = self.record
        rec["uncertain"] += 1
        if rec["uncertain"] < 2:
            return False
        rec["sentAt"] = None
        self.set("paused", next_=now + PAUSE)
        event("warning", self.name, "starter-paused", hours=PAUSE // 3600, window=WINDOWS[self.name])
        return True

    def step(self):
        rec, now = self.record, self.clock()
        if unstep(rec, now):
            self.persist()
        if rec["pending"] is not None:
            rec["sentAt"], rec["pending"] = rec["pending"], None
            self.set("confirming", rec["sentAt"], rec["sentAt"] + CONFIRM_DELAY)
        if rec["next"] is not None and now < rec["next"]:
            return
        # Claim the step before reading: should it fail part-way, the
        # widget tries again in five minutes rather than every 30 seconds,
        # and a state that can't be written stops it before any read.
        rec.update(next=now + RETRY_DELAYS[0], steppedAt=now)
        self.persist()
        if rec["state"] == "paused":
            rec["uncertain"] = 0
        # A send older than a window can no longer be told apart from one
        # that never started, as after a long time switched off.
        if rec["sentAt"] is not None and now - rec["sentAt"] >= self.period:
            rec.update(sentAt=None, state="waiting")
        try:
            binary = self.check()
            reading = self.read(rec["sentAt"] + CONFIRM_SLACK if rec["state"] == "confirming" else None)
            window = self.running(reading, now)
        except Failed as err:
            # A send this read was to confirm goes unconfirmed, so a brief
            # sign-out can't let a third send out before the pause.
            if rec["state"] != "confirming" or not self.unconfirmed(now):
                self.set("failed", next_=now + RETRY_DELAYS[0], reason=err.reason)
            return
        except Defer as err:
            rec["next"] = err.until
            self.persist()
            return
        except Unreadable as err:
            self.back_off(err.wait)
            return
        weekly = reading["weekly"]
        if weekly["percent"] >= 100 and weekly["resetsAt"] is None:
            # Reached, with no word of when it resets: as good as unread.
            self.back_off()
            return
        if weekly["percent"] >= 100 and weekly["resetsAt"] > now:
            rec.update(sentAt=None, uncertain=0, failures=0)
            self.set("weekly", next_=weekly["resetsAt"] + 1)
            return
        if window:
            start = window["resetsAt"] - window.get("windowSeconds", self.period)
            # A step again within the window it started, as after the clock
            # stepped back, finds it started still.
            ours = rec["sentAt"] is not None or (rec["state"] == "started" and rec["at"] == start)
            if rec["sentAt"] is not None:
                event("info", self.name, "starter-confirmed", window=WINDOWS[self.name])
            rec.update(sentAt=None, uncertain=0, failures=0)
            if ours:
                self.set("started", start, window["resetsAt"] + 1)
            else:
                self.set("waiting", next_=window["resetsAt"] + 1)
            return
        if rec["state"] == "confirming":
            if not self.unconfirmed(now):
                self.set("retrying", rec["sentAt"], now + CONFIRM_DELAY)
                event("info", self.name, "starter-unconfirmed", window=WINDOWS[self.name], wait=CONFIRM_DELAY)
            return
        rec["pending"] = now
        self.persist()
        try:
            self.send(binary)
        except Failed as err:
            rec["pending"] = None
            self.set("failed", next_=now + RETRY_DELAYS[0], reason=err.reason)
        except NotSent as err:
            rec["pending"] = None
            self.back_off(reason=err.reason or "not-sent")
        except SwitchedOff:
            # Due at once should it be switched on again.
            rec.update(pending=None, sentAt=None, uncertain=0)
            self.set("waiting")
            event("info", self.name, "starter-switched-off")
        else:
            rec.update(pending=None, sentAt=now, failures=0)
            self.set("confirming", now, now + CONFIRM_DELAY)
            event("info", self.name, "starter-sent", wait=CONFIRM_DELAY)


def claude_running(reading, now):
    """Claude's five-hour window while it runs, else None."""
    session = reading.get("session")
    if session and session["resetsAt"] is not None and session["resetsAt"] > now:
        return session
    return None


def codex_running(reading, now):
    """Codex's week while it runs, else None. An idle account reports 0% and
    a reset a week from whenever it is asked, which moves with the clock;
    that is no window, and the next message starts one. A week in use that
    doesn't say when it resets runs all the same, so the reading is as good
    as unread."""
    week = reading["weekly"]
    reset = week["resetsAt"]
    if reset is None and week["percent"] > 0:
        raise Unreadable()
    if reset is None or reset <= now:
        return None
    if week["percent"] == 0 and abs(reset - reading["fetchedAt"] - week.get("windowSeconds", WEEK_SECONDS)) \
            <= ROLLING_SLACK:
        return None
    return week


def starter_read(name, now, not_before):
    """The provider's reading, through the cache and its floor as any poll.
    A confirmation needs a reading taken after the send; while the cache
    still holds an older one, the step waits for it to go stale. Readings
    cached by 0.2, which lack Claude's session, wait the same way. A new
    reading that can't say whether a session runs is a failed read."""
    entry = read_cache().get(name)
    if fresh(entry, now) and ((not_before is not None and entry["fetchedAt"] < not_before)
                              or (name == "claude" and "session" not in entry)):
        raise Defer(entry["fetchedAt"] + CACHE_TTL)
    entry = collect_locked({name: fetchers()[name]}, now)[0][name]
    if entry["status"] == "signed_out":
        raise Failed("signed-out")
    if entry["status"] != "ok":
        raise Unreadable(entry.get("retryAfter", 0))
    if name == "claude" and "session" not in entry:
        raise Unreadable()
    return entry


def installed(name):
    binary, problem = find_cli(name, PROGRAMS.get(name, ""))
    if problem:
        raise Failed("program")
    if not binary:
        raise Failed("not-installed")
    return binary


def run_cli(argv, env, timeout):
    """Run a CLI in WORK_DIR with no input; its exit code and output.

    It runs in a session of its own, and whatever it leaves running there
    is killed once it exits or runs out of time. Output goes to a file, so
    a process that survives outside the session can't stall the read.
    Raises OSError when it can't start and subprocess.TimeoutExpired when
    it ran out of time.
    """
    private_state_dir()
    WORK_DIR.mkdir(mode=0o700, exist_ok=True)
    with tempfile.TemporaryFile(dir=STATE_DIR) as out:
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.DEVNULL,
                                cwd=WORK_DIR, env=env, start_new_session=True)
        try:
            code = proc.wait(timeout=timeout)
        finally:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
        out.seek(0)
        return code, out.read().decode("utf-8", "replace")


# Only what the CLIs need to run and reach the network. An API key or a
# provider override in the session would bill the send to it instead of
# the subscription, and starting a window on the subscription is the point.
CLI_ENVIRONMENT = ("HOME", "USER", "LOGNAME", "PATH", "LANG", "TZ", "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME",
                   "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "DBUS_SESSION_BUS_ADDRESS",
                   "SSL_CERT_FILE", "SSL_CERT_DIR", "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "ALL_PROXY",
                   "http_proxy", "https_proxy", "no_proxy", "all_proxy")


def cli_environment(config_home, settings=None):
    env = {key: value for key, value in os.environ.items()
           if key in CLI_ENVIRONMENT or key == config_home or key.startswith("LC_")}
    env.update(settings or {})
    return env


# The output cap leaves room for a short greeting. A reply that runs past it
# makes the CLI ask again to finish, four requests in all, and then exit
# with an error: Haiku sometimes answers "Hi" in more than 8 tokens even
# when told to reply with OK.
def claude_environment():
    return cli_environment("CLAUDE_CONFIG_DIR", {
        "MAX_THINKING_TOKENS": "0", "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "256",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1", "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1",
        "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION": "false", "CLAUDE_CODE_DISABLE_ADVISOR_TOOL": "1",
        "CLAUDE_CODE_SKIP_PROMPT_HISTORY": "1"})


def claude_options():
    """A send that loads no settings, tools, MCP servers, skills or project
    files, keeps no session, and ends after one short reply."""
    return ["--model", CLAUDE_MODEL, "--safe-mode", "--setting-sources", "",
            "--tools", "", "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
            "--disable-slash-commands", "--no-session-persistence", "--permission-prompts", "none",
            "--max-turns", "1", "--output-format", "json", "--no-chrome",
            "--prompt-suggestions", "false", "--system-prompt", "Reply with OK."]


def send_claude(binary, wanted):
    """Send Claude one word so a five-hour window starts, if wanted() still
    says so once the login and the CLI have been checked.

    The login is renewed first if it expires within CLI_TOKEN_MARGIN, under
    the lock the caller holds, so the CLI has no reason to spend the
    single-use refresh token itself while Ringside might. `claude auth
    status` then checks the login and, since it rejects root options it
    doesn't know, the flags; a problem there means nothing was sent. A
    preflight that times out, can't be read or fails otherwise shows as
    "not-responding", and a login other than a claude.ai subscription as
    "not-subscription".

    Once the send has started, the reading five minutes later decides
    whether it worked, and the CLI's output is not checked. usage-reset,
    which this ports, also required a JSON result with no error, a reply
    and exactly the pinned model: 3 of the 13 sends its journal still
    holds failed that check although the next reading showed a window
    started at the send. It kept no output; the likely cause is the
    8-token output cap it used, which a short greeting overruns.
    """
    try:
        claude_access_token(CLI_TOKEN_MARGIN)
    except SignedOut:
        raise Failed("signed-out") from None
    except Exception:  # noqa: BLE001 - a login that couldn't be renewed sends nothing
        raise NotSent() from None
    env = claude_environment()
    try:
        code, out = run_cli([binary, *claude_options(), "auth", "status"], env, PREFLIGHT_TIMEOUT)
        auth = json.loads(out)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        raise NotSent("not-responding") from None
    if not isinstance(auth, dict):
        raise NotSent("not-responding")
    if auth.get("loggedIn") is not True:
        raise Failed("signed-out")
    # An API key or a cloud provider would bill the send without starting
    # a subscription window.
    if auth.get("authMethod") != "claude.ai" or auth.get("apiProvider") != "firstParty":
        raise Failed("not-subscription")
    if code != 0:
        raise NotSent("not-responding")
    if not wanted():
        raise SwitchedOff()
    try:
        run_cli([binary, *claude_options(), "-p", PROMPT], env, SEND_TIMEOUT)
    except OSError:
        raise NotSent() from None
    except subprocess.TimeoutExpired:
        pass


def codex_model():
    """The model and reasoning effort to send with: of the gpt-<version>-luna
    models the CLI lists for choosing, the highest version, at the lightest
    effort it supports. The list is the CLI's own cache, so a model or a
    list that can't be read counts as not listed."""
    try:
        models = read_json(CODEX_MODEL_CACHE)["models"]
    except (OSError, ValueError, KeyError, TypeError):
        models = []
    newest, newest_version = None, ()
    for model in models if isinstance(models, list) else []:
        slug = model.get("slug") if isinstance(model, dict) else None
        luna = re.fullmatch(r"gpt-([0-9]+(?:\.[0-9]+)*)-luna", slug) if isinstance(slug, str) else None
        if luna and model.get("visibility") == "list":
            version = tuple(int(part) for part in luna[1].split("."))
            if version > newest_version:
                newest, newest_version = model, version
    if newest is None:
        return CODEX_MODEL, CODEX_EFFORT
    levels = newest.get("supported_reasoning_levels")
    listed = [level.get("effort") for level in levels if isinstance(level, dict)] if isinstance(levels, list) else []
    return newest["slug"], next((effort for effort in EFFORTS if effort in listed), CODEX_EFFORT)


def codex_command(binary):
    """One turn that keeps no session, needs no git repository, loads none of
    the user's config or rules, can only read, and thinks as little as the
    model allows."""
    model, effort = codex_model()
    return [binary, "exec", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules",
            "--sandbox", "read-only", "--color", "never", "--json", "--cd", str(WORK_DIR),
            "--config", f'model_reasoning_effort="{effort}"', "--model", model, PROMPT]


def send_codex(binary, wanted):
    """Send Codex one word so a week starts, if wanted() still says so. As
    for Claude, the reading five minutes later decides whether it worked."""
    command = codex_command(binary)
    if not wanted():
        raise SwitchedOff()
    try:
        run_cli(command, cli_environment("CODEX_HOME"), SEND_TIMEOUT)
    except OSError:
        raise NotSent() from None
    except subprocess.TimeoutExpired:
        pass


def fetchers():
    return {"claude": claude_usage, "codex": codex_usage}


# Each provider's session starter: how it sends its message, and whether a
# reading shows the session or week it asked for running.
def starters():
    return {"claude": (send_claude, claude_running), "codex": (send_codex, codex_running)}


def run_starter(name):
    """Run the provider's starter step if its switch is on, holding
    usage.lock from the switch check to the last write, so no poll runs
    between a read and a send and none renews Claude's login while the CLI
    might.

    The switch has a lock of its own, so the user can turn it off while
    the step reads, renews and checks the CLI, which can take most of a
    minute; the sender reads it again just before the message goes out."""
    with locked():
        if name not in read_switches():
            return
        states = read_starter_states()
        record = states.setdefault(name, blank_record())

        def persist():
            private_state_dir()
            write_private(STARTER_STATE, states)

        sender, running = starters()[name]
        Starter(name, record,
                read=lambda not_before: starter_read(name, int(time.time()), not_before),
                check=lambda: installed(name),
                send=lambda binary: sender(binary, lambda: name in read_switches()),
                running=running,
                period=SESSION_SECONDS if name == "claude" else WEEK_SECONDS,
                persist=persist, clock=lambda: int(time.time())).step()
        if record["next"] is not None:
            event("debug", name, "starter-next", state=record["state"],
                  at=time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(record["next"])))


STARTER_OFF = {"enabled": False, "state": "off", "at": None, "next": None, "reason": None}


def starter_report(name, switches, states, now):
    """What the report says of a provider's starter."""
    if name not in switches:
        return dict(STARTER_OFF)
    record = states.get(name) or blank_record()
    # Should the clock have stepped back, the starter is due, so a --start
    # moves its times back for good.
    stepped = unstep(record, now)
    state, at, next_ = record["state"], record["at"], record["next"]
    if record["pending"] is not None:
        state, at, next_ = "confirming", record["pending"], record["pending"] + CONFIRM_DELAY
    if stepped or next_ is None:
        next_ = now
    return {"enabled": True, "state": state, "at": at, "next": next_,
            "reason": record["reason"] if state == "failed" else None}


def attach_starters(providers, now):
    switches, states = read_switches(), read_starter_states()
    for name, entry in providers.items():
        entry["starter"] = starter_report(name, switches, states, now)


# --- clock zone ------------------------------------------------------------


def read_groups(path):
    """A KConfig file as {"[a][b]": {key: value}}, keyed by the full group header.

    Applet ids repeat at different depths (an applet inside the system tray can
    share its id with a panel applet), so only the full header names a group.
    """
    groups = {}
    group = None
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("["):
            group = groups.setdefault(line, {})
        elif group is not None and "=" in line and not line.startswith("#"):
            key, _, value = line.partition("=")
            group[key.split("[")[0].strip()] = value.strip()
    return groups


def zone_named(name):
    """An IANA zone, or Qt's fixed-offset "UTC+05:30" form; None when unknown."""
    fixed = re.fullmatch(r"UTC([+-])(\d\d):(\d\d)", name)
    try:
        if fixed:
            offset = timedelta(hours=int(fixed[2]), minutes=int(fixed[3]))
            return timezone(offset if fixed[1] == "+" else -offset, name)
        return ZoneInfo(name)
    except (ValueError, ZoneInfoNotFoundError):
        return None


def clock_zone():
    """The zone Plasma's digital clock shows instead of system time, or None.

    The clock shows lastSelectedTimezone, where "Local" is system time; KConfig
    leaves that default out of the file. Clocks that disagree leave reset times
    in system time, as does a config that cannot be read.
    """
    try:
        groups = read_groups(APPLETSRC)
    except (OSError, UnicodeDecodeError):
        return None
    shown = {groups.get(header + "[Configuration][Appearance]", {}).get("lastSelectedTimezone") or "Local"
             for header, keys in groups.items() if keys.get("plugin") == CLOCK_PLUGIN}
    if len(shown) != 1 or shown == {"Local"}:
        return None
    return zone_named(shown.pop())


def show_in_zone(providers, zone):
    """Give each window's reset the zone's offset and abbreviation at that
    moment, Claude's session included, and each starter the same at its
    next time, or at its last when it has no next. A starter's last time
    gets its own, atClockZone: a week Codex started can span a change of
    daylight saving time before its next.

    A time the zone cannot place stays in system time on its own.
    """
    for entry in providers.values():
        times = [(window, "clockZone", window.get("resetsAt")) for window in windows(entry)]
        if entry.get("session"):
            times.append((entry["session"], "clockZone", entry["session"].get("resetsAt")))
        if entry.get("starter"):
            starter = entry["starter"]
            times.append((starter, "clockZone",
                          starter["next"] if starter.get("next") is not None else starter.get("at")))
            times.append((starter, "atClockZone", starter.get("at")))
        for item, key, epoch in times:
            if not epoch:
                continue
            try:
                at = datetime.fromtimestamp(epoch, zone)
            except (ValueError, OverflowError, OSError):
                continue
            item[key] = {"offset": int(at.utcoffset().total_seconds()), "abbreviation": at.tzname()}


# --- main ------------------------------------------------------------------


def provider_list(text):
    ids = list(dict.fromkeys(name.strip() for name in text.split(",")))
    unknown = [name for name in ids if name not in PROVIDERS]
    if unknown:
        raise argparse.ArgumentTypeError(f"unknown provider {unknown[0]!r} (choose from {', '.join(PROVIDERS)})")
    return ids


def switch(text):
    name, _, value = text.partition("=")
    if name not in PROVIDERS or value not in ("on", "off"):
        raise argparse.ArgumentTypeError(f"expected <provider>=on or <provider>=off, not {text!r}")
    return name, value == "on"


def chosen_program(text):
    """A --program value: the provider, then the path, which may hold "=" too."""
    name, sep, path = text.partition("=")
    if name not in PROVIDERS or not sep:
        raise argparse.ArgumentTypeError(f"expected <provider>=<path>, not {text!r}")
    return name, path


def arguments(argv):
    parser = argparse.ArgumentParser(description="Report the weekly usage of Claude Code and Codex as JSON.")
    parser.add_argument("--providers", type=provider_list, default=list(PROVIDERS),
                        help="comma-separated providers to poll and report (default: claude,codex)")
    parser.add_argument("--start", action="store_true",
                        help="run the session starter of each listed provider that is switched on and due")
    parser.add_argument("--starter-set", type=switch, action="append", default=[], metavar="PROVIDER=on|off",
                        help="switch a provider's session starter on or off for this user")
    parser.add_argument("--program", type=chosen_program, action="append", default=[], metavar="PROVIDER=PATH",
                        help="run the program at PATH for a provider rather than finding it; ~ is the home folder")
    return parser.parse_args(argv)


def main(argv=None):
    args = arguments(argv)
    EVENTS.clear()
    ids = args.providers
    PROGRAMS.clear()
    PROGRAMS.update(args.program)
    fake = os.environ.get("RINGSIDE_USAGE_FAKE")
    if fake:
        report = read_json(fake)
        report["providers"] = {name: entry for name, entry in (report.get("providers") or {}).items()
                               if name in ids}
        for entry in report["providers"].values():
            entry.setdefault("starter", dict(STARTER_OFF))
            for window in windows(entry):
                window.setdefault("history", [])
    else:
        if args.starter_set:
            # A switch that can't be written stays as it was, and the report
            # shows it so, which moves the widget's switch back. The widget
            # shows the line on stderr under the switch as the reason.
            try:
                set_switches(dict(args.starter_set))
            except (Busy, OSError) as err:
                print(err, file=sys.stderr)
                for name in dict(args.starter_set):
                    event("warning", name, "starter-switch-failed", why=os_why(err))
        if args.start:
            for name in ids:
                # A state that can't be written stops the starter, never the
                # report; the widget shows the reason under the switch.
                try:
                    run_starter(name)
                except (Busy, OSError) as err:
                    print(err, file=sys.stderr)
                    event("warning", name, "starter-stopped", why=os_why(err))
        sources = fetchers()
        try:
            providers = collect({name: sources[name] for name in ids})
        except Busy as err:
            providers = waiting(ids, str(err))
        report = {"fetchedAt": int(time.time()), "providers": providers, "events": EVENTS}
        attach_starters(providers, report["fetchedAt"])
        for name, entry in providers.items():
            entry["program"] = program(name)
    # Read on every run, cached or not, so a change of clock zone shows by the
    # next poll; the cache itself never holds it.
    zone = clock_zone()
    if zone:
        show_in_zone(report["providers"], zone)
    json.dump(report, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
