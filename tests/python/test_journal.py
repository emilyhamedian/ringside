# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

"""The lines the helper hands the widget for Plasma's journal: one per
check at the level it calls for, the starter's steps, and nothing that
could name a token, an address or an account."""

import contextlib
import email.message
import io
import json
import time
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

from test_starter import AUTH, NOW, SESSION, Harness, claude, week
from test_usage import NOT_FOUND, OFF, REAL_FIND_CLI, Isolated, reading, usage


def lines(*fields):
    """The events, each cut down to the given fields."""
    return [{key: e.get(key) for key in fields} for e in usage.EVENTS]


class Checks(Isolated):
    def setUp(self):
        super().setUp()
        usage.EVENTS.clear()

    def collect(self, now, **fetchers):
        usage.EVENTS.clear()
        return usage.collect(fetchers, now)

    def failing(self, error):
        return mock.Mock(side_effect=error)

    def test_each_failure_says_why_with_its_duration(self):
        cases = (
            ("claude", usage.CheckFailed("x", "offline", "api.anthropic.com"),
             "warning", "Claude: check failed after {} ms: can't reach api.anthropic.com"),
            ("claude", usage.CheckFailed("x", "timeout", "platform.claude.com"),
             "warning", "Claude: check failed after {} ms: platform.claude.com didn't answer in time"),
            ("codex", usage.CheckFailed("x", "timeout"),
             "warning", "Codex: check failed after {} ms: the Codex CLI didn't answer in 20 s"),
            ("claude", usage.RateLimited(600, "api.anthropic.com"),
             "warning", "Claude: check failed after {} ms: api.anthropic.com asked Ringside to wait 600 s; "
                        "next check in 600 s"),
            ("codex", usage.RateLimited(30),
             "warning", "Codex: check failed after {} ms: OpenAI asked Ringside to wait 30 s; next check in 300 s"),
            ("claude", usage.CheckFailed("x", "server", "api.anthropic.com", 503),
             "warning", "Claude: check failed after {} ms: api.anthropic.com answered with HTTP 503"),
            ("claude", usage.CheckFailed("x", "server", "api.anthropic.com"),
             "warning", "Claude: check failed after {} ms: api.anthropic.com answered with an error"),
            ("claude", usage.SignedOut(), "info", "Claude: check failed after {} ms: Claude Code is signed out"),
            ("codex", usage.SignedOut(), "info", "Codex: check failed after {} ms: the Codex CLI is signed out"),
            ("codex", usage.CheckFailed("codex CLI not found", "not-installed"),
             "warning", "Codex: check failed after {} ms: the codex CLI isn't installed"),
            ("codex", RuntimeError("no rate limits in app-server reply"),
             "warning", "Codex: check failed after {} ms: an unexpected error, which the popup shows"),
        )
        for name, error, level, words in cases:
            with self.subTest(words=words):
                usage.CACHE_FILE.unlink(missing_ok=True)
                self.collect(1000, **{name: self.failing(error)})
                [e] = usage.EVENTS
                self.assertIsInstance(e["ms"], int)
                self.assertGreaterEqual(e["ms"], 0)
                self.assertEqual(e, {"level": level, "provider": name, "kind": "failed",
                                     "message": words.format(e["ms"]), "ms": e["ms"]})

    def test_a_success_is_debug_with_its_duration(self):
        self.collect(1000, claude=lambda: reading(5, 9))
        [e] = usage.EVENTS
        self.assertEqual(e, {"level": "debug", "provider": "claude", "kind": "check",
                             "message": f"Claude: checked in {e['ms']} ms", "ms": e["ms"]})

    def test_recovery_is_logged_once(self):
        self.collect(1000, claude=self.failing(usage.CheckFailed("x", "offline", "api.anthropic.com")))
        self.collect(1300, claude=lambda: reading(5, 9))
        self.assertEqual(lines("level", "kind"), [{"level": "info", "kind": "recovered"}])
        self.assertTrue(usage.EVENTS[0]["message"].endswith("working again after: can't reach api.anthropic.com"))
        self.collect(1600, claude=lambda: reading(5, 9))
        self.assertEqual(lines("level", "kind"), [{"level": "debug", "kind": "check"}])

    def test_a_repeated_failure_is_debug_until_its_reason_changes(self):
        offline = self.failing(usage.CheckFailed("x", "offline", "api.anthropic.com"))
        self.collect(1000, claude=offline)
        self.assertEqual(lines("level", "kind"), [{"level": "warning", "kind": "failed"}])
        self.collect(1300, claude=offline)
        self.assertEqual(lines("level", "kind"), [{"level": "debug", "kind": "failed-again"}])
        self.collect(1600, claude=self.failing(usage.CheckFailed("x", "offline", "platform.claude.com")))
        self.assertEqual(lines("level", "kind"), [{"level": "warning", "kind": "failed"}])
        self.collect(1900, claude=self.failing(usage.SignedOut()))
        self.collect(2200, claude=self.failing(usage.SignedOut()))
        self.assertEqual(lines("level", "kind"), [{"level": "debug", "kind": "failed-again"}])

    def test_a_wait_lifting_is_logged(self):
        self.collect(1000, claude=self.failing(usage.RateLimited(600, "api.anthropic.com")))
        self.collect(1600, claude=lambda: reading(5, 9))
        self.assertEqual(lines("level", "kind", "message")[0],
                         {"level": "info", "kind": "wait-over",
                          "message": "Claude: the wait api.anthropic.com asked for is over"})
        self.assertEqual(lines("kind")[1:], [{"kind": "recovered"}])
        # A refusal that follows the wait is the same failure going on.
        self.collect(2000, codex=self.failing(usage.RateLimited(600)))
        self.collect(2600, codex=self.failing(usage.RateLimited(600)))
        self.assertEqual(lines("level", "kind"), [{"level": "debug", "kind": "failed-again"}])

    def test_cached_readings_and_held_failures_are_debug(self):
        self.collect(1000, claude=lambda: reading(5, 9),
                     codex=self.failing(usage.CheckFailed("x", "timeout")))
        self.collect(1100, claude=mock.Mock(), codex=mock.Mock())
        self.assertEqual(lines("level", "kind", "message"), [
            {"level": "debug", "kind": "cached", "message": "Claude: the reading taken 100 s ago still stands"},
            {"level": "debug", "kind": "held",
             "message": "Codex: next check in 200 s, after the Codex CLI didn't answer in 20 s"}])

    def test_a_run_that_cant_get_the_lock_says_so(self):
        usage.EVENTS.clear()
        usage.waiting(["claude"], "another usage check is still running")
        self.assertEqual(lines("level", "kind", "message"), [
            {"level": "warning", "kind": "busy",
             "message": "Claude: no check: another usage check held the lock for over 150 s"}])

    def test_codex_names_the_cli_it_asked_from_the_home_folder(self):
        usage.CODEX_AUTH.parent.mkdir()
        usage.CODEX_AUTH.write_text("{}")
        cli = str(Path.home() / ".local" / "bin" / "codex")
        with mock.patch.object(usage, "find_cli", return_value=(cli, "")), \
             mock.patch.object(usage, "codex_rate_limits", side_effect=RuntimeError("app-server closed")):
            self.collect(1000, codex=usage.codex_usage)
        self.assertEqual(usage.EVENTS[0]["message"], "Codex: asking ~/.local/bin/codex app-server")
        self.assertEqual(usage.EVENTS[0]["level"], "debug")

    # A chosen codex that can't run is named as the settings show it, with
    # what is wrong with it; the recovery names the one that failed.
    def test_a_chosen_program_that_cant_run_says_which_and_why(self):
        self.enterContext(mock.patch.object(usage, "find_cli", REAL_FIND_CLI))
        usage.CODEX_AUTH.parent.mkdir()
        usage.CODEX_AUTH.write_text("{}")
        folder = Path.home() / "bin" / "codex"
        folder.mkdir(parents=True)
        for chosen, words in ((str(folder), "~/bin/codex, can't be run: it is a folder"),
                              ("~/none/codex", "~/none/codex, can't be run: there is no file there"),
                              ("/opt/none/codex", "/opt/none/codex, can't be run: there is no file there")):
            with self.subTest(chosen=chosen):
                usage.CACHE_FILE.unlink(missing_ok=True)
                usage.PROGRAMS["codex"] = chosen
                self.collect(1000, codex=usage.codex_usage)
                [e] = usage.EVENTS
                self.assertEqual((e["level"], e["kind"]), ("warning", "failed"))
                self.assertEqual(e["message"], f"Codex: check failed after {e['ms']} ms: the codex program set in "
                                               f"Settings, {words}")
        usage.PROGRAMS["codex"] = "~/elsewhere/codex"
        self.collect(1060, codex=lambda: reading(1, 5000))
        recovered = [e for e in usage.EVENTS if e["kind"] == "recovered"]
        self.assertEqual(len(recovered), 1)
        self.assertIn("/opt/none/codex", recovered[0]["message"])

    def test_a_renewed_claude_login_is_debug(self):
        usage.CLAUDE_CREDENTIALS.parent.mkdir()
        usage.CLAUDE_CREDENTIALS.write_text(json.dumps({"claudeAiOauth": {
            "accessToken": "old", "refreshToken": "r1", "expiresAt": 1}}))
        with mock.patch.object(usage, "http_json", side_effect=[
                {"access_token": "new", "refresh_token": "r2", "expires_in": 3600},
                {"seven_day": {"utilization": 5, "resets_at": 9}, "five_hour": None}]):
            self.collect(1000, claude=usage.claude_usage)
        self.assertEqual(lines("level", "kind"), [{"level": "debug", "kind": "renewed"},
                                                  {"level": "debug", "kind": "check"}])

    # The widget of before reads "fetchedAt" and "providers", and the cache
    # takes neither the events nor the HTTP status kept for them.
    def test_the_report_keeps_its_shape_and_the_cache_takes_no_events(self):
        with mock.patch.object(usage, "claude_usage",
                               side_effect=usage.CheckFailed("HTTP 502 from api.anthropic.com", "server",
                                                             "api.anthropic.com", 502)):
            report = self.run_main("--providers", "claude")
        self.assertEqual(set(report), {"fetchedAt", "providers", "events"})
        claude_entry = report["providers"]["claude"]
        self.assertEqual(claude_entry, {"status": "error", "message": "HTTP 502 from api.anthropic.com",
                                        "reason": "server", "host": "api.anthropic.com",
                                        "retryAt": claude_entry["retryAt"], "starter": OFF,
                                        "program": NOT_FOUND})
        self.assertEqual([e["kind"] for e in report["events"]], ["failed"])
        cached = usage.CACHE_FILE.read_text()
        self.assertNotIn("events", cached)
        self.assertNotIn("httpStatus", cached)
        self.assertNotIn("502", cached.replace("HTTP 502 from", ""))

    def test_each_run_starts_with_no_events(self):
        with mock.patch.object(usage, "claude_usage", return_value=reading(5, 9)):
            self.run_main("--providers", "claude")
            self.assertEqual([e["kind"] for e in self.run_main("--providers", "claude")["events"]], ["cached"])


class Starter(unittest.TestCase):
    def setUp(self):
        usage.EVENTS.clear()

    def kinds(self):
        return [(e["level"], e["kind"]) for e in usage.EVENTS]

    def test_a_send_and_its_confirmation(self):
        h = Harness(NOW, reading=claude(NOW))
        h.step()
        self.assertEqual(self.kinds(), [("info", "starter-sent")])
        self.assertEqual(usage.EVENTS[0]["message"],
                         "Claude session starter sent its message; a reading in 300 s confirms it")
        usage.EVENTS.clear()
        h.reading = claude(NOW + 300, session=NOW + SESSION)
        h.step(NOW + 300)
        self.assertEqual(self.kinds(), [("info", "starter-confirmed")])
        self.assertEqual(usage.EVENTS[0]["message"], "Claude session starter: the new session started")

    def test_unconfirmed_sends_then_the_pause(self):
        h = Harness(NOW, reading=claude(NOW), provider="codex")
        h.reading = {"status": "ok", "fetchedAt": NOW, "scoped": [], "weekly": week(0, NOW + 7 * 86400)}
        h.step()
        usage.EVENTS.clear()
        h.reading = dict(h.reading, fetchedAt=NOW + 300, weekly=week(0, NOW + 300 + 7 * 86400))
        h.step(NOW + 300)
        self.assertEqual(self.kinds(), [("info", "starter-unconfirmed")])
        self.assertEqual(usage.EVENTS[0]["message"],
                         "Codex session starter: no new week after its message; trying once more in 300 s")
        h.reading = dict(h.reading, fetchedAt=NOW + 600, weekly=week(0, NOW + 600 + 7 * 86400))
        h.step(NOW + 600)
        usage.EVENTS.clear()
        h.reading = dict(h.reading, fetchedAt=NOW + 900, weekly=week(0, NOW + 900 + 7 * 86400))
        h.step(NOW + 900)
        self.assertEqual(self.kinds(), [("warning", "starter-paused")])
        self.assertEqual(usage.EVENTS[0]["message"],
                         "Codex session starter paused for 5 h: two messages in a row started no week")

    def test_a_failure_is_logged_once_then_debug(self):
        h = Harness(NOW)
        h.missing = True
        h.step()
        self.assertEqual(self.kinds(), [("warning", "starter-failed")])
        self.assertEqual(usage.EVENTS[0]["message"],
                         "Claude session starter can't send: the CLI isn't installed; trying again in 300 s")
        usage.EVENTS.clear()
        h.step(NOW + 300)
        self.assertEqual(self.kinds(), [("debug", "starter-failed-again")])
        usage.EVENTS.clear()
        h.missing = False
        h.outcome = usage.NotSent("not-responding")
        h.step(NOW + 600)
        self.assertEqual(self.kinds(), [("warning", "starter-failed")])

    def test_a_chosen_program_that_cant_run(self):
        h = Harness(NOW)
        h.starter.check = mock.Mock(side_effect=usage.Failed("program"))
        h.step()
        self.assertEqual(usage.EVENTS[0]["message"], "Claude session starter can't send: the program set in Settings "
                                                     "can't be run; trying again in 300 s")

    def test_switched_off_before_the_send(self):
        Harness(NOW, outcome=usage.SwitchedOff()).step()
        self.assertEqual(self.kinds(), [("info", "starter-switched-off")])


class StarterRuns(Isolated):
    def setUp(self):
        super().setUp()
        self.enterContext(mock.patch.object(usage, "claude_usage", side_effect=lambda: {
            "weekly": week(10, int(time.time()) + 86400), "scoped": [], "session": None}))
        self.enterContext(mock.patch.object(usage, "find_cli", side_effect=lambda name, chosen="": (f"/mock/{name}", "")))
        self.enterContext(mock.patch.object(usage, "claude_access_token", return_value="token"))
        self.enterContext(mock.patch.object(usage, "run_cli", return_value=(0, json.dumps(AUTH))))

    def events(self, *argv):
        return [(e["level"], e["kind"], e["message"]) for e in self.run_main(*argv)["events"]]

    def test_the_switch_turning_is_logged_once(self):
        self.assertEqual(self.events("--providers", "claude", "--starter-set", "claude=on")[0],
                         ("info", "starter-on", "Claude session starter switched on"))
        self.assertNotIn("starter-on", [k for _, k, _ in self.events("--providers", "claude",
                                                                     "--starter-set", "claude=on")])
        self.assertEqual(self.events("--providers", "claude", "--starter-set", "claude=off")[0],
                         ("info", "starter-off", "Claude session starter switched off"))

    def test_a_switch_that_cant_be_saved_says_why(self):
        write = usage.write_private

        def refuse(path, data):
            if path == usage.STARTER_FILE:
                raise PermissionError(13, "Permission denied", "/home/someone/x")
            write(path, data)
        with mock.patch.object(usage, "write_private", side_effect=refuse):
            events = self.events("--providers", "claude", "--starter-set", "claude=on")
        self.assertIn(("warning", "starter-switch-failed",
                       "Claude session starter switch not saved: Permission denied"), events)
        self.assertNotIn("someone", json.dumps(events))

    def test_a_start_says_when_its_next_step_is(self):
        self.run_main("--providers", "claude", "--starter-set", "claude=on")
        events = self.events("--providers", "claude", "--start")
        self.assertEqual([k for _, k, _ in events][:3], ["cached", "starter-sent", "starter-next"])
        self.assertEqual(events[2][0], "debug")
        self.assertRegex(events[2][2], r"^Claude session starter is confirming; next step at \d{4}-\d\d-\d\d \d\d:\d\d:\d\d$")

    def test_a_start_that_cant_run_says_why(self):
        self.run_main("--providers", "claude", "--starter-set", "claude=on")
        with mock.patch.object(usage, "run_starter", side_effect=usage.Busy()):
            self.assertIn(("warning", "starter-stopped",
                           "Claude session starter didn't run: another usage check is still running"),
                          self.events("--providers", "claude", "--start"))


# Stand-ins for everything that must never reach the journal.
SECRETS = ("sk-ant-oat01-ACCESSSECRET", "sk-ant-ort01-REFRESHSECRET", "sk-ant-oat01-NEWACCESS",
           "sk-ant-ort01-NEWREFRESH", "someone@example.com", "Some Person", "203.0.113.7", "2001:db8::7",
           "Berlin", "QUERYSECRET")
LEAKY = (f"for someone@example.com (Some Person) at 203.0.113.7 / 2001:db8::7 in Berlin "
         f"with sk-ant-oat01-ACCESSSECRET ?token=QUERYSECRET")


class Privacy(Isolated):
    """Every failing and renewing path, fed tokens, addresses and an
    account in every input it reads, leaves none of them in an event."""

    def setUp(self):
        super().setUp()
        usage.CLAUDE_CREDENTIALS.parent.mkdir()
        usage.CODEX_AUTH.parent.mkdir()
        usage.CODEX_AUTH.write_text(json.dumps({"tokens": {"access_token": SECRETS[0]}, "email": SECRETS[4]}))
        self.login()

    def login(self):
        usage.CLAUDE_CREDENTIALS.write_text(json.dumps({
            "claudeAiOauth": {"accessToken": SECRETS[0], "refreshToken": SECRETS[1], "expiresAt": 1,
                              "account": {"email": SECRETS[4], "name": SECRETS[5]}},
            "oauthAccount": {"emailAddress": SECRETS[4], "displayName": SECRETS[5]}}))

    def answer(self, failure):
        """urlopen that renews the login with an account in the reply, then
        fails the usage request with `failure`."""
        def urlopen(request, timeout):
            if request.full_url == usage.CLAUDE_TOKEN_URL:
                return contextlib.nullcontext(io.BytesIO(json.dumps({
                    "access_token": SECRETS[2], "refresh_token": SECRETS[3], "expires_in": 3600,
                    "account": {"email_address": SECRETS[4]}}).encode()))
            raise failure
        return urlopen

    def http_error(self, code, retry_after=None):
        headers = email.message.Message()
        headers["X-Forwarded-For"] = SECRETS[6]
        if retry_after:
            headers["Retry-After"] = retry_after
        error = urllib.error.HTTPError(f"{usage.CLAUDE_USAGE_URL}?token=QUERYSECRET", code, LEAKY, headers,
                                       io.BytesIO(LEAKY.encode()))
        self.addCleanup(error.close)
        return error

    def assert_clean(self, events):
        self.assertTrue(events)
        text = json.dumps(events)
        for secret in SECRETS:
            self.assertNotIn(secret, text)

    def test_claude_failures_after_a_renewal(self):
        failures = (self.http_error(500), self.http_error(429, "120"), self.http_error(401),
                    urllib.error.URLError(OSError(111, LEAKY)), urllib.error.URLError(TimeoutError(LEAKY)),
                    ConnectionResetError(104, LEAKY), ValueError(LEAKY))
        for failure in failures:
            with self.subTest(failure=type(failure).__name__):
                self.login()
                usage.CACHE_FILE.unlink(missing_ok=True)
                with mock.patch.object(usage.urllib.request, "urlopen", side_effect=self.answer(failure)):
                    events = self.run_main("--providers", "claude")["events"]
                self.assertIn("renewed", [e["kind"] for e in events])
                self.assert_clean(events)
                with mock.patch.object(usage.urllib.request, "urlopen", side_effect=self.answer(failure)):
                    self.assert_clean(self.run_main("--providers", "claude")["events"])

    def test_a_failed_renewal(self):
        refused = urllib.error.HTTPError(f"{usage.CLAUDE_TOKEN_URL}?code=QUERYSECRET", 400, LEAKY,
                                         email.message.Message(), io.BytesIO(LEAKY.encode()))
        self.addCleanup(refused.close)
        with mock.patch.object(usage.urllib.request, "urlopen", side_effect=refused):
            self.assert_clean(self.run_main("--providers", "claude")["events"])

    def test_codex_failures(self):
        cli = str(Path.home() / ".local" / "bin" / "codex")
        for failure in (RuntimeError(LEAKY), usage.CheckFailed(LEAKY, "offline", SECRETS[6]),
                        usage.CheckFailed(LEAKY, "server", SECRETS[6], 500), usage.RateLimited(60, SECRETS[6]),
                        OSError(13, LEAKY), KeyError(LEAKY)):
            with self.subTest(failure=type(failure).__name__):
                usage.CACHE_FILE.unlink(missing_ok=True)
                with mock.patch.object(usage, "find_cli", return_value=(cli, "")), \
                     mock.patch.object(usage, "codex_rate_limits", side_effect=failure):
                    self.assert_clean(self.run_main("--providers", "codex")["events"])

    # A chosen program is named as the settings show it: the home folder,
    # which names the user, as ~.
    def test_a_chosen_program_under_home(self):
        self.enterContext(mock.patch.object(usage, "find_cli", REAL_FIND_CLI))
        for chosen in (str(Path.home() / "bin" / "codex"), "~/bin/codex"):
            with self.subTest(chosen=chosen):
                usage.CACHE_FILE.unlink(missing_ok=True)
                events = self.run_main("--providers", "codex", "--program", f"codex={chosen}")["events"]
                self.assert_clean(events)
                self.assertIn("~/bin/codex", json.dumps(events))
                self.assertNotIn(str(Path.home()), json.dumps(events))

    # A host that only a tampered cache could hold is left out too.
    def test_a_held_failure_from_the_cache(self):
        self.write_cache({"claude": {"status": "error", "message": LEAKY, "reason": "offline", "host": SECRETS[6],
                                     "heldUntil": int(time.time()) + 300, "holdSeconds": 300}})
        self.assert_clean(self.run_main("--providers", "claude")["events"])

    def test_the_starter_renewing_and_failing_its_preflight(self):
        self.run_main("--providers", "claude", "--starter-set", "claude=on")
        renewed = {"seven_day": {"utilization": 5, "resets_at": int(time.time()) + 86400}, "five_hour": None}
        def urlopen(request, timeout):
            body = renewed if request.full_url == usage.CLAUDE_USAGE_URL else {
                "access_token": SECRETS[2], "refresh_token": SECRETS[3], "expires_in": 600}
            return contextlib.nullcontext(io.BytesIO(json.dumps(body).encode()))
        for preflight in ((1, LEAKY), (0, json.dumps({"loggedIn": True, "email": SECRETS[4],
                                                       "authMethod": "console"}))):
            with self.subTest(preflight=preflight[0]):
                self.login()
                usage.STARTER_STATE.unlink(missing_ok=True)
                usage.CACHE_FILE.unlink(missing_ok=True)
                with mock.patch.object(usage, "find_cli", return_value=("/mock/claude", "")), \
                     mock.patch.object(usage, "run_cli", return_value=preflight), \
                     mock.patch.object(usage.urllib.request, "urlopen", side_effect=urlopen):
                    events = self.run_main("--providers", "claude", "--start")["events"]
                self.assertIn("starter-failed", [e["kind"] for e in events])
                self.assert_clean(events)


if __name__ == "__main__":
    unittest.main()
