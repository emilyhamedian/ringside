// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import "code/format.js" as Format
import "code/hardware.js" as Hardware

// Each item's readings in words, for screen readers and tooltips, the short
// readings beside a ring, and the times the Claude and Codex views show.
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
        case "claude":
        case "codex":
            return usageText(item, nowMs ?? Date.now());
        }
        return "";
    }

    // The two short readings by a ring: the ring's own percentage, or "off"
    // for the only GPU while it sleeps, then its temperature, the memory in
    // use or the time to the weekly reset; empty where there is none, as for Intel GPUs, which publish no temperature.
    // `level` and `heat` choose their colours (see Readout). The integrated
    // GPU's temperature stays in the words and the popup.
    function readout(item, nowMs) {
        const percent = value => Number.isFinite(value) ? i18nc("@info:status a percentage", "%1%", Format.percent(value)) : "–";
        const temperature = celsius => Format.temperatureValid(celsius)
            ? Format.temperature(celsius, monitor.fahrenheit) + "°" : "–";
        switch (item) {
        case "cpu":
            return { first: percent(monitor.cpuUsage), level: Format.level(monitor.cpuUsage),
                     second: temperature(monitor.cpuTemperature), heat: monitor.heat(monitor.cpuTemperature) };
        case "gpu": {
            const gpu = Hardware.gpuView(monitor.gpuOuter, monitor.gpuInner).primary;
            if (gpu.phase === "asleep") {
                return { first: i18nc("@info:status the GPU is powered down", "off"), off: true, second: "" };
            }
            return { first: percent(gpu.usage), level: Format.level(gpu.usage),
                     second: gpu.reportsTemperature ? temperature(gpu.temperature) : "",
                     heat: gpu.reportsTemperature ? monitor.heat(gpu.temperature) : 0 };
        }
        case "memory": {
            const used = Format.bytes(monitor.memoryUsed);
            return { first: percent(monitor.memoryPercent), level: Format.level(monitor.memoryPercent),
                     second: used.value + used.unit.charAt(0) };
        }
        }
        const entry = monitor.usage.entry(item);
        const weekly = entry && entry.weekly ? entry.weekly : null;
        return { first: percent(weekly ? weekly.percent : NaN), level: Format.level(weekly ? weekly.percent : NaN),
                 second: countdown(weekly ? weekly.resetsAt : null, nowMs ?? Date.now()) || "–" };
    }

    // The widest texts each line of readout() can show, for the room it keeps.
    function widestReadout(item) {
        const percent = i18nc("@info:status a percentage", "%1%", Format.percent(100));
        const temperature = Format.whole(100) + "°";
        switch (item) {
        case "cpu":
            return [[percent], [temperature]];
        case "gpu":
            return [[percent, i18nc("@info:status the GPU is powered down", "off")], [temperature]];
        case "memory":
            return [[percent], [Format.whole(1000) + "M"]];
        }
        return [[percent], [widestCountdown()]];
    }

    // A Claude or Codex item: its weekly use, the limit on its inner ring,
    // when the week resets, and a failed last check.
    function usageText(item, nowMs) {
        const usage = monitor.usage;
        const entry = usage.entry(item);
        if (entry === null) {
            return usage.helperError || i18nc("@info:tooltip the usage has not been read yet", "Not checked yet");
        }
        if (entry.status === "signed_out") {
            return i18nc("@info:tooltip", "Signed out");
        }
        const used = percentText(entry.weekly ? entry.weekly.percent : NaN);
        const left = duration(entry.weekly ? entry.weekly.resetsAt : null, nowMs);
        const limit = usage.inner(item);
        let text;
        if (limit) {
            text = left ? i18nc("@info:tooltip weekly share used, a model's own limit, time to the reset, e.g. 62% used, Opus 78%, resets in 2 days 21 hours",
                                "%1 used, %2 %3, resets in %4", used, limit.label, percentText(limit.percent), left)
                        : i18nc("@info:tooltip weekly share used and a model's own limit, e.g. 62% used, Opus 78%",
                                "%1 used, %2 %3", used, limit.label, percentText(limit.percent));
        } else {
            text = left ? i18nc("@info:tooltip weekly share used and time to the reset, e.g. 62% used, resets in 2 days 21 hours",
                                "%1 used, resets in %2", used, left)
                        : i18nc("@info:tooltip weekly share used, e.g. 62% used", "%1 used", used);
        }
        return entry.lastError === undefined ? text
            : i18nc("@info:tooltip a reading, then when checking it last failed", "%1. Last check failed at %2.",
                    text, timeOfDay(entry.lastErrorAt, nowMs));
    }

    // Time to a reset in the panel's letters: "2d 21h", "5h 12m", "12m";
    // empty once it has passed.
    function countdown(resetsAt, nowMs) {
        const left = Format.timeLeft(resetsAt, nowMs);
        if (left === null) {
            return "";
        }
        return left.days > 0 ? i18nc("@info time left in days and hours, e.g. 2d 21h", "%1d %2h",
                                     Format.whole(left.days), Format.whole(left.hours))
             : left.hours > 0 ? i18nc("@info time left in hours and minutes, e.g. 5h 12m", "%1h %2m",
                                      Format.whole(left.hours), Format.whole(left.minutes))
             : i18nc("@info time left in minutes, e.g. 12m", "%1m", Format.whole(left.minutes));
    }

    // The longest countdown() can get, for reserving its room: a week holds
    // no more than one digit of days.
    function widestCountdown() {
        const one = Format.whole(0);
        const two = one + one;
        return [i18nc("@info time left in days and hours, e.g. 2d 21h", "%1d %2h", one, two),
                i18nc("@info time left in hours and minutes, e.g. 5h 12m", "%1h %2m", two, two),
                i18nc("@info time left in minutes, e.g. 12m", "%1m", two)]
            .reduce((a, b) => b.length > a.length ? b : a);
    }

    // Time to a reset spelled out for screen readers: "2 days 21 hours".
    function duration(resetsAt, nowMs) {
        const left = Format.timeLeft(resetsAt, nowMs);
        if (left === null) {
            return "";
        }
        const days = i18ncp("@info:tooltip part of a time left", "%1 day", "%1 days", left.days);
        const hours = i18ncp("@info:tooltip part of a time left", "%1 hour", "%1 hours", left.hours);
        const minutes = i18ncp("@info:tooltip part of a time left", "%1 minute", "%1 minutes", left.minutes);
        const pair = (first, second, secondCount) => secondCount > 0
            ? i18nc("@info:tooltip a time left in two units, e.g. 2 days 21 hours", "%1 %2", first, second) : first;
        return left.days > 0 ? pair(days, hours, left.hours)
             : left.hours > 0 ? pair(hours, minutes, left.minutes)
             : minutes;
    }

    // When a window resets, in the user's locale: "Sun 7:00 AM EDT" in the
    // desktop clock's zone when the helper passes one, else "Sun 7:00 AM" in
    // system time.
    function resetDate(window) {
        if (!window || !Format.usable(window.resetsAt)) {
            return "";
        }
        const zone = window.clockZone;
        // To the nearest minute: a reset reported as 10:59:59 reads as 11:00.
        const at = Math.round(window.resetsAt / 60) * 60;
        const date = zone ? Format.wallClock(at, zone.offset) : new Date(at * 1000);
        const locale = Qt.locale();
        const day = locale.dayName(date.getDay(), Locale.ShortFormat);
        const time = date.toLocaleTimeString(locale, Locale.ShortFormat);
        return zone && zone.abbreviation
            ? i18nc("@info weekday, time and time zone of a reset, e.g. Sun 7:00 AM EDT", "%1 %2 %3", day, time, zone.abbreviation)
            : i18nc("@info weekday and time of a reset, e.g. Sun 7:00 AM", "%1 %2", day, time);
    }

    // "4:12 PM" today, the date and time otherwise, in system time.
    function timeOfDay(epoch, nowMs) {
        if (!Format.usable(epoch)) {
            return "";
        }
        const when = new Date(epoch * 1000);
        return when.toDateString() === new Date(nowMs).toDateString()
            ? when.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
            : when.toLocaleString(Qt.locale(), Locale.ShortFormat);
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
