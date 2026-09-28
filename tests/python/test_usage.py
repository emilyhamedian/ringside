# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import contextlib
import email.message
import email.utils
import fcntl
import importlib.util
import io
import json
import os
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
HELPER = ROOT / "package" / "contents" / "code" / "usage.py"
WEEK = 7 * 24 * 3600


def load_helper():
    spec = importlib.util.spec_from_file_location("usage", HELPER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# A __pycache__ beside the helper would ship with the package.
sys.dont_write_bytecode = True
usage = load_helper()


def fixture(name):
    with open(FIXTURES / name, encoding="utf-8") as fh:
        return json.load(fh)


def window(percent, resets_at, seconds=WEEK):
    return {"percent": percent, "resetsAt": resets_at, "windowSeconds": seconds}


def reading(percent, resets_at, **scoped):
    """What a fetcher returns: the weekly window, and scoped windows given as id=percent."""
    return {"weekly": window(percent, resets_at),
            "scoped": [{"id": key, "label": key, **window(value, resets_at)} for key, value in scoped.items()]}


class Isolated(unittest.TestCase):
    """Points every path the helper uses into a temporary folder and fails any
    network call, so no test reaches the real ~/.claude, ~/.codex, cache or API."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.tmp = Path(folder.name)
        (self.tmp / "home").mkdir()
        self.enterContext(mock.patch.dict(os.environ, {
            "HOME": str(self.tmp / "home"),
            "XDG_CACHE_HOME": str(self.tmp / "cache"),
            "XDG_CONFIG_HOME": str(self.tmp / "config"),
            "CLAUDE_CONFIG_DIR": str(self.tmp / "claude"),
            "CODEX_HOME": str(self.tmp / "codex"),
            "RINGSIDE_USAGE_FAKE": "",
        }))
        paths = load_helper()
        self.enterContext(mock.patch.multiple(usage, **{name: getattr(paths, name) for name in (
            "CLAUDE_CREDENTIALS", "CODEX_AUTH", "CACHE_DIR", "CACHE_FILE", "HISTORY_FILE",
            "LOCK_FILE", "APPLETSRC")}))
        self.enterContext(mock.patch.object(usage.urllib.request, "urlopen",
                                            side_effect=AssertionError("a test reached the network")))

    def write_cache(self, data):
        usage.CACHE_DIR.mkdir(parents=True, exist_ok=True)
        usage.CACHE_FILE.write_text(json.dumps(data))

    def run_main(self, *argv):
        with mock.patch("sys.stdout", new=io.StringIO()) as out:
            usage.main(list(argv))
        return json.loads(out.getvalue())


class CodexParsing(Isolated):
    def test_reads_all_models_and_scoped_weekly_windows(self):
        report = usage.parse_codex(fixture("codex_rate_limits.json"))
        self.assertEqual(report, {
            "weekly": {"percent": 34, "resetsAt": 1788926677, "windowSeconds": WEEK},
            "scoped": [{"id": "codex_bengalfox", "label": "GPT-5.3-Codex-Spark",
                        "percent": 5, "resetsAt": 1788926677, "windowSeconds": WEEK}]})

    def test_scoped_window_may_sit_in_primary(self):
        result = fixture("codex_rate_limits.json")
        spark = result["rateLimitsByLimitId"]["codex_bengalfox"]
        spark["primary"], spark["secondary"] = spark["secondary"], None
        self.assertEqual(usage.parse_codex(result)["scoped"][0]["percent"], 5)

    def test_scoped_needs_a_seven_day_window(self):
        result = fixture("codex_rate_limits.json")
        result["rateLimitsByLimitId"]["codex_bengalfox"]["secondary"] = None
        self.assertEqual(usage.parse_codex(result)["scoped"], [])

    def test_scoped_label_falls_back_to_id_and_order_is_by_id(self):
        result = fixture("codex_rate_limits.json")
        week = {"usedPercent": 1, "windowDurationMins": 10080, "resetsAt": 1788926677}
        result["rateLimitsByLimitId"] = {
            "codex_zeta": {"limitName": None, "primary": week},
            "codex": result["rateLimitsByLimitId"]["codex"],
            "codex_alpha": {"limitName": "Alpha", "secondary": week},
        }
        scoped = usage.parse_codex(result)["scoped"]
        self.assertEqual([(s["id"], s["label"]) for s in scoped],
                         [("codex_alpha", "Alpha"), ("codex_zeta", "codex_zeta")])

    def test_weekly_window_may_sit_in_secondary(self):
        limit = fixture("codex_rate_limits.json")["rateLimitsByLimitId"]["codex_bengalfox"]
        self.assertEqual(usage.weekly_window(limit)["usedPercent"], 5)

    def test_falls_back_to_longest_window(self):
        limit = {"primary": {"usedPercent": 1, "windowDurationMins": 300},
                 "secondary": {"usedPercent": 2, "windowDurationMins": 1440}}
        self.assertEqual(usage.weekly_window(limit)["usedPercent"], 2)

    def test_falls_back_to_top_level_limits(self):
        for by_id in ("absent", None):
            result = fixture("codex_rate_limits.json")
            if by_id == "absent":
                del result["rateLimitsByLimitId"]
            else:
                result["rateLimitsByLimitId"] = None
            report = usage.parse_codex(result)
            self.assertEqual(report["weekly"]["percent"], 34)
            self.assertEqual(report["scoped"], [])

    def test_missing_windows_is_an_error(self):
        with self.assertRaises(RuntimeError):
            usage.parse_codex({"rateLimits": {"primary": None, "secondary": None}})

    def test_window_length_is_the_picked_windows(self):
        result = fixture("codex_rate_limits.json")
        result["rateLimitsByLimitId"]["codex"]["primary"]["windowDurationMins"] = 1440
        report = usage.parse_codex(result)
        self.assertEqual(report["weekly"]["windowSeconds"], 86400)
        self.assertEqual(report["scoped"][0]["windowSeconds"], WEEK)


class ClaudeParsing(Isolated):
    def test_reads_weekly_and_scoped_windows(self):
        report = usage.parse_claude(fixture("claude_usage.json"))
        self.assertEqual(report["weekly"], {"percent": 62, "resetsAt": 1788537600, "windowSeconds": WEEK})
        self.assertEqual(report["scoped"], [
            {"id": "Fable", "label": "Fable", "percent": 78, "resetsAt": 1788537600, "windowSeconds": WEEK},
            {"id": "Opus", "label": "Opus", "percent": 9, "resetsAt": 1788537600, "windowSeconds": WEEK}])

    def test_scoped_skips_duplicates_and_nameless_scopes(self):
        usage_body = fixture("claude_usage.json")
        fable = usage_body["limits"][2]
        usage_body["limits"] += [
            dict(fable, percent=12),
            dict(fable, scope={"model": {"id": None, "display_name": None}, "surface": None}),
            dict(fable, scope={"model": None, "surface": {"name": "Claude Code"}}),
        ]
        scoped = usage.parse_claude(usage_body)["scoped"]
        self.assertEqual([(s["id"], s["percent"]) for s in scoped], [("Fable", 78), ("Opus", 9)])

    def test_fable_falls_back_to_cinder_cove(self):
        usage_body = fixture("claude_usage.json")
        usage_body["limits"] = []
        usage_body["cinder_cove"] = {"utilization": 55.6, "resets_at": "2026-09-04T16:00:00Z"}
        self.assertEqual(usage.parse_claude(usage_body)["scoped"],
                         [{"id": "Fable", "label": "Fable", "percent": 56, "resetsAt": 1788537600,
                           "windowSeconds": WEEK}])

    def test_cinder_cove_does_not_duplicate_a_listed_fable(self):
        usage_body = fixture("claude_usage.json")
        usage_body["cinder_cove"] = {"utilization": 55.6, "resets_at": "2026-09-04T16:00:00Z"}
        self.assertEqual([s["id"] for s in usage.parse_claude(usage_body)["scoped"]], ["Fable", "Opus"])

    def test_scoped_is_empty_when_not_reported(self):
        usage_body = fixture("claude_usage.json")
        usage_body["limits"] = []
        self.assertEqual(usage.parse_claude(usage_body)["scoped"], [])

    def test_missing_weekly_is_an_error(self):
        with self.assertRaises(RuntimeError):
            usage.parse_claude({"five_hour": {"utilization": 1}})


class Conversions(Isolated):
    def test_percent_is_clamped_and_rounded(self):
        self.assertEqual(usage.clamp_percent(101.2), 100)
        self.assertEqual(usage.clamp_percent(-3), 0)
        self.assertEqual(usage.clamp_percent(61.5), 62)
        self.assertEqual(usage.clamp_percent(None), 0)

    def test_epoch_accepts_seconds_and_iso(self):
        self.assertEqual(usage.epoch_seconds(1788926677), 1788926677)
        self.assertEqual(usage.epoch_seconds("2026-09-04T16:00:00Z"), 1788537600)
        self.assertEqual(usage.epoch_seconds("2026-09-04T16:00:00.000000+00:00"), 1788537600)
        self.assertIsNone(usage.epoch_seconds("soon"))


class CredentialWriteBack(Isolated):
    def setUp(self):
        super().setUp()
        self.path = usage.CLAUDE_CREDENTIALS
        self.folder = self.path.parent
        self.folder.mkdir()
        self.path.write_text(json.dumps({
            "mcpOAuth": {"keep": "me"},
            "claudeAiOauth": {"accessToken": "old", "refreshToken": "r1", "expiresAt": 1},
        }))
        self.fresh = {"accessToken": "new", "refreshToken": "r2", "expiresAt": 2}
        self.http = mock.Mock(return_value={"access_token": "new", "refresh_token": "r2", "expires_in": 3600})
        self.enterContext(mock.patch.object(usage, "http_json", self.http))

    def test_replaces_record_when_refresh_token_unchanged(self):
        self.assertTrue(usage.store_claude(self.path, "r1", self.fresh))
        stored = json.loads(self.path.read_text())
        self.assertEqual(stored["claudeAiOauth"], self.fresh)
        self.assertEqual(stored["mcpOAuth"], {"keep": "me"})
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(os.listdir(self.folder), [".credentials.json"])

    def test_keeps_file_when_cli_rotated_first(self):
        self.assertFalse(usage.store_claude(self.path, "stale", self.fresh))
        self.assertEqual(json.loads(self.path.read_text())["claudeAiOauth"]["accessToken"], "old")

    @unittest.skipIf(os.geteuid() == 0, "root writes past mode bits")
    def test_unwritable_folder_spends_no_refresh_token(self):
        before = self.path.read_text()
        os.chmod(self.folder, 0o500)
        try:
            with self.assertRaises(RuntimeError):
                usage.claude_access_token()
        finally:
            os.chmod(self.folder, 0o700)
        self.http.assert_not_called()
        self.assertEqual(self.path.read_text(), before)

    def test_reply_without_lifetime_still_saves_the_new_refresh_token(self):
        self.http.side_effect = [{"access_token": "a2", "refresh_token": "r2"},
                                 {"access_token": "a3", "refresh_token": "r3", "expires_in": 3600}]
        tokens = [usage.claude_access_token() for _ in range(3)]
        self.assertEqual(tokens, ["a2", "a3", "a3"])
        self.assertEqual([call.args[2]["refresh_token"] for call in self.http.call_args_list], ["r1", "r2"])

    def test_symlinked_file_is_written_through_to_its_target(self):
        target = self.folder / "dotfiles" / ".credentials.json"
        target.parent.mkdir()
        self.path.rename(target)
        self.path.symlink_to(target)
        self.assertEqual(usage.claude_access_token(), "new")
        self.assertTrue(self.path.is_symlink())
        self.assertEqual(json.loads(target.read_text())["claudeAiOauth"]["refreshToken"], "r2")
        self.assertEqual(sorted(os.listdir(self.folder)), [".credentials.json", "dotfiles"])
        self.assertEqual(os.listdir(target.parent), [".credentials.json"])


def http_error(code, retry_after=None):
    headers = email.message.Message()
    if retry_after is not None:
        headers["Retry-After"] = retry_after
    return urllib.error.HTTPError("https://example.test/x", code, "", headers, io.BytesIO())


class Http(Isolated):
    def test_identifies_itself(self):
        with mock.patch.object(usage.urllib.request, "urlopen") as urlopen:
            urlopen.return_value.__enter__.return_value.read.return_value = b"{}"
            usage.http_json("https://example.test/x", {"X-One": "1"})
        request = urlopen.call_args.args[0]
        self.assertEqual(request.get_header("User-agent"), usage.USER_AGENT)
        self.assertEqual(request.get_header("X-one"), "1")

    def poll_raising(self, error):
        with mock.patch.object(usage.urllib.request, "urlopen", side_effect=error):
            return usage.poll(lambda: usage.http_json("https://example.test/x", {}))

    def test_unreachable_host_is_named_without_errno(self):
        for reason, words in ((socket.gaierror(-2, "Name or service not known"), "Name or service not known"),
                              (ConnectionRefusedError(111, "Connection refused"), "Connection refused"),
                              (TimeoutError("timed out"), "timed out")):
            with self.subTest(words):
                self.assertEqual(self.poll_raising(urllib.error.URLError(reason)),
                                 {"status": "error", "message": f"can't reach example.test: {words}"})

    def test_http_errors_are_not_mistaken_for_unreachable_hosts(self):
        busy, down = http_error(429, "120"), http_error(503)
        self.addCleanup(busy.close)
        self.addCleanup(down.close)
        self.assertEqual(self.poll_raising(busy),
                         {"status": "rate_limited", "retryAfter": 120,
                          "message": "rate limited, retrying in 120 s"})
        self.assertEqual(self.poll_raising(down), {"status": "error", "message": "HTTP 503 from example.test"})

    def test_retry_after_may_be_an_http_date(self):
        busy = http_error(429, email.utils.formatdate(time.time() + 90, usegmt=True))
        self.addCleanup(busy.close)
        self.assertIn(self.poll_raising(busy)["retryAfter"], range(88, 92))

    def test_retry_after_is_seconds_or_a_date_and_never_below_one(self):
        self.assertEqual(usage.retry_seconds("120"), 120)
        self.assertEqual(usage.retry_seconds(" 30 "), 30)
        self.assertEqual(usage.retry_seconds("0"), 1)
        self.assertEqual(usage.retry_seconds("-5"), 1)
        self.assertEqual(usage.retry_seconds(email.utils.formatdate(time.time() - 90, usegmt=True)), 1)
        self.assertIn(usage.retry_seconds(email.utils.formatdate(time.time() + 600)), range(598, 602))

    def test_missing_or_garbled_retry_after_waits_a_minute(self):
        for value in (None, "", "soon", "1.5", "Wed, 99 Foo 2026 25:61:00 GMT"):
            with self.subTest(value):
                self.assertEqual(usage.retry_seconds(value), 60)
        busy = http_error(429)
        self.addCleanup(busy.close)
        self.assertEqual(self.poll_raising(busy)["retryAfter"], 60)

    def test_version_is_the_widgets(self):
        metadata = json.loads((ROOT / "package" / "metadata.json").read_text())
        self.assertEqual(usage.VERSION, metadata["KPlugin"]["Version"])
        self.assertEqual(usage.USER_AGENT, "ringside/" + usage.VERSION)


class ConfigHomes(Isolated):
    def test_follow_the_clis_overrides(self):
        with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": "/cfg/claude", "CODEX_HOME": "/cfg/codex"}):
            helper = load_helper()
        self.assertEqual(helper.CLAUDE_CREDENTIALS, Path("/cfg/claude/.credentials.json"))
        self.assertEqual(helper.CODEX_AUTH, Path("/cfg/codex/auth.json"))

    def test_default_to_home_when_unset_or_empty(self):
        with mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": "", "CODEX_HOME": ""}):
            helper = load_helper()
        self.assertEqual(helper.CLAUDE_CREDENTIALS, Path.home() / ".claude" / ".credentials.json")
        self.assertEqual(helper.CODEX_AUTH, Path.home() / ".codex" / "auth.json")

    def test_cache_follows_xdg_cache_home(self):
        self.assertEqual(usage.CACHE_FILE, self.tmp / "cache" / "ringside" / "usage.json")
        self.assertEqual(usage.HISTORY_FILE, self.tmp / "cache" / "ringside" / "usage-history.json")
        self.assertEqual(usage.LOCK_FILE, self.tmp / "cache" / "ringside" / "usage.lock")
        with mock.patch.dict(os.environ, {"XDG_CACHE_HOME": ""}):
            helper = load_helper()
        self.assertEqual(helper.CACHE_DIR, Path.home() / ".cache" / "ringside")


class CodexAppServer(Isolated):
    def server(self, body):
        path = self.tmp / "fake-codex"
        path.write_text(body)
        path.chmod(0o700)
        return str(path)

    def test_reads_the_answer_to_the_rate_limit_request(self):
        binary = self.server(f"""#!{sys.executable}
import json, sys
for line in sys.stdin:
    message = json.loads(line)
    if message.get("id") == 1:
        version = message["params"]["clientInfo"]["version"]
    elif message.get("id") == 2:
        print(json.dumps({{"id": 2, "result": {{"clientVersion": version}}}}), flush=True)
""")
        self.assertEqual(usage.codex_rate_limits(binary), {"clientVersion": usage.VERSION})

    def test_deadline_ends_what_the_server_started(self):
        # The child keeps stdout open, so the read only ends once it is killed too.
        binary = self.server("#!/bin/sh\nsleep 30 &\nwait\n")
        start = time.monotonic()
        with mock.patch.object(usage, "CODEX_TIMEOUT", 0.5), \
                self.assertRaisesRegex(RuntimeError, r"^no answer from codex app-server in 0\.5 s$"):
            usage.codex_rate_limits(binary)
        self.assertLess(time.monotonic() - start, 10)

    def test_early_close_is_not_a_timeout(self):
        binary = self.server("#!/bin/sh\nexec >&-\nsleep 30\n")
        with self.assertRaisesRegex(RuntimeError, "^app-server closed without answering$"):
            usage.codex_rate_limits(binary)


class Polling(Isolated):
    def test_statuses_come_from_exceptions(self):
        self.assertEqual(usage.poll(lambda: {"weekly": {}}), {"weekly": {}, "status": "ok"})
        self.assertEqual(usage.poll(mock.Mock(side_effect=usage.SignedOut())),
                         {"status": "signed_out"})
        self.assertEqual(usage.poll(mock.Mock(side_effect=usage.RateLimited(90))),
                         {"status": "rate_limited", "retryAfter": 90,
                          "message": "rate limited, retrying in 90 s"})
        self.assertEqual(usage.poll(mock.Mock(side_effect=RuntimeError("boom"))),
                         {"status": "error", "message": "boom"})

    def test_codex_login_errors_read_as_signed_out(self):
        with mock.patch.object(usage, "CODEX_AUTH", Path(__file__)), \
             mock.patch.object(usage, "find_codex", return_value="codex"), \
             mock.patch.object(usage, "codex_rate_limits",
                               side_effect=RuntimeError("Not logged in")):
            self.assertEqual(usage.poll(usage.codex_usage), {"status": "signed_out"})


class ReadingCache(Isolated):
    def setUp(self):
        super().setUp()
        self.good = {"status": "ok", "weekly": window(1, 5), "scoped": [], "fetchedAt": 1000}

    def collect(self, now, **fetchers):
        return usage.collect(fetchers, now)

    def cached(self):
        return json.loads(usage.CACHE_FILE.read_text())

    def test_fresh_reading_is_served_without_polling(self):
        self.write_cache({"codex": self.good})
        fetch = mock.Mock()
        served = self.collect(1000 + 299, codex=fetch)["codex"]
        self.assertEqual(served, dict(self.good, weekly=dict(self.good["weekly"], history=[])))
        fetch.assert_not_called()

    def test_stale_reading_is_polled_again(self):
        self.write_cache({"codex": self.good})
        fetch = mock.Mock(return_value=reading(2, 6))
        result = self.collect(1000 + 300, codex=fetch)["codex"]
        self.assertEqual(result["weekly"]["percent"], 2)
        self.assertEqual(self.cached()["codex"]["fetchedAt"], 1300)

    def test_errors_are_reported_but_not_cached(self):
        fetch = mock.Mock(side_effect=RuntimeError("HTTP 500 from api.anthropic.com"))
        self.assertEqual(self.collect(1000, codex=fetch)["codex"],
                         {"status": "error", "message": "HTTP 500 from api.anthropic.com"})
        self.assertEqual(self.cached(), {})

    # A refusal holds the provider back for every run until Retry-After has
    # passed, and only that provider.
    def test_a_rate_limit_holds_until_retry_after(self):
        refused = mock.Mock(side_effect=usage.RateLimited(600))
        self.assertEqual(self.collect(1000, codex=refused)["codex"],
                         {"status": "rate_limited", "retryAfter": 600, "message": "rate limited, retrying in 600 s"})
        again = mock.Mock(return_value=reading(3, 5))
        self.assertEqual(self.collect(1400, codex=again)["codex"],
                         {"status": "rate_limited", "retryAfter": 200, "message": "rate limited, retrying in 200 s"})
        again.assert_not_called()
        other = mock.Mock(return_value=reading(7, 5))
        self.assertEqual(self.collect(1400, claude=other)["claude"]["status"], "ok")
        self.assertEqual(self.collect(1600, codex=again)["codex"]["status"], "ok")
        again.assert_called_once()

    def test_a_hold_never_lasts_more_than_a_day(self):
        self.collect(1000, codex=mock.Mock(side_effect=usage.RateLimited(10 ** 9)))
        self.assertEqual(self.collect(1000, codex=mock.Mock())["codex"]["retryAfter"], usage.HOLD_MAX)
        self.assertEqual(self.collect(1000 + usage.HOLD_MAX, codex=mock.Mock(return_value=reading(1, 5)))["codex"]["status"],
                         "ok")

    def test_corrupt_cache_is_ignored(self):
        self.write_cache({})
        usage.CACHE_FILE.write_text("{not json")
        fetch = mock.Mock(return_value=reading(1, 5))
        self.assertEqual(self.collect(1000, codex=fetch)["codex"]["status"], "ok")
        self.assertEqual(stat.S_IMODE(usage.CACHE_FILE.stat().st_mode), 0o600)

    def test_providers_are_cached_independently(self):
        self.write_cache({"claude": self.good})
        claude, codex = mock.Mock(), mock.Mock(return_value=reading(1, 5))
        self.collect(1000 + 10, claude=claude, codex=codex)
        claude.assert_not_called()
        codex.assert_called_once()
        self.assertEqual(set(self.cached()), {"claude", "codex"})

    def test_a_run_for_one_provider_leaves_the_others_entry(self):
        stale = dict(self.good, fetchedAt=0)
        self.write_cache({"claude": stale, "codex": stale})
        self.collect(1000, codex=mock.Mock(return_value=reading(7, 5)))
        self.assertEqual(self.cached()["claude"], stale)
        self.assertEqual(self.cached()["codex"]["weekly"]["percent"], 7)
        self.collect(2000, codex=mock.Mock(side_effect=RuntimeError("down")))
        self.assertEqual(self.cached(), {"claude": stale})

    def test_a_cached_entry_keeps_the_time_it_was_polled(self):
        polled_at = int(time.time()) - 100
        self.write_cache({"claude": dict(self.good, fetchedAt=polled_at)})
        with mock.patch.object(usage, "claude_usage") as claude:
            report = self.run_main("--providers", "claude")
        claude.assert_not_called()
        self.assertEqual(report["providers"]["claude"]["fetchedAt"], polled_at)
        self.assertGreaterEqual(report["fetchedAt"], polled_at + 100)

    def test_the_lock_is_held_while_polling(self):
        held = []

        def fetch():
            fd = os.open(usage.LOCK_FILE, os.O_RDWR)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                held.append(False)
            except BlockingIOError:
                held.append(True)
            finally:
                os.close(fd)
            return reading(1, 5)

        self.collect(1000, codex=fetch)
        self.assertEqual(held, [True])

    def test_a_run_that_waits_for_the_lock_reads_the_fresh_cache(self):
        polling = threading.Event()
        calls = []
        results = []

        def fetch():
            calls.append(time.monotonic())
            polling.set()
            time.sleep(0.3)
            return reading(4, 5)

        def run():
            results.append(usage.collect({"codex": fetch}, 1000))

        first = threading.Thread(target=run)
        first.start()
        self.assertTrue(polling.wait(5))
        second = threading.Thread(target=run)
        second.start()
        first.join(10)
        second.join(10)
        self.assertEqual(len(calls), 1)
        self.assertEqual([r["codex"]["fetchedAt"] for r in results], [1000, 1000])

    # A run that started first can get the lock last, after a later run
    # polled: the reading it finds is newer than its start, and still fresh.
    def test_the_time_is_taken_once_the_lock_is_held(self):
        clock = [1000]
        self.write_cache({"codex": dict(reading(4, 5), status="ok", fetchedAt=1010)})
        real_locked = usage.locked

        @contextlib.contextmanager
        def late_lock():
            with real_locked():
                clock[0] = 1020
                yield

        calls = []
        with mock.patch.object(usage.time, "time", lambda: clock[0]), \
                mock.patch.object(usage, "locked", late_lock):
            report = usage.collect({"codex": lambda: calls.append(1) or reading(9, 5)})
        self.assertEqual(calls, [])
        self.assertEqual(report["codex"]["fetchedAt"], 1010)


class ProviderChoice(Isolated):
    def setUp(self):
        super().setUp()
        self.claude = self.enterContext(mock.patch.object(
            usage, "claude_usage", side_effect=lambda: reading(10, 2000000000)))
        self.codex = self.enterContext(mock.patch.object(
            usage, "codex_usage", side_effect=lambda: reading(20, 2000000000)))

    def test_only_the_requested_providers_are_polled_and_reported(self):
        report = self.run_main("--providers", "codex")
        self.assertEqual(list(report["providers"]), ["codex"])
        self.claude.assert_not_called()
        self.assertEqual(set(self.run_main()["providers"]), {"claude", "codex"})
        self.assertEqual(set(self.run_main("--providers", "codex,claude")["providers"]), {"claude", "codex"})
        self.assertEqual(self.claude.call_count, 1)
        self.assertEqual(self.codex.call_count, 1)

    def test_names_are_trimmed_and_deduplicated(self):
        self.assertEqual(usage.provider_list(" codex,claude,codex"), ["codex", "claude"])

    def test_unknown_provider_exits_with_usage_error(self):
        for argv in (["--providers", "gemini"], ["--providers", "claude,"], ["--providers", ""]):
            with self.subTest(argv), mock.patch("sys.stderr", new=io.StringIO()) as err, \
                    self.assertRaises(SystemExit) as exit_:
                usage.main(argv)
            self.assertEqual(exit_.exception.code, 2)
            self.assertIn("unknown provider", err.getvalue())
        self.claude.assert_not_called()
        self.codex.assert_not_called()
        self.assertFalse(usage.CACHE_DIR.exists())

    def test_the_script_itself(self):
        env = dict(os.environ, RINGSIDE_USAGE_FAKE=str(FIXTURES / "fake_report.json"))
        run = subprocess.run([sys.executable, HELPER, "--providers", "claude"], env=env,
                             capture_output=True, text=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(list(json.loads(run.stdout)["providers"]), ["claude"])
        run = subprocess.run([sys.executable, HELPER, "--providers", "nope"], env=env,
                             capture_output=True, text=True, timeout=30)
        self.assertEqual(run.returncode, 2)
        self.assertEqual(run.stdout, "")


class History(Isolated):
    NOW = 1800000000
    RESET = NOW + 2 * 86400
    START = RESET - WEEK

    def collect(self, result, now=NOW, name="claude"):
        return usage.collect({name: lambda: json.loads(json.dumps(result))}, now)[name]

    def seed(self, history):
        usage.CACHE_DIR.mkdir(parents=True, exist_ok=True)
        usage.HISTORY_FILE.write_text(json.dumps(history))

    def stored(self):
        return json.loads(usage.HISTORY_FILE.read_text())

    def test_real_polls_append_and_cache_hits_do_not(self):
        self.collect(reading(10, self.RESET, Opus=5))
        first = {"claude": {"weekly": [[self.NOW, 10]], "scoped": {"Opus": [[self.NOW, 5]]}}}
        self.assertEqual(self.stored(), first)
        hit = self.collect(reading(99, self.RESET), now=self.NOW + 60)
        self.assertEqual(self.stored(), first)
        self.assertEqual(hit["weekly"]["history"], [[self.NOW, 10]])
        self.assertEqual(hit["scoped"][0]["history"], [[self.NOW, 5]])
        self.collect(reading(12, self.RESET, Opus=5), now=self.NOW + 300)
        self.assertEqual(self.stored()["claude"]["weekly"], [[self.NOW, 10], [self.NOW + 300, 12]])

    def test_points_before_the_window_or_over_a_week_old_are_dropped(self):
        self.seed({"claude": {"weekly": [[self.START - 1, 1], [self.START, 2], [self.NOW - 10, 3]],
                              "scoped": {"Opus": [[self.NOW - WEEK - 1, 1], [self.NOW - WEEK, 2]]}}})
        result = reading(4, self.RESET, Opus=3)
        result["scoped"][0]["resetsAt"] = None
        self.collect(result)
        self.assertEqual(self.stored()["claude"], {
            "weekly": [[self.START, 2], [self.NOW - 10, 3], [self.NOW, 4]],
            "scoped": {"Opus": [[self.NOW - WEEK, 2], [self.NOW, 3]]}})

    def test_a_reset_starts_a_new_week(self):
        old_reset = self.NOW - 60
        self.seed({"claude": {"weekly": [[old_reset - 86400, 70], [old_reset - 120, 90]], "scoped": {}}})
        report = self.collect(reading(0, old_reset + WEEK))
        self.assertEqual(self.stored()["claude"]["weekly"], [[self.NOW, 0]])
        self.assertEqual(report["weekly"]["history"], [[self.NOW, 0]])

    def test_a_cleared_window_starts_over(self):
        before = [[self.NOW - 600, 50]]
        self.seed({"claude": {"weekly": before, "scoped": {"Opus": before}}})
        self.collect(reading(30, self.RESET, Opus=31))
        self.assertEqual(self.stored()["claude"], {
            "weekly": [[self.NOW, 30]],
            "scoped": {"Opus": [[self.NOW - 600, 50], [self.NOW, 31]]}})

    def test_a_flat_stretch_keeps_its_first_and_last_sample(self):
        a, b, c = self.NOW - 900, self.NOW - 600, self.NOW - 300
        self.seed({"claude": {"weekly": [[a, 5], [b, 10], [c, 10]], "scoped": {"Opus": [[a, 5], [b, 10]]}}})
        self.collect(reading(10, self.RESET, Opus=10))
        self.assertEqual(self.stored()["claude"], {
            "weekly": [[a, 5], [b, 10], [self.NOW, 10]],
            "scoped": {"Opus": [[a, 5], [b, 10], [self.NOW, 10]]}})

    def test_a_series_is_capped_at_its_newest_points(self):
        seeded = [[self.NOW - (2100 - i) * 60, 1 + i % 2] for i in range(2100)]
        self.seed({"claude": {"weekly": seeded, "scoped": {}}})
        report = self.collect(reading(3, self.RESET))
        weekly = self.stored()["claude"]["weekly"]
        self.assertEqual(len(weekly), usage.HISTORY_POINTS)
        self.assertEqual(weekly, seeded[1:] + [[self.NOW, 3]])
        self.assertEqual(report["weekly"]["history"], weekly)

    def test_signed_out_providers_and_unreported_limits_lose_their_series(self):
        series = [[self.NOW - 60, 1]]
        self.seed({"claude": {"weekly": series, "scoped": {"Opus": series, "Retired": series}},
                   "codex": {"weekly": series, "scoped": {}}})
        usage.collect({"claude": lambda: reading(1, self.RESET, Opus=1),
                       "codex": mock.Mock(side_effect=usage.SignedOut())}, self.NOW)
        self.assertEqual(self.stored(), {"claude": {"weekly": series + [[self.NOW, 1]],
                                                    "scoped": {"Opus": series + [[self.NOW, 1]]}}})

    def test_failed_and_unrequested_providers_keep_their_series(self):
        series = {"weekly": [[self.NOW - 60, 1]], "scoped": {"codex_bengalfox": [[self.NOW - 60, 2]]}}
        self.seed({"codex": series})
        usage.collect({"codex": mock.Mock(side_effect=RuntimeError("down"))}, self.NOW)
        self.assertEqual(self.stored(), {"codex": series})
        self.collect(reading(5, self.RESET))
        self.assertEqual(self.stored()["codex"], series)

    def test_an_unreadable_or_malformed_history_is_treated_as_empty(self):
        for content in (b"{not json", b"\xff\xfe", b"[]", b'{"claude": 5, "codex": []}',
                        b'{"claude": {"weekly": {}, "scoped": []}}'):
            with self.subTest(content):
                usage.CACHE_DIR.mkdir(parents=True, exist_ok=True)
                usage.HISTORY_FILE.write_bytes(content)
                usage.CACHE_FILE.unlink(missing_ok=True)
                report = self.collect(reading(8, self.RESET, Opus=2))
                self.assertEqual(report["status"], "ok")
                self.assertEqual(report["weekly"]["history"], [[self.NOW, 8]])
                self.assertEqual(self.stored()["claude"]["weekly"], [[self.NOW, 8]])

    def test_malformed_points_are_dropped_and_good_ones_kept(self):
        good = [self.NOW - 60, 7]
        self.seed({"claude": {"weekly": [[1, "x"], "y", [2], [self.NOW - 60, 7, 1], [True, 3], [1.5, 2], good],
                              "scoped": {"Opus": None}}})
        self.collect(reading(8, self.RESET, Opus=2))
        self.assertEqual(self.stored()["claude"], {"weekly": [good, [self.NOW, 8]],
                                                   "scoped": {"Opus": [[self.NOW, 2]]}})

    def test_every_window_of_the_report_carries_its_history(self):
        codex = {"status": "ok", "fetchedAt": self.NOW - 60, "weekly": window(40, self.RESET),
                 "scoped": [{"id": "spark", "label": "Spark", **window(3, self.RESET)},
                            {"id": "new", "label": "New", **window(0, self.RESET)}]}
        self.write_cache({"codex": codex})
        self.seed({"codex": {"weekly": [[self.START - 60, 1], [self.NOW - 60, 40]],
                             "scoped": {"spark": [[self.NOW - 60, 3]]}}})
        report = usage.collect({"claude": lambda: reading(10, self.RESET, Opus=5),
                                "codex": mock.Mock()}, self.NOW)
        self.assertEqual(report["claude"]["weekly"]["history"], [[self.NOW, 10]])
        self.assertEqual(report["claude"]["scoped"][0]["history"], [[self.NOW, 5]])
        self.assertEqual(report["codex"]["weekly"]["history"], [[self.NOW - 60, 40]])
        self.assertEqual([s["history"] for s in report["codex"]["scoped"]], [[[self.NOW - 60, 3]], []])
        self.assertNotIn("history", json.loads(usage.CACHE_FILE.read_text())["claude"]["weekly"])

    def test_cache_and_history_are_private(self):
        self.collect(reading(10, self.RESET))
        self.assertEqual(stat.S_IMODE(usage.CACHE_DIR.stat().st_mode), 0o700)
        for path in (usage.CACHE_FILE, usage.HISTORY_FILE, usage.LOCK_FILE):
            with self.subTest(path.name):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(sorted(os.listdir(usage.CACHE_DIR)), ["usage-history.json", "usage.json", "usage.lock"])


class Fake(Isolated):
    def setUp(self):
        super().setUp()
        self.enterContext(mock.patch.dict(os.environ, {"RINGSIDE_USAGE_FAKE": str(FIXTURES / "fake_report.json")}))
        self.claude = self.enterContext(mock.patch.object(usage, "claude_usage"))
        self.codex = self.enterContext(mock.patch.object(usage, "codex_usage"))

    def test_reports_the_requested_providers_without_polling(self):
        self.assertEqual(list(self.run_main("--providers", "codex")["providers"]), ["codex"])
        self.assertEqual(set(self.run_main()["providers"]), {"claude", "codex"})
        self.claude.assert_not_called()
        self.codex.assert_not_called()
        self.assertFalse(usage.CACHE_DIR.exists())

    def test_every_window_carries_a_history(self):
        providers = self.run_main()["providers"]
        self.assertEqual(providers["claude"]["weekly"]["history"],
                         fixture("fake_report.json")["providers"]["claude"]["weekly"]["history"])
        self.assertEqual(providers["claude"]["scoped"][0]["history"], [])
        self.assertEqual(providers["codex"]["weekly"]["history"], [])
        self.assertEqual(providers["codex"]["scoped"][0]["history"], [])


class ClockZone(Isolated):
    # The tray's weather applet reuses the clock's id one level down.
    APPLETSRC = """[Containments][23][Applets][28][Applets][38]
plugin=org.kde.plasma.weather

[Containments][23][Applets][38]
immutability=1
plugin=org.kde.plasma.digitalclock

[Containments][23][Applets][38][Configuration][Appearance]
lastSelectedTimezone=America/New_York
selectedTimeZones=Local,America/New_York
"""
    SEP_4_NOON_EDT = 1788537600
    NOV_2_NOON_EST = 1793638800

    def setUp(self):
        super().setUp()
        self.config = usage.APPLETSRC
        self.config.parent.mkdir(parents=True)
        self.config.write_text(self.APPLETSRC)

    def zone_after(self, old, new):
        self.config.write_text(self.APPLETSRC.replace(old, new))
        return usage.clock_zone()

    def test_follows_the_zone_the_clock_shows(self):
        self.assertEqual(usage.clock_zone().key, "America/New_York")

    def test_system_time_when_the_clock_shows_it(self):
        self.assertIsNone(self.zone_after("=America/New_York\n", "=Local\n"))
        self.assertIsNone(self.zone_after("lastSelectedTimezone=America/New_York\n", ""))

    def test_system_time_when_clocks_disagree(self):
        second_clock = "plugin=org.kde.plasma.digitalclock"
        self.assertIsNone(self.zone_after("plugin=org.kde.plasma.weather", second_clock))
        self.assertIsNone(self.zone_after("plugin=org.kde.plasma.weather", second_clock + (
            "\n\n[Containments][23][Applets][28][Applets][38][Configuration][Appearance]"
            "\nlastSelectedTimezone=Europe/Berlin")))

    def test_system_time_when_unreadable_or_unknown(self):
        self.assertIsNone(self.zone_after("America/New_York\n", "Mars/Base\n"))
        self.assertIsNone(self.zone_after("America/New_York\n", "UTC+24:00\n"))
        self.config.unlink()
        self.assertIsNone(usage.clock_zone())

    def test_reads_qt_fixed_offset_zones(self):
        zone = self.zone_after("America/New_York\n", "UTC+05:30\n")
        self.assertEqual(zone.utcoffset(None).total_seconds(), 19800)
        self.assertEqual(usage.zone_named("UTC-08:00").utcoffset(None).total_seconds(), -28800)

    def test_every_reset_gets_the_zone_at_that_moment(self):
        providers = {"claude": {"weekly": {"resetsAt": self.SEP_4_NOON_EDT},
                                "scoped": [{"id": "Fable", "resetsAt": self.NOV_2_NOON_EST},
                                           {"id": "Opus", "resetsAt": None}]},
                     "codex": {"weekly": {"resetsAt": self.NOV_2_NOON_EST}},
                     "other": {"weekly": {"resetsAt": None}},
                     "signed_out": {"status": "signed_out"}}
        usage.show_in_zone(providers, usage.clock_zone())
        self.assertEqual(providers["claude"]["weekly"]["clockZone"], {"offset": -14400, "abbreviation": "EDT"})
        self.assertEqual(providers["claude"]["scoped"][0]["clockZone"], {"offset": -18000, "abbreviation": "EST"})
        self.assertNotIn("clockZone", providers["claude"]["scoped"][1])
        self.assertEqual(providers["codex"]["weekly"]["clockZone"], {"offset": -18000, "abbreviation": "EST"})
        self.assertNotIn("clockZone", providers["other"]["weekly"])

    def test_reset_the_zone_cannot_place_keeps_system_time(self):
        providers = {"claude": {"weekly": {"resetsAt": self.SEP_4_NOON_EDT * 1000}},
                     "codex": {"weekly": {"resetsAt": self.SEP_4_NOON_EDT}}}
        usage.show_in_zone(providers, usage.zone_named("Asia/Tokyo"))
        self.assertNotIn("clockZone", providers["claude"]["weekly"])
        self.assertEqual(providers["codex"]["weekly"]["clockZone"]["abbreviation"], "JST")

    def test_report_carries_the_zone_but_the_cache_does_not(self):
        with mock.patch.object(usage, "claude_usage", return_value=reading(1, self.SEP_4_NOON_EDT, Opus=2)), \
                mock.patch.object(usage, "codex_usage", side_effect=usage.SignedOut()):
            report = self.run_main()
        claude = report["providers"]["claude"]
        self.assertEqual(claude["weekly"]["clockZone"]["abbreviation"], "EDT")
        self.assertEqual(claude["scoped"][0]["clockZone"]["abbreviation"], "EDT")
        cached = json.loads(usage.CACHE_FILE.read_text())["claude"]
        self.assertNotIn("clockZone", cached["weekly"])
        self.assertNotIn("clockZone", cached["scoped"][0])

    def test_fake_reports_carry_the_zone(self):
        with mock.patch.dict(os.environ, {"RINGSIDE_USAGE_FAKE": str(FIXTURES / "fake_report.json")}):
            report = self.run_main()
        self.assertEqual(report["providers"]["codex"]["weekly"]["clockZone"]["abbreviation"], "EDT")
        self.assertEqual(report["providers"]["codex"]["scoped"][0]["clockZone"]["abbreviation"], "EDT")


if __name__ == "__main__":
    unittest.main()
