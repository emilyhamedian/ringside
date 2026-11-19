# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import json
import threading
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

    def test_pool_cache_uses_distinct_storage_and_no_direct_credit_or_history(self):
        result = self.poll("--credits-providers", "claude")
        self.assertEqual((result["source"], result["proxyStatus"], result["fetchedAt"]), ("cliproxyapi", "connected", NOW))
        self.assertEqual(result["weekly"]["percent"], 50)
        self.assertEqual(result["affinity"], {"enabled": True, "ttlSeconds": 900})
        self.assertNotIn("credits", result)
        self.assertNotIn("history", result["weekly"])
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
        self.assertEqual(result["fetchedAt"], NOW)
        self.assertTrue(result["stale"])
        self.assertEqual([(row["state"], row["fetchedAt"]) for row in result["accounts"]],
                         [("ok", self.now), ("stale", NOW)])
        self.client.usage.reset_mock()
        self.now += usage.CACHE_TTL
        self.poll("--retry-providers", "claude")
        self.assertEqual([call.args[0] for call in self.client.usage.call_args_list], [self.credential_a])
        self.direct.assert_not_called()

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

    def test_auth_failure_latches_after_discovery_and_until_key_revision_changes(self):
        self.client.usage.side_effect = self.backend.ProxyError("management-auth")
        self.assertEqual(self.poll()["proxyStatus"], "unauthorized")
        self.client.usage.assert_called_once()
        self.client.affinity.assert_not_called()
        self.now += 2 * usage.HOLD_MAX
        self.assertEqual(self.poll()["proxyStatus"], "unauthorized")
        self.client.credentials.assert_called_once()
        self.client.usage.assert_called_once()
        self.client.configuration_fingerprint = "revision-2"
        self.client.usage.side_effect = None
        self.client.usage.return_value = self.pooled(30)
        self.assertEqual(self.poll()["proxyStatus"], "connected")
        self.assertEqual(self.client.credentials.call_count, 2)

    def test_discovery_management_auth_failure_does_not_reach_any_account(self):
        self.client.credentials.side_effect = self.backend.ProxyError("management-auth")
        self.assertEqual(self.poll()["proxyStatus"], "unauthorized")
        self.now += 2 * usage.HOLD_MAX
        self.assertEqual(self.poll()["proxyStatus"], "unauthorized")
        self.client.credentials.assert_called_once()
        self.client.usage.assert_not_called()
        self.client.affinity.assert_not_called()

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
