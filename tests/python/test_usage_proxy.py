# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import io
import json
import os
import socket
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from test_usage import usage

proxy = usage.proxy_backend()
NOW = 1_790_000_000
KEY = "fixture-operator-key"
PRIVATE_ACCOUNT = "fixture-chatgpt-workspace"
PRIVATE_MEMBER = "member@example.invalid"


def codex_window(used, *, length=proxy.WEEK, reset=NOW + 1000):
    return {"used_percent": used, "limit_window_seconds": length, "reset_at": reset}


def claude_window(used=20.4, reset=NOW + 1000, **extras):
    return {"utilization": used, "resets_at": reset, **extras}


def kimi_window(used, reset=NOW + 1000):
    return {"used_ratio": used, "reset_time": reset}


def wrapped(body, *, status=200, headers=None):
    return {"status_code": status, "header": headers or {}, "body": json.dumps(body)}


class ManagementSocket:
    def __init__(self, server):
        self.server = server
        self.sent = bytearray()
        self.interrupted = threading.Event()

    def sendall(self, data):
        self.sent.extend(data)

    def makefile(self, _):
        headers, body = bytes(self.sent).split(b"\r\n\r\n", 1)
        request, *headers = headers.decode().split("\r\n")
        method, path, _ = request.split()
        headers = dict(line.split(": ", 1) for line in headers)
        self.server.requests.append((method, path, headers.get("Authorization"), body))
        status, payload, headers = self.server.replies[path]
        if status is None:
            stop = self.interrupted

            class SlowHeaders(io.BytesIO):
                def readline(self, limit=-1):
                    if self.tell():
                        stop.wait(1)
                    return super().readline(limit)

            return SlowHeaders(b"HTTP/1.0 200 OK\r\n")
        data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        headers = {"Content-Length": len(data), **headers}
        encoded = "".join(f"{name}: {value}\r\n" for name, value in headers.items())
        return io.BytesIO(f"HTTP/1.0 {status} Test response\r\n{encoded}\r\n".encode() + data)

    def shutdown(self, how):
        if how == socket.SHUT_RDWR:
            self.interrupted.set()

    def close(self):
        pass


class ProxyClient(unittest.TestCase):
    def setUp(self):
        folder = self.enterContext(tempfile.TemporaryDirectory())
        self.key_file = Path(folder) / "key"
        self.key_file.touch(mode=0o600)
        self.key_file.write_text(KEY + "\n")

    def client(self, url="http://localhost:8317"):
        return proxy.Client(url, self.key_file)

    def server(self, **replies):
        server = SimpleNamespace(server_port=8317, requests=[], replies={
            proxy.MANAGEMENT + path if path != "/" else path: value for path, value in replies.items()})

        def connect(connection):
            self.assertEqual((connection.host, connection.port), ("127.0.0.1", server.server_port))
            connection.sock = ManagementSocket(server)

        self.enterContext(mock.patch.object(proxy.http.client.HTTPConnection, "connect", connect))
        return server, self.client(f"http://127.0.0.1:{server.server_port}")

    def usage(self, client, credential, **options):
        return client.usage(credential, NOW, claude_parser=usage.parse_session, kimi_parser=usage.parse_kimi, **options)

    def test_loopback_http_is_required_and_localhost_is_numeric(self):
        for url in ("https://127.0.0.1:8317", "http://0.0.0.0", "http://192.0.2.1", "http://127.1",
                    "http://2130706433", "http://localhost.example.invalid", "http://127.0.0.1@192.0.2.1",
                    "http://user@localhost", "http://localhost/credentials", "http://localhost#",
                    "http://localhost?", "http://localhost:", "http://localhost:0", "http://localhost:65536",
                    "http://localhost\t", "http://[::ffff:127.0.0.1]"):
            with self.subTest(url=url), self.assertRaisesRegex(proxy.ProxyError, "^configuration$"):
                self.client(url)
        for url, host in (("http://localhost:8317/", "127.0.0.1"), ("http://127.12.34.56", "127.12.34.56"),
                          ("http://[::1]:8317", "::1")):
            with self.subTest(url=url):
                self.assertEqual(self.client(url)._host, host)

    def test_key_is_private_regular_and_changes_revision(self):
        first = self.client().configuration_fingerprint
        self.assertEqual(first, self.client("http://127.0.0.1:8317/").configuration_fingerprint)
        self.key_file.write_text("changed-key\n")
        self.assertNotEqual(first, self.client().configuration_fingerprint)
        self.key_file.chmod(0o640)
        with self.assertRaisesRegex(proxy.ProxyError, "^key-file$"):
            self.client()
        self.key_file.unlink()
        os.mkfifo(self.key_file, 0o600)
        with self.assertRaisesRegex(proxy.ProxyError, "^key-file$"):
            self.client()
        self.key_file.unlink()
        target = self.key_file.with_suffix(".target")
        target.touch(mode=0o600)
        target.write_text(KEY)
        self.key_file.symlink_to(target)
        with self.assertRaisesRegex(proxy.ProxyError, "^key-file$"):
            self.client()
        self.key_file.unlink()
        with self.assertRaisesRegex(proxy.ProxyError, "^key-file$"):
            self.client()
        self.key_file.touch(mode=0o600)
        for key in ("a\nb", "a b", "a" * (proxy.KEY_LIMIT + 1)):
            self.key_file.write_text(key)
            with self.subTest(key_length=len(key)), self.assertRaisesRegex(proxy.ProxyError, "^key-file$"):
                self.client()

    def test_discovery_routing_affinity_and_private_output(self):
        rows = {
            "files": [
                {"provider": "claude", "auth_index": "alpha", "account_type": "oauth", "email": PRIVATE_MEMBER},
                {"provider": "claude", "auth_index": "ignored", "account_type": "api_key", "account": "fixture-api-secret"},
                {"provider": "claude", "auth_index": "off", "disabled": True},
                {"provider": "codex", "auth_index": "bravo", "id_token": {"chatgpt_account_id": PRIVATE_ACCOUNT}},
                {"provider": "codex", "auth_index": "charlie", "id_token": {"chatgpt_account_id": PRIVATE_ACCOUNT}},
                {"provider": "codex", "auth_index": "legacy"},
                {"provider": "codex", "auth_index": "legacy"},
                {"provider": "kimi", "auth_index": "delta", "oauth_provider": "kimi-ai"},
                {"provider": "kimi", "auth_index": "echo", "oauth_provider": "kimi"},
                {"provider": "kimi", "auth_index": "missing", "oauth_provider": "unknown"},
                {"provider": "opencode", "auth_index": "unknown"},
            ],
        }
        server, client = self.server(**{
            "/credentials": (200, rows, {}),
            "/requests/api-call": (200, wrapped({"seven_day": claude_window(),
                                                "limits": [{"kind": "weekly_all"}]}), {}),
            "/config/routing/session-affinity": (200, True, {}),
            "/config/routing/session-affinity-ttl": (200, "1h30m", {}),
        })
        with mock.patch.dict(os.environ, {"http_proxy": "http://192.0.2.1:9", "no_proxy": ""}):
            roster = client.credentials()
            self.assertEqual(client.affinity(), {"enabled": True, "ttlSeconds": 5400})
        self.assertEqual({provider: len(entries) for provider, entries in roster.items()},
                         {"claude": 1, "codex": 3, "kimi": 3})
        self.assertEqual(proxy.pool_fingerprint(roster["codex"]), proxy.pool_fingerprint(reversed(roster["codex"])))
        self.assertNotIn(PRIVATE_ACCOUNT, repr(roster))
        self.assertNotIn(PRIVATE_MEMBER, repr(roster))

        claude_reading = self.usage(client, roster["claude"][0])
        claude_request = json.loads(server.requests[-1][3])
        self.assertEqual(claude_request["url"], "https://api.anthropic.com/api/oauth/usage")
        self.assertEqual(claude_request["header"]["anthropic-beta"], "oauth-2025-04-20")

        codex_reply = {"account_id": PRIVATE_ACCOUNT,
                       "rate_limit": {"primary_window": codex_window(50)}}
        server.replies[proxy.MANAGEMENT + "/requests/api-call"] = (200, wrapped(codex_reply), {})
        for seat in roster["codex"]:
            reading = self.usage(client, seat)
            self.assertEqual(reading["weekly"]["percent"], 50)
            request = json.loads(server.requests[-1][3])
            self.assertEqual(request["url"], "https://chatgpt.com/backend-api/wham/usage")
            self.assertEqual(request["header"].get("Chatgpt-Account-Id"), seat.account_id or None)
        server.replies[proxy.MANAGEMENT + "/requests/api-call"] = (
            200, wrapped(dict(codex_reply, account_id="other-workspace")), {})
        seat = next(seat for seat in roster["codex"] if seat.account_id)
        with self.assertRaisesRegex(proxy.ProxyError, "^invalid-response$"):
            self.usage(client, seat)

        kimi_reply = {"usages": {"limit_month_total": kimi_window(".30")}}
        server.replies[proxy.MANAGEMENT + "/requests/api-call"] = (200, wrapped(kimi_reply), {})
        for credential in roster["kimi"]:
            if credential.region is None:
                with self.assertRaisesRegex(proxy.ProxyError, "^unsupported-credential$"):
                    self.usage(client, credential)
                self.usage(client, credential, kimi_region="global")
            else:
                self.usage(client, credential)
            request = json.loads(server.requests[-1][3])
            host = "api.kimi.com" if credential.region == "china" else "api.kimi.ai"
            self.assertEqual(request["url"], f"https://{host}/coding/v1/usages")

        for method, path, authorization, body in server.requests:
            self.assertEqual(authorization, "Bearer " + KEY)
            if path.endswith("/requests/api-call"):
                self.assertEqual(method, "POST")
                request = json.loads(body)
                self.assertEqual(request["method"], "GET")
                self.assertEqual(request["header"]["Authorization"], "Bearer $TOKEN$")
                self.assertNotIn(KEY, str(request))
            else:
                self.assertEqual(method, "GET")
                self.assertEqual(body, b"")
        report = json.dumps(proxy.aggregate([dict(claude_reading, state="ok")], NOW))
        for private in ("alpha", PRIVATE_MEMBER, PRIVATE_ACCOUNT, KEY, "_used"):
            self.assertNotIn(private, report)

    def test_management_redirects_error_bodies_and_pinned_upstream_refusal(self):
        server, client = self.server(**{"/credentials": (302, b"", {"Location": "/redirect-target"})})
        with self.assertRaisesRegex(proxy.ProxyError, "^invalid-response$"):
            client.credentials()
        self.assertEqual(len(server.requests), 1)

        discovery = proxy.MANAGEMENT + "/credentials"
        calls = proxy.MANAGEMENT + "/requests/api-call"
        server.replies[discovery] = (401, {"message": KEY}, {})
        with self.assertRaisesRegex(proxy.ProxyError, "^management-auth$"):
            client.credentials()

        account = proxy.Credential("claude", "fingerprint", "index")
        server.replies[calls] = (200, wrapped({"message": KEY}, status=403), {})
        with self.assertRaisesRegex(proxy.ProxyError, "^upstream-auth$"):
            self.usage(client, account)
        server.replies[calls] = (400, {"error": "auth token not found"}, {})
        with self.assertRaisesRegex(proxy.ProxyError, "^upstream-auth$"):
            self.usage(client, account)
        server.replies[calls] = (200, wrapped({"message": KEY}, status=429, headers={"retry-after": ["90"]}), {})
        with self.assertRaisesRegex(proxy.ProxyError, "^rate-limited$") as error:
            self.usage(client, account)
        self.assertEqual(error.exception.retry_after, 90)
        server.replies[calls] = (429, b"", {"Retry-After": "120"})
        with self.assertRaisesRegex(proxy.ProxyError, "^management-rate-limited$") as error:
            self.usage(client, account)
        self.assertEqual(error.exception.retry_after, 120)

    def test_request_bounds_json_and_expired_deadline(self):
        server, client = self.server(**{"/credentials": (200, b"{}" * 100, {})})
        with self.assertRaisesRegex(proxy.ProxyError, "^timeout$"):
            client.credentials(deadline=time.monotonic() - 1)
        self.assertEqual(server.requests, [])
        with mock.patch.object(proxy, "RESPONSE_LIMIT", 100), self.assertRaisesRegex(proxy.ProxyError, "^invalid-response$"):
            client.credentials()

    def test_discovery_checks_only_the_unauthenticated_identity_route(self):
        identity = {"message": "CLI Proxy API Server", "endpoints": ["GET /v1/models"]}
        server, _ = self.server(**{"/": (200, identity, {})})
        url = f"http://localhost:{server.server_port}"
        self.assertTrue(proxy.discover(url))
        self.assertEqual(server.requests, [("GET", "/", None, b"")])
        server.replies["/"] = (200, {"status": "ok"}, {})
        self.assertFalse(proxy.discover(url))
        self.assertFalse(proxy.discover("http://192.0.2.1"))

    def test_affinity_preserves_management_refusal(self):
        _, client = self.server(**{
            "/config/routing/session-affinity": (200, True, {}),
            "/config/routing/session-affinity-ttl": (403, b"", {}),
        })
        with self.assertRaisesRegex(proxy.ProxyError, "^management-auth$"):
            client.affinity()

    def test_slow_headers_stop_at_absolute_deadline(self):
        _, client = self.server(**{"/credentials": (None, None, {})})
        started = time.monotonic()
        with self.assertRaisesRegex(proxy.ProxyError, "^timeout$"):
            client.credentials(deadline=started + .15)
        self.assertLess(time.monotonic() - started, 1)


class ProxyWindows(unittest.TestCase):
    def test_claude_preserves_reported_fable_and_distinguishes_idle_unknown_and_dollars(self):
        def fable(label, used, active=False):
            return {"kind": "weekly_scoped", "percent": used, "resets_at": NOW + 1800,
                    "is_active": active, "scope": {"model": {"display_name": label}}}

        raw = {"seven_day": claude_window(), "five_hour": None, "limits": [
            {"kind": "session"}, fable("Fable", 90), fable("Fable 5", 34.49, True),
        ], "iguana_necktie": claude_window(55, used_dollars=400)}
        reading = proxy.parse_claude(raw, usage.parse_session)
        self.assertIsNone(reading["session"])
        self.assertEqual([(w["id"], w["_used"]) for w in reading["scoped"]], [("Fable", 34.49)])
        raw.pop("five_hour")
        raw["limits"] = [{"kind": "session"}]
        reading = proxy.parse_claude(raw, usage.parse_session)
        self.assertTrue(reading["sessionUnknown"])
        self.assertEqual(reading["scoped"], [])
        raw["iguana_necktie"] = claude_window(55)
        self.assertEqual(proxy.parse_claude(raw, usage.parse_session)["scoped"][0]["id"], "Fable")
        raw["seven_day"] = claude_window(None)
        self.assertNotIn("weekly", proxy.parse_claude(raw, usage.parse_session))

    def test_kimi_uses_calendar_months_and_allows_missing_auxiliary_limits(self):
        first_reset = "2026-03-31T12:00:00Z"
        raw = {"usages": {"limit_month_total": kimi_window("0.346", first_reset), "limit_5h": kimi_window(None)}}
        reading = proxy.parse_kimi(raw, usage.parse_kimi)
        self.assertEqual(reading["weekly"]["percent"], 35)
        self.assertEqual(reading["weekly"]["windowSeconds"], 31 * proxy.DAY)
        self.assertTrue(reading["sessionUnknown"])
        self.assertNotIn("week", reading)
        self.assertEqual(proxy.parse_kimi({"usages": {"limit_7d": kimi_window(.4)}}, usage.parse_kimi)["week"]["percent"],
                         40)

    def test_codex_separates_main_periods_and_code_review(self):
        raw = {"rate_limit": {"primary_window": codex_window(20.1, length=30 * proxy.DAY),
                              "secondary_window": codex_window(71.8)},
               "code_review_rate_limit": {"primary_window": codex_window(13, length=proxy.SESSION),
                                          "secondary_window": codex_window(80, length=30 * proxy.DAY)}}
        reading = proxy.parse_codex(raw, NOW)
        self.assertEqual((reading["weekly"]["period"], reading["weekly"]["percent"]), ("week", 72))
        self.assertEqual((reading["otherPeriods"][0]["period"], reading["otherPeriods"][0]["percent"]), ("month", 20))
        self.assertEqual({w["id"]: w["percent"] for w in reading["scoped"]},
                         {"code-review-session": 13, "code-review-month": 80})
        self.assertNotIn("weekly", proxy.parse_codex({"rate_limit": {"primary_window": codex_window(None)}}, NOW))
        raw["rate_limit"]["secondary_window"].pop("limit_window_seconds")
        ambiguous = proxy.parse_codex(raw, NOW)
        self.assertEqual(ambiguous["weekly"]["period"], "month")
        self.assertNotIn("otherPeriods", ambiguous)

    def test_codex_block_exhaustion_does_not_fill_in_unknown_session(self):
        block = {"allowed": False, "primary_window": codex_window(None, length=proxy.SESSION),
                 "secondary_window": codex_window(100)}
        unknown = proxy.parse_codex({"rate_limit": block}, NOW)
        self.assertTrue(unknown["sessionUnknown"])
        self.assertNotIn("session", unknown)
        self.assertEqual(unknown["weekly"]["percent"], 100)

        block["primary_window"] = codex_window(25, length=proxy.SESSION)
        known = proxy.parse_codex({"rate_limit": block}, NOW)
        summary = proxy.aggregate([dict(unknown, state="ok"), dict(known, state="ok")], NOW)
        self.assertEqual(summary["session"]["percent"], 25)
        self.assertTrue(summary["session"]["incomplete"])

    def test_rounds_only_once_and_keeps_future_resets_and_missing_accounts(self):
        def reading(used, reset):
            return dict(proxy.parse_claude({"seven_day": claude_window(used, reset)}, usage.parse_session), state="ok",
                        fetchedAt=NOW - 10)
        accounts = [reading(33.49, NOW + 1000), reading(33.49, NOW + 3000), reading(34.49, NOW - 500),
                    {"state": "unavailable"}]
        result = proxy.aggregate(accounts, NOW)
        self.assertEqual(result["weekly"]["percent"], 34)
        self.assertEqual(result["weekly"]["resetTimes"], [NOW + 1000, NOW + 3000])
        self.assertEqual(result["weekly"]["resetsAt"], NOW + 1000)
        self.assertTrue(result["weekly"]["accountAverage"])
        self.assertTrue(result["weekly"]["incomplete"])
        self.assertEqual(result["accounts"][0]["fetchedAt"], NOW - 10)
        self.assertEqual(result["accounts"][-1], {"state": "unavailable", "scoped": []})
        self.assertEqual(result["accounts"][-2]["weekly"]["resetTimes"], [])
        self.assertNotIn("weekly", proxy.aggregate([accounts[-1]], NOW))

    def test_different_known_periods_never_blend(self):
        def reading(used, length):
            block = {"primary_window": codex_window(used, length=length)}
            return dict(proxy.parse_codex({"rate_limit": block}, NOW), state="ok")

        result = proxy.aggregate([reading(100, proxy.WEEK), reading(0, proxy.DAY * 30), reading(50, proxy.SESSION)], NOW)
        self.assertEqual(result["weekly"]["percent"], 100)
        self.assertNotIn("incomplete", result["weekly"])
        self.assertEqual([(w["period"], w["percent"]) for w in result["otherPeriods"]], [("month", 0), ("session", 50)])

    def test_session_averages_idle_but_flags_unknown(self):
        base = {"seven_day": claude_window(), "limits": [{"kind": "session"}]}
        running = dict(proxy.parse_claude(dict(base, five_hour=claude_window(45)), usage.parse_session), state="ok")
        idle = dict(proxy.parse_claude(dict(base, five_hour=None), usage.parse_session), state="ok")
        unknown = dict(proxy.parse_claude(base, usage.parse_session), state="ok")
        aggregate = proxy.aggregate([running, idle, unknown], NOW)
        self.assertEqual(aggregate["session"]["percent"], 23)
        self.assertTrue(aggregate["session"]["incomplete"])
        self.assertTrue(aggregate["accounts"][2]["sessionUnknown"])
