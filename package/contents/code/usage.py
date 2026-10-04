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
"error", and the last two carry a "message" to show. Tokens never reach
stdout or stderr.

When Plasma's digital clock shows a zone other than system time, every window
also carries "clockZone": {"offset": <seconds east of UTC>, "abbreviation":
"EDT"}, the zone's offset and abbreviation at that window's reset.

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

Set RINGSIDE_USAGE_FAKE to a JSON report to print it instead of polling,
limited to the requested providers and with the clock zone added as on a live
run.
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

VERSION = "0.2.2"

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
CODEX_TIMEOUT = 20

HTTP_TIMEOUT = 10
# Seconds to wait after a 429 whose Retry-After is missing or unreadable.
RETRY_AFTER_DEFAULT = 60

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "ringside"
CACHE_FILE = CACHE_DIR / "usage.json"
HISTORY_FILE = CACHE_DIR / "usage-history.json"
LOCK_FILE = CACHE_DIR / "usage.lock"
CACHE_TTL = 5 * 60
# How long a run waits for another to finish before giving up; one run
# takes at most about 50 s (Codex, then a token refresh and a poll).
LOCK_WAIT = 90
# The longest a refusal holds a provider back, whatever Retry-After says.
HOLD_MAX = 24 * 3600
# A week of polls five minutes apart is 2016 points; flat stretches collapse,
# so this is only reached by a series that changes on nearly every poll.
HISTORY_POINTS = 2100
# A fall of this many points means the provider cleared the window early.
HISTORY_CLEARED = 20

APPLETSRC = (Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
             / "plasma-org.kde.plasma.desktop-appletsrc")
CLOCK_PLUGIN = "org.kde.plasma.digitalclock"


class SignedOut(Exception):
    pass


class Busy(RuntimeError):
    def __init__(self):
        super().__init__("another usage check is still running")


class RateLimited(Exception):
    def __init__(self, retry_after):
        super().__init__(f"rate limited, retrying in {retry_after} s")
        self.retry_after = retry_after


# --- Codex -----------------------------------------------------------------


def find_codex():
    """~/.local/bin/codex if executable, else codex on PATH, which in a Plasma
    session may lack ~/.local/bin."""
    wrapper = Path.home() / ".local" / "bin" / "codex"
    if os.access(wrapper, os.X_OK):
        return str(wrapper)
    return shutil.which("codex")


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
    deadline = time.monotonic() + CODEX_TIMEOUT
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
            raise RuntimeError(f"no answer from codex app-server in {CODEX_TIMEOUT} s")
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
    binary = find_codex()
    if not binary:
        raise RuntimeError("codex CLI not found")
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
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            return json.load(response)
    except urllib.error.HTTPError as err:
        if err.code == 401:
            raise SignedOut() from err
        if err.code == 429:
            raise RateLimited(retry_seconds(err.headers.get("retry-after"))) from err
        raise RuntimeError(f"HTTP {err.code} from {host}") from err
    except urllib.error.URLError as err:
        # A socket error's str() leads with its errno, as in "[Errno -2] Name or
        # service not known"; strerror is the readable part.
        reason = getattr(err.reason, "strerror", None) or err.reason
        raise RuntimeError(f"can't reach {host}: {reason}") from err
    except OSError as err:
        raise RuntimeError(f"can't reach {host}: {err.strerror or 'timed out'}") from err
    except ValueError as err:
        raise RuntimeError(f"unreadable reply from {host}") from err


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


def expired(oauth):
    try:
        return float(oauth.get("expiresAt") or 0) / 1000 - time.time() <= CLAUDE_EXPIRY_MARGIN
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


def claude_access_token():
    path = CLAUDE_CREDENTIALS
    if not path.exists():
        raise SignedOut()
    path = path.resolve()
    oauth, _ = read_oauth(path)
    if not expired(oauth):
        return oauth["accessToken"]
    if not usable(oauth.get("refreshToken")):
        raise SignedOut()
    # Spending the CLI's single-use refresh token without saving the new pair
    # would sign Claude Code out, so check the write can happen first, then
    # read the file once more in case the CLI renewed it meanwhile.
    check_writable(path)
    current, _ = read_oauth(path)
    if generation(current) != generation(oauth):
        if not expired(current):
            return current["accessToken"]
        if not usable(current.get("refreshToken")):
            raise SignedOut()
    try:
        fresh = refresh_claude(current)
    except Exception:
        latest, _ = read_oauth(path)
        if generation(latest) != generation(current) and not expired(latest):
            return latest["accessToken"]
        raise
    store_claude(path, current["refreshToken"], fresh)
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
    other than a model are skipped. The cinder_cove entry is the older unscoped
    form of the Fable window and stands in when the list has no Fable entry.
    """
    weekly = usage.get("seven_day")
    if not weekly:
        raise RuntimeError("no weekly window in usage reply")
    scoped = []
    for limit in usage.get("limits") or []:
        name = ((limit.get("scope") or {}).get("model") or {}).get("display_name") or ""
        if limit.get("kind") == "weekly_scoped" and name and all(s["id"] != name for s in scoped):
            scoped.append({"id": name, "label": name,
                           **window_from(limit.get("percent"), limit.get("resets_at"), WEEK_SECONDS)})
    fallback = usage.get("cinder_cove")
    if (fallback and fallback.get("utilization") is not None
            and not any("fable" in s["id"].lower() for s in scoped)):
        scoped.append({"id": "Fable", "label": "Fable",
                       **window_from(fallback["utilization"], fallback.get("resets_at"), WEEK_SECONDS)})
    return {"weekly": window_from(weekly.get("utilization"), weekly.get("resets_at"), WEEK_SECONDS),
            "scoped": scoped}


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
        return {"status": "rate_limited", "retryAfter": err.retry_after, "message": str(err)}
    except RuntimeError as err:
        return {"status": "error", "message": str(err) or "error"}
    except Exception as err:  # noqa: BLE001 - every failure becomes a status
        # Anything else could carry request details, a token among them, so
        # only its type is reported.
        return {"status": "error", "message": f"unexpected {err.__class__.__name__}"}
    report["status"] = "ok"
    return report


@contextlib.contextmanager
def locked():
    """Hold usage.lock until the block ends, waiting up to LOCK_WAIT seconds
    for another run to finish.

    Python opens the descriptor non-inheritable, so a process the Codex CLI
    leaves behind cannot keep holding the lock after this run exits.
    """
    CACHE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        deadline = time.monotonic() + LOCK_WAIT
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
            and all(well_formed(w, scoped=True) for w in entry.get("scoped", [])))


def held(entry, now):
    """Seconds left before a provider whose last poll failed is polled again,
    or 0. Never more than the hold's own length, should the clock have stepped
    back. Anything malformed in the cache reads as no hold."""
    if not (isinstance(entry, dict) and entry.get("status") in ("error", "signed_out", "rate_limited")
            and type(entry.get("heldUntil")) is int and type(entry.get("holdSeconds")) is int
            and (entry["status"] != "error" or isinstance(entry.get("message"), str))):
        return 0
    return max(0, min(entry["heldUntil"] - now, entry["holdSeconds"], HOLD_MAX))


def hold(report, now):
    """The cache entry that stands in for a failed poll: five minutes, or as
    long as a rate-limit reply asked if that is longer, up to HOLD_MAX."""
    length = CACHE_TTL
    if report["status"] == "rate_limited":
        length = min(max(CACHE_TTL, report["retryAfter"]), HOLD_MAX)
    entry = {"status": report["status"], "heldUntil": now + length, "holdSeconds": length}
    if report["status"] == "error":
        entry["message"] = report["message"]
    return entry


def replay(entry, wait):
    """What a held entry reports with wait seconds of its hold left."""
    if entry["status"] == "rate_limited":
        return {"status": "rate_limited", "retryAfter": wait, "message": str(RateLimited(wait))}
    return {key: entry[key] for key in ("status", "message") if key in entry}


def collect(fetchers, now=None):
    """Poll each provider unless its last poll is recent enough to report
    again.

    Every poll's result is cached, so no run from any widget polls a provider
    twice within CACHE_TTL: a reading is served until it is that old, and a
    failure or a sign-out is reported again as it was. A rate-limit reply
    holds the provider back for as long as Retry-After asked, if that is
    longer, and reports the seconds left. A hold with more left than its own
    length means the clock stepped back; it is cut to that length so it
    still ends on time. The cache is shared with runs that ask for other
    providers, so their entries stay as they were. The lock covers everything
    from reading the cache to writing it and the history, so a run that
    waited for another finds its result fresh; the time is taken once the
    lock is held, since a reading from a run that started later would
    otherwise look like one from the future.
    """
    with locked():
        now = int(time.time()) if now is None else now
        cache = read_cache()
        providers, polled = {}, {}
        stepped = False
        for name, fetch in fetchers.items():
            entry = cache.get(name)
            if fresh(entry, now):
                providers[name] = entry
                continue
            wait = held(entry, now)
            if wait:
                if entry["heldUntil"] - now > wait:
                    entry["heldUntil"] = now + wait
                    stepped = True
                providers[name] = replay(entry, wait)
                continue
            report = poll(fetch)
            if report["status"] == "ok":
                report["fetchedAt"] = now
                cache[name] = providers[name] = report
            else:
                cache[name] = hold(report, now)
                providers[name] = replay(cache[name], cache[name]["holdSeconds"])
            polled[name] = report
        history = read_history()
        if polled or stepped:
            write_private(CACHE_FILE, cache)
        if polled:
            updated = record_history(history, polled, now)
            if updated != history:
                write_private(HISTORY_FILE, updated)
                history = updated
    attach_history(providers, history, now)
    return providers


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
        wait = held(entry, now)
        if fresh(entry, now):
            providers[name] = entry
        elif wait:
            providers[name] = replay(entry, wait)
        else:
            providers[name] = {"status": "error", "message": message}
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
    """Give each window's reset the zone's offset and abbreviation at that moment.

    A reset time the zone cannot place stays in system time on its own ring.
    """
    for entry in providers.values():
        for window in windows(entry):
            if not window.get("resetsAt"):
                continue
            try:
                at = datetime.fromtimestamp(window["resetsAt"], zone)
            except (ValueError, OverflowError, OSError):
                continue
            window["clockZone"] = {"offset": int(at.utcoffset().total_seconds()),
                                   "abbreviation": at.tzname()}


# --- main ------------------------------------------------------------------


def provider_list(text):
    ids = list(dict.fromkeys(name.strip() for name in text.split(",")))
    unknown = [name for name in ids if name not in PROVIDERS]
    if unknown:
        raise argparse.ArgumentTypeError(f"unknown provider {unknown[0]!r} (choose from {', '.join(PROVIDERS)})")
    return ids


def arguments(argv):
    parser = argparse.ArgumentParser(description="Report the weekly usage of Claude Code and Codex as JSON.")
    parser.add_argument("--providers", type=provider_list, default=list(PROVIDERS),
                        help="comma-separated providers to poll and report (default: claude,codex)")
    return parser.parse_args(argv)


def main(argv=None):
    ids = arguments(argv).providers
    fake = os.environ.get("RINGSIDE_USAGE_FAKE")
    if fake:
        report = read_json(fake)
        report["providers"] = {name: entry for name, entry in (report.get("providers") or {}).items()
                               if name in ids}
        for entry in report["providers"].values():
            for window in windows(entry):
                window.setdefault("history", [])
    else:
        fetchers = {"claude": claude_usage, "codex": codex_usage}
        try:
            providers = collect({name: fetchers[name] for name in ids})
        except Busy as err:
            providers = waiting(ids, str(err))
        report = {"fetchedAt": int(time.time()), "providers": providers}
    # Read on every run, cached or not, so a change of clock zone shows by the
    # next poll; the cache itself never holds it.
    zone = clock_zone()
    if zone:
        show_in_zone(report["providers"], zone)
    json.dump(report, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
