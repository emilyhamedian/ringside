// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/hardware.js" as Hardware

// A panel ring with the item's name inside it, and beside it the ring's
// percentage over the CPU's or GPU's temperature or the memory in use. The
// ring and its percentage turn amber or red from the ring's reading, the
// temperature from its own; with the text hidden, a hot temperature raises
// the ring instead. A GPU that is asleep drops out, and the one still awake
// is shown as the only ring, as on a single-GPU machine. When the readings
// turn to another GPU, or it sleeps or wakes, they fade out, change and fade
// back in; other readings change at once.
Item {
    id: content

    required property var monitor
    required property string item
    required property real ring
    required property bool textShown
    required property bool twoLines
    // Strip.egg.
    property Egg egg: null

    readonly property var gpuOuter: monitor.gpuOuter
    readonly property var gpuInner: monitor.gpuInner
    readonly property var gpuView: Hardware.gpuView(gpuOuter, gpuInner)
    readonly property bool dual: item === "gpu" && gpuView.dual
    // The GPU the ring shows: the outer one, unless it sleeps and the inner one doesn't.
    readonly property var primary: gpuView.primary
    readonly property real hottest: Math.max(...(item === "cpu" ? [monitor.panel.cpuTemperature]
                                                 : item === "gpu" ? [primary.panelTemperature, dual ? gpuInner.panelTemperature : NaN]
                                                 : []).filter(Format.temperatureValid))

    // The readings in words, for screen readers and the tooltip.
    readonly property string accessibleDescription: words.describe(item)

    // Off changes the readings, and the name in the ring, at once, as at
    // Plasma's Instant speed. The tests turn it off to check layouts.
    property bool animated: Kirigami.Units.longDuration > 1
    readonly property var lines: words.readout(item)
    readonly property string described: describes()
    // The readings shown: set rather than bound, so a fade can hold them.
    property var shownLines: ({ first: "", level: 0, second: "" })
    property string shownDescribed: ""
    property bool fading: false
    property bool ready: false

    // Which GPU the readings describe, and whether it is awake. Worked out
    // afresh, since the bindings may not have caught up with a change yet.
    function describes() {
        const gpu = item === "gpu" ? Hardware.gpuView(gpuOuter, gpuInner).primary : null;
        return gpu ? (gpu === gpuInner ? "inner" : "outer") + (gpu.phase === "asleep" ? " off" : "") : "";
    }

    function show() {
        shownLines = lines;
        shownDescribed = describes();
    }

    // A change back before the old readings have faded out fades them up again.
    function update() {
        if (!ready) {
            return;
        }
        if (describes() === shownDescribed) {
            shownLines = lines;
            if (fading) {
                fading = false;
                change.stop();
                back.start();
            }
        } else if (!animated) {
            show();
        } else if (!fading) {
            fading = true;
            back.stop();
            change.restart();
        }
    }

    Component.onCompleted: {
        show();
        ready = true;
    }
    onLinesChanged: update()
    onDescribedChanged: update()

    SequentialAnimation {
        id: change
        NumberAnimation { target: readout; property: "opacity"; to: 0; duration: Kirigami.Units.shortDuration; easing.type: Easing.InQuad }
        ScriptAction {
            script: {
                content.fading = false;
                content.show();
            }
        }
        NumberAnimation { target: readout; property: "opacity"; to: 1; duration: Kirigami.Units.shortDuration; easing.type: Easing.OutQuad }
    }

    NumberAnimation { id: back; target: readout; property: "opacity"; to: 1; duration: Kirigami.Units.shortDuration; easing.type: Easing.OutQuad }

    // As tall as the ring, which the cell centres; the readings centre on it
    // in whole pixels, as the cell centres the rates, so their rows line up
    // even where the two lines are taller than the ring.
    implicitWidth: gauge.width + (readout.visible ? Kirigami.Units.largeSpacing + readout.textWidth : 0)
    implicitHeight: ring

    Words {
        id: words
        monitor: content.monitor
    }

    RingGauge {
        id: gauge
        anchors.left: parent.left
        width: content.ring
        height: content.ring
        inner: content.dual
        value: content.item === "cpu" ? content.monitor.panel.cpuUsage
             : content.item === "memory" ? content.monitor.panel.memoryPercent : content.primary.panelUsage
        innerValue: content.gpuInner.panelUsage
        minimumLevel: content.textShown ? 0 : content.monitor.heat(content.hottest)
        interval: content.monitor.interval
        egg: content.egg
        // The cell's description covers it.
        Accessible.ignored: true

        RingName {
            item: content.item
            room: gauge.centreWidth
            // Readings on one line, on a thin panel, go unnamed as the
            // rings there are too small to name them all.
            active: content.twoLines || !content.textShown
            animated: content.animated
        }
    }

    Readout {
        id: readout
        anchors.left: gauge.right
        anchors.leftMargin: Kirigami.Units.largeSpacing
        y: Math.round((content.height - height) / 2)
        visible: content.textShown
        lines: content.shownLines
        oneLine: !content.twoLines
        widest: words.widest(content.item)
    }
}
