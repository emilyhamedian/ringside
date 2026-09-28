// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/style.js" as Style

// A Claude or Codex item in the panel: the weekly limit as a ring, with the
// chosen model's limit inside it, and the item's name over the time left
// until the week resets. The ring and the time turn amber or red with the
// weekly reading, and the ring breathes from 90 % until the limit is hit.
// A failed check dims the item and keeps its last reading.
RowLayout {
    id: content

    required property var monitor
    required property string item
    required property real ring
    required property bool textShown
    required property bool twoLines

    readonly property var usage: monitor.usage
    readonly property var entry: usage.entry(item)
    readonly property var weekly: entry && entry.weekly ? entry.weekly : null
    readonly property var innerLimit: usage.inner(item)
    readonly property real valuePointSize: Kirigami.Theme.defaultFont.pointSize * 0.96
    // Stepped by the minute timer below, for the countdown.
    property real nowMs: Date.now()

    // The readings in words, for screen readers and the tooltip.
    readonly property string accessibleDescription: words.describe(item, nowMs)

    spacing: Kirigami.Units.largeSpacing
    opacity: usage.degraded(item) ? 0.55 : 1

    Words {
        id: words
        monitor: content.monitor
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: content.nowMs = Date.now()
    }

    // Sent before the readings change, so the arcs start from the old ones.
    // An inner limit's reset plays only while that limit is the one shown.
    Connections {
        target: content.usage

        function onResetsDetected(events) {
            const limit = content.innerLimit;
            gauge.playResets(events[content.item + ".weekly"] ?? null,
                             limit ? events[content.item + ".scoped." + limit.id] ?? null : null);
        }
    }

    RingGauge {
        id: gauge
        Layout.preferredWidth: content.ring
        Layout.preferredHeight: content.ring
        value: content.weekly ? content.weekly.percent : NaN
        inner: content.innerLimit !== null
        innerValue: content.innerLimit ? content.innerLimit.percent : NaN
        text: Format.percent(value)
        pulsing: value >= 90 && value < 100
        // The cell's description covers it.
        Accessible.ignored: true
    }

    ColumnLayout {
        visible: content.textShown
        spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)

        Text {
            visible: content.twoLines
            text: content.item === "claude" ? i18nc("@label the Claude Code item, in capitals like CPU", "CLAUDE")
                                            : i18nc("@label the Codex item, in capitals like CPU", "CODEX")
            color: Style.dim(Kirigami.Theme.textColor)
            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.95
            font.letterSpacing: Kirigami.Theme.smallFont.pointSize * 0.08
            textFormat: Text.PlainText
        }

        Reading {
            value: words.countdown(content.weekly ? content.weekly.resetsAt : null, content.nowMs) || "–"
            widest: words.widestCountdown()
            color: gauge.outerTone
            pointSize: content.valuePointSize
        }
    }
}
