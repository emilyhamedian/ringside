# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import json
import threading
from datetime import datetime, timezone
from unittest import mock

from test_usage import Isolated, reading, usage


NOW = 1800000000


class ProxyPolling(Isolated):
    def setUp(self):
        super().setUp()
        self.now = NOW
        self.enterContext(mock.patch.object(usage.time, "time", side_effect=lambda: self.now))
        self.backend = usage.proxy_backend()
        self.real_client = self.backend.Client
        self.client = mock.Mock(configuration_fingerprint="revision-1")
        self.client.affinity.return_value = {"enabled": True, "ttlSeconds": 900}
        self.factory = self.enterContext(mock.patch.object(self.backend, "Client", return_value=self.client))
        self.discovery = self.enterContext(mock.patch.object(self.backend, "discover", return_value=False))
        self.credential_a = self.credential("a")
        self.credential_b = self.credential("b")
        self.client.credentials.return_value = {"claude": [self.credential_a, self.credential_b]}
        self.client.usage.side_effect = lambda credential, now, **kwargs: self.pooled(30 if credential.index == "a" else 70)
        self.direct = self.enterContext(mock.patch.object(usage, "claude_usage", side_effect=self.direct_reading))

    def credential(self, key, **kwargs):
        return self.backend.Credential("claude", "fingerprint-" + key, key, **kwargs)

    def direct_reading(self):
        return dict(reading(12, self.now + 24 * 3600), session=None)

    def pooled(self, percent):
        return {"weekly": self.backend.window(percent, self.now + 24 * 3600, usage.WEEK_SECONDS, "week"),
                "session": None, "scoped": []}

    def poll(self, *argv):
        return self.run_main("--providers", "claude", "--proxy-url", usage.PROXY_URL, *argv)["providers"]["claude"]

    def test_pool_cache_keeps_its_own_history_and_no_direct_credit(self):
        result = self.poll()
        self.assertEqual((result["source"], result["proxyStatus"], result["fetchedAt"]), ("cliproxyapi", "connected", NOW))
        self.assertEqual(result["weekly"]["percent"], 50)
        self.assertEqual(result["affinity"], {"enabled": True, "ttlSeconds": 900})
        self.assertNotIn("credits", result)
        self.assertEqual(result["weekly"]["history"], [[NOW, 50]])
        self.assertNotIn("history", result["accounts"][0]["weekly"])
        self.assertFalse(usage.CACHE_FILE.exists())
        self.assertFalse(usage.HISTORY_FILE.exists())
        self.direct.assert_not_called()
        self.now += 40
        self.assertEqual(self.poll(), result)
        self.client.credentials.assert_called_once()
        self.assertEqual(self.client.usage.call_count, 2)
        stored = (usage.CACHE_DIR / "usage-proxy.json").read_text()
        self.assertNotIn('"index"', stored)
        self.assertNotIn("resetTimes", stored)

    def test_pool_history_keeps_drops_from_staggered_resets_and_ages_out(self):
        first_reset, second_reset = NOW + usage.CACHE_TTL, NOW + 2 * usage.CACHE_TTL

        def reply(credential, now, **kwargs):
            first = credential == self.credential_a
            reset = first_reset if first else second_reset
            used = (80 if first else 70) if now < reset else 0
            if now >= reset:
                reset += ((now - reset) // usage.WEEK_SECONDS + 1) * usage.WEEK_SECONDS
            weekly = self.backend.window(used, reset, usage.WEEK_SECONDS, "week")
            fable = self.backend.window(100 if used else 0, reset, usage.WEEK_SECONDS, "week")
            return {"weekly": weekly, "scoped": [dict(fable, id="Fable", label="Fable")]}

        self.client.usage.side_effect = reply
        self.poll()
        self.now = first_reset
        self.poll()
        self.now = second_reset
        result = self.poll()
        self.assertEqual(result["weekly"]["history"], [[NOW, 75], [first_reset, 35], [second_reset, 0]])
        self.assertEqual(result["scoped"][0]["history"], [[NOW, 100], [first_reset, 50], [second_reset, 0]])
        self.assertEqual(result["weekly"]["resetsAt"], first_reset + usage.WEEK_SECONDS)
        self.assertNotIn("earlyReset", result["weekly"])
        self.now = second_reset + usage.WEEK_SECONDS + 1
        self.assertEqual(self.poll()["weekly"]["history"], [[self.now, 0]])

    def test_pool_history_restarts_a_model_when_its_contributors_change(self):
        advertise = self.credential_a

        def reply(credential, now, **kwargs):
            entry = self.pooled(50)
            if credential == advertise:
                entry["scoped"] = [dict(entry["weekly"], id="Fable", label="Fable")]
            return entry

        self.client.usage.side_effect = reply
        self.assertEqual(self.poll()["scoped"][0]["history"], [[NOW, 50]])
        self.now += usage.CACHE_TTL
        advertise = self.credential_b
        result = self.poll()
        self.assertEqual(result["scoped"][0]["history"], [[self.now, 50]])
        self.assertEqual(result["weekly"]["history"], [[NOW, 50], [self.now, 50]])

    def test_actual_hub_client_and_engine_do_not_report_routing_details(self):
        key = self.tmp / "management.key"
        key.write_text("fixture-management-secret\n")
        key.chmod(0o600)
        self.factory.side_effect = self.real_client
        routing_id = "fixture-routing-index"
        email = "fixture-account@example.invalid"

        def request(host, port, path, *, request=None, **kwargs):
            self.assertEqual((host, port), ("127.0.0.1", 8317))
            self.assertEqual(kwargs["key"], b"fixture-management-secret")
            if path.endswith("/credentials"):
                return {"files": [{"provider": "claude", "auth_index": routing_id, "email": email}]}
            if path.endswith("/requests/api-call"):
                self.assertEqual((request["auth_index"], request["method"]), (routing_id, "GET"))
                self.assertEqual(request["header"]["Authorization"], "Bearer $TOKEN$")
                return {"status_code": 200, "body": json.dumps({
                    "seven_day": {"utilization": 25, "resets_at": self.now + 3600}, "five_hour": None,
                })}
            self.assertTrue(path.endswith("/session-affinity"))
            return False

        self.enterContext(mock.patch.object(self.backend, "request_json", side_effect=request))
        report = self.run_main("--providers", "claude", "--proxy-url", usage.PROXY_URL, "--proxy-key-file", str(key))
        self.assertEqual(report["providers"]["claude"]["weekly"]["percent"], 25)
        report_and_cache = json.dumps(report) + (usage.CACHE_DIR / "usage-proxy.json").read_text()
        for private in ("fixture-management-secret", routing_id, email, str(key)):
            self.assertNotIn(private, report_and_cache)
        self.direct.assert_not_called()

    def test_real_client_scopes_tickets_and_balances_to_each_selected_account(self):
        key = self.tmp / "management.key"
        key.write_text("fixture-management-secret\n")
        key.chmod(0o600)
        self.factory.side_effect = self.real_client
        org = "aaaa0000-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        profiles = {"fixture-claude-a": org, "fixture-claude-b": "fixture-invalid-org"}
        codex = {"fixture-codex-a": "fixture-workspace-a", "fixture-codex-b": "fixture-workspace-b"}
        rows = [{"provider": "claude", "auth_index": index, "modtime": "2026-09-09T00:00:00Z"} for index in profiles]
        rows += [{"provider": "codex", "auth_index": index, "id_token": {"chatgpt_account_id": workspace}}
                 for index, workspace in codex.items()]
        rows += [{"provider": channel, "auth_index": "fixture-" + channel} for channel in ("kimi", "kimi-ai")]
        requests = []
        expires = NOW + 100
        remote_expiry = datetime.fromtimestamp(expires, timezone.utc).isoformat()

        def request(host, port, path, *, request=None, **kwargs):
            if path.endswith("/credentials"):
                return {"files": rows}
            if path.endswith("/session-affinity"):
                return False
            self.assertTrue(path.endswith("/requests/api-call"))
            index, url, headers = (request[key] for key in ("auth_index", "url", "header"))
            requests.append((index, url, kwargs["deadline"]))
            self.assertEqual((request["method"], headers["Authorization"]), ("GET", "Bearer $TOKEN$"))
            if index in profiles:
                if url.endswith("/usage?cedar_ember=1"):
                    self.assertEqual(headers["User-Agent"], usage.CLAUDE_CODE_AGENT)
                    body = {
                        "seven_day": {"utilization": 25 if index.endswith("-a") else 35, "resets_at": NOW + 3600},
                        "five_hour": None, "extra_usage": {"is_enabled": True, "used_credits": 90000},
                        "cedar_ember": {"eligible": True, "grants": [
                            {"resets_left": 1, "ends_at": expires},
                            {"resets_left": 2, "ends_at": None},
                        ]} if index.endswith("-a") else {"eligible": True, "grants": [{"resets_left": False}]},
                    }
                elif url.endswith("/profile"):
                    self.assertEqual(headers["anthropic-beta"], usage.CLAUDE_BETA_HEADER)
                    body = {"organization": {"uuid": profiles[index]}, "account": {"email": "fixture-person@example.invalid"}}
                else:
                    self.assertEqual((index, url), ("fixture-claude-a", usage.CLAUDE_OAUTH_URL + f"/organizations/{org}/prepaid/credits"))
                    self.assertEqual(headers["x-organization-uuid"], org)
                    self.assertEqual(headers["anthropic-client-platform"], "claude_code_cli")
                    body = {"amount": 1234, "currency": "USD"}
            elif index in codex:
                self.assertEqual(headers["Chatgpt-Account-Id"], codex[index])
                if url.endswith("/rate-limit-reset-credits"):
                    self.assertEqual(index, "fixture-codex-a")
                    body = {"available_count": 2, "credits": [
                        {"status": "available", "expires_at": remote_expiry}, {"status": "redeemed", "expires_at": expires},
                    ]}
                else:
                    self.assertTrue(url.endswith("/wham/usage"))
                    first = index.endswith("-a")
                    body = {
                        "account_id": codex[index], "rate_limit": {"primary_window": {
                            "used_percent": 40 if first else 50, "limit_window_seconds": 604800, "reset_at": NOW + 3600,
                        }},
                        "rate_limit_reset_credits": {"available_count": 2} if first else {
                            "available_count": 1, "credits": [{"status": "available", "expires_at": expires}],
                        },
                        "credits": {"has_credits": True, "unlimited": False, "balance": "12.50" if first else {}},
                    }
            else:
                region_host = "api.kimi.ai" if index.endswith("-ai") else "api.kimi.com"
                self.assertEqual(url, f"https://{region_host}/coding/v1/usages")
                body = {
                    "usages": {"limit_month_total": {"used_ratio": .35 if index.endswith("-ai") else .45,
                                                    "reset_time": "2027-02-01T00:00:00Z"}},
                    "boosterWallet": {"balance": {"type": "BOOSTER", "amount": 900000000, "amountLeft": 765000000}},
                }
            return {"status_code": 200, "body": json.dumps(body)}

        self.enterContext(mock.patch.object(self.backend, "request_json", side_effect=request))
        for name in ("codex", "kimi"):
            self.enterContext(mock.patch.object(usage, name + "_usage", side_effect=AssertionError("unexpected Direct check")))

        def poll(credits):
            args = ("--credits-providers", "claude,codex,kimi") if credits else ()
            return self.run_main("--providers", "claude,codex,kimi", "--proxy-url", usage.PROXY_URL,
                                 "--proxy-key-file", str(key), *args)["providers"]

        result = poll(True)
        for provider in result.values():
            self.assertNotIn("bankedResets", provider)
            self.assertNotIn("credits", provider)
        claude, codex_result, kimi = (
            {row["weekly"]["percent"]: row for row in result[name]["accounts"]} for name in ("claude", "codex", "kimi"))
        self.assertEqual(claude[25]["credits"]["balance"], {"amount": 12.34, "currency": "USD", "precision": 2})
        self.assertEqual(claude[25]["bankedResets"], {"count": 3, "expires": [expires]})
        self.assertNotIn("bankedResets", claude[35])
        self.assertEqual(claude[35]["credits"]["status"], "error")
        self.assertEqual(codex_result[40]["bankedResets"], {"count": 2, "expires": [expires]})
        self.assertEqual(codex_result[40]["credits"]["balance"], {"amount": 12.5, "currency": "", "precision": 2})
        self.assertEqual(codex_result[50]["bankedResets"], {"count": 1, "expires": [expires]})
        self.assertEqual(codex_result[50]["credits"]["status"], "error")
        self.assertEqual([(kimi[n]["credits"]["balance"]["currency"], kimi[n]["credits"]["balance"]["amount"])
                          for n in (35, 45)], [("USD", 7.65), ("CNY", 7.65)])
        self.assertTrue(all("/usages" in url or "/usage" in url for _, url, _ in requests[:6]))
        self.assertEqual(len(requests), 10)
        self.assertTrue(all(request[2] <= requests[0][2] for request in requests))
        self.assertEqual(len({request[2] for request in requests[:6]}), 1)
        self.now = expires
        cached = poll(False)
        self.assertTrue(all("credits" not in row for report in cached.values() for row in report["accounts"]))
        kept = {row["weekly"]["percent"]: row for row in cached["claude"]["accounts"]}
        self.assertEqual(kept[25]["bankedResets"], {"count": 2, "expires": []})
        self.assertEqual(len(requests), 10)
        stored = (usage.CACHE_DIR / "usage-proxy.json").read_text()
        self.assertIn(org, stored)
        self.assertNotIn(org, json.dumps(result))
        serialized = json.dumps(result) + stored
        for private in ("fixture-invalid-org", *profiles, *codex, *codex.values(), "fixture-person", "fixture-management-secret",
                        "2026-09-09T00:00:00Z"):
            self.assertNotIn(private, serialized)
        self.direct.assert_not_called()
        self.assertFalse(usage.CACHE_FILE.exists())

        self.now = NOW + usage.CACHE_TTL + 2
        poll(True)
        a_profiles = lambda: sum(index == "fixture-claude-a" and url.endswith("/profile") for index, url, _ in requests)
        self.assertEqual(a_profiles(), 1)
        rows[0]["modtime"] = "2026-09-09T00:05:00Z"
        self.now += usage.CACHE_TTL + 2
        poll(True)
        self.assertEqual(a_profiles(), 2)

    def test_claude_disabled_credits_remain_off_until_usage_enables_them(self):
        enabled = False

        def reading_with_credits(credential, now, *, extras, **kwargs):
            return dict(self.pooled(25), **extras("claude", {"extra_usage": {"is_enabled": enabled}}, None, now))

        self.client.usage.side_effect = reading_with_credits
        self.client.claude_credits.return_value = {"amount": 100, "currency": "USD"}
        self.poll()
        self.now += usage.CACHE_TTL
        result = self.poll("--credits-providers", "claude")
        self.assertEqual([row["credits"]["status"] for row in result["accounts"]], ["disabled", "disabled"])
        self.client.claude_credits.assert_not_called()
        enabled = True
        self.now += usage.CACHE_TTL
        result = self.poll("--credits-providers", "claude")
        self.assertEqual([row["credits"]["status"] for row in result["accounts"]], ["ok", "ok"])
        self.assertEqual(self.client.claude_credits.call_count, 2)

    def test_optional_management_refusal_stops_collection_after_preserving_core_usage(self):
        for reason in ("management-rate-limited", "management-auth"):
            with self.subTest(reason=reason):
                self.client.configuration_fingerprint = reason
                self.client.credentials.reset_mock()
                self.client.usage.reset_mock()
                self.client.claude_credits.reset_mock()
                self.client.claude_credits.side_effect = self.backend.ProxyError(reason, retry_after=900)
                shown_status = "rate-limited" if reason == "management-rate-limited" else "unauthorized"
                for _ in range(2):
                    result = self.poll("--credits-providers", "claude")
                    self.assertEqual((result["proxyStatus"], result["weekly"]["percent"], result["stale"]),
                                     (shown_status, 50, False))
                    self.assertEqual([row["state"] for row in result["accounts"]], ["ok", "ok"])
                self.client.credentials.assert_called_once()
                self.assertEqual(self.client.usage.call_count, 2)
                self.client.claude_credits.assert_called_once()
                self.direct.assert_not_called()
                self.now += usage.CACHE_TTL

    def test_optional_management_auth_hold_allows_core_to_revalidate(self):
        self.client.claude_credits.side_effect = self.backend.ProxyError("management-auth")
        response = self.poll("--credits-providers", "claude")
        self.assertEqual(response["proxyStatus"], "unauthorized")
        self.now += usage.CACHE_TTL - 1
        self.assertEqual(self.poll("--credits-providers", "claude")["proxyStatus"], "unauthorized")
        self.client.credentials.assert_called_once()
        self.client.claude_credits.side_effect = None
        self.client.claude_credits.return_value = {"amount": 500, "currency": "EUR"}
        self.now += 2
        report = self.poll("--credits-providers", "claude")
        self.assertEqual((report["proxyStatus"], report["fetchedAt"]), ("connected", self.now))
        self.assertEqual(self.client.credentials.call_count, 2)
        self.assertEqual([row["credits"]["status"] for row in report["accounts"]], ["ok", "ok"])
        self.direct.assert_not_called()

    def test_budget_rotates_optional_checks_and_persists_attempt_before_request(self):
        clock = [100.]
        self.enterContext(mock.patch.object(usage.time, "monotonic", side_effect=lambda: clock[0]))
        members = [self.credential(key) for key in ("a", "b", "c", "d")]
        self.client.credentials.return_value = {"claude": members}
        attempts = []

        def slow_credit_check(credential, *, deadline, **kwargs):
            cache = usage.read_proxy_cache()
            state = next(value for value in cache.values() if isinstance(value, dict))
            cached = state["rosters"]["claude"]["members"][credential.fingerprint]
            self.assertEqual(cached["extrasAt"], self.now)
            self.assertIn("claude", cache["_starterPaused"])
            attempts.append(credential.index)
            clock[0] = deadline
            return {"amount": 100, "currency": "EUR"}

        self.client.claude_credits.side_effect = slow_credit_check
        first = self.poll("--credits-providers", "claude")
        self.assertEqual([row["state"] for row in first["accounts"]], ["ok"] * 4)
        self.assertEqual(attempts, ["a", "b"])
        self.now += usage.CACHE_TTL
        self.poll("--credits-providers", "claude")
        self.assertEqual(attempts, ["a", "b", "c", "d"])

    def test_optional_upstream_rate_limit_keeps_cached_credit_and_guards_only_that_member(self):
        self.client.claude_credits.return_value = {"amount": 1234, "currency": "EUR"}
        self.poll("--credits-providers", "claude")
        self.now += usage.CACHE_TTL

        def check(credential, **kwargs):
            if credential == self.credential_a:
                raise self.backend.ProxyError("rate-limited", retry_after=900)
            return {"amount": 500, "currency": "EUR"}

        self.client.claude_credits.side_effect = check
        result = self.poll("--credits-providers", "claude")
        first, second = result["accounts"]
        self.assertEqual(first["state"], "ok")
        self.assertEqual((first["credits"]["status"], first["credits"]["reason"], first["credits"]["fetchedAt"]),
                         ("error", "rate-limited", NOW))
        self.assertEqual(first["credits"]["balance"]["amount"], 12.34)
        self.assertEqual(second["credits"]["balance"]["amount"], 5)
        self.client.usage.reset_mock()
        self.client.claude_credits.reset_mock()
        self.now += usage.CACHE_TTL
        self.poll("--credits-providers", "claude", "--retry-providers", "claude")
        self.assertEqual([call.args[0] for call in self.client.usage.call_args_list], [self.credential_b])
        self.assertEqual([call.args[0] for call in self.client.claude_credits.call_args_list], [self.credential_b])

    def test_codex_detail_rate_limit_keeps_count_and_allows_core_reads(self):
        codex = self.backend.Credential("codex", "fingerprint-codex", "codex")
        self.client.credentials.return_value = {"codex": [codex]}
        self.client.usage.side_effect = lambda *a, **kw: dict(self.pooled(50), bankedResets={"count": 1, "expires": []})
        self.client.codex_reset_details.side_effect = self.backend.ProxyError("rate-limited", retry_after=900)

        for _ in range(2):
            result = self.run_main("--providers", "codex", "--proxy-url", usage.PROXY_URL)["providers"]["codex"]
            self.assertEqual((result["status"], result["fetchedAt"]), ("ok", self.now))
            self.assertEqual(result["accounts"][0]["bankedResets"], {"count": 1, "expires": []})
            self.now += usage.CACHE_TTL
        self.assertEqual(self.client.usage.call_count, 2)
        self.client.codex_reset_details.assert_called_once()

    def test_codex_does_not_refetch_missing_expiries_on_every_usage_read(self):
        codex = self.backend.Credential("codex", "fingerprint-codex", "codex")
        self.client.credentials.return_value = {"codex": [codex]}
        count = 2
        expires = NOW + 3 * 3600
        self.client.usage.side_effect = lambda *a, **kw: dict(self.pooled(50), bankedResets={"count": count, "expires": []})
        self.client.codex_reset_details.return_value = {"available_count": count, "credits": [
            {"status": "available", "expires_at": expires},
        ]}

        def poll():
            return self.run_main("--providers", "codex", "--proxy-url", usage.PROXY_URL)["providers"]["codex"]

        self.assertEqual(poll()["accounts"][0]["bankedResets"], {"count": 2, "expires": [expires]})
        self.now += usage.CACHE_TTL
        self.assertEqual(poll()["accounts"][0]["bankedResets"], {"count": 2, "expires": [expires]})
        self.client.codex_reset_details.assert_called_once()
        self.assertEqual(self.client.usage.call_count, 2)
        count = 1
        self.client.codex_reset_details.return_value["available_count"] = count
        self.now += usage.CACHE_TTL
        self.assertEqual(poll()["accounts"][0]["bankedResets"], {"count": 1, "expires": [expires]})
        self.assertEqual(self.client.codex_reset_details.call_count, 2)

    def test_one_upstream_rate_limit_keeps_same_roster_reading_and_original_age(self):
        self.poll()
        self.now += usage.CACHE_TTL

        def reply(credential, now, **kwargs):
            if credential == self.credential_b:
                raise self.backend.ProxyError("rate-limited", retry_after=900)
            return self.pooled(50)

        self.client.usage.side_effect = reply
        result = self.poll()
        self.assertEqual(result["weekly"]["percent"], 60)
        self.assertTrue(result["weekly"]["incomplete"])
        self.assertEqual(result["weekly"]["history"], [[NOW, 50]])
        self.assertEqual(result["fetchedAt"], NOW)
        self.assertTrue(result["stale"])
        self.assertEqual([(row["state"], row["fetchedAt"]) for row in result["accounts"]],
                         [("ok", self.now), ("stale", NOW)])
        self.client.usage.reset_mock()
        self.now += usage.CACHE_TTL
        self.poll("--retry-providers", "claude")
        self.assertEqual([call.args[0] for call in self.client.usage.call_args_list], [self.credential_a])
        self.direct.assert_not_called()

    def test_pool_uses_zero_for_a_cached_window_that_already_reset(self):
        reset = NOW + usage.CACHE_TTL
        b = self.credential_b

        def reply(credential, now, **kwargs):
            if credential == b and now >= reset:
                raise self.backend.ProxyError("timeout")
            entry = self.pooled(95 if credential == b else 10)
            if credential == b:
                entry["weekly"]["resetsAt"] = reset
            return entry

        self.client.usage.side_effect = reply
        self.assertEqual(self.poll()["weekly"]["percent"], 53)
        self.now = reset
        result = self.poll()
        self.assertEqual(result["weekly"]["percent"], 5)
        self.assertTrue(result["weekly"]["incomplete"])
        self.assertEqual(result["weekly"]["history"], [[NOW, 53]])
        self.assertEqual(result["accounts"][1]["weekly"]["percent"], 0)
        self.assertIsNone(result["accounts"][1]["weekly"]["resetsAt"])
        self.assertTrue(result["accounts"][1]["weekly"]["incomplete"])

    def test_management_rate_limit_stops_the_round_and_holds_other_providers(self):
        codex = self.backend.Credential("codex", "fingerprint-codex", "codex")
        self.client.credentials.return_value["codex"] = [codex]
        self.enterContext(mock.patch.object(usage, "codex_usage", side_effect=AssertionError("unexpected Direct check")))

        def poll(names):
            return self.run_main("--providers", names, "--proxy-url", usage.PROXY_URL)["providers"]

        first = poll("claude,codex")
        self.now += usage.CACHE_TTL
        self.client.usage.reset_mock()
        self.client.affinity.reset_mock()
        self.client.usage.side_effect = self.backend.ProxyError("management-rate-limited", retry_after=900)
        result = poll("claude,codex")
        self.client.usage.assert_called_once()
        self.client.affinity.assert_not_called()
        for name in first:
            self.assertEqual(result[name]["weekly"]["percent"], first[name]["weekly"]["percent"])
            self.assertEqual(result[name]["fetchedAt"], NOW)
            self.assertEqual(result[name]["proxyStatus"], "rate-limited")
            self.assertTrue(result[name]["stale"])
            self.assertGreaterEqual(result[name]["retryAt"], self.now + 900)

        self.now = result["codex"]["retryAt"] - 1
        self.assertEqual(poll("codex")["codex"]["retryAt"], self.now + 1)
        self.assertEqual(self.client.credentials.call_count, 2)
        self.client.usage.assert_called_once()
        self.client.affinity.assert_not_called()

        self.now += 1
        self.client.usage.side_effect = None
        self.client.usage.return_value = self.pooled(25)
        self.assertEqual(poll("codex")["codex"]["weekly"]["percent"], 25)
        self.assertEqual(self.client.credentials.call_count, 3)
        self.direct.assert_not_called()

    def test_management_rate_limit_during_affinity_persists_without_aging_new_data(self):
        self.client.affinity.side_effect = self.backend.ProxyError("management-rate-limited", retry_after=900)
        first = self.poll()
        self.assertEqual(first["proxyStatus"], "rate-limited")
        self.assertFalse(first["stale"])
        self.now += usage.CACHE_TTL
        self.assertTrue(self.poll()["stale"])
        self.client.credentials.assert_called_once()
        self.client.affinity.assert_called_once()
        self.direct.assert_not_called()

    def test_replaced_roster_does_not_borrow_old_windows_and_never_falls_back_after_read_error(self):
        first = self.poll()
        self.now += usage.CACHE_TTL
        self.client.credentials.return_value = {"claude": [self.credential_a, self.credential("new")]}
        self.client.usage.side_effect = self.backend.ProxyError("offline")
        result = self.poll()
        self.assertEqual((result["status"], result["source"], result["proxyStatus"]), ("error", "cliproxyapi", "connected"))
        self.assertNotEqual(first["pool"], result["pool"])
        self.assertNotIn("weekly", result)
        self.assertNotIn("fetchedAt", result)
        self.assertEqual([row["state"] for row in result["accounts"]], ["unavailable", "unavailable"])
        self.now += 2 * usage.CACHE_TTL
        self.client.usage.side_effect = None
        self.client.usage.return_value = self.pooled(25)
        self.assertEqual(self.poll()["weekly"]["history"], [[self.now, 25]])
        self.direct.assert_not_called()

    def test_revoked_credential_cannot_contribute_old_usage(self):
        self.poll()
        self.now += usage.CACHE_TTL
        self.client.credentials.return_value = {"claude": [self.credential_a, self.credential("b", requires_sign_in=True)]}
        self.client.usage.reset_mock()
        result = self.poll()
        self.assertEqual([call.args[0] for call in self.client.usage.call_args_list], [self.credential_a])
        self.assertEqual(result["weekly"]["percent"], 30)
        self.assertTrue(result["weekly"]["incomplete"])
        self.assertEqual(result["accounts"][1]["state"], "unavailable")
        self.assertNotIn("weekly", result["accounts"][1])

    def test_empty_roster_and_management_connection_outage_take_direct_path(self):
        online = self.poll()
        self.assertEqual(online["source"], "cliproxyapi")
        self.now += usage.CACHE_TTL
        self.client.credentials.side_effect = self.backend.ProxyError("offline")
        result = self.poll()
        self.assertEqual(result["proxyStatus"], "offline")
        self.assertNotIn("source", result)
        self.assertEqual(result["weekly"]["percent"], 12)
        self.direct.assert_called_once()
        self.now += usage.CACHE_TTL + 1
        self.client.credentials.side_effect = None
        self.client.credentials.return_value = {}
        self.assertEqual(self.poll()["proxyStatus"], "no-accounts")

    def test_auth_failure_waits_unless_the_key_revision_changes(self):
        self.client.usage.side_effect = self.backend.ProxyError("management-auth")
        self.assertEqual(self.poll()["proxyStatus"], "unauthorized")
        self.client.usage.assert_called_once()
        self.client.affinity.assert_not_called()
        self.now += usage.PROXY_AUTH_HOLD - 1
        self.assertEqual(self.poll()["proxyStatus"], "unauthorized")
        self.client.credentials.assert_called_once()
        self.client.usage.assert_called_once()
        self.client.configuration_fingerprint = "revision-2"
        self.client.usage.side_effect = None
        self.client.usage.return_value = self.pooled(30)
        self.assertEqual(self.poll()["proxyStatus"], "connected")
        self.assertEqual(self.client.credentials.call_count, 2)

    def test_discovery_management_auth_retries_with_the_same_key_after_a_hold(self):
        self.client.credentials.side_effect = self.backend.ProxyError("management-auth")
        self.assertEqual(self.poll()["proxyStatus"], "unauthorized")
        self.now += usage.PROXY_AUTH_HOLD - 1
        self.assertEqual(self.poll()["proxyStatus"], "unauthorized")
        self.client.credentials.assert_called_once()
        self.client.usage.assert_not_called()
        self.client.affinity.assert_not_called()
        self.client.credentials.side_effect = None
        self.now += 2
        self.assertEqual(self.poll()["proxyStatus"], "connected")
        self.assertEqual(self.client.credentials.call_count, 2)

    def test_direct_override_and_switch_only_never_resolve_the_hub(self):
        self.assertNotIn("source", self.poll("--direct-providers", "claude"))
        self.direct.assert_called_once()
        self.factory.assert_not_called()
        result = self.poll("--starter-switch-only", "--starter-set", "claude=off")
        self.assertFalse(result["starter"]["enabled"])
        self.direct.assert_called_once()
        self.factory.assert_not_called()

    def test_busy_auto_keeps_source_undecided_without_reading_direct_cache(self):
        self.run_main("--providers", "claude")
        with mock.patch.object(usage, "locked", side_effect=usage.Busy()):
            result = self.run_main("--providers", "claude", "--proxy-url", usage.PROXY_URL)
        self.assertEqual(result["providers"], {})
        self.assertEqual([event["kind"] for event in result["events"]], ["busy"])
        self.direct.assert_called_once()
        self.factory.assert_not_called()

    def test_keyless_discovery_is_cached_and_does_not_authenticate(self):
        self.factory.side_effect = self.backend.ProxyError("key-file")
        self.discovery.return_value = True
        for _ in range(2):
            result = self.run_main("--providers", "claude", "--proxy-auto")["providers"]["claude"]
            self.assertEqual(result["proxyStatus"], "key-needed")
            self.assertNotIn("source", result)
        self.discovery.assert_called_once()
        self.client.credentials.assert_not_called()
        self.client.usage.assert_not_called()

    def test_default_hub_not_found_reports_ordinary_direct_reading(self):
        self.factory.side_effect = self.backend.ProxyError("key-file")
        result = self.run_main("--providers", "claude", "--proxy-auto")["providers"]["claude"]
        self.assertNotIn("proxyStatus", result)
        self.assertEqual(result["weekly"]["percent"], 12)
        self.discovery.assert_called_once()

    def test_kimi_region_override_keeps_independent_cache_layouts_and_health(self):
        ambiguous = self.backend.Credential("kimi", "fingerprint-kimi", "kimi")
        self.client.credentials.return_value = {"kimi": [ambiguous]}
        self.enterContext(mock.patch.object(usage, "kimi_usage", return_value=self.direct_reading()))

        def reply(credential, now, kimi_region, **kwargs):
            if kimi_region == "auto":
                raise self.backend.ProxyError("unsupported-credential")
            return self.pooled(30 if kimi_region == "global" else 70)

        self.client.usage.side_effect = reply

        def kimi(region):
            return self.run_main("--providers", "kimi", "--proxy-url", usage.PROXY_URL,
                                 "--proxy-kimi-region", region)["providers"]["kimi"]

        self.assertEqual(kimi("auto")["proxyStatus"], "region-needed")
        global_pool = kimi("global")
        china_pool = kimi("china")
        self.assertNotEqual(global_pool["pool"], china_pool["pool"])
        self.assertEqual(kimi("global"), global_pool)
        self.assertEqual(kimi("china"), china_pool)
        self.assertEqual(self.client.usage.call_count, 3)

    def test_server_failure_during_roster_discovery_keeps_known_accounts_stale(self):
        first = self.poll()
        self.now += usage.CACHE_TTL
        self.client.credentials.side_effect = self.backend.ProxyError("server")
        result = self.poll()
        self.assertEqual((result["source"], result["pool"], result["fetchedAt"], result["stale"]),
                         ("cliproxyapi", first["pool"], NOW, True))
        self.assertEqual([row["state"] for row in result["accounts"]], ["stale", "stale"])
        self.direct.assert_not_called()

    def test_start_checks_route_under_lock_and_resumes_after_a_real_direct_read(self):
        send = self.enterContext(mock.patch.object(usage, "send_claude"))
        self.enterContext(mock.patch.object(usage, "installed", return_value="/mock/claude"))
        self.run_main("--providers", "claude", "--starter-set", "claude=on")
        self.direct.assert_called_once()
        result = self.poll("--start")
        starter = result["starter"]
        self.assertEqual((starter["state"], starter["next"], starter["reason"], starter["on"]),
                         ("paused", None, "proxy-source", ["session"]))
        send.assert_not_called()
        self.direct.assert_called_once()
        result = self.poll("--start", "--direct-providers", "claude")
        self.assertEqual(result["starter"]["reason"], "proxy-source")
        send.assert_not_called()
        self.direct.assert_called_once()
        self.now += usage.CACHE_TTL
        result = self.poll("--start", "--direct-providers", "claude")
        self.assertEqual((result["starter"]["state"], result["starter"]["next"], result["weekly"]["percent"]),
                         ("waiting", self.now, 12))
        self.assertEqual(self.direct.call_count, 2)
        send.assert_not_called()
        result = self.poll("--start", "--direct-providers", "claude")
        self.assertEqual(result["starter"]["state"], "confirming")
        send.assert_called_once()

    def test_failed_starter_pause_write_cannot_send_using_previous_direct_cache(self):
        send = self.enterContext(mock.patch.object(usage, "send_claude"))
        self.enterContext(mock.patch.object(usage, "installed", return_value="/mock/claude"))
        self.run_main("--providers", "claude", "--starter-set", "claude=on")
        write_private = usage.write_private

        def fail_pause_write(path, data):
            if path == usage.STARTER_STATE:
                raise OSError("fixture: temporary starter state write failure")
            write_private(path, data)

        with mock.patch.object(usage, "write_private", side_effect=fail_pause_write):
            self.assertEqual(self.poll("--start")["starter"]["reason"], "proxy-source")
        self.assertFalse(usage.STARTER_STATE.exists())
        result = self.poll("--start", "--direct-providers", "claude")
        self.assertEqual((result["starter"]["reason"], result["starter"]["next"]), ("proxy-source", None))
        send.assert_not_called()
        self.direct.assert_called_once()

        self.now += usage.CACHE_TTL
        self.direct.side_effect = usage.SignedOut()
        self.assertEqual(self.poll("--start", "--direct-providers", "claude")["starter"]["reason"], "proxy-source")
        send.assert_not_called()
        self.now += usage.CACHE_TTL + 1
        self.direct.side_effect = self.direct_reading
        result = self.poll("--start", "--direct-providers", "claude")
        self.assertEqual(result["starter"]["next"], self.now)
        self.assertEqual(self.direct.call_count, 3)
        send.assert_not_called()
        self.assertEqual(self.poll("--start", "--direct-providers", "claude")["starter"]["state"], "confirming")
        send.assert_called_once()

    def test_all_parallel_reads_share_one_deadline_and_respect_worker_bound(self):
        members = [self.credential(str(i)) for i in range(usage.PROXY_WORKERS + 3)]
        self.client.credentials.return_value = {"claude": members}
        group = threading.Barrier(usage.PROXY_WORKERS)
        lock = threading.Lock()
        active = peak = 0

        def reply(credential, now, **kwargs):
            nonlocal active, peak
            with lock:
                active += 1
                peak = max(peak, active)
            if 1 <= int(credential.index) <= usage.PROXY_WORKERS:
                group.wait(3)
            with lock:
                active -= 1
            return self.pooled(30)

        self.client.usage.side_effect = reply
        self.assertEqual(len(self.poll()["accounts"]), len(members))
        self.assertEqual(peak, usage.PROXY_WORKERS)
        deadline = self.client.credentials.call_args.kwargs["deadline"]
        self.assertTrue(all(call.kwargs["deadline"] == deadline for call in self.client.usage.call_args_list))
        self.assertEqual(self.client.affinity.call_args.kwargs["deadline"], deadline)

    def test_proxy_cache_preserves_backoff_across_process_runs(self):
        self.client.usage.side_effect = self.backend.ProxyError("rate-limited", retry_after=1800)
        first = self.poll()
        self.assertEqual(first["status"], "rate_limited")
        self.now += usage.CACHE_TTL + 30
        second = self.poll()
        self.assertEqual(second["retryAt"], first["retryAt"])
        self.assertLess(second["retryAfter"], first["retryAfter"])
        self.assertEqual(self.client.usage.call_count, 2)
        self.assertEqual(usage.read_starter_states()["claude"]["proxyPaused"], True)
        self.assertEqual(json.loads(usage.STARTER_STATE.read_text())["claude"]["proxyPaused"], True)
        self.direct.assert_not_called()
