// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/hardware.js" as Hardware
import "code/style.js" as Style

// A panel ring with the item's name over its main reading: the CPU's
// temperature, the GPUs' temperatures, or memory in use. The ring turns
// amber or red from its own reading; with the text hidden, a hot
// temperature raises it too. A GPU that is asleep drops out, and the one
// still awake is shown as the only ring, as on a single-GPU machine.
RowLayout {
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
    // Intel GPUs publish no temperature, so theirs is left out.
    readonly property bool outerShown: item !== "gpu" || primary.reportsTemperature || primary.phase === "asleep"
    readonly property bool innerShown: dual && gpuInner.reportsTemperature
    readonly property color dimColor: Style.dim(Kirigami.Theme.textColor)
    readonly property real valuePointSize: Kirigami.Theme.defaultFont.pointSize * 0.96
    readonly property string offText: i18nc("@info:status the GPU is powered down", "off")
    // Three digits hold any temperature (under 150 °C, 302 °F); an asleep
    // GPU says "off" in their place.
    readonly property string widestTemperature: item === "gpu" && offText.length > 3 ? offText : "000"
    readonly property real hottest: Math.max(...(item === "cpu" ? [monitor.cpuTemperature]
                                                 : item === "gpu" ? [primary.temperature, dual ? gpuInner.temperature : NaN]
                                                 : []).filter(Format.temperatureValid))

    // The readings in words, for screen readers and the tooltip.
    readonly property string accessibleDescription: words.describe(item)

    function heatColor(celsius, normal) {
        const level = monitor.heat(celsius);
        return level === 2 ? Kirigami.Theme.negativeTextColor : level === 1 ? Kirigami.Theme.neutralTextColor : normal;
    }

    spacing: Kirigami.Units.largeSpacing

    Words {
        id: words
        monitor: content.monitor
    }

    RingGauge {
        Layout.preferredWidth: content.ring
        Layout.preferredHeight: content.ring
        inner: content.dual
        value: content.item === "cpu" ? content.monitor.cpuUsage
             : content.item === "memory" ? content.monitor.memoryPercent : content.primary.usage
        innerValue: content.gpuInner.usage
        text: Format.percent(value)
        minimumLevel: content.textShown ? 0 : content.monitor.heat(content.hottest)
        // The cell's description covers it.
        Accessible.ignored: true
    }

    ColumnLayout {
        visible: content.textShown && (content.twoLines || content.outerShown || content.innerShown)
        spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)

        Text {
            visible: content.twoLines
            text: content.item === "cpu" ? i18nc("@label short for processor", "CPU")
                : content.item === "gpu" ? i18nc("@label short for graphics card", "GPU")
                : i18nc("@label short for memory", "MEM")
            color: content.dimColor
            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.95
            font.letterSpacing: Kirigami.Theme.smallFont.pointSize * 0.08
            textFormat: Text.PlainText
        }

        RowLayout {
            spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)

            Reading {
                readonly property var used: Format.bytes(content.monitor.memoryUsed)
                readonly property real celsius: content.item === "cpu" ? content.monitor.cpuTemperature
                                                                       : content.primary.temperature
                readonly property bool asleep: content.item === "gpu" && content.primary.phase === "asleep"

                visible: content.outerShown
                degree: content.item !== "memory" && !asleep
                value: content.item === "memory" ? used.value
                     : asleep ? content.offText
                     : Format.temperature(celsius, content.monitor.fahrenheit)
                unit: content.item === "memory" ? used.unit : ""
                widest: content.item === "memory" ? "0000" : content.widestTemperature
                widestUnit: "GiB"
                color: asleep ? content.dimColor
                     : content.item === "memory" ? Kirigami.Theme.textColor
                     : content.heatColor(celsius, Kirigami.Theme.textColor)
                pointSize: content.valuePointSize
            }

            Reading {
                readonly property real celsius: content.gpuInner.temperature

                visible: content.innerShown
                degree: true
                value: Format.temperature(celsius, content.monitor.fahrenheit)
                widest: content.widestTemperature
                color: content.heatColor(celsius, content.dimColor)
                pointSize: content.valuePointSize
            }
        }
    }
}
