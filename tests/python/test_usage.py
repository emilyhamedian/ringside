# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import contextlib
import email.message
import email.utils
import errno
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
# What every entry says of its session starter while it is switched off.
OFF = {"enabled": False, "state": "off", "at": None, "next": None, "reason": None}
# What every entry says of its program when none is chosen or found.
NOT_FOUND = {"path": "", "chosen": False, "problem": ""}


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
    network call or CLI run, so no test reaches the real ~/.claude, ~/.codex,
    cache, config, state, API or CLIs."""

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.tmp = Path(folder.name)
        (self.tmp / "home").mkdir()
        self.enterContext(mock.patch.dict(os.environ, {
            "HOME": str(self.tmp / "home"),
            "XDG_CACHE_HOME": str(self.tmp / "cache"),
            "XDG_CONFIG_HOME": str(self.tmp / "config"),
            "XDG_STATE_HOME": str(self.tmp / "state"),
            "CLAUDE_CONFIG_DIR": str(self.tmp / "claude"),
            "CODEX_HOME": str(self.tmp / "codex"),
        }))
        paths = load_helper()
        self.enterContext(mock.patch.multiple(usage, **{name: getattr(paths, name) for name in (
            "CLAUDE_CREDENTIALS", "CODEX_AUTH", "CACHE_DIR", "CACHE_FILE", "HISTORY_FILE",
            "LOCK_FILE", "APPLETSRC", "STARTER_FILE", "STATE_DIR", "STARTER_STATE", "SWITCH_LOCK",
            "WORK_DIR", "CODEX_MODEL_CACHE")}))
        self.enterContext(mock.patch.object(usage.urllib.request, "urlopen",
                                            side_effect=AssertionError("a test reached the network")))
        self.enterContext(mock.patch.object(usage, "run_cli", side_effect=AssertionError("a test ran a CLI")))
        self.enterContext(mock.patch.object(usage, "find_cli", return_value=("", "")))
        self.enterContext(mock.patch.dict(usage.PROGRAMS, clear=True))

    def write_cache(self, data):
        usage.CACHE_DIR.mkdir(parents=True, exist_ok=True)
        usage.CACHE_FILE.write_text(json.dumps(data))

    def run_main(self, *argv):
        """main() as a fresh process would run it: with no events and no
        programs left from an earlier run."""
        usage.EVENTS.clear()
        usage.PROGRAMS.clear()
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

    # 1e999 is valid JSON that parses to infinity; read as 0% it would pass
    # for an idle week.
    def test_a_week_without_its_share_is_an_error(self):
        for used in (None, "soon", "absent", json.loads("1e999"), float("-inf"), float("nan")):
            with self.subTest(used=used):
                result = fixture("codex_rate_limits.json")
                week = result["rateLimitsByLimitId"]["codex"]["primary"]
                if used == "absent":
                    del week["usedPercent"]
                else:
                    week["usedPercent"] = used
                with self.assertRaises(RuntimeError):
                    usage.parse_codex(result)

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

    def test_only_weekly_scoped_entries_count(self):
        usage_body = fixture("claude_usage.json")
        fable = usage_body["limits"][2]
        opus = {"model": {"id": None, "display_name": "Opus"}, "surface": None}
        usage_body["limits"] = [dict(fable, kind=kind, scope=opus, percent=40)
                                for kind in ("session", "weekly_all", "weekly", "five_hour", None)] + [fable]
        scoped = usage.parse_claude(usage_body)["scoped"]
        self.assertEqual([(s["id"], s["percent"]) for s in scoped], [("Fable", 78)])

    def test_scoped_is_keyed_by_display_name_even_with_a_model_id(self):
        usage_body = fixture("claude_usage.json")
        usage_body["limits"][2]["scope"]["model"]["id"] = "claude-fable-5"
        scoped = usage.parse_claude(usage_body)["scoped"]
        self.assertEqual([(s["id"], s["label"]) for s in scoped], [("Fable", "Fable"), ("Opus", "Opus")])

    # An empty, null or missing limits list: the weekly window stands alone.
    def test_scoped_is_empty_when_not_reported(self):
        for limits in ([], None, "absent"):
            with self.subTest(limits=limits):
                usage_body = fixture("claude_usage.json")
                if limits == "absent":
                    del usage_body["limits"]
                else:
                    usage_body["limits"] = limits
                report = usage.parse_claude(usage_body)
                self.assertEqual((report["weekly"]["percent"], report["scoped"]), (62, []))

    # Read as 0%, it would let the starter send past a reached weekly limit.
    def test_a_weekly_window_without_its_share_is_an_error(self):
        for utilization in (None, "soon", "absent", json.loads("1e999"), float("-inf"), float("nan")):
            with self.subTest(utilization=utilization):
                usage_body = fixture("claude_usage.json")
                if utilization == "absent":
                    del usage_body["seven_day"]["utilization"]
                else:
                    usage_body["seven_day"]["utilization"] = utilization
                with self.assertRaises(RuntimeError):
                    usage.parse_claude(usage_body)

    def test_missing_weekly_is_an_error(self):
        with self.assertRaises(RuntimeError):
            usage.parse_claude({"five_hour": {"utilization": 1}})


class Conversions(Isolated):
    # Half rounds up, as the widget's Math.round does. Anything else reads
    # as 0 for a scoped window, which is only shown; the parsers reject it
    # for a share the starter acts on.
    def test_percent_is_clamped_and_rounded_half_up(self):
        for value, percent in ((101.2, 100), (-3, 0), (62.5, 63), (61.5, 62), (0.5, 1), ("34.4", 34), (None, 0),
                               ("soon", 0), (float("inf"), 0), (float("-inf"), 0), (float("nan"), 0)):
            with self.subTest(value=value):
                self.assertEqual(usage.clamp_percent(value), percent)
        usage_body = fixture("claude_usage.json")
        usage_body["limits"][2]["percent"] = json.loads("1e999")
        self.assertEqual([s["percent"] for s in usage.parse_claude(usage_body)["scoped"]], [0, 9])

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
        usage.store_claude(self.path, "r1", self.fresh)
        stored = json.loads(self.path.read_text())
        self.assertEqual(stored["claudeAiOauth"], self.fresh)
        self.assertEqual(stored["mcpOAuth"], {"keep": "me"})
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(os.listdir(self.folder), [".credentials.json"])

    def test_keeps_file_when_cli_rotated_first(self):
        usage.store_claude(self.path, "stale", self.fresh)
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

    # After the refresh POST the old token is spent: whatever the reply looks
    # like, the new pair must reach the file. Each lifetime is tried in
    # each field on its own, with the other field sound. 1e308 seconds is a
    # finite number that overflows once in milliseconds; a lifetime that
    # can't be read leaves the access token expired at once and the refresh
    # token's end unknown.
    def test_odd_lifetimes_still_save_the_new_pair(self):
        stored_as = {"expires_in": "expiresAt", "refresh_token_expires_in": "refreshTokenExpiresAt"}
        for field in stored_as:
            for lifetime in ("3600.0", "soon", None, -5, float("nan"), 1e308, json.loads("1e999")):
                with self.subTest(field=field, lifetime=lifetime):
                    self.setUp()
                    self.http.return_value = {"access_token": "new", "refresh_token": "r2", "expires_in": 3600,
                                              "refresh_token_expires_in": 3600, "scope": ["not", "a", "string"],
                                              field: lifetime}
                    before = int(time.time() * 1000)
                    self.assertEqual(usage.claude_access_token(), "new")
                    stored = json.loads(self.path.read_text())["claudeAiOauth"]
                    self.assertEqual((stored["accessToken"], stored["refreshToken"]), ("new", "r2"))
                    other = next(key for name, key in stored_as.items() if name != field)
                    self.assertGreaterEqual(stored[other], before + 3600 * 1000)
                    if lifetime == "3600.0":
                        self.assertGreaterEqual(stored[stored_as[field]], before + 3600 * 1000)
                    elif field == "expires_in":
                        self.assertLessEqual(stored["expiresAt"], int(time.time() * 1000))
                    else:
                        self.assertNotIn("refreshTokenExpiresAt", stored)
                    self.doCleanups()

    def test_a_file_caught_mid_write_is_read_again(self):
        real = Path.read_bytes
        reads = []

        def read_bytes(path):
            reads.append(path)
            return b'{"claudeAiOauth": {"acc' if len(reads) == 1 else real(path)

        with mock.patch.object(Path, "read_bytes", read_bytes):
            usage.store_claude(self.path, "r1", self.fresh)
        self.assertEqual(json.loads(self.path.read_text())["claudeAiOauth"]["refreshToken"], "r2")

    def test_a_write_racing_the_replace_is_not_overwritten(self):
        real = Path.read_bytes
        reads = []

        def read_bytes(path):
            reads.append(path)
            if len(reads) == 2:
                # Claude Code renews between this run's read and its replace.
                path.write_text(json.dumps({"claudeAiOauth": {"accessToken": "cli", "refreshToken": "r9"}}))
            return real(path)

        with mock.patch.object(Path, "read_bytes", read_bytes):
            usage.store_claude(self.path, "r1", self.fresh)
        self.assertEqual(json.loads(self.path.read_text())["claudeAiOauth"]["refreshToken"], "r9")
        self.assertEqual(os.listdir(self.folder), [".credentials.json"])

    def test_record_fields_the_refresh_doesnt_touch_are_kept(self):
        data = json.loads(self.path.read_text())
        data["claudeAiOauth"]["subscriptionType"] = "max"
        self.path.write_text(json.dumps(data))
        usage.claude_access_token()
        self.assertEqual(json.loads(self.path.read_text())["claudeAiOauth"]["subscriptionType"], "max")

    # Each of these would lose the renewed pair after the POST, so the check
    # before it must catch them and spend nothing.
    def test_a_file_that_couldnt_be_replaced_spends_no_refresh_token(self):
        real_access = os.access
        cases = {
            "read-only or immutable file": mock.patch.object(
                usage.os, "access", lambda p, mode: False if Path(p) == self.path.resolve() else real_access(p, mode)),
            "full disk": mock.patch.object(
                usage.os, "write", lambda fd, data: (_ for _ in ()).throw(OSError(28, "No space left on device"))),
        }
        for name, patch in cases.items():
            with self.subTest(name), patch, self.assertRaises(RuntimeError):
                usage.claude_access_token()
            self.http.assert_not_called()
        self.assertEqual(json.loads(self.path.read_text())["claudeAiOauth"]["refreshToken"], "r1")
        self.assertEqual(os.listdir(self.folder), [".credentials.json"])

    # write(2) takes only part of the data when the disk is nearly full: the
    # rest must be written, or the write must fail and leave the file whole.
    def test_short_writes_never_leave_a_truncated_file(self):
        real_write = os.write

        def filling(whole):
            """os.write on a disk with room for `whole` writes and half the next."""
            calls = []

            def write(fd, data):
                calls.append(fd)
                if len(calls) > whole + 1:
                    raise OSError(errno.ENOSPC, "No space left on device")
                return real_write(fd, data if len(calls) <= whole else data[:len(data) // 2])

            return mock.patch.object(usage.os, "write", write)

        # The probe stops short, so nothing is spent; then the probe fits but
        # the renewed file stops short.
        for whole, error, posts in ((0, "can't take a new file", 0), (1, "couldn't be saved", 1)):
            with self.subTest(whole=whole):
                self.http.reset_mock()
                with filling(whole), self.assertRaisesRegex(RuntimeError, error):
                    usage.claude_access_token()
                self.assertEqual(self.http.call_count, posts)
                self.assertEqual(json.loads(self.path.read_text())["claudeAiOauth"]["refreshToken"], "r1")
                self.assertEqual(os.listdir(self.folder), [".credentials.json"])
        with mock.patch.object(usage.os, "write", lambda fd, data: real_write(fd, data[:64])):
            self.assertEqual(usage.claude_access_token(), "new")
        stored = json.loads(self.path.read_text())
        self.assertEqual(stored["claudeAiOauth"]["refreshToken"], "r2")
        self.assertEqual(stored["mcpOAuth"], {"keep": "me"})

    # A bind-mounted file, or one in a sticky folder, can't be replaced but
    # can be rewritten.
    def test_a_file_that_cant_be_replaced_is_rewritten_in_place(self):
        with mock.patch.object(usage.os, "replace", side_effect=OSError(16, "Device or resource busy")):
            self.assertEqual(usage.claude_access_token(), "new")
        stored = json.loads(self.path.read_text())
        self.assertEqual(stored["claudeAiOauth"]["refreshToken"], "r2")
        self.assertEqual(stored["mcpOAuth"], {"keep": "me"})
        self.assertEqual(os.listdir(self.folder), [".credentials.json"])

    # Once the replace has succeeded, a folder that can't be synced is no
    # reason to rewrite the file in place.
    def test_a_folder_that_cant_be_synced_after_the_replace_is_left_alone(self):
        real_os_open, real_open = os.open, open

        def no_folder_fd(path, flags, *args):
            if flags & os.O_DIRECTORY:
                raise PermissionError(13, "Permission denied")
            return real_os_open(path, flags, *args)

        def refuse_rewrite(file, mode="r", *args, **kwargs):
            if mode == "r+b":
                raise AssertionError("rewrote in place after a successful replace")
            return real_open(file, mode, *args, **kwargs)

        with mock.patch.object(usage.os, "open", no_folder_fd), mock.patch("builtins.open", refuse_rewrite):
            usage.store_claude(self.path, "r1", self.fresh)
        self.assertEqual(json.loads(self.path.read_text())["claudeAiOauth"]["refreshToken"], "r2")
        self.assertEqual(os.listdir(self.folder), [".credentials.json"])

    def test_when_nothing_can_be_written_the_new_pair_is_kept_beside_it(self):
        real_open = open

        def refuse_rewrite(file, mode="r", *args, **kwargs):
            if mode == "r+b":
                raise PermissionError(1, "Operation not permitted")
            return real_open(file, mode, *args, **kwargs)

        with mock.patch.object(usage.os, "replace", side_effect=OSError(16, "Device or resource busy")), \
                mock.patch("builtins.open", refuse_rewrite), \
                self.assertRaisesRegex(RuntimeError, r"it is in \.credentials\.\w+\.tmp beside"):
            usage.claude_access_token()
        kept = [name for name in os.listdir(self.folder) if name.endswith(".tmp")]
        self.assertEqual(len(kept), 1)
        self.assertEqual(json.loads((self.folder / kept[0]).read_text())["claudeAiOauth"]["refreshToken"], "r2")
        self.assertEqual(stat.S_IMODE((self.folder / kept[0]).stat().st_mode), 0o600)

    def test_a_reply_without_a_usable_access_token_keeps_its_refresh_token(self):
        self.http.return_value = {"access_token": "A2 x", "refresh_token": "r2", "expires_in": 3600}
        with self.assertRaisesRegex(RuntimeError, "no usable access token"):
            usage.claude_access_token()
        record = json.loads(self.path.read_text())["claudeAiOauth"]
        self.assertEqual((record["accessToken"], record["refreshToken"], record["expiresAt"]), ("old", "r2", 0))

    def test_after_a_failed_refresh_a_login_renewed_meanwhile_is_used(self):
        def renewed_elsewhere(*args):
            self.path.write_text(json.dumps({"claudeAiOauth": {
                "accessToken": "cli", "refreshToken": "r9", "expiresAt": (time.time() + 3600) * 1000}}))
            raise RuntimeError("HTTP 400 from platform.claude.com")

        self.http.side_effect = renewed_elsewhere
        self.assertEqual(usage.claude_access_token(), "cli")

    def test_a_token_that_would_break_a_header_counts_as_signed_out(self):
        secret = "sk-ant-oat01-SECRETVALUE"
        self.path.write_text(json.dumps({"claudeAiOauth": {
            "accessToken": secret + "\n", "refreshToken": "r1", "expiresAt": (time.time() + 3600) * 1000}}))
        report = usage.poll(usage.claude_usage)
        self.assertEqual(report, {"status": "signed_out"})
        self.http.assert_not_called()

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
        for reason, words, kind in ((socket.gaierror(-2, "Name or service not known"), "Name or service not known", "offline"),
                                    (ConnectionRefusedError(111, "Connection refused"), "Connection refused", "offline"),
                                    (TimeoutError("timed out"), "timed out", "timeout")):
            with self.subTest(words):
                self.assertEqual(self.poll_raising(urllib.error.URLError(reason)),
                                 {"status": "error", "message": f"can't reach example.test: {words}",
                                  "reason": kind, "host": "example.test"})

    # A reply that stalls part-way, or a connection dropped in the middle.
    def test_a_failure_while_reading_names_its_host(self):
        for error, words, kind in ((TimeoutError(), "timed out", "timeout"),
                                   (ConnectionResetError(104, "Connection reset by peer"), "Connection reset by peer",
                                    "offline")):
            with self.subTest(kind):
                self.assertEqual(self.poll_raising(error),
                                 {"status": "error", "message": f"can't reach example.test: {words}",
                                  "reason": kind, "host": "example.test"})

    def test_an_unreadable_reply_is_the_servers(self):
        with mock.patch.object(usage.urllib.request, "urlopen") as urlopen:
            urlopen.return_value.__enter__.return_value.read.return_value = b"<html>"
            self.assertEqual(usage.poll(lambda: usage.http_json("https://example.test/x", {})),
                             {"status": "error", "message": "unreadable reply from example.test",
                              "reason": "server", "host": "example.test"})

    def test_http_errors_are_not_mistaken_for_unreachable_hosts(self):
        busy, down = http_error(429, "120"), http_error(503)
        self.addCleanup(busy.close)
        self.addCleanup(down.close)
        self.assertEqual(self.poll_raising(busy),
                         {"status": "rate_limited", "retryAfter": 120,
                          "message": "rate limited, retrying in 120 s", "reason": "rate-limited", "host": "example.test"})
        self.assertEqual(self.poll_raising(down), {"status": "error", "message": "HTTP 503 from example.test",
                                                   "reason": "server", "host": "example.test",
                                                   "httpStatus": 503})

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
    # The CLIs' config homes and the cache follow their variables, read as
    # the module loads; unset or empty, they sit under the home folder.
    def test_follow_the_environment_or_default_to_home(self):
        home = Path.home()
        for case, env, claude, codex, cache in (
                ("set", {"CLAUDE_CONFIG_DIR": "/cfg/claude", "CODEX_HOME": "/cfg/codex", "XDG_CACHE_HOME": "/cfg/cache"},
                 Path("/cfg/claude"), Path("/cfg/codex"), Path("/cfg/cache/ringside")),
                ("empty", {"CLAUDE_CONFIG_DIR": "", "CODEX_HOME": "", "XDG_CACHE_HOME": ""},
                 home / ".claude", home / ".codex", home / ".cache" / "ringside"),
                ("unset", None, home / ".claude", home / ".codex", home / ".cache" / "ringside")):
            with self.subTest(case), mock.patch.dict(os.environ, env or {}):
                if env is None:
                    for key in ("CLAUDE_CONFIG_DIR", "CODEX_HOME", "XDG_CACHE_HOME"):
                        os.environ.pop(key, None)
                helper = load_helper()
            self.assertEqual(helper.CLAUDE_CREDENTIALS, claude / ".credentials.json")
            self.assertEqual(helper.CODEX_AUTH, codex / "auth.json")
            self.assertEqual((helper.CACHE_DIR, helper.CACHE_FILE, helper.HISTORY_FILE, helper.LOCK_FILE),
                             (cache, cache / "usage.json", cache / "usage-history.json", cache / "usage.lock"))


class CodexAppServer(Isolated):
    def server(self, body):
        path = self.tmp / "fake-codex"
        path.write_text(body)
        path.chmod(0o700)
        return str(path)

    # The fake checks how it was started and each message as it arrives,
    # and answers only once all of it is right; otherwise its error names
    # what was wrong. The answer to initialize and a notification come
    # before the answer, to be passed over.
    def test_reads_the_answer_to_the_rate_limit_request(self):
        binary = self.server("#!" + sys.executable + """
import json, sys

def answer(reply):
    print(json.dumps(reply), flush=True)

def expect(ok, what):
    if not ok:
        answer({"id": 2, "error": {"message": what}})
        sys.exit(0)

first = json.loads(sys.stdin.readline())
expect(sys.argv[1:] == ["app-server", "--stdio"], "started with " + json.dumps(sys.argv[1:]))
info = (first.get("params") or {}).get("clientInfo") or {}
expect(first.get("id") == 1 and first.get("method") == "initialize", "first message " + json.dumps(first))
expect(info.get("name") == "ringside" and info.get("title") == "Ringside" and isinstance(info.get("version"), str),
       "clientInfo " + json.dumps(info))
answer({"id": 1, "result": {"clientVersion": "not the answer"}})
second = json.loads(sys.stdin.readline())
expect(second == {"method": "initialized"}, "second message " + json.dumps(second))
third = json.loads(sys.stdin.readline())
expect(third == {"id": 2, "method": "account/rateLimits/read"}, "third message " + json.dumps(third))
answer({"method": "account/updated", "params": {}})
answer({"id": 2, "result": {"clientVersion": info["version"]}})
""")
        self.assertEqual(usage.codex_rate_limits(binary), {"clientVersion": usage.VERSION})

    def test_an_error_reply_carries_its_message_and_code(self):
        for error, expected in (({"code": -32001, "message": "Not logged in"}, ("Not logged in", -32001)),
                                ({"message": "no"}, ("no", None)), ({"code": "7"}, ("app-server error", None)),
                                (None, ("app-server error", None))):
            with self.subTest(error=error):
                binary = self.server(f"#!/bin/sh\necho '{json.dumps({'id': 2, 'error': error})}'\n")
                with self.assertRaises(usage.AppServerError) as caught:
                    usage.codex_rate_limits(binary)
                self.assertEqual((str(caught.exception), caught.exception.code), expected)

    def test_deadline_ends_what_the_server_started(self):
        # The child keeps stdout open, so the read only ends once it is killed too.
        binary = self.server("#!/bin/sh\nsleep 30 &\nwait\n")
        start = time.monotonic()
        with mock.patch.object(usage, "ANSWER_TIMEOUT", 0.5), \
                self.assertRaisesRegex(RuntimeError, r"^no answer from codex app-server in 0\.5 s$") as caught:
            usage.codex_rate_limits(binary)
        self.assertLess(time.monotonic() - start, 10)
        self.assertEqual((caught.exception.reason, caught.exception.host), ("timeout", ""))

    # A process the server starts in a session of its own survives the kill
    # and keeps stdout open; the deadline still holds.
    def test_deadline_holds_when_a_survivor_keeps_stdout_open(self):
        binary = self.server("#!/bin/sh\nsetsid sleep 8 &\nexit 0\n")
        start = time.monotonic()
        with mock.patch.object(usage, "ANSWER_TIMEOUT", 1), \
                self.assertRaisesRegex(RuntimeError, r"^no answer from codex app-server in 1 s$"):
            usage.codex_rate_limits(binary)
        self.assertLess(time.monotonic() - start, 4)

    def test_early_close_is_not_a_timeout(self):
        binary = self.server("#!/bin/sh\nexec >&-\nsleep 30\n")
        with self.assertRaisesRegex(RuntimeError, "^app-server closed without answering$") as caught:
            usage.codex_rate_limits(binary)
        self.assertFalse(hasattr(caught.exception, "reason"))

    # A program that can't start (a wrapper the kernel can't run) or that
    # quits before reading its input (one that hands off to a container
    # runtime and exits) is the program's fault: a chosen one's, else the
    # installation's.
    def test_a_program_that_cant_run_or_quits_at_once_is_the_programs_fault(self):
        no_exec = self.server("not a program\n")
        gone = mock.Mock()
        gone.stdin.write.side_effect = BrokenPipeError(errno.EPIPE, "Broken pipe")
        for chosen, reason in (("", "not-installed"), ("/opt/codex", "program")):
            usage.PROGRAMS["codex"] = chosen
            with self.subTest(chosen=chosen, fault="exec"), self.assertRaises(usage.CheckFailed) as caught:
                usage.codex_rate_limits(no_exec)
            self.assertEqual((caught.exception.reason, str(caught.exception)),
                             (reason, "can't run the codex CLI: Exec format error"))
            with self.subTest(chosen=chosen, fault="pipe"), \
                    mock.patch.object(usage.subprocess, "Popen", return_value=gone), \
                    mock.patch.object(usage, "stop_session"), self.assertRaises(usage.CheckFailed) as caught:
                usage.codex_rate_limits("/opt/codex")
            self.assertEqual((caught.exception.reason, str(caught.exception)),
                             (reason, "the codex CLI quit before answering: Broken pipe"))


class Polling(Isolated):
    # Only the helper's own messages are passed on: anything else could carry
    # a request's details, a token among them.
    def test_unexpected_errors_report_only_their_type(self):
        self.assertEqual(usage.poll(mock.Mock(side_effect=ValueError("Invalid header value b'Bearer secret'"))),
                         {"status": "error", "message": "unexpected ValueError", "reason": "other", "host": ""})

    def test_statuses_come_from_exceptions(self):
        self.assertEqual(usage.poll(lambda: {"weekly": {}}), {"weekly": {}, "status": "ok"})
        self.assertEqual(usage.poll(mock.Mock(side_effect=usage.SignedOut())),
                         {"status": "signed_out"})
        self.assertEqual(usage.poll(mock.Mock(side_effect=usage.RateLimited(90))),
                         {"status": "rate_limited", "retryAfter": 90,
                          "message": "rate limited, retrying in 90 s", "reason": "rate-limited", "host": ""})
        self.assertEqual(usage.poll(mock.Mock(side_effect=RuntimeError("boom"))),
                         {"status": "error", "message": "boom", "reason": "other", "host": ""})
        self.assertEqual(usage.poll(mock.Mock(side_effect=usage.CheckFailed("HTTP 502 from a.test", "server", "a.test"))),
                         {"status": "error", "message": "HTTP 502 from a.test", "reason": "server", "host": "a.test"})

    def test_missing_codex_cli_says_so(self):
        with mock.patch.object(usage, "CODEX_AUTH", Path(__file__)):
            self.assertEqual(usage.poll(usage.codex_usage),
                             {"status": "error", "message": "codex CLI not found", "reason": "not-installed", "host": ""})

    # Only an app-server error that says the login is missing reads as a
    # sign-out; one that merely mentions an authority, or any other
    # failure, stays an error. The journal gets the error's code, never
    # its message.
    def test_only_a_missing_codex_login_reads_as_signed_out(self):
        for error, report, code in (
                (usage.AppServerError("Not logged in", -32001), {"status": "signed_out"}, -32001),
                (usage.AppServerError("unauthorized"), {"status": "signed_out"}, "none"),
                (usage.AppServerError("the authority service is unreachable", 7),
                 {"status": "error", "message": "the authority service is unreachable", "reason": "other", "host": ""},
                 7),
                (RuntimeError("app-server closed without answering"),
                 {"status": "error", "message": "app-server closed without answering", "reason": "other", "host": ""},
                 None)):
            with self.subTest(str(error)), \
                    mock.patch.object(usage, "CODEX_AUTH", Path(__file__)), \
                    mock.patch.object(usage, "find_cli", return_value=("codex", "")), \
                    mock.patch.object(usage, "codex_rate_limits", side_effect=error):
                usage.EVENTS.clear()
                self.assertEqual(usage.poll(usage.codex_usage), report)
                noted = [e for e in usage.EVENTS if e["kind"] == "cli-error"]
                self.assertEqual([e["message"] for e in noted],
                                 [] if code is None else [f"Codex: app-server answered with an error, code {code}"])
                self.assertTrue(all(e["level"] == "debug" for e in noted))


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

    # A failure or a sign-out stands for five minutes like a reading, so a
    # second widget or a restart doesn't ask again before then.
    # A replay gives the reason, the host and the end of the hold as the
    # failure did.
    def test_errors_and_sign_outs_are_replayed_for_five_minutes(self):
        for name, failure, report in (
                ("claude", usage.CheckFailed("HTTP 500 from api.anthropic.com", "server", "api.anthropic.com"),
                 {"status": "error", "message": "HTTP 500 from api.anthropic.com", "reason": "server",
                  "host": "api.anthropic.com", "retryAt": 1300}),
                ("codex", usage.SignedOut(), {"status": "signed_out"})):
            with self.subTest(report["status"]):
                self.assertEqual(self.collect(1000, **{name: mock.Mock(side_effect=failure)})[name], report)
                again = mock.Mock(return_value=reading(3, 5))
                self.assertEqual(self.collect(1000 + 299, **{name: again})[name], report)
                again.assert_not_called()
                self.assertEqual(self.collect(1000 + 300, **{name: again})[name]["status"], "ok")
                again.assert_called_once()

    # Two widgets, or a widget and a restart, a moment apart.
    def test_runs_in_quick_succession_after_a_failure_poll_once(self):
        failed = {"status": "error", "message": "HTTP 500 from api.anthropic.com", "reason": "other", "host": ""}
        with mock.patch.object(usage, "claude_usage", side_effect=RuntimeError(failed["message"])) as claude:
            reports = [self.run_main("--providers", "claude")["providers"] for _ in range(2)]
        claude.assert_called_once()
        retry = reports[0]["claude"]["retryAt"]
        self.assertLessEqual(abs(retry - (time.time() + usage.CACHE_TTL)), 5)
        self.assertEqual(reports, [{"claude": dict(failed, retryAt=retry, starter=OFF, program=NOT_FOUND)}] * 2)

    # A refusal holds the provider back for every run until Retry-After has
    # passed, and only that provider.
    def test_a_rate_limit_holds_until_retry_after(self):
        refused = mock.Mock(side_effect=usage.RateLimited(600, "a.test"))
        held = {"status": "rate_limited", "reason": "rate-limited", "host": "a.test", "retryAt": 1600}
        self.assertEqual(self.collect(1000, codex=refused)["codex"],
                         dict(held, retryAfter=600, message="rate limited, retrying in 600 s"))
        again = mock.Mock(return_value=reading(3, 5))
        self.assertEqual(self.collect(1400, codex=again)["codex"],
                         dict(held, retryAfter=200, message="rate limited, retrying in 200 s"))
        again.assert_not_called()
        other = mock.Mock(return_value=reading(7, 5))
        self.assertEqual(self.collect(1400, claude=other)["claude"]["status"], "ok")
        self.assertEqual(self.collect(1600, codex=again)["codex"]["status"], "ok")
        again.assert_called_once()

    def test_a_short_rate_limit_still_holds_for_five_minutes(self):
        self.assertEqual(self.collect(1000, codex=mock.Mock(side_effect=usage.RateLimited(60)))["codex"],
                         {"status": "rate_limited", "retryAfter": 300, "message": "rate limited, retrying in 300 s",
                          "reason": "rate-limited", "host": "", "retryAt": 1300})
        again = mock.Mock(return_value=reading(3, 5))
        self.assertEqual(self.collect(1000 + 299, codex=again)["codex"]["retryAfter"], 1)
        self.assertEqual(self.collect(1000 + 299, codex=again)["codex"]["retryAt"], 1300)
        again.assert_not_called()
        self.assertEqual(self.collect(1000 + 300, codex=again)["codex"]["status"], "ok")

    # After the clock steps back, a hold ends its own length later, not the
    # step's length on top.
    def test_a_hold_ends_on_time_after_a_clock_step(self):
        step = 1000 - 7200
        for failure, length, report in (
                (usage.RateLimited(600), 600,
                 {"status": "rate_limited", "retryAfter": 600, "message": "rate limited, retrying in 600 s",
                  "reason": "rate-limited", "host": "", "retryAt": step + 600}),
                (RuntimeError("down"), 300,
                 {"status": "error", "message": "down", "reason": "other", "host": "", "retryAt": step + 300})):
            with self.subTest(report["status"]):
                usage.CACHE_FILE.unlink(missing_ok=True)
                self.collect(1000, codex=mock.Mock(side_effect=failure))
                again = mock.Mock(return_value=reading(3, 5))
                self.assertEqual(self.collect(step, codex=again)["codex"], report)
                self.assertEqual(self.cached()["codex"]["heldUntil"], step + length)
                self.assertEqual(self.collect(step + length - 1, codex=again)["codex"]["status"], report["status"])
                again.assert_not_called()
                self.assertEqual(self.collect(step + length, codex=again)["codex"]["status"], "ok")

    # A reading from before the clock stepped back is ahead of now; it is
    # served for five minutes from the step, not polled again at once.
    def test_a_reading_from_before_a_clock_step_keeps_the_floor(self):
        fetch = mock.Mock(return_value=reading(3, 5))
        self.collect(1000, codex=fetch)
        self.collect(1060, codex=fetch)
        step = 1000 - 600
        self.assertEqual(self.collect(step, codex=fetch)["codex"]["fetchedAt"], step)
        self.assertEqual(self.cached()["codex"]["fetchedAt"], step)
        self.collect(step + 299, codex=fetch)
        fetch.assert_called_once()
        self.collect(step + 300, codex=fetch)
        self.assertEqual(fetch.call_count, 2)

    def test_a_hold_never_lasts_more_than_a_day(self):
        self.assertEqual(self.collect(1000, codex=mock.Mock(side_effect=usage.RateLimited(10 ** 9)))["codex"]["retryAfter"],
                         usage.HOLD_MAX)
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
        self.assertEqual(self.cached(), {"claude": stale, "codex": {
            "status": "error", "message": "down", "heldUntil": 2300, "holdSeconds": 300, "reason": "other", "host": ""}})

    def test_a_cached_entry_keeps_the_time_it_was_polled(self):
        polled_at = int(time.time()) - 100
        self.write_cache({"claude": dict(self.good, fetchedAt=polled_at)})
        with mock.patch.object(usage, "claude_usage") as claude:
            report = self.run_main("--providers", "claude")
        claude.assert_not_called()
        self.assertEqual(report["providers"]["claude"]["fetchedAt"], polled_at)
        self.assertGreaterEqual(report["fetchedAt"], polled_at + 100)

    # A run stuck holding the lock mustn't stall every widget for good.
    def test_a_run_gives_up_on_a_lock_held_too_long(self):
        usage.CACHE_DIR.mkdir(parents=True, exist_ok=True)
        fd = os.open(usage.LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX)
        fetch = mock.Mock(return_value=reading(1, 5))
        with mock.patch.object(usage, "LOCK_WAIT", 0.3), mock.patch.object(usage, "codex_usage", fetch):
            report = self.run_main("--providers", "codex")
        self.assertEqual(report["providers"], {"codex": {"status": "error", "starter": OFF, "program": NOT_FOUND,
                                                         "message": "another usage check is still running",
                                                         "reason": "busy", "host": "",
                                                         "retryAt": report["fetchedAt"]}})
        fetch.assert_not_called()

    # A run that can't get the lock still reports what the cache holds: a
    # fresh reading, or a held failure with its hold's end, as a run with
    # the lock would; of the rest it says the lock was busy and nothing
    # holds them back.
    def test_a_busy_run_reports_what_the_cache_holds(self):
        now = int(time.time())
        fresh = dict(reading(4, now + 3600), status="ok", fetchedAt=now)
        busy = {"status": "error", "message": "another usage check is still running", "starter": OFF,
                "program": NOT_FOUND, "reason": "busy", "host": ""}
        usage.CACHE_DIR.mkdir(parents=True, exist_ok=True)
        fd = os.open(usage.LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
        self.addCleanup(os.close, fd)
        fcntl.flock(fd, fcntl.LOCK_EX)
        for name, entry, expected in (
                ("reading", fresh, dict(fresh, weekly=dict(fresh["weekly"], history=[]), starter=OFF, program=NOT_FOUND)),
                ("sign-out", {"status": "signed_out", "heldUntil": now + 300, "holdSeconds": 300},
                 {"status": "signed_out", "starter": OFF, "program": NOT_FOUND}),
                ("rate limit", {"status": "rate_limited", "heldUntil": now + 900, "holdSeconds": 900,
                                "reason": "rate-limited", "host": "api.anthropic.com"},
                 {"status": "rate_limited", "reason": "rate-limited", "host": "api.anthropic.com", "retryAt": now + 900})):
            with self.subTest(name):
                self.write_cache({"codex": entry})
                with mock.patch.object(usage, "LOCK_WAIT", 0.3):
                    report = self.run_main("--providers", "claude,codex")
                codex = report["providers"]["codex"]
                self.assertEqual({key: codex[key] for key in expected}, expected)
                claude = report["providers"]["claude"]
                self.assertEqual(claude, dict(busy, retryAt=claude["retryAt"]))
                self.assertTrue(now <= claude["retryAt"] <= report["fetchedAt"])

    # A hold without a reason or host is replayed as it was, with none to
    # give, rather than polled again.
    def test_a_hold_without_a_reason_replays_as_other(self):
        for entry, report in (
                ({"status": "error", "message": "down", "heldUntil": 1300, "holdSeconds": 300},
                 {"status": "error", "message": "down", "reason": "other", "host": "", "retryAt": 1300}),
                ({"status": "rate_limited", "heldUntil": 1600, "holdSeconds": 600, "reason": 5, "host": None},
                 {"status": "rate_limited", "retryAfter": 400, "message": "rate limited, retrying in 400 s",
                  "reason": "other", "host": "", "retryAt": 1600})):
            with self.subTest(entry["status"]):
                self.write_cache({"codex": entry})
                fetch = mock.Mock()
                self.assertEqual(self.collect(1200, codex=fetch)["codex"], report)
                fetch.assert_not_called()

    # The reason and host reach the cache with the hold, so every run that
    # replays it says the same.
    def test_the_reason_and_host_are_cached_with_the_hold(self):
        self.collect(1000, claude=mock.Mock(side_effect=usage.CheckFailed("can't reach a.test: x", "offline", "a.test")))
        self.assertEqual(self.cached()["claude"], {"status": "error", "message": "can't reach a.test: x",
                                                   "heldUntil": 1300, "holdSeconds": 300,
                                                   "reason": "offline", "host": "a.test"})
        self.collect(1000, codex=mock.Mock(side_effect=usage.SignedOut()))
        self.assertEqual(self.cached()["codex"], {"status": "signed_out", "heldUntil": 1300, "holdSeconds": 300})

    def test_malformed_cache_entries_read_as_missing(self):
        window = {"percent": 1, "resetsAt": 5, "windowSeconds": WEEK}
        for entry in ({"status": "ok", "fetchedAt": "soon", "weekly": {}}, {"status": "ok", "fetchedAt": 999},
                      {"status": "ok", "fetchedAt": 999, "weekly": {}, "scoped": [1]},
                      {"status": "ok", "fetchedAt": 999, "weekly": dict(window, resetsAt="soon")},
                      {"status": "ok", "fetchedAt": 999, "weekly": dict(window, percent=1.5)},
                      {"status": "ok", "fetchedAt": 999, "weekly": dict(window, windowSeconds=float(WEEK))},
                      {"status": "ok", "fetchedAt": 999, "weekly": {"percent": 1, "resetsAt": 5}},
                      {"status": "ok", "fetchedAt": 999, "weekly": window, "scoped": [window]},
                      {"status": "rate_limited", "heldUntil": "later"},
                      {"status": "error", "heldUntil": 1100, "holdSeconds": 300}):
            with self.subTest(entry=entry):
                self.write_cache({"codex": entry})
                fetch = mock.Mock(return_value=reading(1, 5))
                self.assertEqual(self.collect(1000, codex=fetch)["codex"]["status"], "ok")
                fetch.assert_called_once()

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

    # The second run is seen trying the lock while the first still polls:
    # its non-blocking flock is refused and it waits. The first is held in
    # its poll until then, so the order is forced, not timed.
    def test_a_run_that_waits_for_the_lock_reads_the_fresh_cache(self):
        polling, release, refused = threading.Event(), threading.Event(), threading.Event()
        calls, results, errors = [], [], []
        real_flock = fcntl.flock

        def fetch():
            calls.append(1)
            polling.set()
            if not release.wait(10):
                raise AssertionError("the first run was never released")
            return reading(4, 5)

        def run():
            try:
                results.append(usage.collect({"codex": fetch}, 1000))
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
        with mock.patch.object(usage.fcntl, "flock", flock):
            first.start()
            self.assertTrue(polling.wait(10))
            second.start()
            self.assertTrue(refused.wait(5), "the second run never tried the lock while the first polled")
            second.join(0.5)
            self.assertTrue(second.is_alive())
            self.assertEqual(len(calls), 1)
            release.set()
            first.join(10)
            second.join(10)
        self.assertFalse(first.is_alive() or second.is_alive())
        self.assertEqual(errors, [])
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


class ChosenProgram(Isolated):
    """A program chosen in the settings is run as it is, or reported, and
    never traded for one found by itself."""

    def setUp(self):
        super().setUp()
        self.enterContext(mock.patch.object(usage, "find_cli", REAL_FIND_CLI))
        # Nothing on this machine's PATH.
        self.enterContext(mock.patch.object(usage.shutil, "which", return_value=None))
        # A codex the automatic search would find, to show it isn't used.
        local = Path.home() / ".local" / "bin"
        local.mkdir(parents=True)
        self.found = local / "codex"
        self.found.write_text("#!/bin/sh\n")
        self.found.chmod(0o700)
        self.programs = self.tmp / "programs"
        self.programs.mkdir()

    def program(self, name, mode=0o700):
        path = self.programs / name
        path.write_text("#!/bin/sh\n")
        path.chmod(mode)
        return str(path)

    def test_a_chosen_program_that_runs(self):
        path = self.program("codex")
        self.assertEqual(usage.find_cli("codex", path), (path, ""))

    def test_a_chosen_program_that_cant_run_says_why(self):
        os.mkfifo(self.programs / "pipe")
        (self.programs / "folder").mkdir(mode=0o700)
        for chosen, problem in ((str(self.programs / "nothing"), "missing"),
                                (self.program("plain", 0o600), "not-executable"),
                                (str(self.programs / "pipe"), "not-executable"),
                                (str(self.programs / "folder"), "folder"),
                                ("codex", "missing"), ("bin/codex", "missing")):
            with self.subTest(chosen=chosen):
                self.assertEqual(usage.find_cli("codex", chosen), (chosen, problem))

    def test_the_home_folder_is_expanded(self):
        path = Path.home() / "my bin" / "codex"
        path.parent.mkdir()
        path.write_text("#!/bin/sh\n")
        path.chmod(0o700)
        self.assertEqual(usage.find_cli("codex", "~/my bin/codex"), (str(path), ""))
        self.assertEqual(usage.find_cli("codex", "~/elsewhere/codex"), (str(Path.home() / "elsewhere" / "codex"), "missing"))

    def test_a_chosen_program_never_falls_back(self):
        missing = str(self.programs / "codex")
        self.assertEqual(usage.find_cli("codex"), (str(self.found), ""))
        self.assertEqual(usage.find_cli("codex", missing), (missing, "missing"))
        usage.PROGRAMS["codex"] = missing
        with mock.patch.object(usage, "CODEX_AUTH", Path(__file__)), \
                mock.patch.object(usage, "codex_rate_limits", side_effect=AssertionError("ran a codex")):
            report = usage.poll(usage.codex_usage)
        self.assertEqual((report["status"], report["reason"]), ("error", "program"))
        with self.assertRaises(usage.Failed) as failed:
            usage.installed("codex")
        self.assertEqual(failed.exception.reason, "program")

    def test_the_chosen_program_is_the_one_run(self):
        path = self.program("codex")
        usage.PROGRAMS["codex"] = path
        with mock.patch.object(usage, "CODEX_AUTH", Path(__file__)), \
                mock.patch.object(usage, "codex_rate_limits", side_effect=RuntimeError("stop")) as run:
            usage.poll(usage.codex_usage)
        run.assert_called_once_with(path)
        self.assertEqual(usage.installed("codex"), path)

    # A program that couldn't be found or run is held back for five
    # minutes like any failure, but only while the same one is chosen.
    def test_a_program_hold_is_only_for_the_program_chosen_then(self):
        fetch = mock.Mock(side_effect=usage.CheckFailed("codex CLI not found", "not-installed"))
        self.assertEqual(usage.collect({"codex": fetch}, 1000)["codex"]["reason"], "not-installed")
        usage.collect({"codex": fetch}, 1060)
        self.assertEqual(fetch.call_count, 1, "the same program is held back")
        usage.PROGRAMS["codex"] = "~/bin/codex"
        fetch.side_effect = usage.CheckFailed("can't be run", "program")
        self.assertEqual(usage.collect({"codex": fetch}, 1120)["codex"]["reason"], "program")
        self.assertEqual(fetch.call_count, 2, "a newly chosen program is checked at once")
        usage.collect({"codex": fetch}, 1180)
        self.assertEqual(fetch.call_count, 2)
        self.assertEqual(json.loads(usage.CACHE_FILE.read_text())["codex"]["program"], "~/bin/codex")
        usage.PROGRAMS["codex"] = ""
        usage.collect({"codex": fetch}, 1240)
        self.assertEqual(fetch.call_count, 3, "going back to automatic checks at once")
        # A hold cached before programs could be chosen holds automatic only.
        cache = json.loads(usage.CACHE_FILE.read_text())
        del cache["codex"]["program"]
        self.write_cache(cache)
        usage.PROGRAMS["codex"] = "/opt/codex"
        usage.collect({"codex": fetch}, 1300)
        self.assertEqual(fetch.call_count, 4)

    # A busy run replays holds the same way.
    def test_a_busy_run_ignores_another_programs_hold(self):
        usage.collect({"codex": mock.Mock(side_effect=usage.CheckFailed("codex CLI not found", "not-installed"))})
        usage.PROGRAMS["codex"] = "/opt/codex"
        with mock.patch.object(usage, "read_history", return_value={}):
            self.assertEqual(usage.waiting(["codex"], "busy")["codex"]["reason"], "busy")
            usage.PROGRAMS["codex"] = ""
            self.assertEqual(usage.waiting(["codex"], "busy")["codex"]["reason"], "not-installed")

    # A rate limit is the account's, whichever program asked.
    def test_other_holds_stay_whichever_program_is_chosen(self):
        fetch = mock.Mock(side_effect=usage.RateLimited(900))
        usage.collect({"codex": fetch}, 1000)
        usage.PROGRAMS["codex"] = "/opt/codex"
        self.assertEqual(usage.collect({"codex": fetch}, 1060)["codex"]["status"], "rate_limited")
        self.assertEqual(fetch.call_count, 1)

    def test_every_entry_reports_its_program(self):
        plain = self.program("claude", 0o600)
        with mock.patch.object(usage, "claude_usage", side_effect=usage.SignedOut()), \
                mock.patch.object(usage, "codex_usage", return_value=reading(1, 2000000000)):
            report = self.run_main("--program", f"claude={plain}")["providers"]
            self.assertEqual(report["claude"]["program"], {"path": plain, "chosen": True, "problem": "not-executable"})
            self.assertEqual(report["codex"]["program"], {"path": str(self.found), "chosen": False, "problem": ""})
            # Looked up afresh on every run, a cached reading's too.
            self.found.unlink()
            report = self.run_main("--program", "codex=~/.local/bin/codex")["providers"]
            self.assertEqual(report["codex"]["program"], {"path": str(self.found), "chosen": True, "problem": "missing"})
            self.assertEqual(report["claude"]["program"], NOT_FOUND)
        self.assertNotIn("program", json.loads(usage.CACHE_FILE.read_text())["codex"])

    def test_program_arguments(self):
        with mock.patch.object(usage, "collect", return_value={}):
            self.run_main("--program", "codex=/a b/=c/$(x)`y`'z", "--program", "claude=")
        self.assertEqual(usage.PROGRAMS, {"codex": "/a b/=c/$(x)`y`'z", "claude": ""})
        for value in ("codex", "gemini=/x", "=/x", " codex=/x"):
            with self.subTest(value), mock.patch("sys.stderr", new=io.StringIO()) as err, \
                    self.assertRaises(SystemExit) as exit_:
                usage.main(["--program", value])
            self.assertEqual(exit_.exception.code, 2)
            self.assertIn("expected <provider>=<path>", err.getvalue())


REAL_FIND_CLI = usage.find_cli


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

    # The script as the widget runs it, in a home with no logins, no cache
    # and nothing on PATH: both providers are signed out, nothing is polled
    # and the starter flags are taken.
    def test_the_script_itself(self):
        home = self.tmp / "fresh"
        home.mkdir()
        env = {"PATH": str(home), "HOME": str(home), "XDG_CACHE_HOME": str(home / "cache"),
               "XDG_CONFIG_HOME": str(home / "config"), "XDG_STATE_HOME": str(home / "state"),
               "CLAUDE_CONFIG_DIR": str(home / "claude"), "CODEX_HOME": str(home / "codex")}
        run = subprocess.run([sys.executable, HELPER, "--start", "--starter-set", "codex=on"], env=env,
                             capture_output=True, text=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stderr)
        report = json.loads(run.stdout)
        self.assertEqual({name: entry["status"] for name, entry in report["providers"].items()},
                         {"claude": "signed_out", "codex": "signed_out"})
        self.assertEqual(report["providers"]["claude"]["starter"], OFF)
        self.assertEqual((report["providers"]["codex"]["starter"]["enabled"],
                          report["providers"]["codex"]["starter"]["state"]), (True, "failed"))
        self.assertEqual(sorted(os.listdir(home)), ["cache", "config", "state"])
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
        """The stored series; EarlyResets checks the reset records beside them."""
        return {name: {key: value for key, value in series.items() if key != "resets"}
                for name, series in json.loads(usage.HISTORY_FILE.read_text()).items()}

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

    # A spurious sign-out (a 401 from the token endpoint, say) mustn't cost
    # the week's graph.
    def test_unreported_limits_lose_their_series_and_signed_out_keeps_it(self):
        series = [[self.NOW - 60, 1]]
        self.seed({"claude": {"weekly": series, "scoped": {"Opus": series, "Retired": series}},
                   "codex": {"weekly": series, "scoped": {}}})
        usage.collect({"claude": lambda: reading(1, self.RESET, Opus=1),
                       "codex": mock.Mock(side_effect=usage.SignedOut())}, self.NOW)
        self.assertEqual(self.stored(), {"claude": {"weekly": series + [[self.NOW, 1]],
                                                    "scoped": {"Opus": series + [[self.NOW, 1]]}},
                                         "codex": {"weekly": series, "scoped": {}}})

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


class EarlyResets(History):
    """A window that starts over before its reset time, told apart from the
    history's stored reset time, and carried on the report for a day."""

    LAST = History.NOW - 300

    def seed_window(self, percent, reset, name="claude", early=None, **scoped):
        record = {"resetsAt": reset, **({"early": early} if early else {})}
        self.seed({name: {"weekly": [[self.LAST, percent]],
                          "scoped": {key: [[self.LAST, value]] for key, value in scoped.items()},
                          "resets": {"weekly": record, "scoped": {key: {"resetsAt": reset} for key in scoped}}}})

    def record(self, name="claude"):
        return json.loads(usage.HISTORY_FILE.read_text())[name]["resets"]

    def test_a_window_that_moved_out_before_its_reset_is_early_from_its_new_start(self):
        self.seed_window(62, self.RESET)
        start = self.NOW - 120
        report = self.collect(reading(3, start + WEEK))
        early = {"at": start, "from": 62}
        self.assertEqual(report["weekly"]["earlyReset"], dict(early, until=start + usage.EARLY_SHOWN))
        self.assertEqual(report["weekly"]["startedAt"], start)
        self.assertEqual(self.record()["weekly"], {"resetsAt": start + WEEK, "early": early})
        self.assertNotIn("earlyReset", json.loads(usage.CACHE_FILE.read_text())["claude"]["weekly"])

    def test_a_new_start_before_the_last_poll_dates_it_at_this_poll(self):
        self.seed_window(62, self.RESET)
        report = self.collect(reading(3, self.LAST - 60 + WEEK))
        self.assertEqual(report["weekly"]["earlyReset"]["at"], self.NOW)

    def test_a_window_cleared_in_place_is_early_from_this_poll(self):
        self.seed_window(61, self.RESET, name="codex")
        report = self.collect(reading(2, self.RESET), name="codex")
        self.assertEqual(report["weekly"]["earlyReset"], {"at": self.NOW, "from": 61, "until": self.NOW + usage.EARLY_SHOWN})
        self.assertEqual(report["weekly"]["startedAt"], self.NOW)

    def test_what_is_not_an_early_reset(self):
        cases = (
            # The week ran out on schedule.
            ("scheduled", 78, self.NOW - 60, reading(4, self.NOW - 60 + WEEK)),
            ("spending", 40, self.RESET, reading(46, self.RESET)),
            # Too small a fall in place to be anything but noise.
            ("small fall", 50, self.RESET, reading(35, self.RESET)),
            # A limit doubled part-way through the week halves the share.
            ("raised limit", 60, self.RESET, reading(30, self.RESET)),
            # The provider moved the week's start and gave nothing back.
            ("moved day", 30, self.RESET, reading(30, self.RESET + 2 * 86400)),
            # Codex puts an idle week a week from when it is asked.
            ("idle codex", 0, self.NOW - 2 * 3600 + WEEK, reading(0, self.NOW + WEEK)),
            # A reset time a second off is the same window.
            ("jitter", 50, self.RESET, reading(45, self.RESET + 1)),
            # The provider's clock a minute and a half ahead of this one.
            ("clock behind", 80, self.NOW + 90, reading(0, self.NOW + WEEK)),
        )
        for tag, before, reset, after in cases:
            with self.subTest(tag):
                usage.CACHE_FILE.unlink(missing_ok=True)
                self.seed_window(before, reset)
                report = self.collect(after)
                self.assertNotIn("earlyReset", report["weekly"])
                self.assertNotIn("startedAt", report["weekly"])
                self.assertEqual(self.record()["weekly"], {"resetsAt": after["weekly"]["resetsAt"]})

    # Claude may give a week no one has used no reset time at all.
    def test_a_week_back_to_unused_is_early_until_it_is_used_and_after(self):
        self.seed_window(62, self.RESET)
        report = self.collect(reading(0, None))
        early = {"at": self.NOW, "from": 62}
        self.assertEqual(report["weekly"]["earlyReset"], dict(early, until=self.NOW + usage.EARLY_SHOWN))
        self.assertEqual(self.record()["weekly"], {"resetsAt": None, "early": early})
        self.assertIn("earlyReset", self.collect(reading(0, None), now=self.NOW + 600)["weekly"])
        report = self.collect(reading(3, self.NOW + 900 + WEEK), now=self.NOW + 900)
        self.assertEqual(report["weekly"]["earlyReset"]["at"], self.NOW)
        self.assertEqual(self.record()["weekly"], {"resetsAt": self.NOW + 900 + WEEK, "early": early})

    # An idle Codex week's reset moves with every ask, hours apart overnight.
    def test_an_idle_codex_week_keeps_it_across_a_gap(self):
        self.seed_window(70, self.RESET, name="codex")
        self.assertIn("earlyReset", self.collect(reading(0, self.NOW + WEEK), name="codex")["weekly"])
        later = self.NOW + 5 * 3600
        report = self.collect(reading(0, later + WEEK), now=later, name="codex")
        self.assertEqual(report["weekly"]["earlyReset"]["at"], self.NOW)

    def test_a_reading_in_use_that_doesnt_say_when_it_resets_changes_nothing(self):
        early = {"at": self.NOW - 600, "from": 62}
        self.seed_window(3, self.RESET, early=early)
        report = self.collect(reading(5, None))
        self.assertEqual(report["weekly"]["earlyReset"]["at"], early["at"])
        self.assertEqual(self.record()["weekly"], {"resetsAt": self.RESET, "early": early})

    # A history written before reset times were kept has no record to go by.
    def test_a_window_without_a_record_starts_one(self):
        self.seed({"claude": {"weekly": [[self.LAST, 62]], "scoped": {}}})
        report = self.collect(reading(3, self.NOW + WEEK))
        self.assertNotIn("earlyReset", report["weekly"])
        self.assertEqual(self.record()["weekly"], {"resetsAt": self.NOW + WEEK})

    # Told of for a day; counted from for as long as the window lasts.
    def test_it_is_told_for_a_day_and_kept_while_the_window_lasts(self):
        early = {"at": self.NOW - usage.EARLY_SHOWN + 600, "from": 62}
        self.seed_window(3, self.RESET, early=early)
        report = self.collect(reading(5, self.RESET))
        self.assertEqual(report["weekly"]["earlyReset"], dict(early, until=early["at"] + usage.EARLY_SHOWN))
        self.assertEqual(self.record()["weekly"]["early"], early)
        # A cached reading carries it too.
        self.assertIn("earlyReset", self.collect(reading(99, self.RESET), now=self.NOW + 299)["weekly"])
        report = self.collect(reading(6, self.RESET), now=self.NOW + 600)
        self.assertNotIn("earlyReset", report["weekly"])
        self.assertEqual(report["weekly"]["startedAt"], early["at"])
        self.assertEqual(self.record()["weekly"], {"resetsAt": self.RESET, "early": early})

    def test_a_reset_after_it_ends_it(self):
        early = {"at": self.NOW - 3600, "from": 62}
        self.seed_window(3, self.NOW - 60, early=early)
        report = self.collect(reading(0, self.NOW - 60 + WEEK))
        self.assertNotIn("earlyReset", report["weekly"])
        self.assertNotIn("startedAt", report["weekly"])
        self.assertEqual(self.record()["weekly"], {"resetsAt": self.NOW - 60 + WEEK})

    def test_a_model_limit_resets_early_on_its_own(self):
        self.seed_window(55, self.RESET, Fable=81)
        result = reading(56, self.RESET, Fable=2)
        result["scoped"][0]["resetsAt"] = self.NOW - 60 + WEEK
        report = self.collect(result)
        self.assertNotIn("earlyReset", report["weekly"])
        self.assertEqual(report["scoped"][0]["earlyReset"]["from"], 81)
        self.assertEqual(self.record()["scoped"]["Fable"]["early"]["from"], 81)

    def test_malformed_records_count_as_none(self):
        for resets in (None, [], {"weekly": "x"}, {"weekly": {"resetsAt": "1"}}, {"weekly": {"resetsAt": 1.5}},
                       {"weekly": {"resetsAt": True}}, {"scoped": []}):
            with self.subTest(resets):
                usage.CACHE_FILE.unlink(missing_ok=True)
                self.seed({"claude": {"weekly": [[self.LAST, 62]], "scoped": {}, "resets": resets}})
                report = self.collect(reading(3, self.NOW + WEEK))
                self.assertNotIn("earlyReset", report["weekly"])
                self.assertEqual(self.record()["weekly"], {"resetsAt": self.NOW + WEEK})

    def test_a_malformed_early_reset_is_dropped(self):
        for early in ("x", {"at": "1", "from": 2}, {"at": 1}, {"at": self.NOW, "from": 2.5}):
            with self.subTest(early):
                usage.CACHE_FILE.unlink(missing_ok=True)
                self.seed_window(5, self.RESET, early=early)
                self.assertNotIn("earlyReset", self.collect(reading(6, self.RESET))["weekly"])


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

    def test_the_session_and_each_starter_get_the_zone_too(self):
        off = dict(OFF)
        providers = {"claude": {"weekly": {"resetsAt": None}, "scoped": [],
                                "session": {"resetsAt": self.NOV_2_NOON_EST},
                                "starter": {"enabled": True, "state": "started", "at": self.NOV_2_NOON_EST,
                                            "next": self.SEP_4_NOON_EDT, "reason": None}},
                     "codex": {"weekly": {"resetsAt": None},
                               "starter": {"enabled": True, "state": "confirming", "at": self.NOV_2_NOON_EST,
                                           "next": None, "reason": None}},
                     "off": {"status": "signed_out", "starter": off}}
        usage.show_in_zone(providers, usage.clock_zone())
        self.assertEqual(providers["claude"]["session"]["clockZone"], {"offset": -18000, "abbreviation": "EST"})
        self.assertEqual(providers["claude"]["starter"]["clockZone"], {"offset": -14400, "abbreviation": "EDT"})
        self.assertEqual(providers["claude"]["starter"]["atClockZone"], {"offset": -18000, "abbreviation": "EST"})
        self.assertEqual(providers["codex"]["starter"]["clockZone"], {"offset": -18000, "abbreviation": "EST"})
        self.assertEqual(providers["codex"]["starter"]["atClockZone"], {"offset": -18000, "abbreviation": "EST"})
        self.assertEqual(off, OFF)

    # A Codex week started on daylight saving time ends a week later on
    # standard time; the status shows the start, so it needs the start's zone.
    def test_a_started_week_gets_the_zone_at_its_start(self):
        start = self.NOV_2_NOON_EST - 3 * 86400 - 3 * 3600
        providers = {"codex": {"weekly": {"resetsAt": None}, "starter": {
            "enabled": True, "state": "started", "at": start, "next": start + 7 * 86400 + 1, "reason": None}}}
        usage.show_in_zone(providers, usage.clock_zone())
        self.assertEqual(providers["codex"]["starter"]["atClockZone"], {"offset": -14400, "abbreviation": "EDT"})
        self.assertEqual(providers["codex"]["starter"]["clockZone"], {"offset": -18000, "abbreviation": "EST"})

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
        self.assertNotIn("clockZone", claude["starter"])
        usage.STARTER_FILE.parent.mkdir(parents=True)
        usage.STARTER_FILE.write_text('{"claude": true}')
        self.assertIn(self.run_main()["providers"]["claude"]["starter"]["clockZone"]["abbreviation"], ("EDT", "EST"))
        cached = json.loads(usage.CACHE_FILE.read_text())["claude"]
        self.assertNotIn("clockZone", cached["weekly"])
        self.assertNotIn("clockZone", cached["scoped"][0])


if __name__ == "__main__":
    unittest.main()
