# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import io
import json
import math
import time
import unittest
import urllib.error
from unittest import mock

from test_usage import Isolated, fixture, reading, usage

ORG = "11111111-1111-4111-8111-111111111111"
ACCOUNT = "22222222-2222-4222-8222-222222222222"
OTHER = "33333333-3333-4333-8333-333333333333"


class CreditParsing(unittest.TestCase):
    def test_claude_uses_explicit_currency_and_provider_minor_units(self):
        for currency, amount, precision in (("USD", 12.34, 2), ("EUR", 12.34, 2),
                                            ("JPY", 1234, 0), ("KRW", 1234, 0), ("VND", 1234, 0)):
            self.assertEqual(usage.parse_claude_credits({"amount": 1234, "currency": currency}),
                             {"amount": amount, "currency": currency, "precision": precision})
        self.assertIsNone(usage.parse_claude_credits({"amount": 0, "currency": "USD"}))

    def test_claude_rejects_missing_or_invalid_amount_and_currency(self):
        for amount in (None, -1, True, "10", math.inf, math.nan):
            with self.subTest(amount=amount), self.assertRaises(ValueError):
                usage.parse_claude_credits({"amount": amount, "currency": "USD"})
        for currency in (None, "usd", "US", "USDD", "ＵＳＤ", ""):
            with self.subTest(currency=currency), self.assertRaises(ValueError):
                usage.parse_claude_credits({"amount": 10, "currency": currency})
        with self.assertRaises(ValueError):
            usage.parse_claude_credits({"balance": {"amount": 10, "currency": "USD"}})

    def test_codex_credits_are_provider_units_and_validate_flags(self):
        def parse(**credits):
            return usage.parse_codex_credits({"rateLimits": {"credits": credits}})
        self.assertEqual(parse(hasCredits=True, unlimited=False, balance="12.50"),
                         ("ok", {"amount": 12.5, "currency": "", "precision": 2}))
        self.assertEqual(parse(hasCredits=False), ("disabled", None))
        self.assertEqual(parse(hasCredits=True, unlimited=True), ("ok", None))
        self.assertEqual(parse(hasCredits=True, unlimited=False, balance="0.00"), ("ok", None))
        self.assertEqual(usage.parse_codex_credits({}), ("unavailable", None))
        for value in (10, None, "NaN", "Infinity", "-1", "", "1e999", "9" * 1000):
            with self.subTest(value=value), self.assertRaises(ValueError):
                parse(hasCredits=True, unlimited=False, balance=value)
        for flags in ({"hasCredits": 1, "unlimited": False}, {"hasCredits": True, "unlimited": None}):
            with self.assertRaises(ValueError):
                parse(**flags)


class Credits(Isolated):
    def setUp(self):
        super().setUp()
        self.enterContext(mock.patch.object(usage.time, "monotonic", return_value=0))
        usage.CLAUDE_CREDENTIALS.parent.mkdir(parents=True)
        self.credentials = {"claudeAiOauth": {"accessToken": "test-access", "refreshToken": "test-refresh",
                                               "expiresAt": (time.time() + 3600) * 1000}}
        usage.CLAUDE_CREDENTIALS.write_text(json.dumps(self.credentials))
        self.config = usage.CLAUDE_CREDENTIALS.parent / ".claude.json"
        self.account()
        usage.CODEX_AUTH.parent.mkdir(parents=True)
        usage.CODEX_AUTH.write_text('{"tokens":{"account_id":"fixture-account"}}')
        self.enterContext(mock.patch.object(usage.urllib.request, "build_opener",
                                            side_effect=AssertionError("a test reached the credits network")))

    def account(self, account=ACCOUNT, org=ORG):
        self.config.write_text(json.dumps({"oauthAccount": {"accountUuid": account, "organizationUuid": org}}))

    def base(self, now=1000, **extra):
        self.write_cache({"claude": dict(status="ok", fetchedAt=now, **reading(1, 50000)), **extra})

    def collect(self, now, *, consent=("claude",), opened=("claude",), fetch=None, provider="claude"):
        return usage.collect({provider: fetch or mock.Mock(return_value=reading(2, 50000))}, now,
                             credits=consent, credits_open=opened)[provider]

    def cache(self):
        return json.loads(usage.CACHE_FILE.read_text())

    def test_opt_out_never_resolves_credit_identity_or_fetches(self):
        self.base()
        with mock.patch.object(usage, "claude_credit_identity", side_effect=AssertionError), \
                mock.patch.object(usage, "http_json", side_effect=AssertionError):
            self.assertNotIn("credits", self.collect(1001, consent=(), opened=()))

    def test_cached_weekly_still_allows_due_credits_with_exact_request(self):
        self.base()
        fetch = mock.Mock(side_effect=AssertionError("extra weekly request"))
        with mock.patch.object(usage, "http_json", return_value={"amount": 1234, "currency": "USD"}) as get:
            result = self.collect(1001, fetch=fetch)
        self.assertEqual(result["credits"], {"status": "ok", "balance": {"amount": 12.34, "currency": "USD", "precision": 2},
                                             "fetchedAt": 1001, "retryAt": 1901, "reason": None})
        args, kwargs = get.call_args
        self.assertEqual(args[0], "https://api.anthropic.com/api/oauth/organizations/" + ORG + "/prepaid/credits")
        self.assertEqual(args[1], {"Authorization": "Bearer test-access", "Content-Type": "application/json",
                                  "anthropic-version": "2023-06-01", "anthropic-client-platform": "claude_code_cli",
                                  "x-organization-uuid": ORG})
        self.assertEqual(kwargs, {"timeout": 5, "redirects": False, "max_bytes": 65536})
        self.assertNotIn("credits", self.cache()["claude"])

    def test_closed_popup_does_not_fetch_and_open_attempts_have_fifteen_minute_floor(self):
        self.base()
        with mock.patch.object(usage, "http_json", return_value={"amount": 100, "currency": "USD"}) as get:
            self.assertEqual(self.collect(1001, opened=())["credits"]["status"], "unavailable")
            get.assert_not_called()
            self.collect(1002)
            for at in (1003, 1302, 1901):
                self.collect(at)
            self.assertEqual(get.call_count, 1)
            self.collect(1902)
            self.assertEqual(get.call_count, 2)

    def test_failure_preserves_balance_and_zero_replaces_it(self):
        self.base()
        with mock.patch.object(usage, "http_json", side_effect=[{"amount": 100, "currency": "USD"},
                                 usage.CheckFailed("private response", "offline"), {"amount": 0, "currency": "USD"}]) as get:
            self.collect(1001)
            error = self.collect(1901)["credits"]
            self.assertEqual(error["status"], "error")
            self.assertEqual(error["balance"]["amount"], 1)
            self.assertEqual(error["fetchedAt"], 1001)
            self.collect(1902)
            self.assertEqual(get.call_count, 2)
            zero = self.collect(2801)["credits"]
            self.assertEqual((zero["status"], zero["balance"], zero["fetchedAt"]), ("ok", None, 2801))

    def test_credits_failures_do_not_change_weekly_or_renew_auth(self):
        self.base()
        with mock.patch.object(usage, "http_json", side_effect=usage.SignedOut()), \
                mock.patch.object(usage, "claude_access_token", side_effect=AssertionError), \
                mock.patch.object(usage, "refresh_claude", side_effect=AssertionError):
            result = self.collect(1001)
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["credits"]["reason"], "signed-out")

    def test_expired_credit_only_auth_is_not_refreshed(self):
        self.base()
        self.credentials["claudeAiOauth"]["expiresAt"] = 0
        usage.CLAUDE_CREDENTIALS.write_text(json.dumps(self.credentials))
        with mock.patch.object(usage, "http_json", side_effect=AssertionError), \
                mock.patch.object(usage, "refresh_claude", side_effect=AssertionError):
            self.assertEqual(self.collect(1001)["credits"]["reason"], "signed-out")

    def test_403_has_one_hour_cooldown(self):
        self.base()
        with mock.patch.object(usage, "http_json", side_effect=usage.CheckFailed("forbidden", "server", status=403)) as get:
            self.assertEqual(self.collect(1001)["credits"]["retryAt"], 4601)
            self.collect(1901)
            get.assert_called_once()

    def test_credit_429_persists_shared_hold_across_opt_out_account_change_and_restart(self):
        self.base()
        with mock.patch.object(usage, "http_json", side_effect=usage.RateLimited(2000)) as get:
            result = self.collect(1001)
            self.assertEqual(result["credits"]["retryAt"], 3001)
            self.account(OTHER)
            fetch = mock.Mock(side_effect=AssertionError("held weekly endpoint"))
            result = self.collect(1500, consent=(), opened=(), fetch=fetch)
            self.assertEqual(result["status"], "rate_limited")
            result = self.collect(1901, fetch=fetch)
            self.assertIsNone(result["credits"]["balance"])
            self.assertEqual(result["credits"]["retryAt"], 3001)
            get.assert_called_once()

    def test_weekly_429_and_existing_holds_prevent_credit_get(self):
        for failure in (usage.RateLimited(3600), usage.CheckFailed("offline", "offline")):
            with self.subTest(failure=failure):
                self.write_cache({})
                with mock.patch.object(usage, "http_json", side_effect=AssertionError):
                    self.collect(1000, fetch=mock.Mock(side_effect=failure))
                self.assertEqual(self.cache()["_credits"]["claude"]["retryAt"],
                                 4600 if isinstance(failure, usage.RateLimited) else 1300)

    def test_shared_429_has_fifteen_minute_floor_and_honors_longer_explicit_retry_after(self):
        for requested, wait in ((1, 900), (3 * 86400, 3 * 86400)):
            self.base()
            with mock.patch.object(usage, "http_json", side_effect=usage.RateLimited(requested)) as get:
                self.assertEqual(self.collect(1001)["credits"]["retryAt"], 1001 + wait)
                if wait > 86400:
                    fetch = mock.Mock(side_effect=AssertionError("long shared throttle bypassed"))
                    result = self.collect(1001 + 86401, fetch=fetch)
                    self.assertEqual(result["retryAt"], 1001 + wait)
                    self.assertEqual(result["credits"]["retryAt"], 1001 + wait)
                    self.collect(1001 + 86402, consent=(), opened=(), fetch=fetch)
                    get.assert_called_once()

    def test_weekly_explicit_retry_after_longer_than_day_is_shared(self):
        with mock.patch.object(usage, "http_json", side_effect=AssertionError):
            self.collect(1000, fetch=mock.Mock(side_effect=usage.RateLimited(3 * 86400)))
            fetch = mock.Mock(side_effect=AssertionError("long weekly throttle bypassed"))
            result = self.collect(1000 + 86401, fetch=fetch)
        self.assertEqual(result["retryAt"], 1000 + 3 * 86400)
        self.assertEqual(result["credits"]["retryAt"], 1000 + 3 * 86400)

    def test_weekly_error_does_not_erase_cached_credit_balance(self):
        self.base()
        with mock.patch.object(usage, "http_json", return_value={"amount": 100, "currency": "USD"}):
            self.collect(1001)
            result = self.collect(1300, fetch=mock.Mock(side_effect=RuntimeError("failed")))
        self.assertEqual(result["status"], "error")
        self.assertEqual(result["credits"]["balance"]["amount"], 1)

    def test_opt_out_preserves_private_balance_for_another_widget(self):
        self.base()
        with mock.patch.object(usage, "http_json", return_value={"amount": 100, "currency": "USD"}):
            self.collect(1001)
        saved = self.cache()["_credits"]
        with mock.patch.object(usage, "claude_credit_identity", side_effect=AssertionError), \
                mock.patch.object(usage, "http_json", side_effect=AssertionError):
            result = self.collect(1002, consent=(), opened=())
        self.assertNotIn("credits", result)
        self.assertEqual(self.cache()["_credits"], saved)

    def test_cached_provider_disabled_flag_prevents_get_after_later_consent(self):
        raw = fixture("claude_usage.json")
        raw["extra_usage"] = {"is_enabled": False}
        with mock.patch.object(usage, "http_json", return_value=raw), \
                mock.patch.object(usage, "claude_credit_identity", side_effect=AssertionError):
            result = self.collect(1000, fetch=usage.claude_usage, consent=(), opened=())
        self.assertNotIn("credits", result)
        with mock.patch.object(usage, "http_json", side_effect=AssertionError):
            result = self.collect(1001)
        self.assertEqual(result["credits"]["status"], "disabled")

    def test_disabled_observed_while_opted_out_survives_prior_account_identity(self):
        self.base()
        with mock.patch.object(usage, "http_json", return_value={"amount": 100, "currency": "USD"}):
            self.collect(1001)
        self.account(OTHER)
        raw = fixture("claude_usage.json")
        raw["extra_usage"] = {"is_enabled": False}
        with mock.patch.object(usage, "http_json", return_value=raw) as get, \
                mock.patch.object(usage, "claude_credit_identity", side_effect=AssertionError):
            self.collect(1901, fetch=usage.claude_usage, consent=(), opened=())
            get.assert_called_once()
        with mock.patch.object(usage, "http_json", side_effect=AssertionError("disabled account requested credits")):
            result = self.collect(1902)
        self.assertEqual(result["credits"]["status"], "disabled")
        self.assertIsNone(result["credits"]["balance"])

    def test_busy_main_serves_matched_balance_as_cached_without_requests_or_cache_writes(self):
        self.base()
        with mock.patch.object(usage, "http_json", return_value={"amount": 100, "currency": "USD"}):
            self.collect(1001)
        before = usage.CACHE_FILE.read_bytes()
        with mock.patch.object(usage, "collect", side_effect=usage.Busy()), \
                mock.patch.object(usage, "http_json", side_effect=AssertionError), \
                mock.patch.object(usage, "refresh_claude", side_effect=AssertionError), \
                mock.patch.object(usage, "write_private", side_effect=AssertionError):
            result = self.run_main("--credits-providers", "claude", "--providers", "claude")["providers"]["claude"]["credits"]
        self.assertEqual(result["status"], "error")
        self.assertEqual(result["balance"]["amount"], 1)
        self.assertEqual(result["fetchedAt"], 1001)
        self.assertEqual(usage.CACHE_FILE.read_bytes(), before)

    def test_busy_main_hides_balance_after_account_switch_or_missing_identity(self):
        self.base()
        with mock.patch.object(usage, "http_json", return_value={"amount": 100, "currency": "USD"}):
            self.collect(1001)
        for account in (OTHER, "invalid"):
            self.account(account)
            with mock.patch.object(usage, "collect", side_effect=usage.Busy()), \
                    mock.patch.object(usage, "http_json", side_effect=AssertionError), \
                    mock.patch.object(usage, "write_private", side_effect=AssertionError):
                result = self.run_main("--credits-providers", "claude", "--providers", "claude")["providers"]["claude"]["credits"]
            self.assertEqual(result["status"], "unavailable")
            self.assertIsNone(result["balance"])
            self.assertIsNone(result["fetchedAt"])

    def test_busy_opt_out_does_not_validate_identity_or_expose_credits(self):
        self.base()
        with mock.patch.object(usage, "collect", side_effect=usage.Busy()), \
                mock.patch.object(usage, "claude_credit_identity", side_effect=AssertionError), \
                mock.patch.object(usage, "credential_digest", side_effect=AssertionError), \
                mock.patch.object(usage, "http_json", side_effect=AssertionError):
            result = self.run_main("--providers", "claude")["providers"]["claude"]
        self.assertNotIn("credits", result)

    def test_busy_disabled_record_cannot_expose_a_malformed_old_balance(self):
        self.base()
        with mock.patch.object(usage, "http_json", return_value={"amount": 100, "currency": "USD"}):
            self.collect(1001)
        cache = self.cache()
        cache["_credits"]["claude"].update(status="disabled", enabled=False)
        self.write_cache(cache)
        result = usage.waiting(["claude"], "busy", credits=("claude",))["claude"]["credits"]
        self.assertEqual(result["status"], "disabled")
        self.assertIsNone(result["balance"])

    def test_busy_codex_validates_identity_without_reading_an_unconsented_provider(self):
        self.write_cache({"_credits": {"codex": {"identity": usage.credential_digest(usage.CODEX_AUTH),
                          "status": "ok", "balance": {"amount": 5, "currency": "", "precision": 2}, "fetchedAt": 1000}}})
        with mock.patch.object(usage, "claude_credit_identity", side_effect=AssertionError):
            result = usage.waiting(["claude", "codex"], "busy", credits=("codex",))["codex"]["credits"]
            self.assertEqual(result["status"], "error")
            self.assertEqual(result["balance"]["amount"], 5)
            usage.CODEX_AUTH.write_text('{"changed":true}')
            result = usage.waiting(["claude", "codex"], "busy", credits=("codex",))["codex"]["credits"]
        self.assertIsNone(result["balance"])

    def test_credit_retry_after_starts_at_response_and_keeps_pre_request_attempt_floor(self):
        self.base()
        elapsed = [0]
        def response(*args, **kwargs):
            self.assertEqual(self.cache()["_credits"]["claude"]["retryAt"], 1901)
            elapsed[0] = 4.2
            raise usage.RateLimited(3600)
        with mock.patch.object(usage.time, "monotonic", side_effect=lambda: elapsed[0]), \
                mock.patch.object(usage, "http_json", side_effect=response):
            result = self.collect(1001)
        self.assertEqual(result["credits"]["retryAt"], 1001 + 5 + 3600)
        self.assertEqual(self.cache()["_anthropicHold"], 1001 + 5 + 3600)

    def test_long_weekly_retry_after_starts_at_response_including_fractional_seconds(self):
        elapsed = [0]
        def response():
            elapsed[0] = 4.2
            raise usage.RateLimited(3 * 86400)
        with mock.patch.object(usage.time, "monotonic", side_effect=lambda: elapsed[0]):
            self.collect(1000, fetch=response)
        deadline = 1000 + 5 + 3 * 86400
        self.assertEqual(self.cache()["_anthropicHold"], deadline)
        fetch = mock.Mock(side_effect=AssertionError("shared throttle ended early"))
        result = self.collect(1000 + 3 * 86400 + 4, fetch=fetch)
        self.assertEqual(result["retryAt"], deadline)
        self.assertEqual(result["credits"]["retryAt"], deadline)

    def test_missing_or_invalid_identity_never_fetches_and_hides_old_balance(self):
        self.base()
        with mock.patch.object(usage, "http_json", return_value={"amount": 100, "currency": "USD"}) as get:
            self.collect(1001)
            self.account(org="invalid")
            result = self.collect(1002)
            self.assertIsNone(result["credits"]["balance"])
            self.assertEqual(result["credits"]["status"], "unavailable")
            get.assert_called_once()

    def test_identity_and_credentials_changes_during_get_discard_response(self):
        for change in (lambda: self.account(OTHER), lambda: usage.CLAUDE_CREDENTIALS.write_text('{}')):
            self.base()
            self.account()
            usage.CLAUDE_CREDENTIALS.write_text(json.dumps(self.credentials))
            def response(*args, **kwargs):
                change()
                return {"amount": 100, "currency": "USD"}
            with mock.patch.object(usage, "http_json", side_effect=response):
                result = self.collect(1001)["credits"]
            self.assertEqual((result["status"], result["balance"]), ("unavailable", None))
            self.assertEqual(result["retryAt"], 1901)

    def test_legacy_config_precedes_primary_and_malformed_selected_file_does_not_fall_back(self):
        legacy = self.config.parent / ".config.json"
        primary_identity = usage.claude_credit_identity()
        legacy.write_text(json.dumps({"oauthAccount": {"accountUuid": OTHER, "organizationUuid": ORG}}))
        self.assertNotEqual(usage.claude_credit_identity(), primary_identity)
        legacy.write_text('{broken')
        self.assertIsNone(usage.claude_credit_identity())
        legacy.unlink()
        self.assertEqual(usage.claude_credit_identity(), primary_identity)

    def test_provider_disabled_clears_balance_without_a_credit_request(self):
        self.base()
        raw = fixture("claude_usage.json")
        raw["extra_usage"] = {"is_enabled": False}
        with mock.patch.object(usage, "http_json", return_value={"amount": 100, "currency": "USD"}):
            self.collect(1001)
        with mock.patch.object(usage, "http_json", return_value=raw) as get:
            result = self.collect(1300, fetch=usage.claude_usage)
        self.assertEqual(result["credits"]["status"], "disabled")
        self.assertIsNone(result["credits"]["balance"])
        get.assert_called_once()

    def test_normal_claude_parser_error_holds_credits_without_token_renewal(self):
        self.write_cache({})
        with mock.patch.object(usage, "claude_access_token", return_value="test-access") as token, \
                mock.patch.object(usage, "http_json", side_effect=[{}, {"amount": 100, "currency": "USD"}]) as get:
            result = self.collect(1000, fetch=usage.claude_usage)
        token.assert_called_once()
        # A failed weekly reading holds the endpoint; it cannot provoke another GET.
        self.assertEqual(get.call_count, 1)
        self.assertEqual(result["status"], "error")

    def test_codex_reuses_one_rpc_even_with_bad_weekly_data_and_never_polls_for_missing_cached_credits(self):
        raw = {"rateLimits": {"credits": {"hasCredits": True, "unlimited": False, "balance": "23.25"}}}
        with mock.patch.object(usage, "find_cli", return_value=("codex", "")), \
                mock.patch.object(usage, "codex_rate_limits", return_value=raw) as rpc:
            result = self.collect(1000, provider="codex", fetch=usage.codex_usage, consent=("codex",), opened=("codex",))
            self.assertEqual(result["status"], "error")
            self.assertEqual(result["credits"]["balance"]["amount"], 23.25)
            self.collect(1001, provider="codex", fetch=usage.codex_usage, consent=("codex",), opened=("codex",))
            rpc.assert_called_once()
        self.write_cache({"codex": dict(status="ok", fetchedAt=1000, **reading(1, 5000))})
        fetch = mock.Mock(side_effect=AssertionError)
        result = self.collect(1001, provider="codex", fetch=fetch, consent=("codex",), opened=("codex",))
        self.assertEqual(result["credits"]["status"], "unavailable")

    def test_codex_failed_read_keeps_matching_balance_as_cached(self):
        raw = fixture("codex_rate_limits.json")
        raw["rateLimitsByLimitId"]["codex"]["credits"] = {"hasCredits": True, "unlimited": False, "balance": "5"}
        with mock.patch.object(usage, "find_cli", return_value=("codex", "")), \
                mock.patch.object(usage, "codex_rate_limits", return_value=raw) as rpc:
            self.collect(1000, provider="codex", fetch=usage.codex_usage, consent=("codex",), opened=("codex",))
            fresh = self.collect(1001, provider="codex", fetch=usage.codex_usage, consent=("codex",), opened=("codex",))
            self.assertEqual(fresh["credits"]["status"], "ok")
            rpc.side_effect = usage.CheckFailed("private response", "offline")
            failed = self.collect(1300, provider="codex", fetch=usage.codex_usage, consent=("codex",), opened=("codex",))
            self.assertEqual(failed["credits"]["status"], "error")
            self.assertEqual(failed["credits"]["reason"], "offline")
            self.assertEqual(failed["credits"]["balance"]["amount"], 5)
            self.assertEqual(failed["credits"]["fetchedAt"], 1000)
            held = self.collect(1301, provider="codex", fetch=usage.codex_usage, consent=("codex",), opened=("codex",))
            self.assertEqual(held["credits"], failed["credits"])
            self.assertEqual(rpc.call_count, 2)

    def test_codex_changed_auth_discards_reply(self):
        raw = fixture("codex_rate_limits.json")
        raw["rateLimitsByLimitId"]["codex"]["credits"] = {"hasCredits": True, "unlimited": False, "balance": "5"}
        def response(_):
            usage.CODEX_AUTH.write_text('{"changed":true}')
            return raw
        with mock.patch.object(usage, "find_cli", return_value=("codex", "")), \
                mock.patch.object(usage, "codex_rate_limits", side_effect=response):
            result = self.collect(1000, provider="codex", fetch=usage.codex_usage, consent=("codex",), opened=("codex",))
        self.assertIsNone(result["credits"]["balance"])
        self.assertEqual(result["credits"]["status"], "unavailable")

    def test_cli_validates_credit_subsets(self):
        for argv in (("--credits-providers", "codex", "--providers", "claude"),
                     ("--credits-open", "claude"), ("--credits-providers", "bogus")):
            with mock.patch("sys.stderr", new=io.StringIO()), self.assertRaises(SystemExit):
                usage.arguments(argv)

    def test_credit_http_refuses_redirect_and_bounds_body(self):
        opener = mock.MagicMock()
        with mock.patch.object(usage.urllib.request, "build_opener", return_value=opener) as build:
            response = opener.open.return_value.__enter__.return_value
            response.read.return_value = b"x" * 65537
            with self.assertRaises(usage.CheckFailed):
                usage.http_json("https://api.anthropic.com/test", {}, timeout=5, redirects=False, max_bytes=65536)
            response.read.assert_called_once_with(65537)
            self.assertIsInstance(build.call_args.args[0], usage.NoRedirect)
            self.assertIsNone(build.call_args.args[0].redirect_request(None, None, 302, "", {}, "https://other.example"))
            request = opener.open.call_args.args[0]
            self.assertEqual(request.get_header("User-agent"), usage.USER_AGENT)

    def test_private_report_and_journal_never_include_account_or_tokens(self):
        self.base()
        with mock.patch.object(usage, "http_json", side_effect=RuntimeError("test-access " + ORG)):
            result = self.collect(1001)
        serialized = json.dumps({"report": result, "events": usage.EVENTS, "cache": self.cache()})
        for secret in ("test-access", "test-refresh", ACCOUNT, ORG):
            self.assertNotIn(secret, serialized)


if __name__ == "__main__":
    unittest.main()
