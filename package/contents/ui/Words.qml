// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import "code/format.js" as Format
import "code/providers.js" as Providers
import "code/hardware.js" as Hardware
import "code/history.js" as History

// Each item's readings in words, for screen readers and tooltips, the short
// readings beside a ring, the times the Claude and Codex views show, and
// the peak a rate graph's caption line names.
// describe() and readout() speak for the panel, so they give the readings
// it shows (Monitor.panel), not the live ones.
QtObject {
    id: words

    // Monitor.qml, or anything shaped like it.
    required property var monitor

    function describe(item, nowMs) {
        switch (item) {
        case "cpu":
            return i18nc("@info:tooltip processor usage and temperature", "Usage %1, temperature %2",
                         percentText(monitor.panel.cpuUsage), temperatureText(monitor.panel.cpuTemperature));
        case "memory": {
            const used = Format.bytes(monitor.panel.memoryUsed);
            return Number.isFinite(monitor.panel.memoryUsed)
                ? i18nc("@info:tooltip memory in use; %1 %2 is e.g. 13.4 GiB, %3 a percentage", "%1 %2 in use, %3",
                        used.value, used.unit, percentText(monitor.panel.memoryPercent))
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
                         rateText(Format.rate(monitor.panel.networkDown, monitor.networkBits)),
                         rateText(Format.rate(monitor.panel.networkUp, monitor.networkBits)));
        case "disk":
            return i18nc("@info:tooltip disk read and write rates", "Read %1, write %2",
                         rateText(Format.rate(monitor.panel.diskRead, false)), rateText(Format.rate(monitor.panel.diskWrite, false)));
        case "claude":
        case "codex":
            return usageText(item, nowMs ?? Date.now());
        }
        return "";
    }

    // A provider's name as its popup and tooltip give it: the OpenAI item is
    // ChatGPT while its ring shows the OpenAI logo, and Codex with the Codex
    // mark.
    // An item's name as the panel's tooltip and screen readers give it.
    function title(item) {
        switch (item) {
        case "cpu":
            return i18nc("@info:tooltip", "Processor");
        case "gpu":
            return i18nc("@info:tooltip", "Graphics");
        case "memory":
            return i18nc("@info:tooltip", "Memory");
        case "network":
            return i18nc("@info:tooltip", "Network");
        case "disk":
            return i18nc("@info:tooltip", "Disk activity");
        default:
            return providerName(item);
        }
    }

    // What to run to sign a provider in.
    function signInHint(item) {
        return i18nc("@info %1 is a command, such as claude", "Run %1 in a terminal to sign in.", Providers.facts(item).command);
    }

    function providerName(item) {
        return item === "claude" ? i18nc("@title", "Claude")
             : monitor.codexMark === "openai" ? i18nc("@title the OpenAI weekly limits, with the OpenAI logo chosen for their ring", "ChatGPT")
             : i18nc("@title", "Codex");
    }

    // The two short readings by a ring: the ring's own percentage, or "off"
    // for the only GPU while it sleeps, then its temperature, the memory in
    // use or the time to the weekly reset; empty where there is none, as for
    // Intel GPUs, which publish no temperature. `level` and `heat` choose
    // their colours (see Readout). The integrated GPU's temperature stays in
    // the words and the popup. A countdown keeps to its largest unit, "6d",
    // "23h", "12m"; the popup and the words give more. With the limit reached
    // it turns red, as in the popup, since it then says how long the lock-out
    // lasts. Before a first reading and after a failed check both are dim,
    // and with `cancelled`, while the ring is struck, dashes.
    function readout(item, nowMs, cancelled) {
        const percent = value => Number.isFinite(value) ? i18nc("@info:status a percentage", "%1%", Format.percent(value)) : "–";
        const temperature = celsius => Format.temperatureValid(celsius)
            ? Format.temperature(celsius, monitor.fahrenheit) + "°" : "–";
        switch (item) {
        case "cpu":
            return { first: percent(monitor.panel.cpuUsage), level: Format.level(monitor.panel.cpuUsage),
                     second: temperature(monitor.panel.cpuTemperature), heat: monitor.heat(monitor.panel.cpuTemperature) };
        case "gpu": {
            const gpu = Hardware.gpuView(monitor.gpuOuter, monitor.gpuInner).primary;
            if (gpu.phase === "asleep") {
                return { first: i18nc("@info:status the GPU is powered down", "off"), off: true, second: "" };
            }
            return { first: percent(gpu.panelUsage), level: Format.level(gpu.panelUsage),
                     second: gpu.reportsTemperature ? temperature(gpu.panelTemperature) : "",
                     heat: gpu.reportsTemperature ? monitor.heat(gpu.panelTemperature) : 0 };
        }
        case "memory": {
            const used = Format.panelBytes(monitor.panel.memoryUsed);
            return { first: percent(monitor.panel.memoryPercent), level: Format.level(monitor.panel.memoryPercent),
                     second: used.unit === "" ? used.value : used.value + " " + used.unit };
        }
        }
        const entry = monitor.usage.entry(item);
        const weekly = entry && entry.weekly ? entry.weekly : null;
        const now = nowMs ?? Date.now();
        // Two dashes where the figures go, in the percentage's own pattern
        // so a language's sign keeps its place, and one before the days'
        // letter.
        if (cancelled) {
            return { first: i18nc("@info:status a percentage", "%1%", "––"), off: true,
                     second: "–" + timeParts("", "", "")[0].unit, heat: 0 };
        }
        const parts = countdownParts(weekly ? weekly.resetsAt : null, now, true);
        if (!entry || entry.lastError !== undefined) {
            return { first: percent(weekly ? weekly.percent : NaN), off: true, second: spelled(parts) || "–", heat: 0 };
        }
        return { first: percent(weekly ? weekly.percent : NaN), level: Format.level(weekly ? weekly.percent : NaN),
                 second: spelled(parts) || "–", heat: parts.length > 0 && weekly.percent >= 100 ? 2 : 0 };
    }

    // The memory in use as the panel can show it: up to the installed total,
    // "31.9 GiB", and from 1 GiB, below which no desktop running Plasma
    // gets, so a total just past a unit, "1.0 TiB", keeps room for three
    // figures of the unit below. Every unit until the total is known.
    function memoryRoom() {
        const units = Format.panelByteUnits();
        const total = Format.panelBytes(monitor.memoryTotal);
        if (total.unit === "") {
            return units.map(unit => Format.decimal(100, 1) + " " + unit);
        }
        const floor = units.indexOf(Format.panelBytes(Math.min(monitor.memoryTotal, 1024 * 1024 * 1024)).unit);
        return [total.value + " " + total.unit].concat(units.slice(floor, units.indexOf(total.unit))
                                                            .map(unit => Format.decimal(100, 1) + " " + unit));
    }

    // The texts readout() can give for `item` at their widest, line by line,
    // with every digit counting as the widest: the room the panel keeps for
    // them whatever they read.
    function widest(item) {
        const percent = i18nc("@info:status a percentage", "%1%", Format.percent(100));
        // Memory to one decimal and its unit (see memoryRoom()); a countdown
        // in two figures and its unit, "23h".
        const second = item === "cpu" || item === "gpu" ? [Format.whole(100) + "°"]
                     : item === "memory" ? memoryRoom()
                     : timeParts(Format.whole(10), Format.whole(10), Format.whole(10)).map(part => part.value + part.unit);
        return {
            first: item === "gpu" ? [percent, i18nc("@info:status the GPU is powered down", "off")] : [percent],
            second: second
        };
    }

    // A Claude or Codex item: its weekly use, the limit on its inner ring,
    // when the week resets, and a failed last check (see failedText()); or,
    // while its first check runs, that it is checking.
    function usageText(item, nowMs) {
        const usage = monitor.usage;
        const entry = usage.entry(item);
        if (usage.loading(item)) {
            return i18nc("@info:tooltip the first check of the Claude or Codex limits since Ringside started is running",
                         "Checking your usage…");
        }
        if (entry === null) {
            return usage.helperError || i18nc("@info:tooltip the usage has not been read yet", "Not checked yet");
        }
        if (entry.status === "signed_out") {
            return i18nc("@info:tooltip", "Signed out");
        }
        if (!entry.weekly && entry.lastError !== undefined) {
            return failedText(item, entry, "", nowMs);
        }
        const used = percentText(entry.weekly ? entry.weekly.percent : NaN);
        const left = duration(entry.weekly ? entry.weekly.resetsAt : null, nowMs);
        const limit = usage.inner(item);
        let text;
        if (limit) {
            text = left ? i18nc("@info:tooltip weekly share used, a model's own limit, time to the reset, e.g. 62% used, Fable 78%, resets in 2 days 21 hours",
                                "%1 used, %2 %3, resets in %4", used, limit.label, percentText(limit.percent), left)
                        : i18nc("@info:tooltip weekly share used and a model's own limit, e.g. 62% used, Fable 78%",
                                "%1 used, %2 %3", used, limit.label, percentText(limit.percent));
        } else {
            text = left ? i18nc("@info:tooltip weekly share used and time to the reset, e.g. 62% used, resets in 2 days 21 hours",
                                "%1 used, resets in %2", used, left)
                        : i18nc("@info:tooltip weekly share used, e.g. 62% used", "%1 used", used);
        }
        return entry.lastError === undefined ? text : failedText(item, entry, text, nowMs);
    }

    // A failed check in words, a sentence a line: when it failed and why;
    // the last reading and when it was taken, or that the week has reset
    // since; and when the next check runs.
    function failedText(item, entry, reading, nowMs) {
        const weekly = entry.weekly ?? null;
        const lines = [i18nc("@info:tooltip %1 is a time, %2 why, a sentence, e.g. Can't reach api.anthropic.com.",
                             "Last check failed at %1. %2", timeOfDay(entry.lastErrorAt, nowMs), failureReason(item, entry))];
        if (weekly && weekly.resetsAt <= nowMs / 1000) {
            lines.push(i18nc("@info:tooltip %1 is a weekday and time, with a time zone where the reset has one, as in Sun 7:00 AM EDT",
                             "The week reset at %1, with no reading since.", resetDate(weekly)));
        } else if (weekly) {
            lines.push(i18nc("@info:tooltip %1 is a time, %2 the reading, e.g. 52% used, resets in 2 days 21 hours",
                             "Last reading at %1: %2.", timeOfDay(entry.fetchedAt, nowMs), reading));
        }
        lines.push(nextCheckText(item, nowMs));
        return lines.join("\n");
    }

    // "Checking now." or "Next check at 4:15 PM.", after a failed check,
    // with the weekday for a check on another day: "Next check at Fri
    // 12:35 AM."
    function nextCheckText(item, nowMs) {
        const usage = monitor.usage;
        const next = usage.nextCheck(item);
        return usage.checking ? i18nc("@info", "Checking now.")
            : i18nc("@info %1 is a time, or a weekday and time", "Next check at %1.",
                    new Date(next * 1000).toDateString() === new Date(nowMs).toDateString()
                        ? shortTime(new Date(next * 1000)) : weekdayTime(next, null));
    }

    // Why a check failed, as a sentence, from the reason the helper gives
    // (see usage.py and code/report.js): the network, a server, a provider
    // asking to wait, a Codex CLI that isn't installed or a chosen program
    // that can't be run, or the helper itself. The helper's own message, which names the Python error, is
    // for the settings page and screen readers. Anything else, another
    // check holding the helper's lock among it, is the helper's message as
    // it gave it. A rate limit's end is left to the next check's time: the
    // helper waits at least five minutes, which may be longer than the
    // provider asked.
    function failureReason(item, entry) {
        const host = entry.host ?? "";
        switch (entry.reason) {
        case "offline":
            if (host) {
                return i18nc("@info %1 is a server, such as api.anthropic.com", "Can't reach %1.", host);
            }
            break;
        case "timeout":
            // Codex is asked through its program, which names no server.
            return i18nc("@info %1 is a server, such as api.anthropic.com, or a program, such as Codex", "%1 didn't answer in time.",
                         host || Providers.facts(item).product);
        case "server":
            if (host) {
                return i18nc("@info %1 is a server, such as api.anthropic.com", "%1 answered with an error.", host);
            }
            break;
        case "rate-limited":
            return i18nc("@info %1 is a company, such as Anthropic or OpenAI", "%1 asked Ringside to wait before checking again.",
                         Providers.facts(item).company);
        case "not-installed":
            if (item === "codex") {
                return i18nc("@info AI Providers and Panel Items are settings pages; OpenAI is the item's name there", "Plasma can't find Codex. Install it, set where it is under AI Providers, or turn OpenAI off in Panel Items.");
            }
            break;
        case "program":
            return i18nc("@info %1 is a program name such as codex", "The %1 program set in Settings can't be run.", Providers.facts(item).command);
        case "missing":
            return i18nc("@info", "python3 was not found on the Plasma session's PATH.");
        case "files":
            return i18nc("@info", "The usage helper couldn't read or write its files.");
        case "helper":
            return i18nc("@info", "The usage helper stopped with an error.");
        }
        const message = String(entry.lastError);
        const sentence = message.charAt(0).toUpperCase() + message.slice(1);
        return /[.!?]$/.test(sentence) ? sentence : i18nc("@info a message that lacks its full stop", "%1.", sentence);
    }

    // Time to a reset in the panel's letters: "2d 21h", "5h 12m", "12m";
    // empty once it has passed.
    function countdown(resetsAt, nowMs) {
        return spelled(countdownParts(resetsAt, nowMs));
    }

    // countdown() as number and unit pairs, for setting the units apart:
    // [{ value: "5", unit: "d" }, { value: "18", unit: "h" }]. With
    // leadingOnly, only the largest unit. Empty once the reset has passed.
    function countdownParts(resetsAt, nowMs, leadingOnly) {
        const left = Format.timeLeft(resetsAt, nowMs);
        if (left === null) {
            return [];
        }
        const [days, hours, minutes] = timeParts(Format.whole(left.days), Format.whole(left.hours), Format.whole(left.minutes));
        const parts = left.days > 0 ? [days, hours] : left.hours > 0 ? [hours, minutes] : [minutes];
        return leadingOnly ? parts.slice(0, 1) : parts;
    }

    // Numbers of days, hours and minutes with their unit letters. Each unit is
    // one message, so every countdown reads in the same notation.
    function timeParts(days, hours, minutes) {
        return [{ value: days, unit: i18nc("@info unit after a number of days left, as in 5d 18h", "d") },
                { value: hours, unit: i18nc("@info unit after a number of hours left, as in 5d 18h or 5h 12m", "h") },
                { value: minutes, unit: i18nc("@info unit after a number of minutes left, as in 5h 12m", "m") }];
    }

    // countdownParts() as one text: "5d 18h".
    function spelled(parts) {
        return parts.map(part => part.value + part.unit).join(" ");
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
        const date = zonedDate(Math.round(window.resetsAt / 60) * 60, window);
        const day = Qt.locale().dayName(date.getDay(), Locale.ShortFormat);
        const time = shortTime(date);
        return zone && zone.abbreviation
            ? i18nc("@info weekday, time and time zone of a reset, e.g. Sun 7:00 AM EDT", "%1 %2 %3", day, time, zone.abbreviation)
            : i18nc("@info weekday and time of a reset, e.g. Sun 7:00 AM", "%1 %2", day, time);
    }

    // A time within a window, such as when its limit runs out, as a weekday
    // and time: "Tue 3:30 AM". It carries no zone; the words around it say
    // which clock the window keeps.
    function weekdayTime(epoch, window) {
        if (!Format.usable(epoch)) {
            return "";
        }
        const date = zonedDate(epoch, window);
        return i18nc("@info weekday and time within a weekly window, e.g. Tue 3:30 AM", "%1 %2",
                     Qt.locale().dayName(date.getDay(), Locale.ShortFormat), shortTime(date));
    }

    // What the session starter is doing, under its switch in the Claude or
    // Codex popup. `starter` is the helper's { enabled, state, at, next,
    // reason, clockZone, atClockZone } (see usage.py), or UsageData's
    // "failed" with the helper's error and reason "helper" after a --start
    // that didn't run, or "switch" after a switch change that didn't take.
    // Times are to the minute, in the desktop clock's zone when the helper
    // gives the starter one, as it does the resets, else in system time; the
    // tile's caption names the zone once. `at` takes the zone at that time,
    // since a week Codex started can span a change of daylight saving time.
    // Each sentence has a string for a time today ("at 11:40 PM") and one
    // for another day, with the weekday and time apart ("Wed 1:46 AM"), so a
    // language can word each its own way. Six or more days away, as a Codex
    // week's start and end can be, the weekday could be today's, so the date
    // follows it ("Tue 10/13/26 3:33 AM").
    function starterStatus(item, starter, nowMs) {
        const s = starter ?? { state: "off" };
        const claude = item === "claude";
        const zone = epoch => {
            const clockZone = epoch === s.at && s.atClockZone ? s.atClockZone : s.clockZone;
            return clockZone ? { clockZone: clockZone, resetsAt: epoch } : null;
        };
        const date = epoch => zonedDate(Math.round(epoch / 60) * 60, zone(epoch));
        const day = epoch => {
            const weekday = Qt.locale().dayName(date(epoch).getDay(), Locale.ShortFormat);
            return Math.abs(epoch * 1000 - nowMs) < 6 * 86400000 ? weekday
                : i18nc("@info a weekday and a date, e.g. Tue 10/13/26", "%1 %2", weekday,
                        date(epoch).toLocaleDateString(Qt.locale(), Locale.ShortFormat));
        };
        const time = epoch => shortTime(date(epoch));
        const onDay = (epoch, today, otherDay) =>
            date(epoch).toDateString() === zonedDate(nowMs / 1000, zone(epoch)).toDateString() ? today : otherDay;
        const both = (first, second) => i18nc("@info two sentences of the session starter's status, in order", "%1 %2", first, second);
        const confirming = onDay(s.next, i18nc("@info %1 is a time today", "Confirming at %1.", time(s.next)),
                                 i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Confirming %1 %2.", day(s.next), time(s.next)));
        const tryingAgain = onDay(s.next, i18nc("@info %1 is a time today", "Trying once more at %1.", time(s.next)),
                                  i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Trying once more %1 %2.", day(s.next), time(s.next)));
        switch (s.state) {
        case "off":
            return claude
                ? i18nc("@info under the session starter's switch while it is off", "When a session ends, Ringside sends Claude a one-word message to start the next one.")
                : i18nc("@info under the session starter's switch while it is off", "When a week ends, Ringside sends Codex a one-word message to start the next one.");
        case "waiting":
            return claude
                ? onDay(s.next, i18nc("@info %1 is a time today", "The next session starts at %1.", time(s.next)),
                        i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "The next session starts %1 %2.", day(s.next), time(s.next)))
                : onDay(s.next, i18nc("@info %1 is a time today", "The next week starts at %1.", time(s.next)),
                        i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "The next week starts %1 %2.", day(s.next), time(s.next)));
        case "confirming":
            return both(claude
                ? onDay(s.at, i18nc("@info %1 is a time today", "Started a session at %1.", time(s.at)),
                        i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Started a session %1 %2.", day(s.at), time(s.at)))
                : onDay(s.at, i18nc("@info %1 is a time today", "Started a week at %1.", time(s.at)),
                        i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Started a week %1 %2.", day(s.at), time(s.at))),
                confirming);
        case "started":
            // Codex's next is the week's end, which the reset line gives.
            return claude
                ? both(onDay(s.at, i18nc("@info %1 is a time today", "Started a session at %1.", time(s.at)),
                             i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Started a session %1 %2.", day(s.at), time(s.at))),
                       onDay(s.next, i18nc("@info the next session; %1 is a time today", "The next one starts at %1.", time(s.next)),
                             i18nc("@info the next session; %1 is a weekday, or a weekday and date, %2 a time", "The next one starts %1 %2.", day(s.next), time(s.next))))
                : onDay(s.at, i18nc("@info %1 is a time today", "Started this week at %1.", time(s.at)),
                        i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Started this week %1 %2.", day(s.at), time(s.at)));
        case "weekly":
            return claude
                ? onDay(s.next, i18nc("@info %1 is a time today", "Weekly limit reached. The next session starts at %1, when the limit resets.", time(s.next)),
                        i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Weekly limit reached. The next session starts %1 %2, when the limit resets.", day(s.next), time(s.next)))
                : onDay(s.next, i18nc("@info %1 is a time today", "Weekly limit reached. The next week starts at %1, when the limit resets.", time(s.next)),
                        i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Weekly limit reached. The next week starts %1 %2, when the limit resets.", day(s.next), time(s.next)));
        case "failed":
            if (s.reason === "not-installed") {
                return claude ? i18nc("@info", "Can't start a session: Claude Code isn't installed.")
                              : i18nc("@info", "Can't start a week: Codex isn't installed.");
            }
            if (s.reason === "program") {
                return claude ? i18nc("@info", "Can't start a session: the claude program set in Settings can't be run.")
                              : i18nc("@info", "Can't start a week: the codex program set in Settings can't be run.");
            }
            if (s.reason === "signed-out") {
                return claude
                    ? i18nc("@info", "Can't start a session: Claude Code is signed out. Run claude in a terminal to sign in.")
                    : i18nc("@info", "Can't start a week: Codex is signed out. Run codex in a terminal to sign in.");
            }
            if (s.reason === "not-subscription" && claude) {
                return i18nc("@info", "Can't start a session: Claude Code isn't signed in with a Claude subscription.");
            }
            if (s.reason === "not-responding") {
                return claude
                    ? onDay(s.next, i18nc("@info %1 is a time today", "Can't start a session: Claude Code isn't responding. Trying again at %1.", time(s.next)),
                            i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Can't start a session: Claude Code isn't responding. Trying again %1 %2.", day(s.next), time(s.next)))
                    : onDay(s.next, i18nc("@info %1 is a time today", "Can't start a week: Codex isn't responding. Trying again at %1.", time(s.next)),
                            i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Can't start a week: Codex isn't responding. Trying again %1 %2.", day(s.next), time(s.next)));
            }
            if (s.reason === "unchecked") {
                return onDay(s.next, i18nc("@info %1 is a time today", "Couldn't check the limits. Trying again at %1.", time(s.next)),
                             i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Couldn't check the limits. Trying again %1 %2.", day(s.next), time(s.next)));
            }
            // A send that never left, or a --start that didn't run.
            if (s.reason === "not-sent" || s.reason === "helper") {
                const retry = claude
                    ? onDay(s.next, i18nc("@info %1 is a time today", "Couldn't start a session. Trying again at %1.", time(s.next)),
                            i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Couldn't start a session. Trying again %1 %2.", day(s.next), time(s.next)))
                    : onDay(s.next, i18nc("@info %1 is a time today", "Couldn't start a week. Trying again at %1.", time(s.next)),
                            i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Couldn't start a week. Trying again %1 %2.", day(s.next), time(s.next)));
                return s.error ? both(retry, s.error) : retry;
            }
            if (s.reason === "switch") {
                return i18nc("@info under the session starter's switch, which snapped back; %1 is the error the usage helper printed",
                             "Couldn't change the switch: %1", s.error);
            }
            break;
        case "retrying":
            return both(claude
                ? onDay(s.at, i18nc("@info %1 is a time today", "Couldn't confirm the session started at %1.", time(s.at)),
                        i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Couldn't confirm the session started %1 %2.", day(s.at), time(s.at)))
                : onDay(s.at, i18nc("@info %1 is a time today", "Couldn't confirm the week started at %1.", time(s.at)),
                        i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Couldn't confirm the week started %1 %2.", day(s.at), time(s.at))),
                tryingAgain);
        case "paused":
            return claude
                ? onDay(s.next, i18nc("@info %1 is a time today", "Couldn't confirm two sessions in a row. Paused until %1.", time(s.next)),
                        i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Couldn't confirm two sessions in a row. Paused until %1 %2.", day(s.next), time(s.next)))
                : onDay(s.next, i18nc("@info %1 is a time today", "Couldn't confirm two weeks in a row. Paused until %1.", time(s.next)),
                        i18nc("@info %1 is a weekday, or a weekday and date, %2 a time", "Couldn't confirm two weeks in a row. Paused until %1 %2.", day(s.next), time(s.next)));
        }
        return "";
    }

    // A Date whose fields read as the wall clock at `epoch` for a window: in
    // its clock zone when that differs from system time at the reset, else in
    // system time, which keeps daylight saving right across the week.
    function zonedDate(epoch, window) {
        const zone = window ? window.clockZone : null;
        const resetsAt = window && Format.usable(window.resetsAt) ? window.resetsAt : epoch;
        const systemOffset = -new Date(resetsAt * 1000).getTimezoneOffset() * 60;
        return zone && zone.offset !== systemOffset ? Format.wallClock(epoch, zone.offset) : new Date(epoch * 1000);
    }

    // "4:12 PM" today, the date and time otherwise, in system time.
    function timeOfDay(epoch, nowMs) {
        if (!Format.usable(epoch)) {
            return "";
        }
        const when = new Date(epoch * 1000);
        const locale = Qt.locale();
        return when.toDateString() === new Date(nowMs).toDateString()
            ? shortTime(when)
            : when.toLocaleString(locale, withoutSeconds(locale.dateTimeFormat(Locale.ShortFormat)));
    }

    // A time in the locale's short format, to the minute. Qt 6.6 gives the
    // C locale's short time with seconds, "17:49:00", which would claim more
    // than a reset to the minute or a run-out to ten minutes knows.
    function shortTime(date) {
        const locale = Qt.locale();
        return date.toLocaleTimeString(locale, withoutSeconds(locale.timeFormat(Locale.ShortFormat)));
    }

    function withoutSeconds(format) {
        return format.replace(/[:.]ss?/, "");
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
                    percentText(slot.panelUsage), temperatureText(slot.panelTemperature))
            : i18nc("@info:tooltip GPU usage; this GPU has no temperature sensor", "Usage %1", percentText(slot.panelUsage));
    }

    function rateText(reading) {
        return reading.value === "–" ? i18nc("@info:tooltip no reading", "unavailable")
                                     : i18nc("@info:tooltip a transfer rate, e.g. 24.8 Mb/s", "%1 %2", reading.value, reading.unit);
    }

    // What a rate graph's caption line says about its top, which is the
    // peak in view: "peak 24.8 Mb/s", or nothing before the first sample.
    // An hour or a day passes its buckets' highest readings, which its band
    // reaches. Under the graph's floor the top is the floor, and this still
    // names the peak.
    function peakText(samples, bits) {
        const top = History.peak(samples);
        if (top === null) {
            return "";
        }
        const r = Format.rate(top.value, bits);
        return i18nc("@title:group at the end of a rate graph's caption line, after THROUGHPUT · 1 min or READ · 1 day: its highest rate, as in peak 24.8 Mb/s",
                     "peak %1 %2", r.value, r.unit);
    }

    // A temperature sensor's label in plain words, for the caption under a
    // CPU or GPU temperature: k10temp's Tccd1, amdgpu's junction and mem.
    // The whole chip's sensor (k10temp's Tctl and Tdie, coretemp's Package
    // id 0, amdgpu's edge) gets none. Any other label, such as an NVMe
    // drive's Composite, is shown as it is.
    function sensorName(raw) {
        // The whole chip's own sensor goes unnamed: a CPU's or GPU's
        // temperature is the chip's unless a caption says otherwise.
        if (/^(Tctl|Tdie|Package id \d+|edge)$/.test(raw)) {
            return "";
        }
        const chiplet = /^Tccd(\d+)$/.exec(raw);
        if (chiplet) {
            return i18nc("@label temperature sensor for one of a processor's chiplets, e.g. chiplet 1", "chiplet %1",
                         Format.whole(Number(chiplet[1])));
        }
        switch (raw) {
        case "junction":
            return i18nc("@label temperature sensor for the hottest spot on a GPU", "hotspot");
        case "mem":
            return i18nc("@label temperature sensor for a GPU's memory", "memory");
        }
        return raw;
    }
}
