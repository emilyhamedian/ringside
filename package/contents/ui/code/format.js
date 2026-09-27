.pragma library

// Readings come back as { value, unit } so the panel and popups can set the
// number in the monospace face and the unit dimmer beside it. Anything that
// isn't a usable number formats as an en dash.

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

function temperature(celsius, fahrenheit) {
    if (!temperatureValid(celsius)) {
        return DASH;
    }
    return whole(fahrenheit ? celsius * 9 / 5 + 32 : celsius);
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

const BYTE_UNITS = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];

function byteScale(bytes) {
    let i = 0;
    while (i < BYTE_UNITS.length - 1 && Math.abs(bytes) >= 1024 ** (i + 1) * 0.9995) {
        ++i;
    }
    return i;
}

// Bytes in binary units, the way Plasma's own System Monitor shows them.
function bytes(v, trim) {
    if (!usable(v)) {
        return { value: DASH, unit: "" };
    }
    const i = byteScale(v);
    const scaled = v / 1024 ** i;
    return { value: i === 0 ? whole(scaled) : trim ? compact(scaled) : number(scaled),
             unit: BYTE_UNITS[i] };
}

// "used / total" in the total's unit: { value: "0.2", total: "16", unit: "GiB" }.
function bytesOf(used, total) {
    if (!usable(total) || total <= 0) {
        return { value: DASH, total: DASH, unit: "" };
    }
    const i = byteScale(total);
    const d = 1024 ** i;
    return { value: usable(used) ? number(used / d) : DASH, total: compact(total / d), unit: BYTE_UNITS[i] };
}

// Network rates in decimal bits, as links are sold, or in binary bytes.
function rate(bytesPerSecond, bits) {
    if (!usable(bytesPerSecond)) {
        return { value: DASH, unit: bits ? "b/s" : "B/s" };
    }
    if (!bits) {
        const b = bytes(bytesPerSecond, false);
        return { value: b.value, unit: b.unit + "/s" };
    }
    const units = ["b/s", "kb/s", "Mb/s", "Gb/s", "Tb/s"];
    let v = bytesPerSecond * 8;
    let i = 0;
    while (i < units.length - 1 && Math.abs(v) >= 999.5) {
        v /= 1000;
        ++i;
    }
    return { value: i === 0 ? whole(v) : number(v), unit: units[i] };
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

// A graph's span in whole minutes where that reads better ("2 min" rather
// than "120 s"), otherwise 0 and the caption gives it in seconds.
function spanMinutes(seconds) {
    return seconds >= 120 && seconds % 60 === 0 ? seconds / 60 : 0;
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
        layout = sizes.map(s => compact(s / 1024 ** i)).join(" + ") + " " + BYTE_UNITS[i];
    }
    return kind ? kind + " · " + layout : layout;
}
