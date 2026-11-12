// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/style.js" as Style

// A Claude or Codex account's banked resets, drawn as tickets: one for each
// reset, with the time left until it expires printed on it, soonest first.
// With more than three, it shows two tickets and a fainter one with the
// number of the rest. A reset that expires within three days is drawn in
// the theme's neutral colour, and one with no known expiry is a plain
// ticket. Its baseline is the labels' baseline, so a LineTile can centre it.
Item {
    id: tickets

    // usage.py's "bankedResets": { count, expires }.
    required property var banked
    required property var texts
    required property real nowMs

    // One { text, soon, more } for each ticket drawn.
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
    // When the first reset expires, for the screen reader description.
    readonly property real soonest: Math.min(...Array.from(banked.expires ?? []))

    // Sizes are whole pixels, so the tickets' straight edges stay sharp.
    readonly property real cap: Style.capHeight(labelMetrics, labelCap)
    readonly property real ticketHeight: 2 * Math.round((cap + 3 * Kirigami.Units.smallSpacing) / 2)
    readonly property real bite: Math.round(ticketHeight * 0.15)
    readonly property real padding: bite + Kirigami.Units.smallSpacing
    // Every ticket gets the same width: wide enough for the widest label,
    // and at least 1.7 times the height, so it still looks like a ticket.
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
