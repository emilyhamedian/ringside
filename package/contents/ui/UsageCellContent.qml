// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami

// A Claude or Codex item in the panel: the weekly limit as a ring with the
// provider's mark inside it and the chosen model's limit as an inner ring,
// and beside it the weekly percentage over the time left until the week
// resets. The ring and its percentage turn amber or red with the weekly
// reading, and the ring breathes from 90 % until the limit is hit. A failed
// check dims the item and keeps its last reading.
Item {
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
    // Stepped by the minute timer below, for the countdown.
    property real nowMs: Date.now()

    // The readings in words, for screen readers and the tooltip.
    readonly property string accessibleDescription: words.describe(item, nowMs)

    // As tall as the ring, which the cell centres; the readings centre on it
    // in whole pixels, as the cell centres the rates, so their rows line up
    // even where the two lines are taller than the ring.
    implicitWidth: gauge.width + (readout.visible ? Kirigami.Units.largeSpacing + readout.implicitWidth : 0)
    implicitHeight: ring
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
        anchors.left: parent.left
        width: content.ring
        height: content.ring
        value: content.weekly ? content.weekly.percent : NaN
        inner: content.innerLimit !== null
        innerValue: content.innerLimit ? content.innerLimit.percent : NaN
        pulsing: value >= 90 && value < 100
        // The cell's description covers it.
        Accessible.ignored: true

        RingName {
            item: content.item
            room: gauge.centreWidth
            // Readings on one line, on a thin panel, go unnamed as the
            // rings there are too small to name them all.
            active: content.twoLines || !content.textShown
        }
    }

    Readout {
        id: readout
        anchors.left: gauge.right
        anchors.leftMargin: Kirigami.Units.largeSpacing
        y: Math.round((content.height - height) / 2)
        visible: content.textShown
        lines: words.readout(content.item, content.nowMs)
        widest: words.widestReadout(content.item)
        oneLine: !content.twoLines
    }
}
