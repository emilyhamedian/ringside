// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import "code/format.js" as Format

QtObject {
    readonly property string sourceName: i18nc("@info usage source under a provider name", "CLIProxyAPI")

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
}
