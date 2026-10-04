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
// is shown as the only ring, as on a single-GPU machine.
Item {
    id: content

    required property var monitor
    required property string item
    required property real ring
    required property bool textShown
    required property bool twoLines

    readonly property var gpuOuter: monitor.gpuOuter
    readonly property var gpuInner: monitor.gpuInner
    readonly property var gpuView: Hardware.gpuView(gpuOuter, gpuInner)
    readonly property bool dual: item === "gpu" && gpuView.dual
    // The GPU the ring shows: the outer one, unless it sleeps and the inner one doesn't.
    readonly property var primary: gpuView.primary
    readonly property real hottest: Math.max(...(item === "cpu" ? [monitor.cpuTemperature]
                                                 : item === "gpu" ? [primary.temperature, dual ? gpuInner.temperature : NaN]
                                                 : []).filter(Format.temperatureValid))

    // The readings in words, for screen readers and the tooltip.
    readonly property string accessibleDescription: words.describe(item)

    // As tall as the ring, which the cell centres; the readings centre on it
    // in whole pixels, as the cell centres the rates, so their rows line up
    // even where the two lines are taller than the ring.
    implicitWidth: gauge.width + (readout.visible ? Kirigami.Units.largeSpacing + readout.implicitWidth : 0)
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
        value: content.item === "cpu" ? content.monitor.cpuUsage
             : content.item === "memory" ? content.monitor.memoryPercent : content.primary.usage
        innerValue: content.gpuInner.usage
        minimumLevel: content.textShown ? 0 : content.monitor.heat(content.hottest)
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
        lines: words.readout(content.item)
        widest: words.widestReadout(content.item)
        oneLine: !content.twoLines
    }
}
