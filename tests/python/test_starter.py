# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

"""The session starter: its steps on a fake clock with fake reads and sends,
the commands it runs, the lock and login it keeps, and what it reports.
Ported in part from usage-reset's scheduler and CLI tests."""

import fcntl
import io
import json
import os
import stat
import subprocess
import sys
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

from test_usage import FIXTURES, OFF, WEEK, Isolated, usage

NOW = 1800000000
HOUR = 3600
SESSION = 5 * HOUR
REAL_RUN_CLI = usage.run_cli
AUTH = {"loggedIn": True, "authMethod": "claude.ai", "apiProvider": "firstParty", "subscriptionType": "max"}


def switched_on():
    """The switch, as a sender reads it just before sending."""
    return True


def week(percent, resets_at, seconds=WEEK):
    return {"percent": percent, "resetsAt": resets_at, "windowSeconds": seconds}


def claude(fetched, session=None, session_percent=0, weekly_percent=0, weekly_reset=None):
    """A Claude reading as the cache holds it; session is the five-hour reset."""
    return {"status": "ok", "fetchedAt": fetched, "scoped": [],
            "weekly": week(weekly_percent, weekly_reset or fetched + 3 * 86400),
            "session": None if session is None else week(session_percent, session, SESSION)}


def codex(fetched, percent, resets_at):
    return {"status": "ok", "fetchedAt": fetched, "scoped": [], "weekly": week(percent, resets_at)}


class Harness:
    """A Starter on a fake clock. reading is what a read returns, or an
    exception it raises; outcome is what a send raises, if anything."""

    def __init__(self, now, reading=None, record=None, outcome=None, provider="claude"):
        self.now = now
        self.reading = reading if reading is not None else claude(now)
        self.record = record if record is not None else usage.blank_record()
        self.outcome = outcome
        self.missing = False
        self.events = []
        self.starter = usage.Starter(
            self.record, read=self.read, check=self.check, send=self.send,
            running=usage.claude_running if provider == "claude" else usage.codex_running,
            period=SESSION if provider == "claude" else WEEK,
            persist=self.persist, clock=lambda: self.now)

    def read(self, not_before):
        self.events.append(("read", not_before))
        if isinstance(self.reading, Exception):
            raise self.reading
        return self.reading

    def check(self):
        if self.missing:
            raise usage.Failed("not-installed")
        return "/bin/cli"

    def send(self, binary):
        self.events.append(("send", dict(self.record)))
        if self.outcome:
            raise self.outcome

    def persist(self):
        self.events.append(("persist", dict(self.record)))

    def count(self, name):
        return sum(event == name for event, _ in self.events)

    def step(self, at=None):
        if at is not None:
            self.now = at
        self.starter.step()

    def shows(self):
        return self.record["state"], self.record["at"], self.record["next"]


class Steps(unittest.TestCase):
    def test_a_running_window_waits_for_its_reset_even_at_zero_percent(self):
        reset = NOW + 1234
        h = Harness(NOW, claude(NOW, session=reset, session_percent=0))
        h.step()
        self.assertEqual(h.count("send"), 0)
        self.assertEqual(h.shows(), ("waiting", None, reset + 1))
        h.step(reset)
        self.assertEqual(h.count("read"), 1)

    def test_no_window_or_an_ended_one_each_get_one_send(self):
        for session in (None, NOW - 4):
            with self.subTest(session=session):
                h = Harness(NOW, claude(NOW, session=session, session_percent=40))
                h.step()
                self.assertEqual(h.count("send"), 1)
                self.assertEqual(h.shows(), ("confirming", NOW, NOW + usage.CONFIRM_DELAY))
                h.step(NOW + 1)
                self.assertEqual(h.count("send"), 1)

    def test_a_send_is_confirmed_by_a_reading_five_minutes_later(self):
        h = Harness(NOW)
        h.step()
        reset = NOW + SESSION - 1
        h.reading = claude(NOW + 300, session=reset, session_percent=1)
        h.step(NOW + 299)
        self.assertEqual(h.count("read"), 1)
        h.step(NOW + 300)
        self.assertEqual(h.events[-2], ("read", NOW + usage.CONFIRM_SLACK))
        self.assertEqual(h.shows(), ("started", reset - SESSION, reset + 1))
        self.assertEqual(h.count("send"), 1)
        self.assertIsNone(h.record["sentAt"])

    def test_the_next_window_starts_when_a_started_one_ends(self):
        reset = NOW + SESSION
        h = Harness(NOW, claude(NOW, session=reset), record=dict(
            usage.blank_record(), state="started", at=NOW, next=reset + 1))
        h.step(reset)
        self.assertEqual(h.count("read"), 0)
        h.reading = claude(reset - 100, session=reset, session_percent=30)
        h.step(reset + 1)
        self.assertEqual(h.count("send"), 1)

    def test_the_weekly_limit_holds_until_it_resets(self):
        reset = NOW + 987
        h = Harness(NOW, claude(NOW, weekly_percent=100, weekly_reset=reset))
        h.step()
        self.assertEqual(h.count("send"), 0)
        self.assertEqual(h.shows(), ("weekly", None, reset + 1))
        h.step(reset)
        self.assertEqual(h.count("read"), 1)
        h.reading = claude(reset + 1, weekly_percent=0, weekly_reset=reset + WEEK)
        h.step(reset + 1)
        self.assertEqual(h.count("send"), 1)

    # A reached limit that doesn't say when it resets sends nothing; it is
    # read again as after a failed read, and says so rather than promising
    # a start at the retry.
    def test_a_weekly_limit_without_a_reset_holds_like_a_failed_read(self):
        for provider, reading in (("claude", dict(claude(NOW), weekly=week(100, None))),
                                  ("codex", codex(NOW, 100, None))):
            with self.subTest(provider=provider):
                h = Harness(NOW, reading, provider=provider)
                h.step()
                self.assertEqual(h.count("send"), 0)
                self.assertEqual(h.shows(), ("failed", None, NOW + 300))
                self.assertEqual(h.record["reason"], "unchecked")
                h.step(NOW + 300)
                self.assertEqual(h.shows(), ("failed", None, NOW + 300 + 900))
                self.assertEqual(h.count("send"), 0)

    # A cached reading from before the weekly reset still says 100%; the
    # reset has passed, so it holds nothing.
    def test_a_weekly_limit_whose_reset_has_passed_holds_nothing(self):
        h = Harness(NOW + 1, claude(NOW - 100, weekly_percent=100, weekly_reset=NOW))
        h.step()
        self.assertEqual(h.count("send"), 1)
        self.assertEqual(h.record["state"], "confirming")

    # Only the window it started reads as started; another is the user's.
    def test_a_started_window_stepped_again_stays_started(self):
        reset = NOW + 4 * HOUR
        for at, shows in ((reset - SESSION, ("started", reset - SESSION, reset + 1)),
                          (reset - SESSION - 60, ("waiting", None, reset + 1))):
            with self.subTest(at=at):
                record = dict(usage.blank_record(), state="started", at=at, next=reset + 1, steppedAt=NOW + 86400)
                h = Harness(NOW, claude(NOW, session=reset, session_percent=3), record=record)
                h.step()
                self.assertEqual(h.count("read"), 1)
                self.assertEqual(h.shows(), shows)

    # A reading that finds the weekly limit reached holds even a send it
    # would otherwise confirm, as usage-reset did.
    def test_the_weekly_limit_reached_while_confirming_holds(self):
        h = Harness(NOW)
        h.step()
        h.reading = claude(NOW + 300, session=NOW + SESSION, weekly_percent=100, weekly_reset=NOW + 86400)
        h.step(NOW + 300)
        self.assertEqual(h.shows(), ("weekly", None, NOW + 86401))
        self.assertEqual(h.record["uncertain"], 0)

    def test_missed_windows_are_not_replayed(self):
        h = Harness(NOW + 4 * SESSION, record=dict(usage.blank_record(), next=NOW))
        h.step()
        self.assertEqual(h.count("send"), 1)
        h.step(NOW + 4 * SESSION + 300)
        self.assertEqual(h.count("send"), 1)

    def test_failed_reads_back_off_and_keep_a_longer_hold(self):
        now = NOW
        h = Harness(now, usage.Unreadable())
        for delay in (300, 900, 3600, 3600):
            h.step(now)
            self.assertEqual(h.shows(), ("failed", None, now + delay))
            self.assertEqual(h.record["reason"], "unchecked")
            now += delay
        h.reading = usage.Unreadable(4000)
        h.step(now)
        self.assertEqual(h.record["next"], now + 4000)
        self.assertEqual(h.count("send"), 0)
        h.reading = claude(now + 4000, session=now + 4000 + HOUR)
        h.step(now + 4000)
        self.assertEqual(h.record["failures"], 0)

    def test_a_failed_confirmation_read_keeps_confirming(self):
        h = Harness(NOW)
        h.step()
        h.reading = usage.Unreadable()
        h.step(NOW + 300)
        self.assertEqual(h.shows(), ("confirming", NOW, NOW + 600))

    def test_a_step_claims_five_minutes_before_it_reads(self):
        h = Harness(NOW, RuntimeError("a bug"), record=dict(usage.blank_record(), next=NOW))
        with self.assertRaises(RuntimeError):
            h.step()
        self.assertEqual(h.events[0], ("persist", dict(usage.blank_record(), next=NOW + 300, steppedAt=NOW)))
        self.assertEqual(h.shows(), ("waiting", None, NOW + 300))
        h.step(NOW + 299)
        self.assertEqual(h.count("read"), 1)

    def test_a_state_that_cant_be_written_reads_nothing(self):
        h = Harness(NOW)
        h.persist = mock.Mock(side_effect=OSError(28, "No space left on device"))
        h.starter.persist = h.persist
        with self.assertRaises(OSError):
            h.step()
        self.assertEqual(h.events, [])

    def test_the_send_is_recorded_before_it_starts(self):
        h = Harness(NOW)
        h.step()
        sent = next(i for i, (event, _) in enumerate(h.events) if event == "send")
        self.assertEqual(h.events[sent - 1], ("persist", dict(usage.blank_record(), pending=NOW, next=NOW + 300,
                                                             steppedAt=NOW)))

    def test_a_restart_mid_send_confirms_it_then_pauses_after_two(self):
        h = Harness(NOW, record=dict(usage.blank_record(), pending=NOW))
        h.step(NOW + 30)
        self.assertEqual(h.count("read"), 0)
        self.assertEqual(h.shows(), ("confirming", NOW, NOW + 300))
        h.step(NOW + 300)
        self.assertEqual(h.shows(), ("retrying", NOW, NOW + 600))
        self.assertEqual((h.record["uncertain"], h.count("send")), (1, 0))
        h.step(NOW + 600)
        self.assertEqual(h.count("send"), 1)
        self.assertEqual(h.shows(), ("confirming", NOW + 600, NOW + 900))
        h.step(NOW + 900)
        self.assertEqual(h.shows(), ("paused", None, NOW + 900 + usage.PAUSE))
        self.assertEqual(h.record["uncertain"], 2)
        h.step(NOW + 900 + usage.PAUSE - 1)
        self.assertEqual(h.count("read"), 3)
        h.step(NOW + 900 + usage.PAUSE)
        self.assertEqual(h.count("send"), 2)
        self.assertEqual(h.record["uncertain"], 0)

    def test_two_unconfirmed_sends_in_a_row_pause_five_hours(self):
        h = Harness(NOW)
        for at in (NOW, NOW + 300, NOW + 600, NOW + 900):
            h.step(at)
        self.assertEqual(h.count("send"), 2)
        self.assertEqual(h.shows(), ("paused", None, NOW + 900 + 5 * HOUR))
        self.assertEqual(usage.PAUSE, 5 * HOUR)

    def test_a_late_confirmation_counts(self):
        h = Harness(NOW)
        h.step()
        h.step(NOW + 300)
        reset = NOW + SESSION
        h.reading = claude(NOW + 600, session=reset)
        h.step(NOW + 600)
        self.assertEqual(h.shows(), ("started", NOW, reset + 1))
        self.assertEqual((h.record["uncertain"], h.count("send")), (0, 1))

    def test_sends_that_never_left_retry_without_counting(self):
        now = NOW
        h = Harness(now, outcome=usage.NotSent())
        for attempt, delay in enumerate((300, 900, 3600)):
            h.step(now)
            self.assertEqual(h.count("send"), attempt + 1)
            self.assertIsNone(h.record["pending"])
            self.assertEqual(h.record["uncertain"], 0)
            self.assertEqual(h.shows(), ("failed", None, now + delay))
            self.assertEqual(h.record["reason"], "not-sent")
            now += delay
        h.outcome = None
        h.step(now)
        self.assertEqual(h.shows(), ("confirming", now, now + 300))
        self.assertEqual((h.record["failures"], h.record["reason"]), (0, None))

    # A CLI that doesn't answer its check shows as failed, backing off as a
    # send that never left does, and a retry it held up still counts.
    def test_a_cli_not_responding_fails_and_backs_off(self):
        now = NOW
        h = Harness(now, outcome=usage.NotSent("not-responding"),
                    record=dict(usage.blank_record(), state="retrying", at=NOW - 300, sentAt=NOW - 300, uncertain=1))
        for attempt, delay in enumerate((300, 900, 3600)):
            h.step(now)
            self.assertEqual(h.count("send"), attempt + 1)
            self.assertEqual((h.record["state"], h.record["reason"], h.record["next"]),
                             ("failed", "not-responding", now + delay))
            now += delay
        h.outcome = None
        h.step(now)
        self.assertEqual((h.record["state"], h.record["reason"], h.record["failures"]), ("confirming", None, 0))
        h.step(now + 300)
        self.assertEqual(h.record["state"], "paused")

    # A retry the switch stops before it sends forgets the send it would
    # have repeated, so a session the user starts later isn't taken for one
    # the starter started.
    def test_a_switch_found_off_before_a_retry_forgets_the_send(self):
        h = Harness(NOW, outcome=usage.SwitchedOff(), record=dict(
            usage.blank_record(), state="retrying", at=NOW - 300, next=NOW, sentAt=NOW - 300, uncertain=1))
        h.step()
        self.assertEqual(h.count("send"), 1)
        self.assertEqual((h.record["state"], h.record["next"], h.record["sentAt"], h.record["uncertain"],
                          h.record["pending"]), ("waiting", None, None, 0, None))
        h.outcome = None
        h.reading = claude(NOW + 600, session=NOW + SESSION)
        h.step(NOW + 600)
        self.assertEqual(h.shows(), ("waiting", None, NOW + SESSION + 1))

    def test_a_missing_cli_or_login_fails_and_checks_again_in_five_minutes(self):
        h = Harness(NOW)
        h.missing = True
        h.step()
        self.assertEqual(h.count("read"), 0)
        self.assertEqual(h.record["reason"], "not-installed")
        self.assertEqual(h.shows(), ("failed", None, NOW + 300))
        h.missing = False
        h.reading = usage.Failed("signed-out")
        h.step(NOW + 300)
        self.assertEqual((h.record["state"], h.record["reason"]), ("failed", "signed-out"))
        h.reading = claude(NOW + 600)
        h.outcome = usage.Failed("signed-out")
        h.step(NOW + 600)
        self.assertEqual((h.record["state"], h.record["reason"], h.record["pending"]), ("failed", "signed-out", None))
        h.outcome = None
        h.step(NOW + 900)
        self.assertEqual((h.record["state"], h.record["reason"]), ("confirming", None))

    # A send whose confirming read finds the CLI gone or signed out counts
    # as unconfirmed: it is confirmed should a later read find its window,
    # and the second such send pauses the starter.
    def test_a_confirmation_cut_short_by_a_sign_out_goes_unconfirmed(self):
        for cause in ("signed-out", "not-installed"):
            with self.subTest(cause=cause):
                h = Harness(NOW)
                h.step()

                def fail():
                    if cause == "signed-out":
                        h.reading = usage.Failed("signed-out")
                    else:
                        h.missing = True

                fail()
                h.step(NOW + 300)
                self.assertEqual((h.record["state"], h.record["reason"]), ("failed", cause))
                self.assertEqual((h.record["sentAt"], h.record["uncertain"]), (NOW, 1))
                h.reading, h.missing = claude(NOW + 600), False
                h.step(NOW + 600)
                self.assertEqual(h.count("send"), 2)
                fail()
                h.step(NOW + 900)
                self.assertEqual(h.shows(), ("paused", None, NOW + 900 + usage.PAUSE))
                h.reading, h.missing = claude(NOW + 1200), False
                h.step(NOW + 1200)
                self.assertEqual(h.count("send"), 2)

        h = Harness(NOW)
        h.step()
        h.reading = usage.Failed("signed-out")
        h.step(NOW + 300)
        h.reading = claude(NOW + 600, session=NOW + SESSION)
        h.step(NOW + 600)
        self.assertEqual(h.shows(), ("started", NOW, NOW + SESSION + 1))
        self.assertEqual(h.record["uncertain"], 0)

    # A send from before the starter was switched off, older than a window,
    # can't be confirmed or refuted any more.
    def test_a_send_older_than_a_window_is_forgotten_not_counted(self):
        h = Harness(NOW, record=dict(usage.blank_record(), state="confirming", at=NOW - SESSION,
                                     next=NOW - SESSION + 300, sentAt=NOW - SESSION))
        h.step()
        self.assertEqual(next(e for e in h.events if e[0] == "read"), ("read", None))
        self.assertEqual((h.record["uncertain"], h.count("send")), (0, 1))

    def test_a_cached_reading_from_before_the_send_defers_the_confirmation(self):
        h = Harness(NOW)
        h.step()
        h.reading = usage.Defer(NOW + 350)
        h.step(NOW + 300)
        self.assertEqual(h.shows(), ("confirming", NOW, NOW + 350))
        self.assertEqual(h.record["uncertain"], 0)

    # A step while the clock ran a day fast, before NTP stepped it back:
    # the send it made is confirmed five minutes on, not a day later.
    def test_a_clock_stepped_back_moves_a_confirmation_back_with_it(self):
        fast = NOW + 86400
        h = Harness(fast)
        h.step()
        self.assertEqual(h.shows(), ("confirming", fast, fast + 300))
        persisted = h.count("persist")
        h.step(NOW + 60)
        self.assertEqual(h.shows(), ("confirming", NOW + 60, NOW + 360))
        self.assertEqual((h.record["sentAt"], h.record["steppedAt"], h.count("read")), (NOW + 60, NOW + 60, 1))
        self.assertEqual((h.count("persist"), h.events[-1]), (persisted + 1, ("persist", h.record)))
        h.reading = claude(NOW + 360, session=NOW + SESSION)
        h.step(NOW + 360)
        self.assertEqual(h.events[-2], ("read", NOW + 60 + usage.CONFIRM_SLACK))
        self.assertEqual(h.shows(), ("started", NOW, NOW + SESSION + 1))
        self.assertEqual(h.count("send"), 1)

    # Each wait keeps its length from the moment the clock went back, so a
    # pause still lasts and a Retry-After is still kept.
    def test_a_clock_stepped_back_keeps_each_wait_as_long_as_it_was(self):
        fast = NOW + 86400
        for record, reading, wait in (
                (dict(usage.blank_record(), uncertain=1, state="confirming", at=fast - 300, sentAt=fast - 300),
                 claude(fast), usage.PAUSE),
                (None, usage.Unreadable(4000), 4000), (None, usage.Unreadable(), 300)):
            with self.subTest(wait=wait):
                h = Harness(fast, reading, record=record)
                h.step()
                self.assertEqual(h.record["next"], fast + wait)
                reads = h.count("read")
                h.step(NOW)
                self.assertEqual((h.record["next"], h.count("read"), h.count("send")), (NOW + wait, reads, 0))
                h.step(NOW + wait - 1)
                self.assertEqual(h.count("read"), reads)

    # Owner decision: no guard for extra usage or credits; users on them
    # switch the starter off. The reading the starter sees has no such field.
    def test_no_extra_usage_guard(self):
        reading = dict(claude(NOW), extra_usage={"is_enabled": True})
        h = Harness(NOW, reading)
        h.step()
        self.assertEqual(h.count("send"), 1)


class Codex(unittest.TestCase):
    def test_an_idle_accounts_rolling_reset_is_no_window(self):
        for percent, reset, running in ((0, NOW + WEEK, False), (0, NOW + WEEK - 90, False),
                                        (0, NOW + WEEK + 90, False), (0, NOW + WEEK - 300, True),
                                        (1, NOW + WEEK, True), (40, NOW + 3600, True),
                                        (40, NOW - 1, False), (0, None, False)):
            with self.subTest(percent=percent, reset=reset):
                reading = codex(NOW, percent, reset)
                self.assertEqual(usage.codex_running(reading, NOW) is not None, running)

    # Idle is judged from when the reading was taken: a cached one minutes
    # old still shows a week rolling from then, not from now.
    def test_an_idle_account_read_minutes_ago_is_still_idle(self):
        fetched = NOW - 240
        h = Harness(NOW, codex(fetched, 0, fetched + WEEK), provider="codex")
        h.step()
        self.assertEqual(h.count("send"), 1)

    def test_a_week_started_by_the_send_is_confirmed_at_zero_percent(self):
        h = Harness(NOW, codex(NOW, 0, NOW + WEEK), provider="codex")
        h.step()
        self.assertEqual(h.count("send"), 1)
        h.reading = codex(NOW + 300, 0, NOW + WEEK)
        h.step(NOW + 300)
        self.assertEqual(h.shows(), ("started", NOW, NOW + WEEK + 1))

    # The earliest reading that may confirm a send, after the longest send,
    # still tells the week it started from one that moves with the clock.
    def test_the_earliest_confirming_reading_is_clear_of_a_rolling_week(self):
        self.assertGreater(usage.CONFIRM_SLACK - usage.SEND_TIMEOUT, usage.ROLLING_SLACK)
        h = Harness(NOW, codex(NOW, 0, NOW + WEEK), provider="codex")
        h.step()
        started = NOW + usage.SEND_TIMEOUT
        h.reading = codex(NOW + usage.CONFIRM_SLACK, 0, started + WEEK)
        h.step(NOW + 300)
        self.assertEqual(h.events[-2], ("read", NOW + usage.CONFIRM_SLACK))
        self.assertEqual(h.shows(), ("started", started, started + WEEK + 1))

    def test_a_week_still_rolling_after_the_send_is_unconfirmed(self):
        h = Harness(NOW, codex(NOW, 0, NOW + WEEK), provider="codex")
        h.step()
        h.reading = codex(NOW + 300, 0, NOW + 300 + WEEK)
        h.step(NOW + 300)
        self.assertEqual(h.shows(), ("retrying", NOW, NOW + 600))

    # A week in use that doesn't say when it resets is read again as after
    # a failed read; nothing is sent into it.
    def test_a_week_in_use_without_a_reset_holds_like_a_failed_read(self):
        with self.assertRaises(usage.Unreadable):
            usage.codex_running(codex(NOW, 40, None), NOW)
        h = Harness(NOW, codex(NOW, 40, None), provider="codex")
        for at, retry in ((NOW, NOW + 300), (NOW + 300, NOW + 1200), (NOW + 1200, NOW + 4800)):
            h.step(at)
            self.assertEqual(h.record["next"], retry)
        self.assertEqual(h.count("send"), 0)

    def test_a_running_week_waits_and_a_full_one_holds(self):
        h = Harness(NOW, codex(NOW, 30, NOW + 2 * 86400), provider="codex")
        h.step()
        self.assertEqual(h.shows(), ("waiting", None, NOW + 2 * 86400 + 1))
        h = Harness(NOW, codex(NOW, 100, NOW + 86400), provider="codex")
        h.step()
        self.assertEqual(h.shows(), ("weekly", None, NOW + 86401))
        self.assertEqual(h.count("send"), 0)


class Reading(Isolated):
    def cache(self, **entries):
        self.write_cache(entries)

    def test_a_cached_reading_older_than_the_send_waits_for_it_to_go_stale(self):
        self.cache(claude=claude(NOW - 10))
        fetch = mock.Mock()
        with mock.patch.object(usage, "claude_usage", fetch), usage.locked(), \
                self.assertRaises(usage.Defer) as defer:
            usage.starter_read("claude", NOW + 200, NOW + 60)
        self.assertEqual(defer.exception.until, NOW - 10 + usage.CACHE_TTL)
        fetch.assert_not_called()

    def test_a_cached_reading_from_0_2_without_a_session_waits_too(self):
        entry = claude(NOW - 10)
        del entry["session"]
        self.cache(claude=entry)
        with usage.locked(), self.assertRaises(usage.Defer):
            usage.starter_read("claude", NOW, None)

    def test_a_fresh_reading_serves_and_a_stale_one_is_polled(self):
        self.cache(claude=claude(NOW - 10, session=NOW + HOUR))
        fetch = mock.Mock(return_value={"weekly": week(5, NOW + 86400), "scoped": [], "session": None})
        with mock.patch.object(usage, "claude_usage", fetch), usage.locked():
            self.assertEqual(usage.starter_read("claude", NOW, None)["session"]["resetsAt"], NOW + HOUR)
            fetch.assert_not_called()
            self.assertIsNone(usage.starter_read("claude", NOW + 300, None)["session"])
        fetch.assert_called_once()
        self.assertEqual(json.loads(usage.CACHE_FILE.read_text())["claude"]["fetchedAt"], NOW + 300)

    def test_failures_become_starter_exceptions(self):
        for failure, expected in ((usage.SignedOut(), usage.Failed), (RuntimeError("down"), usage.Unreadable),
                                  (usage.RateLimited(900), usage.Unreadable)):
            with self.subTest(failure=failure):
                usage.CACHE_FILE.unlink(missing_ok=True)
                with mock.patch.object(usage, "codex_usage", side_effect=failure), usage.locked(), \
                        self.assertRaises(expected) as raised:
                    usage.starter_read("codex", NOW, None)
                if isinstance(failure, usage.RateLimited):
                    self.assertEqual(raised.exception.wait, 900)


class Commands(Isolated):
    """The commands the senders run, with a fake runner."""

    def runner(self, *results):
        """A fake run_cli giving each call the next result: (code, output) or
        an exception to raise."""
        calls = []
        results = list(results)

        def run(argv, env, timeout):
            calls.append((argv, env, timeout))
            result = results.pop(0)
            if isinstance(result, BaseException):
                raise result
            return result

        self.enterContext(mock.patch.object(usage, "run_cli", run))
        self.enterContext(mock.patch.object(usage, "claude_access_token", return_value="token"))
        return calls

    def test_the_preflight_runs_auth_status_with_every_send_flag(self):
        calls = self.runner((0, json.dumps(AUTH)), (0, "{}"))
        usage.send_claude("/mock/claude", switched_on)
        argv, _, timeout = calls[0]
        self.assertEqual(argv, ["/mock/claude", *usage.claude_options(), "auth", "status"])
        self.assertNotIn("--help", argv)
        self.assertEqual(timeout, usage.PREFLIGHT_TIMEOUT)

    def test_the_send_is_minimal_and_its_environment_sanitised(self):
        source = {"HOME": "/home/test", "PATH": "/usr/bin", "LC_TIME": "de_DE.UTF-8", "HTTPS_PROXY": "http://proxy:3128",
                  "CLAUDE_CONFIG_DIR": "/cfg/claude", "ANTHROPIC_API_KEY": "secret",
                  "ANTHROPIC_BASE_URL": "https://override.example", "CLAUDE_CODE_USE_BEDROCK": "1",
                  "CLAUDE_CODE_USE_VERTEX": "1", "CLAUDE_CODE_OAUTH_TOKEN": "another", "OPENAI_API_KEY": "secret"}
        with mock.patch.dict(os.environ, source, clear=True):
            calls = self.runner((0, json.dumps(AUTH)), (0, "{}"))
            usage.send_claude("/mock/claude", switched_on)
        argv, env, timeout = calls[1]
        self.assertEqual(argv, ["/mock/claude", *usage.claude_options(), "-p", "Hi"])
        self.assertEqual(len(argv[-1].split()), 1)
        self.assertEqual(argv[argv.index("--model") + 1], "haiku")
        self.assertEqual(argv[argv.index("--system-prompt") + 1], "Reply with OK.")
        for flag in ("--safe-mode", "--strict-mcp-config", "--disable-slash-commands",
                     "--no-session-persistence", "--no-chrome"):
            self.assertIn(flag, argv)
        self.assertEqual(argv[argv.index("--tools") + 1], "")
        self.assertEqual(argv[argv.index("--setting-sources") + 1], "")
        self.assertEqual(argv[argv.index("--max-turns") + 1], "1")
        self.assertEqual(argv[argv.index("--permission-prompts") + 1], "none")
        self.assertEqual(json.loads(argv[argv.index("--mcp-config") + 1]), {"mcpServers": {}})
        self.assertNotIn("--dangerously-skip-permissions", argv)
        self.assertEqual(timeout, usage.SEND_TIMEOUT)
        self.assertEqual({key: env[key] for key in ("HOME", "PATH", "LC_TIME", "HTTPS_PROXY", "CLAUDE_CONFIG_DIR")},
                         {key: source[key] for key in ("HOME", "PATH", "LC_TIME", "HTTPS_PROXY", "CLAUDE_CONFIG_DIR")})
        self.assertEqual((env["MAX_THINKING_TOKENS"], env["CLAUDE_CODE_MAX_OUTPUT_TOKENS"]), ("0", "256"))
        for key in ("ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX",
                    "CLAUDE_CODE_OAUTH_TOKEN", "OPENAI_API_KEY"):
            self.assertNotIn(key, env)

    # An API key, Bedrock or Vertex would bill the send without starting a
    # subscription window, and the user is told so rather than signed out.
    def test_a_login_that_isnt_a_subscription_says_so(self):
        for changed, reason in (({"loggedIn": False}, "signed-out"), ({"loggedIn": None}, "signed-out"),
                                ({"authMethod": "apiKey"}, "not-subscription"),
                                ({"apiProvider": "bedrock"}, "not-subscription"),
                                ({"apiProvider": "vertex", "authMethod": None}, "not-subscription")):
            with self.subTest(changed=changed):
                calls = self.runner((1, json.dumps({**AUTH, **changed})))
                with self.assertRaises(usage.Failed) as failed:
                    usage.send_claude("/mock/claude", switched_on)
                self.assertEqual(failed.exception.reason, reason)
                self.assertEqual(len(calls), 1)

    def test_a_preflight_that_fails_sends_nothing_and_isnt_responding(self):
        for result in (OSError("no such file"), subprocess.TimeoutExpired("claude", 20), (1, "error: unknown option"),
                       (0, "[]"), (1, json.dumps(AUTH))):
            with self.subTest(result=result):
                calls = self.runner(result)
                with self.assertRaises(usage.NotSent) as not_sent:
                    usage.send_claude("/mock/claude", switched_on)
                self.assertEqual(not_sent.exception.reason, "not-responding")
                self.assertEqual(len(calls), 1)

    def test_a_send_that_couldnt_start_never_left(self):
        self.runner((0, json.dumps(AUTH)), FileNotFoundError("claude"))
        with self.assertRaises(usage.NotSent):
            usage.send_claude("/mock/claude", switched_on)

    # usage-reset counted these as uncertain; the reading decides now.
    def test_once_started_any_outcome_is_left_to_the_reading(self):
        for result in ((0, json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": "OK",
                                       "modelUsage": {"claude-haiku-4-5-20251001": {}, "claude-haiku-5": {}}})),
                       (0, json.dumps({"type": "result", "is_error": True, "result": ""})), (1, "not json"),
                       subprocess.TimeoutExpired("claude", 60)):
            with self.subTest(result=result):
                self.runner((0, json.dumps(AUTH)), result)
                usage.send_claude("/mock/claude", switched_on)

    def test_a_login_that_cant_be_renewed_sends_nothing(self):
        calls = self.runner()
        for failure, expected in ((usage.SignedOut(), usage.Failed), (RuntimeError("can't reach"), usage.NotSent),
                                  (usage.RateLimited(60), usage.NotSent)):
            with self.subTest(failure=failure), \
                    mock.patch.object(usage, "claude_access_token", side_effect=failure), \
                    self.assertRaises(expected):
                usage.send_claude("/mock/claude", switched_on)
        self.assertEqual(calls, [])

    def test_codex_runs_one_ephemeral_read_only_turn(self):
        source = {"HOME": "/home/test", "PATH": "/usr/bin", "CODEX_HOME": "/cfg/codex",
                  "OPENAI_API_KEY": "secret", "CODEX_API_KEY": "secret", "OPENAI_BASE_URL": "https://override.example"}
        with mock.patch.dict(os.environ, source, clear=True):
            calls = self.runner((0, ""))
            usage.send_codex("/mock/codex", switched_on)
        argv, env, timeout = calls[0]
        self.assertEqual(argv[:2], ["/mock/codex", "exec"])
        for flag in ("--ephemeral", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules", "--json"):
            self.assertIn(flag, argv)
        self.assertEqual(argv[argv.index("--sandbox") + 1], "read-only")
        self.assertEqual(argv[argv.index("--cd") + 1], str(usage.WORK_DIR))
        self.assertEqual(argv[argv.index("--config") + 1], 'model_reasoning_effort="low"')
        self.assertEqual(argv[argv.index("--model") + 1], "gpt-6-luna")
        self.assertEqual(argv[-1], "Hi")
        for flag in ("--dangerously-bypass-approvals-and-sandbox", "--search", "--add-dir", "--full-auto"):
            self.assertNotIn(flag, argv)
        self.assertEqual(timeout, usage.SEND_TIMEOUT)
        self.assertEqual(env, {"HOME": "/home/test", "PATH": "/usr/bin", "CODEX_HOME": "/cfg/codex"})

    def models(self, models):
        usage.CODEX_MODEL_CACHE.parent.mkdir(parents=True, exist_ok=True)
        usage.CODEX_MODEL_CACHE.write_text(json.dumps({"models": models} if isinstance(models, list) else models))

    # Owner decision: the newest Luna the CLI lists, at its lightest effort.
    def test_codex_sends_with_the_newest_listed_luna(self):
        def luna(slug, *efforts, visibility="list"):
            return {"slug": slug, "visibility": visibility,
                    "supported_reasoning_levels": [{"effort": e, "description": ""} for e in efforts]}

        today = [luna("gpt-6.1-sol", "low", "medium"), luna("gpt-6-luna", "low", "medium", "high", "xhigh", "max"),
                 luna("gpt-reserve", "low", visibility="hide"), luna("gpt-5.6-luna", "low", "medium")]
        for models, expected in (
                (today, ("gpt-6-luna", "low")),
                (today + [luna("gpt-6.9-luna", "low"), luna("gpt-6.10-luna", "medium", "low")],
                 ("gpt-6.10-luna", "low")),
                (today + [luna("gpt-7-luna", "low", "high", "minimal"), luna("gpt-6.10-luna", "low")],
                 ("gpt-7-luna", "minimal")),
                (today + [luna("gpt-8-luna", "low", visibility="hide"), luna("gpt-7-luna-mini", "low"),
                          luna("gpt-7.x-luna", "low"), luna("gpt-٧-luna", "low")], ("gpt-6-luna", "low")),
                ([luna("gpt-5.6-luna", "medium", "low")], ("gpt-5.6-luna", "low")),
                ([luna("gpt-7-luna", "ultra")], ("gpt-7-luna", "low")),
                ([{"slug": "gpt-7-luna", "visibility": "list", "supported_reasoning_levels": "low"}],
                 ("gpt-7-luna", "low")),
                ([{"slug": "gpt-7-luna", "visibility": "list", "supported_reasoning_levels": [{"effort": []}]}],
                 ("gpt-7-luna", "low")),
                ([luna("gpt-6.1-sol", "minimal")], ("gpt-6-luna", "low")), ([], ("gpt-6-luna", "low")),
                ("odd", ("gpt-6-luna", "low")), ([["x"], {"slug": 7}, {}], ("gpt-6-luna", "low")),
                ({"models": {"slug": "gpt-7-luna"}}, ("gpt-6-luna", "low")), (["models"], ("gpt-6-luna", "low"))):
            with self.subTest(models=models):
                self.models(models)
                self.assertEqual(usage.codex_model(), expected)
                command = usage.codex_command("codex")
                self.assertEqual(command[command.index("--model") + 1], expected[0])
                self.assertEqual(command[command.index("--config") + 1], f'model_reasoning_effort="{expected[1]}"')

    def test_codex_falls_back_without_a_readable_model_list(self):
        self.assertFalse(usage.CODEX_MODEL_CACHE.exists())
        self.assertEqual(usage.codex_model(), ("gpt-6-luna", "low"))
        usage.CODEX_MODEL_CACHE.parent.mkdir(parents=True, exist_ok=True)
        usage.CODEX_MODEL_CACHE.write_text("{broken")
        self.assertEqual(usage.codex_model(), ("gpt-6-luna", "low"))
        usage.CODEX_MODEL_CACHE.write_bytes(b"\xff\xfe")
        self.assertEqual(usage.codex_model(), ("gpt-6-luna", "low"))

    def test_codex_that_couldnt_start_never_left_and_a_timeout_did(self):
        self.runner(OSError("exec format error"))
        with self.assertRaises(usage.NotSent):
            usage.send_codex("/mock/codex", switched_on)
        self.runner(subprocess.TimeoutExpired("codex", 60))
        usage.send_codex("/mock/codex", switched_on)

    def test_a_missing_cli_is_not_installed(self):
        with self.assertRaises(usage.Failed) as failed:
            usage.installed("claude")
        self.assertEqual(failed.exception.reason, "not-installed")

    def test_the_cli_is_found_in_local_bin_before_path(self):
        self.enterContext(mock.patch.object(usage, "find_cli", REAL_FIND_CLI))
        local = Path.home() / ".local" / "bin"
        local.mkdir(parents=True)
        (local / "claude").write_text("#!/bin/sh\n")
        with mock.patch.object(usage.shutil, "which", return_value="/usr/bin/claude"):
            self.assertEqual(usage.find_cli("claude"), "/usr/bin/claude")
            (local / "claude").chmod(0o700)
            self.assertEqual(usage.find_cli("claude"), str(local / "claude"))


REAL_FIND_CLI = usage.find_cli


class Runner(Isolated):
    """run_cli with real processes."""

    def script(self, body):
        path = self.tmp / "fake-cli"
        path.write_text(body)
        path.chmod(0o700)
        return str(path)

    def test_runs_in_the_work_folder_with_no_input(self):
        binary = self.script("#!/bin/sh\npwd\ncat\necho \"$1\"\nexit 3\n")
        code, out = REAL_RUN_CLI([binary, "word"], {"PATH": os.environ.get("PATH", "")}, 10)
        self.assertEqual((code, out), (3, f"{usage.WORK_DIR}\nword\n"))
        self.assertEqual(stat.S_IMODE(usage.WORK_DIR.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(usage.STATE_DIR.stat().st_mode), 0o700)

    def test_a_timeout_ends_what_the_cli_started(self):
        marker = self.tmp / "survived"
        binary = self.script(f"#!/bin/sh\n(sleep 2; touch '{marker}') &\nsleep 30\n")
        start = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            REAL_RUN_CLI([binary], {"PATH": os.environ.get("PATH", "")}, 0.5)
        self.assertLess(time.monotonic() - start, 5)
        time.sleep(2.5)
        self.assertFalse(marker.exists())

    def test_what_the_cli_leaves_behind_is_ended_too(self):
        marker = self.tmp / "survived"
        binary = self.script(f"#!/bin/sh\n(sleep 2; touch '{marker}') &\necho done\n")
        self.assertEqual(REAL_RUN_CLI([binary], {"PATH": os.environ.get("PATH", "")}, 10), (0, "done\n"))
        time.sleep(2.5)
        self.assertFalse(marker.exists())

    def test_a_survivor_outside_the_session_cant_stall_the_read(self):
        binary = self.script("#!/bin/sh\nsetsid sleep 8 &\necho done\n")
        start = time.monotonic()
        self.assertEqual(REAL_RUN_CLI([binary], {"PATH": os.environ.get("PATH", "")}, 10), (0, "done\n"))
        self.assertLess(time.monotonic() - start, 4)


class Login(Isolated):
    """Claude's login is renewed under the lock before the CLI runs."""

    def setUp(self):
        super().setUp()
        usage.CLAUDE_CREDENTIALS.parent.mkdir()
        self.order = []
        self.enterContext(mock.patch.object(usage, "run_cli", side_effect=self.run_cli))
        self.enterContext(mock.patch.object(usage, "refresh_claude", side_effect=self.refresh))

    def login(self, expires_in):
        usage.CLAUDE_CREDENTIALS.write_text(json.dumps({"claudeAiOauth": {
            "accessToken": "old-access", "refreshToken": "old-refresh",
            "expiresAt": int((time.time() + expires_in) * 1000)}}))

    def run_cli(self, argv, env, timeout):
        self.order.append(argv[-1])
        return 0, json.dumps(AUTH)

    def refresh(self, oauth):
        self.order.append("refresh")
        return {"accessToken": "new-access", "refreshToken": "new-refresh",
                "expiresAt": int((time.time() + 8 * HOUR) * 1000)}

    def test_a_login_expiring_within_fifteen_minutes_is_renewed_first(self):
        self.login(10 * 60)
        usage.send_claude("/mock/claude", switched_on)
        self.assertEqual(self.order, ["refresh", "status", "Hi"])
        stored = json.loads(usage.CLAUDE_CREDENTIALS.read_text())["claudeAiOauth"]
        self.assertEqual(stored["refreshToken"], "new-refresh")

    def test_a_login_good_for_longer_is_left_alone(self):
        self.login(30 * 60)
        usage.send_claude("/mock/claude", switched_on)
        self.assertEqual(self.order, ["status", "Hi"])

    def test_polls_keep_their_own_one_minute_margin(self):
        self.login(10 * 60)
        self.assertEqual(usage.claude_access_token(), "old-access")
        self.assertEqual(self.order, [])


class StarterRuns(Isolated):
    """--start and --starter-set through main, with fake polls and a fake runner."""

    def setUp(self):
        super().setUp()
        self.calls = []
        self.claude = self.enterContext(mock.patch.object(
            usage, "claude_usage", side_effect=lambda: {"weekly": week(10, int(time.time()) + 86400),
                                                        "scoped": [], "session": None}))
        # An idle Codex account: 0% and a reset a week from now.
        self.codex = self.enterContext(mock.patch.object(
            usage, "codex_usage", side_effect=lambda: {"weekly": week(0, int(time.time()) + WEEK), "scoped": []}))
        self.enterContext(mock.patch.object(usage, "find_cli", side_effect=lambda name: f"/mock/{name}"))
        self.enterContext(mock.patch.object(usage, "claude_access_token", return_value="token"))
        self.enterContext(mock.patch.object(usage, "run_cli", side_effect=self.run_cli))

    def run_cli(self, argv, env, timeout):
        self.calls.append(argv)
        return 0, json.dumps(AUTH) if argv[-1] == "status" else "{}"

    def switches(self):
        return json.loads(usage.STARTER_FILE.read_text())

    def test_starter_set_writes_the_per_user_switch_and_reports(self):
        report = self.run_main("--providers", "claude", "--starter-set", "claude=on")
        self.assertEqual(self.switches(), {"claude": True})
        self.assertEqual(stat.S_IMODE(usage.STARTER_FILE.stat().st_mode), 0o600)
        starter = report["providers"]["claude"]["starter"]
        self.assertEqual((starter["enabled"], starter["state"]), (True, "waiting"))
        self.assertLessEqual(starter["next"], int(time.time()))
        self.run_main("--providers", "claude,codex", "--starter-set", "codex=on", "--starter-set", "claude=off")
        self.assertEqual(self.switches(), {"claude": False, "codex": True})
        self.assertEqual(self.calls, [])
        self.assertFalse(usage.STARTER_STATE.exists())

    def test_starter_set_polls_no_more_than_a_normal_run(self):
        self.run_main("--providers", "claude")
        self.run_main("--providers", "claude", "--starter-set", "claude=on")
        self.claude.assert_called_once()

    def test_a_malformed_switch_file_is_off_and_is_replaced(self):
        usage.STARTER_FILE.parent.mkdir(parents=True)
        for content in ("{broken", "[]", '{"claude": "yes"}', '{"claude": 1}'):
            with self.subTest(content=content):
                usage.STARTER_FILE.write_text(content)
                self.assertEqual(self.run_main("--providers", "claude")["providers"]["claude"]["starter"], OFF)
        self.run_main("--providers", "claude", "--starter-set", "claude=on")
        self.assertEqual(self.switches(), {"claude": True})

    def test_a_switch_that_cant_be_written_reports_it_unchanged(self):
        self.run_main("--providers", "claude", "--starter-set", "claude=on")
        write = usage.write_private

        # A folder the user can't write to; chmod wouldn't stop root.
        def unwritable(path, data):
            if path == usage.STARTER_FILE:
                raise PermissionError(13, "Permission denied", str(path))
            write(path, data)

        with mock.patch.object(usage, "write_private", side_effect=unwritable), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            report = self.run_main("--providers", "claude,codex", "--starter-set", "claude=off",
                                   "--starter-set", "codex=on")
        self.assertEqual({name: entry["starter"]["enabled"] for name, entry in report["providers"].items()},
                         {"claude": True, "codex": False})
        self.assertEqual(err.getvalue(), f"[Errno 13] Permission denied: '{usage.STARTER_FILE}'\n")
        self.assertEqual(self.switches(), {"claude": True})

    def test_a_switch_change_that_cant_get_its_lock_reports_it_unchanged(self):
        usage.private_state_dir()
        fd = os.open(usage.SWITCH_LOCK, os.O_RDWR | os.O_CREAT, 0o600)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX)
        with mock.patch.object(usage, "LOCK_WAIT", 0.3), mock.patch("sys.stderr", new=io.StringIO()) as err:
            report = self.run_main("--providers", "claude", "--starter-set", "claude=on")
        self.assertEqual(report["providers"]["claude"]["starter"], OFF)
        self.assertEqual(err.getvalue(), "another usage check is still running\n")

    def test_bad_switches_exit_with_a_usage_error(self):
        for value in ("claude", "claude=yes", "gemini=on", "=on"):
            with self.subTest(value), mock.patch("sys.stderr", new=io.StringIO()), \
                    self.assertRaises(SystemExit) as exit_:
                usage.main(["--starter-set", value])
            self.assertEqual(exit_.exception.code, 2)
        self.assertFalse(usage.STARTER_FILE.exists())

    def test_start_runs_only_switched_on_listed_providers(self):
        self.run_main("--start")
        self.assertEqual(self.calls, [])
        self.run_main("--providers", "claude", "--starter-set", "codex=on")
        self.run_main("--providers", "claude", "--start")
        self.assertEqual(self.calls, [])
        report = self.run_main("--providers", "claude,codex", "--start")
        self.assertEqual([argv[:2] for argv in self.calls], [["/mock/codex", "exec"]])
        self.assertEqual(report["providers"]["codex"]["starter"]["state"], "confirming")
        self.assertEqual(report["providers"]["claude"]["starter"], OFF)

    def test_a_start_that_isnt_due_does_nothing(self):
        self.run_main("--starter-set", "claude=on")
        first = self.run_main("--providers", "claude", "--start")["providers"]["claude"]["starter"]
        self.assertEqual(first["state"], "confirming")
        again = self.run_main("--providers", "claude", "--start")["providers"]["claude"]["starter"]
        self.assertEqual(again, first)
        self.assertEqual(sum(argv[-1] == "Hi" for argv in self.calls), 1)

    def test_state_is_private_and_survives_between_runs(self):
        self.run_main("--starter-set", "claude=on")
        self.run_main("--providers", "claude", "--start")
        self.assertEqual(stat.S_IMODE(usage.STATE_DIR.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(usage.STARTER_STATE.stat().st_mode), 0o600)
        stored = json.loads(usage.STARTER_STATE.read_text())["claude"]
        self.assertEqual((stored["state"], stored["sentAt"], stored["pending"]), ("confirming", stored["at"], None))

    def test_a_restart_mid_send_reports_and_confirms_it(self):
        self.run_main("--starter-set", "claude=on")
        sent = int(time.time()) - 400
        usage.STATE_DIR.mkdir(parents=True, exist_ok=True)
        usage.STARTER_STATE.write_text(json.dumps({"claude": dict(usage.blank_record(), pending=sent)}))
        starter = self.run_main("--providers", "claude")["providers"]["claude"]["starter"]
        self.assertEqual((starter["state"], starter["at"], starter["next"]), ("confirming", sent, sent + 300))
        self.write_cache({})
        self.claude.side_effect = lambda: {"weekly": week(10, int(time.time()) + 86400), "scoped": [],
                                           "session": week(1, sent + SESSION, SESSION)}
        starter = self.run_main("--providers", "claude", "--start")["providers"]["claude"]["starter"]
        self.assertEqual((starter["state"], starter["at"], starter["next"]), ("started", sent, sent + SESSION + 1))
        self.assertEqual(self.calls, [])

    # The --start polls the bad reply itself: one cached by the switch's
    # run would defer it as a reading from 0.2.
    def test_a_reply_that_cant_tell_a_session_sends_nothing(self):
        weekly = {"utilization": 10, "resets_at": int(time.time()) + 86400}
        for body in ({"seven_day": weekly}, {"seven_day": weekly, "five_hour": "soon"}):
            with self.subTest(body=body):
                usage.STARTER_STATE.unlink(missing_ok=True)
                self.claude.side_effect = lambda: usage.parse_claude(body)
                self.run_main("--providers", "claude", "--starter-set", "claude=on")
                self.write_cache({})
                starter = self.run_main("--providers", "claude", "--start")["providers"]["claude"]["starter"]
                self.assertEqual(self.calls, [])
                self.assertEqual((starter["state"], starter["reason"]), ("failed", "unchecked"))
                stored = json.loads(usage.STARTER_STATE.read_text())["claude"]
                self.assertEqual(stored["failures"], 1)
                self.assertIn(starter["next"] - stored["steppedAt"], (300, 301))

    def test_a_cli_that_rejects_a_flag_reports_not_responding(self):
        self.run_main("--starter-set", "claude=on")
        rejects = mock.patch.object(usage, "run_cli", side_effect=lambda argv, env, timeout: self.calls.append(argv)
                                    or (1, "error: unknown option '--max-turns'"))
        with rejects:
            starter = self.run_main("--providers", "claude", "--start")["providers"]["claude"]["starter"]
        self.assertEqual((starter["state"], starter["reason"]), ("failed", "not-responding"))
        self.assertGreater(starter["next"], int(time.time()))
        self.assertEqual([argv[-1] for argv in self.calls], ["status"])

    def test_turning_the_switch_off_stops_the_next_start(self):
        self.run_main("--starter-set", "claude=on")
        self.run_main("--providers", "claude", "--starter-set", "claude=off")
        self.run_main("--providers", "claude", "--start")
        self.assertEqual(self.calls, [])

    # The switch has its own lock, so it can be turned off while a step
    # reads, renews Claude's login or checks the CLI; nothing goes out then.
    def test_a_switch_turned_off_during_the_step_sends_nothing(self):
        def off(result):
            def turn_off(*args):
                usage.set_switches({"claude": False, "codex": False})
                return result(*args) if callable(result) else result
            return turn_off

        for name, target, patched in (
                ("claude", "claude_access_token", off("token")),
                ("claude", "run_cli", off(self.run_cli)),
                ("codex", "codex_usage", off(lambda: {"weekly": week(0, int(time.time()) + WEEK), "scoped": []}))):
            with self.subTest(name=name, during=target):
                self.calls.clear()
                usage.STARTER_STATE.unlink(missing_ok=True)
                self.run_main("--starter-set", f"{name}=on")
                self.write_cache({})
                with mock.patch.object(usage, target, side_effect=patched):
                    report = self.run_main("--providers", name, "--start")
                self.assertEqual([argv[-1] for argv in self.calls], ["status"] if name == "claude" else [])
                self.assertEqual(report["providers"][name]["starter"], OFF)
                stored = json.loads(usage.STARTER_STATE.read_text())[name]
                self.assertEqual((stored["state"], stored["next"], stored["pending"], stored["sentAt"]),
                                 ("waiting", None, None, None))
                again = self.run_main("--providers", name, "--starter-set", f"{name}=on")["providers"][name]
                self.assertEqual(again["starter"]["state"], "waiting")
                self.assertLessEqual(again["starter"]["next"], int(time.time()), "due at once when switched on again")

    def test_a_start_that_cant_get_the_lock_still_reports(self):
        self.run_main("--starter-set", "claude=on")
        fd = os.open(usage.LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX)
        with mock.patch.object(usage, "LOCK_WAIT", 0.3):
            report = self.run_main("--providers", "claude", "--start")
        self.assertEqual(report["providers"]["claude"]["starter"]["state"], "waiting")
        self.assertEqual(self.calls, [])

    def test_a_state_that_cant_be_written_stops_the_send_not_the_report(self):
        self.run_main("--starter-set", "claude=on")
        with mock.patch.object(usage, "write_private", side_effect=OSError(28, "No space left on device")), \
                mock.patch("sys.stderr", new=io.StringIO()) as err:
            report = self.run_main("--providers", "claude", "--start")
        self.assertEqual(self.calls, [])
        self.assertIn("starter", report["providers"]["claude"])
        self.assertEqual(err.getvalue(), "[Errno 28] No space left on device\n")

    def test_the_lock_is_held_from_the_read_to_the_end_of_the_send(self):
        self.run_main("--starter-set", "claude=on")
        sending, release = threading.Event(), threading.Event()
        held = []

        def slow(argv, env, timeout):
            if argv[-1] == "Hi":
                fd = os.open(usage.LOCK_FILE, os.O_RDWR)
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    held.append(False)
                except BlockingIOError:
                    held.append(True)
                finally:
                    os.close(fd)
                sending.set()
                release.wait(10)
            return self.run_cli(argv, env, timeout)

        polled = []
        with mock.patch.object(usage, "run_cli", side_effect=slow):
            starter = threading.Thread(target=usage.run_starter, args=("claude",))
            starter.start()
            self.assertTrue(sending.wait(10))
            poll = threading.Thread(target=lambda: polled.append(usage.collect(
                {"claude": lambda: polled.append("fetched") or {"weekly": week(1, NOW), "scoped": []}},
                int(time.time()) + usage.CACHE_TTL)))
            poll.start()
            time.sleep(0.5)
            self.assertEqual(polled, [])
            release.set()
            starter.join(10)
            poll.join(10)
        self.assertEqual(held, [True])
        self.assertEqual(polled[0], "fetched")

    def test_the_lock_outlasts_the_longest_send(self):
        self.assertGreater(usage.LOCK_WAIT, usage.PREFLIGHT_TIMEOUT + usage.SEND_TIMEOUT + 2 * usage.HTTP_TIMEOUT
                           + usage.CODEX_TIMEOUT)


class Report(Isolated):
    def report(self, name, record, now=NOW, switches=("claude", "codex")):
        return usage.starter_report(name, set(switches), {name: usage.record_from(record)} if record else {}, now)

    def test_every_entry_carries_a_starter_even_when_off(self):
        self.write_cache({name: dict(claude(int(time.time())), status="ok") for name in ("claude", "codex")})
        providers = self.run_main()["providers"]
        self.assertEqual({name: entry["starter"] for name, entry in providers.items()},
                         {"claude": OFF, "codex": OFF})

    def test_each_state_reports_its_times(self):
        blank = usage.blank_record()
        cases = [
            ("claude", None, ("waiting", None, NOW, None)),
            ("claude", dict(blank, next=NOW + 600), ("waiting", None, NOW + 600, None)),
            ("claude", dict(blank, state="confirming", at=NOW, next=NOW + 300, sentAt=NOW),
             ("confirming", NOW, NOW + 300, None)),
            ("claude", dict(blank, pending=NOW - 5), ("confirming", NOW - 5, NOW + 295, None)),
            ("claude", dict(blank, state="started", at=NOW - 60, next=NOW + SESSION - 59),
             ("started", NOW - 60, NOW + SESSION - 59, None)),
            # The widget starts the next week on time; the popup doesn't show when.
            ("codex", dict(blank, state="started", at=NOW - 60, next=NOW + WEEK - 59),
             ("started", NOW - 60, NOW + WEEK - 59, None)),
            ("codex", dict(blank, state="started", at=NOW - WEEK, next=NOW - 5), ("started", NOW - WEEK, NOW - 5, None)),
            ("claude", dict(blank, state="weekly", next=NOW + 86400), ("weekly", None, NOW + 86400, None)),
            ("claude", dict(blank, state="failed", next=NOW + 300, reason="signed-out"),
             ("failed", None, NOW + 300, "signed-out")),
            ("codex", dict(blank, state="failed", next=NOW + 300, reason="not-installed"),
             ("failed", None, NOW + 300, "not-installed")),
            ("claude", dict(blank, state="failed", next=NOW + 300, reason="not-subscription"),
             ("failed", None, NOW + 300, "not-subscription")),
            ("claude", dict(blank, state="failed", next=NOW + 900, reason="not-responding", failures=2),
             ("failed", None, NOW + 900, "not-responding")),
            ("claude", dict(blank, state="failed", next=NOW + 900, reason="unchecked", failures=2),
             ("failed", None, NOW + 900, "unchecked")),
            ("codex", dict(blank, state="failed", next=NOW + 300, reason="not-sent", failures=1),
             ("failed", None, NOW + 300, "not-sent")),
            ("claude", dict(blank, state="retrying", at=NOW - 300, next=NOW + 300, sentAt=NOW - 300),
             ("retrying", NOW - 300, NOW + 300, None)),
            ("claude", dict(blank, state="paused", next=NOW + 5 * HOUR), ("paused", None, NOW + 5 * HOUR, None)),
        ]
        for name, record, (state, at, next_, reason) in cases:
            with self.subTest(name=name, record=record):
                self.assertEqual(self.report(name, record),
                                 {"enabled": True, "state": state, "at": at, "next": next_, "reason": reason})
        self.assertEqual(self.report("claude", dict(blank, state="paused"), switches=()), OFF)

    # The widget runs --start only once next comes, so a clock stepped back
    # since the last step makes the starter due, and that run moves its
    # times back for good.
    def test_a_clock_stepped_back_makes_the_starter_due(self):
        fast = NOW + 86400
        blank = usage.blank_record()
        for record, at in ((dict(blank, state="confirming", at=fast, next=fast + 300, sentAt=fast, steppedAt=fast),
                            NOW),
                           (dict(blank, pending=fast, next=fast + 300, steppedAt=fast), NOW),
                           (dict(blank, state="paused", next=fast + 5 * HOUR, steppedAt=fast), None),
                           (dict(blank, state="started", at=NOW - HOUR, next=NOW + 4 * HOUR + 1, steppedAt=fast),
                            NOW - HOUR)):
            with self.subTest(record=record):
                reported = self.report("claude", record)
                self.assertEqual((reported["state"], reported["at"], reported["next"]),
                                 (record["state"] if not record["pending"] else "confirming", at, NOW))
                self.assertEqual(self.report("claude", dict(record, steppedAt=NOW))["next"],
                                 record["next"] if not record["pending"] else record["pending"] + 300)

    def test_malformed_records_read_as_blank_parts(self):
        blank = usage.blank_record()
        for raw, expected in (
                ("x", blank), ({"state": "dancing"}, blank), ({"state": "failed"}, blank),
                ({"state": "confirming", "at": NOW}, dict(blank, at=NOW)),
                ({"state": "failed", "reason": "boom"}, blank), ({"next": "soon", "uncertain": -1}, blank),
                ({"next": 1.5, "pending": True}, blank),
                ({"state": "retrying", "sentAt": NOW, "uncertain": 1}, dict(blank, state="retrying", sentAt=NOW,
                                                                            uncertain=1))):
            with self.subTest(raw=raw):
                self.assertEqual(usage.record_from(raw), expected)
        usage.STATE_DIR.mkdir(parents=True)
        usage.STARTER_STATE.write_text("{broken")
        self.assertEqual(usage.read_starter_states(), {})

    def test_fake_reports_carry_their_starters_and_default_to_off(self):
        with mock.patch.dict(os.environ, {"RINGSIDE_USAGE_FAKE": str(FIXTURES / "fake_report.json")}):
            providers = self.run_main("--starter-set", "claude=on", "--start")["providers"]
        expected = json.loads((FIXTURES / "fake_report.json").read_text())["providers"]
        self.assertEqual(providers["claude"]["starter"], expected["claude"]["starter"])
        self.assertEqual(providers["codex"]["starter"], expected["codex"]["starter"])
        self.assertFalse(usage.STARTER_FILE.exists())
        bare = self.tmp / "bare.json"
        bare.write_text(json.dumps({"fetchedAt": 1, "providers": {"codex": {"status": "signed_out"}}}))
        with mock.patch.dict(os.environ, {"RINGSIDE_USAGE_FAKE": str(bare)}):
            self.assertEqual(self.run_main()["providers"]["codex"]["starter"], OFF)

    def test_the_script_takes_the_new_flags(self):
        env = dict(os.environ, RINGSIDE_USAGE_FAKE=str(FIXTURES / "fake_report.json"))
        run = subprocess.run([sys.executable, usage.__file__, "--providers", "codex", "--start",
                              "--starter-set", "codex=on"], env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("starter", json.loads(run.stdout)["providers"]["codex"])


class Session(Isolated):
    def test_claude_reports_its_five_hour_window(self):
        body = json.loads((FIXTURES / "claude_usage.json").read_text())
        body["five_hour"] = None
        self.assertIsNone(usage.parse_claude(body)["session"])
        body["five_hour"] = {"utilization": 12.4, "resets_at": "2026-09-02T02:00:00.512345+00:00"}
        self.assertEqual(usage.parse_claude(body)["session"],
                         {"percent": 12, "resetsAt": 1788314400, "windowSeconds": SESSION})
        body["five_hour"] = {"utilization": 0, "resets_at": None}
        self.assertEqual(usage.parse_claude(body)["session"]["resetsAt"], None)

    # Only an explicit null, or 0% with no reset, says no session runs.
    def test_a_missing_or_malformed_five_hour_leaves_the_session_unknown(self):
        body = json.loads((FIXTURES / "claude_usage.json").read_text())
        self.assertNotIn("five_hour", body)
        self.assertNotIn("session", usage.parse_claude(body))
        for five_hour in ("soon", [], 12, {"utilization": 40}, {"utilization": "40", "resets_at": None},
                          {"utilization": True, "resets_at": "2026-09-02T02:00:00Z"},
                          {"utilization": 40, "resets_at": None}, {"utilization": 0, "resets_at": "soon"}):
            with self.subTest(five_hour=five_hour):
                body["five_hour"] = five_hour
                reading = usage.parse_claude(body)
                self.assertNotIn("session", reading)
                self.assertEqual(reading["weekly"]["percent"], 62)

    def test_a_reading_that_cant_tell_a_session_is_a_failed_read(self):
        fetch = mock.Mock(return_value={"weekly": week(5, NOW + 86400), "scoped": []})
        with mock.patch.object(usage, "claude_usage", fetch), usage.locked(), self.assertRaises(usage.Unreadable):
            usage.starter_read("claude", NOW, None)
        fetch.assert_called_once()

    def test_a_malformed_cached_session_reads_as_no_reading(self):
        entry = dict(claude(NOW - 10), session={"percent": "x"})
        self.write_cache({"claude": entry})
        fetch = mock.Mock(return_value={"weekly": week(1, NOW + 86400), "scoped": [], "session": None})
        self.assertEqual(usage.collect({"claude": fetch}, NOW)["claude"]["status"], "ok")
        fetch.assert_called_once()


if __name__ == "__main__":
    unittest.main()
