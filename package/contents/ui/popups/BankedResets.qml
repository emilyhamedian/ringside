// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import ".."

LineTile {
    id: row
    objectName: "resets"

    required property var banked
    required property Words texts
    required property real nowMs

    readonly property alias ticketHeight: tickets.ticketHeight
    readonly property var availableResets: {
        const dates = Array.from(banked?.expires ?? []);
        const unexpired = dates.filter(at => at * 1000 > nowMs);
        const count = (banked?.count ?? 0) - (dates.length - unexpired.length);
        return { count: Math.max(count, 0), expires: unexpired };
    }

    visible: availableResets.count > 0
    caption: i18nc("@title:group resets the account has saved to use later", "Banked resets")
    // The tickets' accessible name already says "3 banked resets".
    captionRead: false
    reading: tickets
    readingCap: tickets.cap

    ResetTickets {
        id: tickets
        banked: row.availableResets
        texts: row.texts
        nowMs: row.nowMs
    }
}
