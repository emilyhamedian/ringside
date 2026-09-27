import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/style.js" as Style

// A panel ring with the item's name over its main reading: the CPU's
// temperature, the GPUs' temperatures, or memory in use. With the text
// hidden, the ring itself turns amber or red for the hottest temperature.
RowLayout {
    id: content

    required property var monitor
    required property string item
    required property real ring
    required property bool textShown
    required property bool twoLines

    readonly property var gpuOuter: monitor.gpuOuter
    readonly property var gpuInner: monitor.gpuInner
    readonly property bool dual: item === "gpu" && gpuInner.present
    // Intel GPUs publish no temperature, so theirs is left out.
    readonly property bool outerShown: item !== "gpu" || gpuOuter.reportsTemperature || gpuOuter.phase === "asleep"
    readonly property bool innerShown: dual && (gpuInner.reportsTemperature || gpuInner.phase === "asleep")
    readonly property color dimColor: Style.dim(Kirigami.Theme.textColor)
    readonly property real valuePointSize: Kirigami.Theme.defaultFont.pointSize * 0.96
    readonly property string offText: i18nc("@info:status the GPU is powered down", "off")
    // Three digits hold any temperature (under 150 °C, 302 °F); an asleep
    // GPU says "off" in their place.
    readonly property string widestTemperature: item === "gpu" && offText.length > 3 ? offText : "000"
    readonly property real hottest: Math.max(...(item === "cpu" ? [monitor.cpuTemperature]
                                                 : item === "gpu" ? [gpuOuter.temperature, dual ? gpuInner.temperature : NaN]
                                                 : []).filter(Format.temperatureValid))

    // The readings in words, for screen readers and the tooltip.
    readonly property string accessibleDescription: {
        if (item === "cpu") {
            return i18nc("@info:tooltip processor usage and temperature", "Usage %1, temperature %2",
                         percentText(monitor.cpuUsage), temperatureText(monitor.cpuTemperature));
        }
        if (item === "memory") {
            const used = Format.bytes(monitor.memoryUsed);
            return Number.isFinite(monitor.memoryUsed)
                ? i18nc("@info:tooltip memory in use; %1 %2 is e.g. 13.4 GiB, %3 a percentage", "%1 %2 in use, %3",
                        used.value, used.unit, percentText(monitor.memoryPercent))
                : i18nc("@info:tooltip memory in use", "In use: unavailable");
        }
        return dual ? i18nc("@info:tooltip two GPUs, one per line: name, then readings", "%1: %2\n%3: %4",
                            gpuOuter.name, gpuText(gpuOuter), gpuInner.name, gpuText(gpuInner))
                    : gpuText(gpuOuter);
    }

    function heatColor(celsius, normal) {
        const level = monitor.heat(celsius);
        return level === 2 ? Kirigami.Theme.negativeTextColor : level === 1 ? Kirigami.Theme.neutralTextColor : normal;
    }

    function percentText(value) {
        return Number.isFinite(value) ? i18nc("@info:tooltip a percentage", "%1%", Format.percent(value))
                                      : i18nc("@info:tooltip no reading", "unavailable");
    }

    function temperatureText(celsius) {
        if (!Format.temperatureValid(celsius)) {
            return i18nc("@info:tooltip no reading", "unavailable");
        }
        const text = monitor.fahrenheit
            ? i18nc("@info:tooltip a temperature", "%1 °F", Format.temperature(celsius, true))
            : i18nc("@info:tooltip a temperature", "%1 °C", Format.temperature(celsius, false));
        const level = monitor.heat(celsius);
        return level === 2 ? i18nc("@info:tooltip a temperature above the red threshold", "%1, hot", text)
             : level === 1 ? i18nc("@info:tooltip a temperature above the amber threshold", "%1, warm", text)
             : text;
    }

    function gpuText(slot) {
        if (slot.phase === "asleep") {
            return i18nc("@info:tooltip the GPU is powered down", "Off");
        }
        return slot.reportsTemperature
            ? i18nc("@info:tooltip GPU usage and temperature", "Usage %1, temperature %2",
                    percentText(slot.usage), temperatureText(slot.temperature))
            : i18nc("@info:tooltip GPU usage; this GPU has no temperature sensor", "Usage %1", percentText(slot.usage));
    }

    spacing: Kirigami.Units.largeSpacing

    RingGauge {
        Layout.preferredWidth: content.ring
        Layout.preferredHeight: content.ring
        inner: content.dual
        value: content.item === "cpu" ? content.monitor.cpuUsage
             : content.item === "memory" ? content.monitor.memoryPercent : content.gpuOuter.usage
        innerValue: content.gpuInner.usage
        text: Format.percent(value)
        color: content.textShown ? Kirigami.Theme.textColor : content.heatColor(content.hottest, Kirigami.Theme.textColor)
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
                                                                       : content.gpuOuter.temperature
                readonly property bool asleep: content.item === "gpu" && content.gpuOuter.phase === "asleep"

                visible: content.outerShown
                degree: content.item !== "memory"
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
                readonly property bool asleep: content.gpuInner.phase === "asleep"

                visible: content.innerShown
                degree: true
                value: asleep ? content.offText : Format.temperature(celsius, content.monitor.fahrenheit)
                widest: content.widestTemperature
                color: content.heatColor(celsius, content.dimColor)
                pointSize: content.valuePointSize
            }
        }
    }
}
