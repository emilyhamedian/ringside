// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/style.js" as Style

// A Codex account's banked resets as tickets, one for each with the time
// left until it expires printed on it, the soonest first. Past three, two
// and a fainter ticket counting the rest. A reset that expires within three
// days is set in the theme's neutral colour; one whose expiry the reply
// didn't give is a plain ticket. Its baseline is the labels', for a
// LineTile to centre it on.
Item {
    id: tickets

    // usage.py's "bankedResets": { count, expires }.
    required property var banked
    required property var texts
    required property real nowMs

    // { text, soon, more } for each ticket drawn.
    readonly property var slots: {
        const count = banked.count;
        const expires = Array.from(banked.expires ?? []).sort((a, b) => a - b);
        const shown = Array.from({ length: Math.min(count, count > 3 ? 2 : 3) }, (_, i) => {
            const at = expires[i];
            return { text: at !== undefined ? texts.spelled(texts.countdownParts(at, nowMs, true)) : "",
                     soon: at !== undefined && at * 1000 > nowMs && at * 1000 - nowMs <= 3 * 86400000, more: false };
        });
        return count > 3 ? shown.concat([{ text: i18nc("@info more banked resets than the tickets shown, e.g. +3", "+%1", Format.whole(count - 2)),
                                           soon: false, more: true }])
                         : shown;
    }
    // When the first reset expires, for screen readers.
    readonly property real soonest: Math.min(...Array.from(banked.expires ?? []))

    // In whole pixels, so the tickets' straight edges are sharp.
    readonly property real cap: Style.capHeight(labelMetrics, labelCap)
    readonly property real ticketHeight: 2 * Math.round((cap + 3 * Kirigami.Units.smallSpacing) / 2)
    readonly property real bite: Math.round(ticketHeight * 0.15)
    readonly property real padding: bite + Kirigami.Units.smallSpacing
    // One width for every ticket: the widest label's, and no squarer than
    // a ticket is.
    readonly property real ticketWidth: Math.max(Math.round(ticketHeight * 1.7),
                                                 2 * padding + Math.ceil(Math.max(0, ...slots.map(slot => labelMetrics.advanceWidth(slot.text)))))

    implicitWidth: row.implicitWidth
    implicitHeight: ticketHeight
    baselineOffset: Math.round((ticketHeight - cap) / 2 - (labelMetrics.ascent - cap)) + labelMetrics.ascent

    Accessible.role: Accessible.StaticText
    Accessible.name: Number.isFinite(soonest) && soonest * 1000 > nowMs
        ? i18ncp("@info:accessible banked resets and when the first expires, e.g. 3 banked resets, the first expires in 2 days 4 hours",
                 "%1 banked reset, expires in %2", "%1 banked resets, the first expires in %2", banked.count, texts.duration(soonest, nowMs))
        : i18ncp("@info:accessible", "%1 banked reset", "%1 banked resets", banked.count)

    FontMetrics {
        id: labelMetrics
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        font.features: ({ "tnum": 1 })
    }

    TextMetrics {
        id: labelCap
        font: labelMetrics.font
        text: "H"
    }

    Row {
        id: row
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: tickets.slots

            Item {
                id: slot
                required property var modelData
                readonly property color tone: modelData.soon ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                width: tickets.ticketWidth
                height: tickets.ticketHeight

                Ticket {
                    anchors.fill: parent
                    opacity: slot.modelData.more ? 0.5 : 1
                    corner: tickets.bite
                    notch: tickets.bite - 0.5
                    color: Qt.alpha(slot.tone, slot.modelData.soon ? 0.6 : 0.34)
                    fillColor: Qt.alpha(slot.tone, 0.05)
                }

                Text {
                    x: Math.round((slot.width - implicitWidth) / 2)
                    y: Math.round((slot.height - tickets.cap) / 2 - (labelMetrics.ascent - tickets.cap))
                    text: slot.modelData.text
                    color: slot.modelData.more ? Style.dim(Kirigami.Theme.textColor) : slot.tone
                    font: labelMetrics.font
                    textFormat: Text.PlainText
                    Accessible.ignored: true
                }
            }
        }
    }
}
