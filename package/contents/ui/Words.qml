import QtQuick
import "code/format.js" as Format
import "code/hardware.js" as Hardware

// Each item's readings in words, for screen readers and tooltips in either
// layout.
QtObject {
    id: words

    // Monitor.qml, or anything shaped like it.
    required property var monitor

    function describe(item, nowMs) {
        switch (item) {
        case "cpu":
            return i18nc("@info:tooltip processor usage and temperature", "Usage %1, temperature %2",
                         percentText(monitor.cpuUsage), temperatureText(monitor.cpuTemperature));
        case "memory": {
            const used = Format.bytes(monitor.memoryUsed);
            return Number.isFinite(monitor.memoryUsed)
                ? i18nc("@info:tooltip memory in use; %1 %2 is e.g. 13.4 GiB, %3 a percentage", "%1 %2 in use, %3",
                        used.value, used.unit, percentText(monitor.memoryPercent))
                : i18nc("@info:tooltip memory in use", "In use: unavailable");
        }
        case "gpu": {
            const view = Hardware.gpuView(monitor.gpuOuter, monitor.gpuInner);
            return view.dual ? i18nc("@info:tooltip two GPUs, one per line: name, then readings", "%1: %2\n%3: %4",
                                     monitor.gpuOuter.name, gpuText(monitor.gpuOuter),
                                     monitor.gpuInner.name, gpuText(monitor.gpuInner))
                             : gpuText(view.primary);
        }
        case "network":
            return i18nc("@info:tooltip network download and upload rates", "Down %1, up %2",
                         rateText(Format.rate(monitor.networkDown, monitor.networkBits)),
                         rateText(Format.rate(monitor.networkUp, monitor.networkBits)));
        case "disk":
            return i18nc("@info:tooltip disk read and write rates", "Read %1, write %2",
                         rateText(Format.rate(monitor.diskRead, false)), rateText(Format.rate(monitor.diskWrite, false)));
        }
        return "";
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

    function rateText(reading) {
        return reading.value === "–" ? i18nc("@info:tooltip no reading", "unavailable")
                                     : i18nc("@info:tooltip a transfer rate, e.g. 24.8 Mb/s", "%1 %2", reading.value, reading.unit);
    }
}
