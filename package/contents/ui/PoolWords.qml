// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import "code/format.js" as Format

QtObject {
    function sourceStatus(status, count) {
        switch (status) {
        case "connected":
            return Number.isFinite(count)
                ? i18ncp("@info CLIProxyAPI connection status, %2 is the localized number of accounts",
                         "Connected · %2 account", "Connected · %2 accounts", count, Format.whole(count))
                : i18nc("@info CLIProxyAPI connection status", "Connected");
        case "key-needed":
            return i18nc("@info CLIProxyAPI connection status", "A readable management key file is needed.");
        case "unauthorized":
            return i18nc("@info CLIProxyAPI connection status", "The hub declined the management key.");
        case "offline":
            return i18nc("@info CLIProxyAPI connection status", "The hub could not be reached.");
        case "rate-limited":
            return i18nc("@info CLIProxyAPI connection status", "The hub asked Ringside to wait before checking again.");
        case "no-accounts":
            return i18nc("@info CLIProxyAPI connection status", "The hub has no enabled accounts for this provider.");
        case "unsupported":
            return i18nc("@info CLIProxyAPI connection status", "The hub could not read usage for these accounts.");
        case "region-needed":
            return i18nc("@info CLIProxyAPI connection status", "Choose the region for the imported Kimi credentials in AI Providers.");
        case "configuration":
            return i18nc("@info CLIProxyAPI connection status", "Check the hub URL and management key file.");
        default:
            return "";
        }
    }

    function average(period) {
        switch (period) {
        case "week":
            return i18nc("@info pooled weekly usage below a provider name", "Pooled weekly limits");
        case "month":
            return i18nc("@info pooled monthly usage below a provider name", "Pooled monthly limits");
        case "session":
            return i18nc("@info pooled session usage below a provider name", "Pooled session limits");
        default:
            return i18nc("@info pooled usage below a provider name", "Pooled limits");
        }
    }

    function directStatus(entry) {
        const status = sourceStatus(entry?.proxyStatus);
        return status ? i18nc("@info usage has fallen back to a direct login, %1 is the hub connection status",
                             "Using direct login. %1", status) : "";
    }

    function resetCaption(window) {
        if (window?.incomplete) {
            return i18nc("@info:label under a countdown for an incomplete pool", "next known reset");
        }
        switch (window?.period) {
        case "week":
            return i18nc("@info:label under a weekly reset countdown", "next weekly reset");
        case "month":
            return i18nc("@info:label under a monthly reset countdown", "next monthly reset");
        default:
            return i18nc("@info:label under a pooled reset countdown", "next reset");
        }
    }

    function quality(entry) {
        if (entry?.lastError !== undefined || entry?.accounts?.some(account => account.state === "stale")) {
            return i18nc("@info CLIProxyAPI usage snapshot", "Includes last known readings.");
        }
        return "";
    }

    function incomplete(entry, otherPeriods = []) {
        return !!(entry?.partial || entry?.weekly?.incomplete || entry?.scoped?.some(window => window.incomplete)
            || otherPeriods.some(window => window.incomplete)
            || entry?.accounts?.some(account => account.state === "unavailable"));
    }

    function paused() {
        return i18nc("@info CLIProxyAPI automatic session or week starter", "Auto start paused for CLIProxyAPI.");
    }
}
