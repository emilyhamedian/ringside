# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import contextlib
import errno
import fcntl
import io
import json
import socket
import threading
import unittest
import urllib.error
from unittest import mock

from test_usage import Isolated, fixture, http_error, reading, usage


class Clock:
    def __init__(self):
        self.elapsed = 0
        self.sleeps = []

    def advance(self, seconds):
        self.elapsed += seconds

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.advance(seconds)


class InitialUsage(Isolated):
    def setUp(self):
        super().setUp()
        self.clock = Clock()
        self.enterContext(mock.patch.object(usage.time, "monotonic", lambda: self.clock.elapsed))
        self.enterContext(mock.patch.object(usage.time, "time", lambda: 1000 + self.clock.elapsed))
        self.enterContext(mock.patch.object(usage.time, "sleep", self.clock.sleep))

    def transient(self):
        return usage.CheckFailed("connection unavailable", "offline", retryable=True)

    def test_both_providers_recover_on_different_rounds_without_repolling_success(self):
        calls = []

        def fetch(name, failures):
            calls.append((name, self.clock.elapsed))
            if sum(provider == name for provider, _ in calls) <= failures:
                raise self.transient()
            return reading(12, 2000000)

        result = usage.collect({"claude": lambda: fetch("claude", 2),
                                "codex": lambda: fetch("codex", 1)}, initial=usage.PROVIDERS)
        self.assertEqual(calls, [("claude", 0), ("codex", 0), ("claude", 5), ("codex", 5), ("claude", 10)])
        self.assertEqual({name: entry["fetchedAt"] for name, entry in result.items()}, {"claude": 1010, "codex": 1005})
        history = json.loads(usage.HISTORY_FILE.read_text())
        self.assertEqual(history["claude"]["weekly"], [[1010, 12]])
        self.assertEqual(history["codex"]["weekly"], [[1005, 12]])

    def test_deadline_is_shared_and_a_retry_does_not_start_at_its_end(self):
        calls = []

        def claude():
            calls.append(("claude", self.clock.elapsed))
            if len(calls) == 1:
                self.clock.advance(20)
            raise self.transient()

        def codex():
            calls.append(("codex", self.clock.elapsed))
            raise self.transient()

        result = usage.collect({"claude": claude, "codex": codex}, initial=usage.PROVIDERS)
        self.assertEqual(calls, [("claude", 0), ("codex", 20), ("claude", 25), ("codex", 25)])
        self.assertEqual(self.clock.elapsed, 30)
        self.assertEqual([entry["retryAt"] for entry in result.values()], [1330, 1330])

    def test_every_provider_gets_its_first_attempt_even_after_the_deadline(self):
        def slow():
            self.clock.advance(35)
            raise self.transient()

        peer = mock.Mock(return_value=reading(8, 2000000))
        result = usage.collect({"claude": slow, "codex": peer}, initial=usage.PROVIDERS)
        peer.assert_called_once()
        self.assertEqual(result["codex"]["fetchedAt"], 1035)
        self.assertEqual(result["claude"]["retryAt"], 1335)
        self.assertEqual(self.clock.sleeps, [])

    def test_a_retry_started_before_the_deadline_can_complete_after_it(self):
        starts = []

        def fetch():
            starts.append(self.clock.elapsed)
            self.clock.advance(20)
            if len(starts) == 1:
                raise self.transient()
            return reading(8, 2000000)

        result = usage.collect({"claude": fetch}, initial=["claude"])
        self.assertEqual(starts, [0, 25])
        self.assertEqual((result["claude"]["status"], result["claude"]["fetchedAt"]), ("ok", 1045))

    def test_exhaustion_holds_for_five_minutes_from_finalization_and_reload_reuses_it(self):
        starts = []

        def fetch():
            starts.append(self.clock.elapsed)
            raise self.transient()

        first = usage.collect({"claude": fetch}, initial=["claude"])
        self.assertEqual(starts, [0, 5, 10, 15, 20, 25])
        self.assertEqual(first["claude"]["retryAt"], 1330)
        again = mock.Mock(return_value=reading(3, 2000000))
        self.clock.advance(299)
        self.assertEqual(usage.collect({"claude": again}, initial=["claude"])["claude"], first["claude"])
        again.assert_not_called()
        self.clock.advance(1)
        self.assertEqual(usage.collect({"claude": again}, initial=["claude"])["claude"]["status"], "ok")
        again.assert_called_once()
        for data in (first, json.loads(usage.CACHE_FILE.read_text())):
            self.assertNotIn("_retryable", json.dumps(data))

    def test_terminal_peer_hold_begins_when_all_startup_attempts_finish(self):
        result = usage.collect({"claude": mock.Mock(side_effect=RuntimeError("unreadable reply")),
                                "codex": mock.Mock(side_effect=self.transient())}, initial=usage.PROVIDERS)
        self.assertEqual(result["claude"]["retryAt"], 1330)
        self.assertEqual(json.loads(usage.CACHE_FILE.read_text())["claude"]["heldUntil"], 1330)

    def test_ordinary_and_unmarked_provider_checks_do_not_retry(self):
        for initial in ([], ["codex"]):
            with self.subTest(initial=initial):
                usage.CACHE_FILE.unlink(missing_ok=True)
                fetch = mock.Mock(side_effect=self.transient())
                report = usage.collect({"claude": fetch}, initial=initial)
                fetch.assert_called_once()
                self.assertEqual(report["claude"]["retryAt"], 1300)
        self.assertEqual(self.clock.sleeps, [])

    def test_initial_marker_preserves_fresh_readings_and_existing_holds(self):
        fresh = dict(reading(4, 2000000), status="ok", fetchedAt=990)
        held = {"status": "error", "reason": "offline", "host": "", "message": "down",
                "heldUntil": 1200, "holdSeconds": 300}
        self.write_cache({"claude": fresh, "codex": held})
        fetch = mock.Mock(side_effect=AssertionError("cached provider was polled"))
        result = usage.collect({"claude": fetch, "codex": fetch}, initial=usage.PROVIDERS)
        self.assertEqual(result["claude"]["fetchedAt"], 990)
        self.assertEqual(result["codex"]["retryAt"], 1200)
        self.assertEqual(self.clock.sleeps, [])
        fetch.assert_not_called()

    def test_terminal_failures_never_enter_the_retry_loop(self):
        for failure in (usage.RateLimited(600), usage.SignedOut(),
                        usage.CheckFailed("HTTP 503", "server"),
                        usage.CheckFailed("missing program", "program"),
                        usage.CheckFailed("not installed", "not-installed"),
                        RuntimeError("helper failure"), ValueError("bad reply")):
            with self.subTest(failure=type(failure).__name__, message=str(failure)):
                usage.CACHE_FILE.unlink(missing_ok=True)
                fetch = mock.Mock(side_effect=failure)
                usage.collect({"claude": fetch}, initial=["claude"])
                fetch.assert_called_once()
        self.assertEqual(self.clock.sleeps, [])

    def test_the_grace_window_starts_after_the_lock_is_acquired(self):
        real_locked = usage.locked

        @contextlib.contextmanager
        def delayed_lock():
            with real_locked():
                self.clock.advance(80)
                yield

        fetch = mock.Mock(side_effect=[self.transient(), reading(3, 2000000)])
        with mock.patch.object(usage, "locked", delayed_lock):
            result = usage.collect({"claude": fetch}, initial=["claude"])
        self.assertEqual(fetch.call_count, 2)
        self.assertEqual(result["claude"]["fetchedAt"], 1085)

    def test_main_retries_only_the_requested_initial_provider_and_reloads_cache(self):
        claude = mock.Mock(side_effect=[self.transient(), reading(3, 2000000)])
        codex = mock.Mock(side_effect=self.transient())
        with mock.patch.object(usage, "claude_usage", claude), mock.patch.object(usage, "codex_usage", codex):
            first = self.run_main("--initial-providers", "claude")
            second = self.run_main("--initial-providers", "claude,codex")
        self.assertEqual((claude.call_count, codex.call_count), (2, 1))
        self.assertEqual(first["providers"], second["providers"])
        self.assertEqual(first["providers"]["claude"]["status"], "ok")
        self.assertEqual(first["providers"]["codex"]["status"], "error")
        self.assertNotIn("_retryable", json.dumps(first))
        self.assertNotIn("_retryable", usage.CACHE_FILE.read_text())

    def test_successful_refresh_is_not_repeated_after_a_failed_usage_get(self):
        usage.CLAUDE_CREDENTIALS.parent.mkdir()
        usage.CLAUDE_CREDENTIALS.write_text(json.dumps({"claudeAiOauth": {
            "accessToken": "old", "refreshToken": "r1", "expiresAt": 1}}))
        requests = []

        def open_url(request, **kwargs):
            requests.append(request)
            if request.method == "GET" and sum(r.method == "GET" for r in requests) == 1:
                raise urllib.error.URLError(socket.gaierror(-2, "unavailable"))
            body = ({"access_token": "new", "refresh_token": "r2", "expires_in": 3600}
                    if request.method == "POST" else fixture("claude_usage.json"))
            response = mock.MagicMock()
            response.__enter__.return_value = io.BytesIO(json.dumps(body).encode())
            return response

        with mock.patch.object(usage.urllib.request, "urlopen", open_url):
            result = self.run_main("--providers", "claude", "--initial-providers", "claude")
        self.assertEqual(result["providers"]["claude"]["status"], "ok")
        self.assertEqual([request.method for request in requests], ["POST", "GET", "GET"])
        self.assertEqual([request.get_header("Authorization") for request in requests[1:]],
                         ["Bearer new", "Bearer new"])
        self.assertEqual(json.loads(usage.CLAUDE_CREDENTIALS.read_text())["claudeAiOauth"]["refreshToken"], "r2")


class InitialTransport(Isolated):
    def test_get_transport_failures_are_retryable(self):
        for failure in (urllib.error.URLError(socket.gaierror(-2, "unavailable")),
                        urllib.error.URLError(TimeoutError()),
                        urllib.error.URLError(ConnectionResetError(errno.ECONNRESET, "reset")),
                        TimeoutError(), ConnectionResetError(errno.ECONNRESET, "reset")):
            with self.subTest(failure=repr(failure)), \
                    mock.patch.object(usage.urllib.request, "urlopen", side_effect=failure), \
                    self.assertRaises(usage.CheckFailed) as caught:
                usage.http_json("https://example.test/usage", {})
            self.assertTrue(caught.exception.retryable)

    def test_post_retries_only_when_a_wrapped_transport_error_proves_it_never_left(self):
        safe = [socket.gaierror(-2, "unavailable"), ConnectionRefusedError(errno.ECONNREFUSED, "refused"),
                OSError(errno.ENETUNREACH, "no network"), OSError(errno.EHOSTUNREACH, "no host")]
        uncertain = [TimeoutError(), ConnectionResetError(errno.ECONNRESET, "reset"),
                     OSError(errno.EIO, "read failed"), "connection unavailable"]
        for reason in safe + uncertain:
            with self.subTest(reason=repr(reason)), \
                    mock.patch.object(usage.urllib.request, "urlopen", side_effect=urllib.error.URLError(reason)), \
                    self.assertRaises(usage.CheckFailed) as caught:
                usage.http_json("https://example.test/token", {}, {"refresh_token": "one-use"})
            self.assertEqual(caught.exception.retryable, reason in safe)
        for failure in safe + uncertain[:-1]:
            with self.subTest(unwrapped=repr(failure)), \
                    mock.patch.object(usage.urllib.request, "urlopen", side_effect=failure), \
                    self.assertRaises(usage.CheckFailed) as caught:
                usage.http_json("https://example.test/token", {}, {"refresh_token": "one-use"})
            self.assertFalse(caught.exception.retryable)

    def test_response_read_failures_are_safe_to_repeat_only_for_get(self):
        for body in (None, {"refresh_token": "one-use"}):
            for failure in (TimeoutError(), ConnectionResetError(errno.ECONNRESET, "reset"),
                            OSError(errno.EIO, "read failed")):
                with self.subTest(post=body is not None, failure=repr(failure)), \
                        mock.patch.object(usage.urllib.request, "urlopen") as urlopen, \
                        self.assertRaises(usage.CheckFailed) as caught:
                    urlopen.return_value.__enter__.return_value.read.side_effect = failure
                    usage.http_json("https://example.test/x", {}, body)
                self.assertEqual(caught.exception.retryable, body is None)

    def test_http_refusals_and_unreadable_replies_are_terminal(self):
        for code in (401, 403, 429, 500, 503):
            failure = http_error(code)
            self.addCleanup(failure.close)
            with self.subTest(code=code), mock.patch.object(usage.urllib.request, "urlopen", side_effect=failure):
                report = usage.poll(lambda: usage.http_json("https://example.test/x", {}), initial=True)
            self.assertNotIn("_retryable", report)
        with mock.patch.object(usage.urllib.request, "urlopen") as urlopen:
            urlopen.return_value.__enter__.return_value.read.return_value = b"<html>"
            self.assertNotIn("_retryable", usage.poll(lambda: usage.http_json("https://example.test/x", {}), initial=True))

    def test_codex_retries_only_allowlisted_transport_wrappers(self):
        usage.CODEX_AUTH.parent.mkdir()
        usage.CODEX_AUTH.write_text("{}")
        allowed = ["failed to fetch codex rate limits: error sending request",
                   "failed to fetch codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)",
                   "failed to fetch codex rate limits: route-aware request timed out"]
        refused = ["failed to fetch codex rate limits: HTTP 429 Too Many Requests",
                   "failed to fetch codex rate limits: HTTP 503 Service Unavailable",
                   "failed to fetch codex rate limits: error decoding response body",
                   "failed to fetch codex rate limits: connection refused",
                   "error sending request", "route-aware request timed out",
                   allowed[0] + ": HTTP 429", "not logged in", "unknown app-server failure"]
        with mock.patch.object(usage, "find_cli", return_value=("codex", "")):
            for message in allowed + refused:
                with self.subTest(message=message), \
                        mock.patch.object(usage, "codex_rate_limits", side_effect=usage.AppServerError(message)):
                    result = usage.poll(usage.codex_usage, initial=True)
                self.assertEqual(result.get("_retryable", False), message in allowed)

    def test_initial_argument_validation_precedes_any_work(self):
        invalid = [("--initial-providers", "unknown"), ("--initial-providers", ""),
                   ("--providers", "claude", "--initial-providers", "codex"),
                   ("--initial-providers", "claude", "--start"),
                   ("--initial-providers", "claude", "--starter-set", "codex=on")]
        for argv in invalid:
            with self.subTest(argv=argv), mock.patch("sys.stderr", new=io.StringIO()), \
                    self.assertRaises(SystemExit) as caught:
                usage.main(list(argv))
            self.assertEqual(caught.exception.code, 2)
        self.assertFalse(usage.CACHE_DIR.exists())
        self.assertFalse(usage.STATE_DIR.exists())
        args = usage.arguments(["--providers", "claude,codex", "--initial-providers", " codex,codex "])
        self.assertEqual(args.initial_providers, ["codex"])


class InitialLock(Isolated):
    def test_waiter_reuses_the_completed_startup_retry_result(self):
        polling, release, refused = threading.Event(), threading.Event(), threading.Event()
        calls, results, errors = [], [], []
        real_flock = fcntl.flock

        def fetch():
            calls.append(1)
            if len(calls) == 1:
                polling.set()
                if not release.wait(10):
                    raise AssertionError("the first run was never released")
                raise usage.CheckFailed("offline", "offline", retryable=True)
            return reading(4, 2000000)

        def run():
            try:
                results.append(usage.collect({"codex": fetch}, initial=["codex"]))
            except Exception as err:
                errors.append(err)

        first, second = threading.Thread(target=run), threading.Thread(target=run)

        def flock(fd, flags):
            try:
                real_flock(fd, flags)
            except BlockingIOError:
                if threading.current_thread() is second:
                    refused.set()
                raise

        self.addCleanup(first.join, 10)
        self.addCleanup(second.join, 10)
        self.addCleanup(release.set)
        with mock.patch.object(usage.fcntl, "flock", flock), mock.patch.object(usage, "INITIAL_RETRY_DELAY", 0.01):
            first.start()
            self.assertTrue(polling.wait(10))
            second.start()
            self.assertTrue(refused.wait(5), "the waiter never tried the held lock")
            release.set()
            first.join(10)
            second.join(10)
        self.assertFalse(first.is_alive() or second.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual(len(calls), 2)
        self.assertEqual(results[0], results[1])
        self.assertEqual(results[0]["codex"]["status"], "ok")
