// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
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
    readonly property string expiryDetail: plain ? availableResets.expires.slice(0, 3).map(at =>
        i18nc("@info:tooltip when a banked reset expires", "Expires in %1", texts.duration(at, nowMs))).join("\n") : ""

    visible: availableResets.count > 0
    caption: i18nc("@title:group resets the account has saved to use later", "Banked resets")
    // The tickets' accessible name already says "3 banked resets".
    captionRead: false
    reading: plain ? count : tickets
    readingCap: plain ? count.figureHeight : tickets.cap
    Accessible.role: plain ? Accessible.StaticText : Accessible.NoRole
    Accessible.name: plain ? i18ncp("@info:accessible", "%1 banked reset", "%1 banked resets", availableResets.count) : ""
    Accessible.description: expiryDetail
    QQC2.ToolTip.text: expiryDetail
    QQC2.ToolTip.visible: plain && hovered.hovered && expiryDetail !== ""
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

    HoverHandler {
        id: hovered
        enabled: row.plain
    }

    Reading {
        id: count
        visible: row.plain
        value: Format.whole(row.availableResets.count)
        accessibleIgnored: true
    }

    ResetTickets {
        id: tickets
        visible: !row.plain
        banked: row.availableResets
        texts: row.texts
        nowMs: row.nowMs
    }
}
