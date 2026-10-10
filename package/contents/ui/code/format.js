// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Readings come back as { value, unit } so the panel and popups can set the
// unit dimmer beside the number. Anything that isn't a usable number formats
// as an en dash.

const DASH = "–";

function usable(v) {
    return typeof v === "number" && Number.isFinite(v);
}

// libksysguard publishes uninitialised memory when libsensors fails a read
// (a suspended GPU, a sensor mid-reset), and 0 before the first sample. No
// component the widget shows runs below freezing or above 150 °C.
function temperatureValid(celsius) {
    return usable(celsius) && celsius >= 1 && celsius < 150;
}

// Board power as reported by hwmon; the same uninitialised-value bug as
// temperatures can produce absurd numbers.
function powerValid(watts) {
    return usable(watts) && watts >= 0 && watts < 1000;
}

function percent(v) {
    return usable(v) ? whole(Math.max(0, Math.min(100, v))) : DASH;
}

// °C in the unit shown, as a number.
function degrees(celsius, fahrenheit) {
    return fahrenheit ? celsius * 9 / 5 + 32 : celsius;
}

function temperature(celsius, fahrenheit) {
    if (!temperatureValid(celsius)) {
        return DASH;
    }
    return whole(degrees(celsius, fahrenheit));
}

// A ring's alert level from its own percentage: 0 below 75, 1 (amber) from
// 75, 2 (red) from 90. No reading is level 0.
function level(percent) {
    return !usable(percent) ? 0 : percent >= 90 ? 2 : percent >= 75 ? 1 : 0;
}

// 0 below the first threshold, 1 from warm, 2 from hot.
function heat(celsius, warm, hot) {
    if (!temperatureValid(celsius)) {
        return 0;
    }
    return celsius >= hot ? 2 : celsius >= warm ? 1 : 0;
}

// A fixed number of decimals in the user's number format: "3,66" under a
// German locale, native digits under Arabic or Marathi ones. Group
// separators are left out, so "1023" keeps the width of "99.9".
function decimal(v, digits) {
    const locale = Qt.locale();
    locale.numberOptions |= 1; // Locale.OmitGroupSeparator, which a .pragma library can't name
    return v.toLocaleString(locale, "f", digits);
}

// A whole number in the same digits as decimal(), so a readout never mixes
// numeral systems as it crosses a unit or 99.95.
function whole(v) {
    return decimal(Math.round(v), 0);
}

// One decimal under 100, whole numbers above, so a readout keeps its width.
function number(v) {
    return Math.abs(v) < 99.95 ? decimal(v, 1) : whole(v);
}

// Like number(), but drops a trailing zero decimal for totals such as "16 GiB".
function compact(v) {
    const text = number(v);
    const zero = Qt.locale().decimalPoint + Qt.locale().zeroDigit;
    return text.endsWith(zero) ? text.slice(0, -zero.length) : text;
}

// Sizes and byte rates are shown in the units KDE is set to, under Region &
// Language → Data and storage units: KiB, MiB, GiB (1024s, the default), KB,
// MB, GB (1024s) or kB, MB, GB (1000s), named as KDE names them in the
// user's language. The widget learns them once as it starts (see
// Monitor.byteUnits), so a change to the setting shows from the next
// plasmashell start, as in KDE's own apps. Until then, and whenever they
// can't be learnt, binary units in their IEC names.
const IEC = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
let byteBase = 1024;
let byteLabels = IEC;

// The unit two sizes in it share, "KiB" from "1 KiB" and "2 KiB": what they
// end with, or what they start with where the unit comes first, less the
// spaces around it. Comparing two sizes, rather than reading past the
// digits, works whatever digits the locale writes. Nothing if they read the
// same.
function unitLabel(one, two) {
    if (one === two) {
        return "";
    }
    let end = 0;
    while (end < one.length && end < two.length && one[one.length - 1 - end] === two[two.length - 1 - end]) {
        ++end;
    }
    let start = 0;
    while (start < one.length && start < two.length && one[start] === two[start]) {
        ++start;
    }
    return one.slice(one.length - end).trim() || one.slice(0, start).trim();
}

// The base and the six labels, from bytes to PB, of `size`, a function that
// writes a size as KDE does to no decimals; null unless every label comes
// out and each differs from the rest. KDE's 1000 bytes read "1 kB" only in
// units of 1000s.
function byteUnitsFrom(size) {
    const text = n => String(size(n));
    const base = text(1000) === text(1024) ? 1000 : 1024;
    const labels = IEC.map((_, n) => unitLabel(text(base ** n), text(2 * base ** n)));
    return labels.every(label => label !== "") && new Set(labels).size === labels.length
        ? { base: base, labels: labels } : null;
}

function setByteUnits(base, labels) {
    byteBase = base;
    byteLabels = labels.slice();
}

function byteScale(bytes) {
    let i = 0;
    while (i < byteLabels.length - 1 && Math.abs(bytes) >= byteBase ** (i + 1) * 0.9995) {
        ++i;
    }
    return i;
}

// Bytes in KDE's units, with their `scale`: 0 for bytes, 1 for K and so on.
function bytes(v, trim) {
    if (!usable(v)) {
        return { value: DASH, unit: "", scale: 0 };
    }
    const i = byteScale(v);
    const scaled = v / byteBase ** i;
    return { value: i === 0 ? whole(scaled) : trim ? compact(scaled) : number(scaled),
             unit: byteLabels[i], scale: i };
}

// "used / total" in the total's unit: { value: "0.2", total: "16", unit: "GiB" }.
function bytesOf(used, total) {
    if (!usable(total) || total <= 0) {
        return { value: DASH, total: DASH, unit: "" };
    }
    const i = byteScale(total);
    const d = byteBase ** i;
    return { value: usable(used) ? number(used / d) : DASH, total: compact(total / d), unit: byteLabels[i] };
}

// Network rates in decimal bits, as links are sold, or in bytes as bytes()
// gives them, with the unit's `scale`.
function rate(bytesPerSecond, bits) {
    if (!usable(bytesPerSecond)) {
        return { value: DASH, unit: bits ? "b/s" : byteLabels[0] + "/s", scale: 0 };
    }
    if (!bits) {
        const b = bytes(bytesPerSecond, false);
        return { value: b.value, unit: b.unit + "/s", scale: b.scale };
    }
    const units = ["b/s", "kb/s", "Mb/s", "Gb/s", "Tb/s"];
    let v = bytesPerSecond * 8;
    let i = 0;
    while (i < units.length - 1 && Math.abs(v) >= 999.5) {
        v /= 1000;
        ++i;
    }
    return { value: i === 0 ? whole(v) : number(v), unit: units[i], scale: i };
}

// Three significant figures, "8.40", "62.1", "353": every value has three
// digits, and all but those from 100 a decimal point, so a value set in the
// panel's figures of one width takes the same room whatever it reads.
function significant(v) {
    const a = Math.abs(v);
    return a < 9.995 ? decimal(v, 2) : a < 99.95 ? decimal(v, 1) : whole(v);
}

// The units panelRate() steps through.
function panelRateUnits(bits) {
    return bits ? ["kb/s", "Mb/s", "Gb/s", "Tb/s"] : byteLabels.slice(1).map(label => label + "/s");
}

// A rate for the panel, in three significant figures from kb/s or KiB/s up:
// "0.00 KiB/s" idle, "8.40 Mb/s", "353 KiB/s". The unit steps up at 999.5 of
// the one shown, units of 1024 too ("0.98 MiB/s" for 1000 KiB/s), so no
// value takes a fourth digit.
function panelRate(bytesPerSecond, bits) {
    const units = panelRateUnits(bits);
    if (!usable(bytesPerSecond)) {
        return { value: DASH, unit: units[0] };
    }
    const step = bits ? 1000 : byteBase;
    let v = (bits ? bytesPerSecond * 8 : bytesPerSecond) / step;
    let i = 0;
    while (i < units.length - 1 && Math.abs(v) >= 999.5) {
        v /= step;
        ++i;
    }
    return { value: significant(v), unit: units[i] };
}

// The units panelBytes() steps through.
function panelByteUnits() {
    return byteLabels.slice();
}

// Bytes for the panel to one decimal, "9.6 GiB", "512.0 MiB". The unit steps
// up from 999.95 of the one shown, so no value takes a fourth digit before
// the point: 1000 MiB reads "1.0 GiB". Bytes stay whole.
function panelBytes(v) {
    if (!usable(v)) {
        return { value: DASH, unit: "" };
    }
    let i = 0;
    let scaled = v;
    while (i < byteLabels.length - 1 && Math.abs(scaled) >= 999.95) {
        scaled /= byteBase;
        ++i;
    }
    return { value: i === 0 ? whole(scaled) : decimal(scaled, 1), unit: byteLabels[i] };
}

function frequency(megahertz) {
    if (!usable(megahertz) || megahertz <= 0) {
        return { value: DASH, unit: "" };
    }
    return megahertz >= 1000 ? { value: decimal(megahertz / 1000, 2), unit: "GHz" }
                             : { value: whole(megahertz), unit: "MHz" };
}

function watts(v) {
    return powerValid(v) ? { value: whole(v), unit: "W" } : { value: DASH, unit: "" };
}

function fixed(v, digits) {
    return usable(v) ? decimal(v, digits) : DASH;
}

// Time left until `resetsAt` (epoch seconds), to the nearest minute, as
// { days, hours, minutes }; null once it has passed or without a time.
function timeLeft(resetsAt, nowMs) {
    if (!usable(resetsAt)) {
        return null;
    }
    const minutes = Math.round((resetsAt * 1000 - nowMs) / 60000);
    return minutes > 0 ? { days: Math.floor(minutes / 1440), hours: Math.floor(minutes % 1440 / 60), minutes: minutes % 60 }
                       : null;
}

// A local Date whose fields read as the wall clock at `epoch` in a zone
// `offset` seconds east of UTC, so the locale's own day names and time
// format can show a time in the desktop clock's zone. A wall time that falls
// in the system zone's daylight-saving gap moves by the gap.
function wallClock(epoch, offset) {
    const shifted = new Date((epoch + offset) * 1000);
    return new Date(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate(),
                    shifted.getUTCHours(), shifted.getUTCMinutes(), shifted.getUTCSeconds());
}

// Load averages keep four characters or so: "1.42", "14.2", "143".
function load(v) {
    if (!usable(v)) {
        return DASH;
    }
    return v < 10 ? decimal(v, 2) : v < 100 ? decimal(v, 1) : whole(v);
}

// "AMD Ryzen 7 7840HS w/ Radeon 780M Graphics" → "AMD Ryzen 7 7840HS";
// "Intel(R) Core(TM) i7-1165G7 @ 2.80GHz" → "Intel Core i7-1165G7".
function cpuModel(raw) {
    return String(raw || "")
        .replace(/\((R|TM|tm|r)\)/g, "")
        .replace(/\s+(w\/|with)\s+.*Graphics.*$/i, "")
        .replace(/\s+\d+-Core Processor$/i, "")
        .replace(/\s+(CPU\s+)?@\s*[\d.]+\s*GHz$/i, "")
        .replace(/\s+(CPU|Processor)$/i, "")
        .replace(/\s+/g, " ")
        .trim();
}

// hwdb names look like "Navi 33 [Radeon RX 7600/7600 XT/…]" or
// "Raptor Lake-P [Iris Xe Graphics]"; the bracket holds the product family.
function gpuModel(marketing, sensorName, pciName, vendor) {
    if (marketing) {
        return marketing;
    }
    if (vendor === "10de" && sensorName) {
        return sensorName;
    }
    const raw = pciName || sensorName || "";
    const bracket = /\[([^\]]+)\]/.exec(raw);
    const family = bracket && !bracket[1].includes("/") ? bracket[1] : raw;
    const brand = vendor === "8086" ? "Intel " : vendor === "1002" ? "AMD " : "";
    return family && !family.startsWith(brand.trim()) ? brand + family : family;
}

// "DDR5-4800 · 2 × 16 GiB" from the helper's memory block. Mixed sizes share
// the largest module's unit: "8 + 16 GiB", "0.5 + 1 GiB".
function memoryModules(memory) {
    if (!memory || !Array.isArray(memory.modules) || memory.modules.length === 0) {
        return "";
    }
    const type = memory.type && !/^(Unknown|Other|)$/.test(memory.type) ? memory.type : "";
    const kind = type && memory.speed > 0 ? type + "-" + memory.speed : type;
    const sizes = memory.modules.map(Number);
    let layout;
    if (sizes.every(s => s === sizes[0])) {
        const one = bytes(sizes[0], true);
        layout = whole(sizes.length) + " × " + one.value + " " + one.unit;
    } else {
        const i = byteScale(Math.max(...sizes));
        layout = sizes.map(s => compact(s / byteBase ** i)).join(" + ") + " " + byteLabels[i];
    }
    return kind ? kind + " · " + layout : layout;
}
