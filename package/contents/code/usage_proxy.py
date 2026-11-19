# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Read account quotas through the local CLIProxyAPI v8 management API."""

import hashlib
import http.client
import ipaddress
import json
import math
import os
import re
import socket
import stat
import threading
import time
import uuid
from contextlib import suppress
from dataclasses import dataclass, field
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.parse import urlsplit

MANAGEMENT = "/v8/management"
KEY_LIMIT = 4096
RESPONSE_LIMIT = 1024 * 1024
EXTRA_RESPONSE_LIMIT = 65536
REQUEST_TIMEOUT = 8
HOUR = 3600
DAY = 24 * HOUR
SESSION = 5 * HOUR
WEEK = 7 * DAY
TOKEN = "Bearer $TOKEN$"
CLAUDE_OAUTH = "https://api.anthropic.com/api/oauth"
CLAUDE_HEADERS = {"anthropic-beta": "oauth-2025-04-20", "Content-Type": "application/json",
                  "User-Agent": "claude-cli/2.1.321 (external, cli)"}
CODEX_WHAM = "https://chatgpt.com/backend-api/wham"
CODEX_HEADERS = {"Content-Type": "application/json", "User-Agent": "codex-tui"}
KIMI_REGIONS = {"kimi-ai": "global", "kimi": "china"}
KIMI_HOSTS = {"global": "api.kimi.ai", "china": "api.kimi.com"}
PROVIDERS = {"claude": "claude", "codex": "codex", "kimi": "kimi", "kimi-ai": "kimi"}
MODEL_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}")
ROUTING_ID = re.compile(r"[A-Za-z0-9_-]{1,128}")
EMAIL = re.compile(r"[^\s@]+@[^\s@]+\.[^\s@]+")
CREDENTIAL_ERRORS = {"auth credential not found for auth_index", "auth token not found",
                     "auth token refresh failed"}
REASONS = {"configuration", "key-file", "management-auth", "upstream-auth", "rate-limited", "offline",
           "timeout", "server", "invalid-response", "unsupported-credential"}


class ProxyError(RuntimeError):
    def __init__(self, reason, retry_after=None):
        super().__init__(reason)
        self.reason = reason
        self.retry_after = retry_after


@dataclass(frozen=True)
class Credential:
    provider: str
    fingerprint: str
    index: str = field(repr=False)
    account_id: str = field(default="", repr=False)
    region: str | None = None
    requires_sign_in: bool = False
    revision: str = field(default="", repr=False)


def loopback_address(url):
    try:
        if not isinstance(url, str) or any(ord(char) <= 32 or ord(char) > 126 for char in url):
            raise ValueError
        address = urlsplit(url)
        if (address.scheme != "http" or address.path not in ("", "/")
                or any(char in url for char in ("@", "?", "#", "%"))
                or not address.hostname or address.netloc.endswith(":")):
            raise ValueError
        host = "127.0.0.1" if address.hostname == "localhost" else address.hostname
        ip = ipaddress.ip_address(host)
        port = address.port if address.port is not None else 80
        if not ip.is_loopback or ip.version == 6 and ip != ipaddress.IPv6Address("::1") or not port:
            raise ValueError
        expected_host = f"[{address.hostname}]" if ip.version == 6 else address.hostname
        if not re.fullmatch(re.escape(expected_host) + r"(?::[0-9]+)?", address.netloc, re.IGNORECASE):
            raise ValueError
        return str(ip), port
    except ValueError:
        raise ProxyError("configuration") from None


def read_key(path):
    try:
        with os.fdopen(os.open(Path(path).expanduser(), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
                raise ValueError
            raw = stream.read(KEY_LIMIT + 1)
            revision = file_revision(info)
            if revision != file_revision(os.fstat(stream.fileno())):
                raise ValueError
        key = raw.rstrip(b"\r\n")
        if len(raw) > KEY_LIMIT or not re.fullmatch(rb"[!-~]+", key):
            raise ValueError
        return key, revision
    except (OSError, TypeError, ValueError, RuntimeError):
        raise ProxyError("key-file") from None


def file_revision(info):
    return info.st_dev, info.st_ino, info.st_mtime_ns, info.st_ctime_ns, info.st_size


def decode_json(raw):
    try:
        return json.loads(raw)
    except (ValueError, TypeError, RecursionError):
        raise ProxyError("invalid-response") from None


def retry_seconds(value):
    if isinstance(value, str) and len(value) <= 128:
        try:
            return max(1, min(DAY, int(value)))
        except ValueError:
            with suppress(TypeError, ValueError, OverflowError, OSError):
                at = parsedate_to_datetime(value)
                if at.tzinfo is None:
                    at = at.replace(tzinfo=timezone.utc)
                return max(1, min(DAY, math.ceil(at.timestamp() - time.time())))
    return 60


def check_status(status, retry_after, *, management):
    if 200 <= status < 300:
        return
    if status in (401, 403):
        raise ProxyError("management-auth" if management else "upstream-auth")
    if status == 429:
        raise ProxyError("management-rate-limited" if management else "rate-limited", retry_seconds(retry_after))
    if status >= 500:
        raise ProxyError("server")
    raise ProxyError("invalid-response")


def wrapped_retry_after(headers):
    if isinstance(headers, dict):
        for name, values in headers.items():
            if name.lower() == "retry-after" and isinstance(values, list) and values:
                return values[0]
    return None


def shutdown(sock):
    with suppress(OSError):
        sock.shutdown(socket.SHUT_RDWR)


def request_json(host, port, path, *, deadline, limit, request=None, key=None):
    until = time.monotonic() + REQUEST_TIMEOUT
    if deadline is not None:
        until = min(until, deadline)
    if (remaining := until - time.monotonic()) <= 0:
        raise ProxyError("timeout")
    # Numeric loopback and HTTPConnection bypass environment proxies, DNS
    # overrides and redirects. Shut down the socket even on a slow response.
    connection = http.client.HTTPConnection(host, port, timeout=remaining)
    timer = None
    try:
        connection.connect()
        sock = connection.sock
        timer = threading.Timer(max(0, until - time.monotonic()), shutdown, (sock,))
        timer.daemon = True
        timer.start()
        headers = {"Accept": "application/json"}
        if key is not None:
            headers["Authorization"] = "Bearer " + key.decode("ascii")
        body = None
        if request is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(request).encode()
        connection.request("POST" if request is not None else "GET", path, body, headers)
        with connection.getresponse() as response:
            if time.monotonic() >= until:
                raise ProxyError("timeout")
            if response.status != 400 or request is None:
                check_status(response.status, response.getheader("Retry-After"), management=True)
            raw = response.read(limit + 1)
            if time.monotonic() >= until:
                raise ProxyError("timeout")
            if len(raw) > limit:
                raise ProxyError("invalid-response")
            value = decode_json(raw)
            if time.monotonic() >= until:
                raise ProxyError("timeout")
            if response.status == 400:
                error = value.get("error") if isinstance(value, dict) else None
                raise ProxyError("upstream-auth" if isinstance(error, str) and error in CREDENTIAL_ERRORS
                                 else "invalid-response")
            return value
    except TimeoutError:
        raise ProxyError("timeout") from None
    except (OSError, http.client.HTTPException) as error:
        if time.monotonic() >= until:
            raise ProxyError("timeout") from None
        raise ProxyError("offline" if isinstance(error, OSError) else "invalid-response") from None
    finally:
        if timer:
            timer.cancel()
        connection.close()


def discover(url, *, deadline=None):
    """Identify CLIProxyAPI on one loopback address without a management key."""
    until = time.monotonic() + 1
    if deadline is not None:
        until = min(until, deadline)
    try:
        response = request_json(*loopback_address(url), "/", deadline=until, limit=4096)
    except ProxyError:
        return False
    return (isinstance(response, dict) and response.get("message") == "CLI Proxy API Server"
            and "GET /v1/models" in sequence(response.get("endpoints")))


class Client:
    def __init__(self, url, key_file):
        self._host, self._port = loopback_address(url)
        self._key, revision = read_key(key_file)
        self.configuration_fingerprint = self._fingerprint("configuration", revision)

    def _fingerprint(self, *parts):
        message = json.dumps((self._host, self._port, *parts), ensure_ascii=True).encode()
        return hashlib.sha256(message).hexdigest()

    def _request(self, path, *, deadline, request=None):
        return request_json(self._host, self._port, MANAGEMENT + path, deadline=deadline,
                            request=request, key=self._key, limit=RESPONSE_LIMIT)

    def credentials(self, *, deadline=None):
        response = self._request("/credentials", deadline=deadline)
        if not isinstance(response, dict) or not isinstance(response.get("files"), list):
            raise ProxyError("invalid-response")
        by_provider = {"claude": {}, "codex": {}, "kimi": {}}
        for row in response["files"]:
            if not isinstance(row, dict):
                continue
            channel = row.get("provider") or row.get("type")
            provider = PROVIDERS.get(channel) if isinstance(channel, str) else None
            if not provider or row.get("disabled") is True or row.get("status") == "disabled":
                continue
            kind = row.get("account_type")
            if kind == "api_key":
                continue
            index = row.get("auth_index")
            if not isinstance(index, str) or not ROUTING_ID.fullmatch(index):
                continue
            claims = row.get("id_token")
            account_id = claims.get("chatgpt_account_id") if provider == "codex" and isinstance(claims, dict) else None
            if not isinstance(account_id, str) or not ROUTING_ID.fullmatch(account_id):
                account_id = ""
            portal = row.get("oauth_provider") or channel
            region = KIMI_REGIONS.get(portal) if provider == "kimi" and isinstance(portal, str) else None
            email = row.get("email")
            email = email.strip().casefold() if isinstance(email, str) and len(email) <= 254 else ""
            # A file can keep its index after a different account signs in.
            # Use an available email only as input to the opaque account key.
            identity = (email,) if EMAIL.fullmatch(email) else ()
            fingerprint = self._fingerprint("credential", provider, index, account_id, region, *identity)
            modified = row.get("modtime")
            revision = (self._fingerprint("credential-revision", fingerprint, modified)
                        if isinstance(modified, str) and 0 < len(modified) <= 64 else "")
            by_provider[provider][index] = Credential(provider, fingerprint, index, account_id, region,
                                                       row.get("requires_sign_in") is True, revision)
        return {provider: sorted(rows.values(), key=lambda row: row.fingerprint)
                for provider, rows in by_provider.items()}

    def _account_get(self, credential, url, headers, deadline, *, limit=RESPONSE_LIMIT):
        if credential.requires_sign_in:
            raise ProxyError("upstream-auth")
        headers = {**headers, "Authorization": TOKEN, "Accept": "application/json"}
        if credential.provider == "codex" and credential.account_id:
            headers["Chatgpt-Account-Id"] = credential.account_id
        response = self._request("/requests/api-call", deadline=deadline, request={
            "auth_index": credential.index, "method": "GET", "url": url, "header": headers,
        })
        status = response.get("status_code") if isinstance(response, dict) else None
        if type(status) is not int or not 100 <= status <= 599:
            raise ProxyError("invalid-response")
        check_status(status, wrapped_retry_after(response.get("header")), management=False)
        raw = response.get("body")
        if not isinstance(raw, str) or (limit < RESPONSE_LIMIT and len(raw.encode("utf-8", "surrogatepass")) > limit):
            raise ProxyError("invalid-response")
        body = decode_json(raw)
        if not isinstance(body, dict):
            raise ProxyError("invalid-response")
        if credential.provider == "codex" and credential.account_id and (
                body.get("account_id", body.get("accountId", credential.account_id)) != credential.account_id):
            raise ProxyError("invalid-response")
        return body

    def usage(self, credential, now, *, claude_parser, kimi_parser, kimi_region="auto", deadline=None, extras=None):
        if credential.requires_sign_in:
            raise ProxyError("upstream-auth")
        region = None
        if credential.provider == "claude":
            body = self._account_get(credential, CLAUDE_OAUTH + "/usage?cedar_ember=1", CLAUDE_HEADERS, deadline)
            reading = parse_claude(body, claude_parser)
        elif credential.provider == "codex":
            body = self._account_get(credential, CODEX_WHAM + "/usage", CODEX_HEADERS, deadline)
            reading = parse_codex(body, now)
        elif credential.provider == "kimi":
            region = credential.region if kimi_region == "auto" else kimi_region
            if region not in KIMI_HOSTS:
                raise ProxyError("unsupported-credential")
            body = self._account_get(credential, f"https://{KIMI_HOSTS[region]}/coding/v1/usages", {}, deadline)
            reading = parse_kimi(body, kimi_parser)
        else:
            raise ProxyError("unsupported-credential")
        if not any((reading.get("weekly"), reading.get("scoped"), reading.get("week"), "session" in reading)):
            raise ProxyError("invalid-response")
        if extras is not None:
            reading.update(extras(credential.provider, body, region, now))
        return reading

    def claude_credits(self, credential, *, prepaid_request, deadline):
        profile = self._account_get(credential, CLAUDE_OAUTH + "/profile", CLAUDE_HEADERS,
                                    deadline, limit=EXTRA_RESPONSE_LIMIT)
        raw_org = record(profile.get("organization")).get("uuid")
        try:
            org = uuid.UUID(raw_org)
            if not org.int:
                raise ValueError
        except (TypeError, ValueError, AttributeError):
            raise ProxyError("invalid-response") from None
        url, headers = prepaid_request(str(org), TOKEN)
        return self._account_get(credential, url, headers, deadline, limit=EXTRA_RESPONSE_LIMIT)

    def codex_reset_details(self, credential, *, deadline):
        return self._account_get(credential, CODEX_WHAM + "/rate-limit-reset-credits", CODEX_HEADERS,
                                 deadline, limit=EXTRA_RESPONSE_LIMIT)

    def affinity(self, *, deadline=None):
        until = time.monotonic() + 1
        if deadline is not None:
            until = min(until, deadline)
        try:
            enabled = self._request("/config/routing/session-affinity", deadline=until)
        except ProxyError as error:
            if error.reason in ("management-auth", "management-rate-limited"):
                raise
            return None
        if type(enabled) is not bool:
            return None
        result = {"enabled": enabled}
        if enabled:
            try:
                ttl = self._request("/config/routing/session-affinity-ttl", deadline=until)
                if (seconds := duration_seconds(ttl)) is not None:
                    result["ttlSeconds"] = seconds
            except ProxyError as error:
                if error.reason in ("management-auth", "management-rate-limited"):
                    raise
        return result


def duration_seconds(value):
    """Return a Go configuration duration rounded down to seconds."""
    if not isinstance(value, str) or len(value) > 64:
        return None
    factors = {"h": HOUR, "m": 60, "s": 1, "ms": 1e-3, "us": 1e-6, "µs": 1e-6, "ns": 1e-9}
    parts = re.findall(r"(\d+(?:\.\d+)?)(h|ms|m|s|us|µs|ns)", value, flags=re.ASCII)
    if not parts or "".join(number + unit for number, unit in parts) != value:
        return None
    seconds = sum(float(number) * factors[unit] for number, unit in parts)
    return int(seconds) if 0 < seconds <= 366 * DAY else None


def pool_fingerprint(credentials):
    return hashlib.sha256("".join(sorted(row.fingerprint for row in credentials)).encode()).hexdigest()


def record(value):
    return value if isinstance(value, dict) else {}


def sequence(value):
    return value if isinstance(value, list) else []


def number(value):
    if type(value) not in (str, int, float) or isinstance(value, str) and len(value) > 32:
        return None
    with suppress(ValueError, OverflowError):
        parsed = float(value)
        if math.isfinite(parsed):
            return parsed
    return None


def reset_time(value):
    if (stamp := number(value)) is not None:
        return int(stamp) if 0 < stamp <= 253402300799 else None
    if isinstance(value, str) and len(value) <= 64:
        with suppress(ValueError, OSError, OverflowError):
            stamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if stamp.tzinfo is None:
                stamp = stamp.replace(tzinfo=timezone.utc)
            return int(stamp.timestamp())
    return None


def percent(used):
    return min(100, math.floor(used + 0.5))


def window(used, reset, length, period):
    if (used := number(used)) is None or used < 0:
        return None
    return {"percent": percent(used), "exhausted": used >= 100, "resetsAt": reset_time(reset),
            "windowSeconds": length, "period": period, "_used": min(100, used)}


def scoped_window(result, label, candidate, identifier=None):
    if candidate is not None:
        result.append({"id": identifier or label, "label": label, **candidate})


def parse_claude(body, session_parser):
    all_models = record(body.get("seven_day"))
    reading = {"scoped": []}
    if weekly := window(all_models.get("utilization"), all_models.get("resets_at"), WEEK, "week"):
        reading["weekly"] = weekly
    limits = sequence(body.get("limits"))
    if not limits or body.get("five_hour") is not None or any(record(row).get("kind") == "session" for row in limits):
        try:
            session = session_parser(body)
            if session is None:
                reading["session"] = None
            else:
                five_hour = body["five_hour"]
                reading["session"] = window(five_hour["utilization"], session["resetsAt"], SESSION, "session")
        except (KeyError, ValueError, TypeError, OverflowError, OSError):
            reading["sessionUnknown"] = True

    scopes, unknown = {}, set()
    for limit in limits:
        limit = record(limit)
        model = record(record(limit.get("scope")).get("model"))
        label = model.get("display_name")
        if not isinstance(label, str) or not MODEL_NAME.fullmatch(label) or limit.get("kind") != "weekly_scoped":
            continue
        if label.casefold() in ("fable", "fable 5"):
            label = "Fable"
        candidate = window(limit.get("percent"), limit.get("resets_at"), WEEK, "week")
        if candidate and (label not in scopes or limit.get("is_active") is True):
            scopes[label] = candidate
        elif not candidate:
            unknown.add(label)
    for key, label in (("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet"), ("iguana_necktie", "Fable")):
        alias = record(body.get(key))
        if label in scopes or not alias:
            continue
        dollars = ("limit_dollars", "used_dollars", "remaining_dollars")
        if key == "iguana_necktie" and any(number(alias.get(field)) is not None for field in dollars):
            continue
        candidate = window(alias.get("utilization"), alias.get("resets_at"), WEEK, "week")
        if candidate:
            scopes[label] = candidate
        else:
            unknown.add(label)
    for label, candidate in scopes.items():
        scoped_window(reading["scoped"], label, candidate)
    if unknown := sorted(unknown.difference(scopes)):
        reading["_unknownScoped"] = unknown
    return reading


def period_for(length):
    if length == SESSION:
        return "session"
    if length == WEEK:
        return "week"
    if 28 * DAY <= length <= 31 * DAY:
        return "month"
    return "other"


def window_key(candidate):
    period = candidate["period"]
    return (period, candidate["windowSeconds"] if period == "other" else 0)


def primary_order(candidate):
    order = {"week": 3, "month": 2, "other": 1, "session": 0}
    return order[candidate["period"]], candidate["windowSeconds"]


def codex_windows(block, now, unknown=None):
    block = record(block)
    windows = []
    for snake, camel in (("primary_window", "primaryWindow"), ("secondary_window", "secondaryWindow")):
        candidate = record(block.get(snake, block.get(camel)))
        if not candidate:
            continue
        raw_length = candidate.get("limit_window_seconds", candidate.get("limitWindowSeconds"))
        length = number(raw_length)
        if length is None or not length.is_integer() or not 0 < length <= 366 * DAY:
            continue
        length = int(length)
        reset = reset_time(candidate.get("reset_at", candidate.get("resetAt")))
        if reset is None:
            delay = number(candidate.get("reset_after_seconds", candidate.get("resetAfterSeconds")))
            if delay is not None and 0 <= delay <= 366 * DAY:
                reset = now + int(delay)
        period = period_for(length)
        used = candidate.get("used_percent", candidate.get("usedPercent"))
        if parsed := window(used, reset, length, period):
            if not any(window_key(old) == window_key(parsed) for old in windows):
                windows.append(parsed)
        elif unknown is not None:
            # An exhausted rate-limit block does not identify which of its
            # windows is exhausted.
            unknown.append({"period": period, "windowSeconds": length})
    return sorted(windows, key=primary_order, reverse=True)


def parse_codex(body, now):
    rate_limit = body.get("rate_limit", body.get("rateLimit"))
    unknown = []
    windows = codex_windows(rate_limit, now, unknown)
    reading = {"scoped": []}
    known = {window_key(window) for window in windows}
    unknown = [window for window in unknown if window_key(window) not in known]
    if unknown:
        reading["_unknownPeriods"] = unknown
        if any(window["period"] == "session" for window in unknown):
            reading["sessionUnknown"] = True
    if windows:
        reading["weekly"] = windows[0]
        for candidate in windows[1:]:
            if candidate["period"] == "session":
                reading["session"] = candidate
            else:
                reading.setdefault("otherPeriods", []).append(candidate)
    reviews = codex_windows(body.get("code_review_rate_limit", body.get("codeReviewRateLimit")), now)
    for candidate in reviews:
        scoped_window(reading["scoped"], "Code review", candidate, "code-review-" + scope_period(candidate))
    for item in sequence(body.get("additional_rate_limits", body.get("additionalRateLimits"))):
        item = record(item)
        label = item.get("limit_name", item.get("limitName")) or item.get("metered_feature", item.get("meteredFeature"))
        if not isinstance(label, str) or not MODEL_NAME.fullmatch(label):
            continue
        for candidate in codex_windows(item.get("rate_limit", item.get("rateLimit")), now):
            identifier = "model-" + label.casefold() + "-" + scope_period(candidate)
            if all(w["id"] != identifier for w in reading["scoped"]):
                scoped_window(reading["scoped"], label, candidate, identifier)
    return reading


def scope_period(candidate):
    return str(candidate["windowSeconds"]) if candidate["period"] == "other" else candidate["period"]


def parse_kimi(body, kimi_parser):
    usages = record(body.get("usages"))
    reading = {"scoped": []}
    try:
        parsed = kimi_parser(body)
    except (RuntimeError, ValueError, TypeError, OverflowError, OSError):
        parsed = {}
    for key, slot, period, length in (("limit_month_total", "weekly", "month", None),
                                      ("limit_5h", "session", "session", SESSION), ("limit_7d", "week", "week", WEEK)):
        limit = record(usages.get(key))
        ratio = number(limit.get("used_ratio"))
        reset = reset_time(limit.get("reset_time"))
        seconds = record(parsed.get(slot)).get("windowSeconds", length)
        if ratio is not None and reset is not None and seconds is not None:
            candidate = window(ratio * 100, reset, seconds, period)
            if candidate:
                reading[slot] = candidate
        elif slot == "session" and key in usages:
            reading["sessionUnknown"] = True
    return reading


def visible_window(candidate, now):
    result = {key: candidate[key] for key in ("percent", "exhausted", "resetsAt", "windowSeconds", "period", "id", "label")
              if key in candidate}
    reset = candidate["resetsAt"]
    result["resetTimes"] = [reset] if reset is not None and reset > now else []
    result["resetsAt"] = result["resetTimes"][0] if result["resetTimes"] else None
    return result


def pooled_window(candidates, now, *, incomplete=False, idle=0):
    resets = sorted({w["resetsAt"] for w in candidates if w["resetsAt"] is not None and w["resetsAt"] > now})
    count = len(candidates) + idle
    result = visible_window(candidates[0], now)
    used = math.fsum(w["_used"] for w in candidates) / count
    result.update(percent=percent(used), exhausted=used >= 100, resetTimes=resets,
                  resetsAt=resets[0] if resets else None)
    # A calendar-month length comes from the account whose reset is shown.
    if resets:
        result["windowSeconds"] = next(candidate["windowSeconds"] for candidate in candidates
                                       if candidate["resetsAt"] == resets[0])
    if count > 1:
        result["accountAverage"] = True
    if incomplete:
        result["incomplete"] = True
    return result


def visible_account(account, now):
    result = {"state": account["state"]}
    if type(account.get("fetchedAt")) is int:
        result["fetchedAt"] = account["fetchedAt"]
    reason = account.get("reason")
    if isinstance(reason, str) and reason in REASONS:
        result["reason"] = reason
    for slot in ("weekly", "week", "session"):
        if slot in account:
            candidate = account[slot]
            result[slot] = visible_window(candidate, now) if candidate is not None else None
    for slot in ("scoped", "otherPeriods"):
        if slot == "scoped" or slot in account:
            result[slot] = [visible_window(candidate, now) for candidate in account.get(slot, [])]
    if account.get("sessionUnknown"):
        result["sessionUnknown"] = True
    for slot in ("bankedResets", "credits"):
        if slot in account:
            result[slot] = account[slot]
    return result


def aggregate(accounts, now):
    """Average only comparable percentages with the same provider, scope and period."""
    primary = {}
    scoped = {}
    for account in accounts:
        account_windows = account.get("otherPeriods", [])
        if account.get("weekly"):
            account_windows = [account["weekly"], *account_windows]
        for candidate in account_windows:
            primary.setdefault(window_key(candidate), []).append(candidate)
        for candidate in account.get("scoped", []):
            scoped.setdefault((candidate["id"], window_key(candidate)), []).append(candidate)
    session_key = ("session", 0)
    if session_key in primary:
        primary[session_key].extend(account["session"] for account in accounts if account.get("session"))
    missing = any(account["state"] != "ok" for account in accounts)
    missing_primary = missing or any(not account.get("weekly") for account in accounts)
    periods = sorted(primary.values(), key=lambda group: primary_order(group[0]), reverse=True)
    unknown_periods = {window_key(window) for account in accounts for window in account.get("_unknownPeriods", [])}
    pooled_periods = [pooled_window(group, now, incomplete=missing_primary or window_key(group[0]) in unknown_periods)
                      for group in periods]
    unknown_scopes = {scope for account in accounts for scope in account.get("_unknownScoped", [])}
    result = {"scoped": [pooled_window(group, now, incomplete=missing or key[0] in unknown_scopes)
                        for key, group in sorted(scoped.items())],
              "otherPeriods": pooled_periods[1:],
              "accounts": [visible_account(account, now) for account in accounts]}
    if pooled_periods:
        result["weekly"] = pooled_periods[0]
    for slot in ("session", "week"):
        group = primary[session_key] if slot == "session" and session_key in primary else [
            account[slot] for account in accounts if account.get(slot)]
        idle = sum(slot in account and account[slot] is None for account in accounts)
        unknown = slot == "session" and any(account.get("sessionUnknown") for account in accounts)
        if group:
            result[slot] = pooled_window(group, now, incomplete=missing or unknown, idle=idle)
        elif slot == "session":
            if missing or unknown:
                result["sessionUnknown"] = True
            elif idle:
                result["session"] = None
    return result
