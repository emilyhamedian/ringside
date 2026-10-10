// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/code/format.js" as Format

TestCase {
    name: "Format"

    // Expected numbers are written in ASCII digits with a full stop. The
    // formatters use the running locale's digits and decimal separator, so
    // local() rewrites the expectation to match and the suite passes under
    // any locale: "24,8" in German, "٢٤٫٨" in Egyptian Arabic.
    function local(text) {
        const locale = Qt.locale();
        const zero = locale.zeroDigit.codePointAt(0);
        return text.replace(/[0-9.]/g, c => c === "." ? locale.decimalPoint : String.fromCodePoint(zero + Number(c)));
    }

    function test_level_data() {
        return [
            { tag: "nan", value: NaN, expected: 0 },
            { tag: "74.9", value: 74.9, expected: 0 },
            { tag: "75", value: 75, expected: 1 },
            { tag: "89.9", value: 89.9, expected: 1 },
            { tag: "90", value: 90, expected: 2 },
            { tag: "100", value: 100, expected: 2 }
        ];
    }
    function test_level(data) {
        compare(Format.level(data.value), data.expected);
    }

    function test_decimal_followsTheLocale() {
        compare(Format.decimal(3.66, 2), (3.66).toLocaleString(Qt.locale(), "f", 2));
        compare(Format.decimal(3.66, 2), local("3.66"));
    }

    function test_decimal_leavesOutGroupSeparators() {
        compare(Format.decimal(1234567.26, 1), local("1234567.3"));
    }

    function test_whole_data() {
        return [
            { tag: "roundsDown", v: 0.4, expected: "0" },
            { tag: "roundsHalfUp", v: 0.5, expected: "1" },
            { tag: "negativeZeroHasNoSign", v: -0.3, expected: "0" },
            { tag: "roundsUpToHundred", v: 99.96, expected: "100" },
            { tag: "noGrouping", v: 12345.4, expected: "12345" }
        ];
    }
    function test_whole(data) {
        compare(Format.whole(data.v), local(data.expected));
    }

    // Whole numbers and decimals share the locale's digits, so a readout
    // keeps one numeral system as it crosses 99.95 or a unit boundary.
    function test_whole_matchesDecimalDigits() {
        compare(Format.number(99.94), local("99.9"));
        compare(Format.number(99.96), local("100"));
        compare(Format.rate(1023, false).value, local("1023"));
        compare(Format.rate(1024, false).value, local("1.0"));
    }

    function test_fixed_data() {
        return [
            { tag: "twoDigits", v: 0.4213, digits: 2, expected: "0.42" },
            { tag: "noGrouping", v: 1234.5, digits: 1, expected: "1234.5" },
            { tag: "nan", v: NaN, digits: 1, expected: "–" }
        ];
    }
    function test_fixed(data) {
        compare(Format.fixed(data.v, data.digits), local(data.expected));
    }

    function test_percent_data() {
        return [
            { tag: "rounds", input: 50.4, expected: "50" },
            { tag: "roundsUp", input: 50.6, expected: "51" },
            { tag: "clampsBelowZero", input: -12, expected: "0" },
            { tag: "clampsAboveHundred", input: 137, expected: "100" },
            { tag: "nan", input: NaN, expected: "–" },
            { tag: "wrongType", input: "50", expected: "–" },
            { tag: "undefined", input: undefined, expected: "–" }
        ];
    }
    function test_percent(data) {
        compare(Format.percent(data.input), local(data.expected));
    }

    function test_temperature_data() {
        return [
            { tag: "whole", celsius: 37, fahrenheit: false, expected: "37" },
            { tag: "fahrenheitConversion", celsius: 37, fahrenheit: true, expected: "99" },
            { tag: "zeroIsUninitialisedNotAReading", celsius: 0, fahrenheit: false, expected: "–" },
            { tag: "hugeNegativeGarbage", celsius: -1.397e62, fahrenheit: false, expected: "–" },
            // A subnormal double near zero passes a > 0 check; the 1 °C floor
            // keeps it from printing as a real freezing-point reading.
            { tag: "tinySubnormalGarbageIsDash", celsius: 6.92e-310, fahrenheit: false, expected: "–" },
            { tag: "nan", celsius: NaN, fahrenheit: false, expected: "–" },
            { tag: "atUpperBoundaryIsInvalid", celsius: 150, fahrenheit: false, expected: "–" },
            { tag: "justBelowUpperBoundaryRoundsToIt", celsius: 149.6, fahrenheit: false, expected: "150" }
        ];
    }
    function test_temperature(data) {
        compare(Format.temperature(data.celsius, data.fahrenheit), local(data.expected));
    }

    function test_heat_data() {
        return [
            { tag: "cold", celsius: 40, warm: 75, hot: 90, expected: 0 },
            { tag: "warm", celsius: 80, warm: 75, hot: 90, expected: 1 },
            { tag: "warmBoundaryIsInclusive", celsius: 75, warm: 75, hot: 90, expected: 1 },
            { tag: "hot", celsius: 95, warm: 75, hot: 90, expected: 2 },
            { tag: "hotBoundaryIsInclusive", celsius: 90, warm: 75, hot: 90, expected: 2 },
            { tag: "invalidGarbageReadsAsCold", celsius: -1.397e62, warm: 75, hot: 90, expected: 0 },
            { tag: "nanReadsAsCold", celsius: NaN, warm: 75, hot: 90, expected: 0 }
        ];
    }
    function test_heat(data) {
        compare(Format.heat(data.celsius, data.warm, data.hot), data.expected);
    }

    function test_bytes_data() {
        return [
            { tag: "smallWholeBytesNeverGetADecimal", v: 500, trim: false, value: "500", unit: "B" },
            { tag: "kibNoTrim", v: 2048, trim: false, value: "2.0", unit: "KiB" },
            { tag: "kibTrimDropsTrailingZero", v: 2048, trim: true, value: "2", unit: "KiB" },
            { tag: "mib", v: 5 * 1024 * 1024, trim: false, value: "5.0", unit: "MiB" },
            { tag: "invalid", v: NaN, trim: false, value: "–", unit: "" }
        ];
    }
    function test_bytes(data) {
        var result = Format.bytes(data.v, data.trim);
        compare(result.value, local(data.value));
        compare(result.unit, data.unit);
    }

    // The 0.9995 fudge factor in byteScale() means a value just a hair under
    // the next unit already rounds up into it once formatted to one decimal.
    function test_bytes_roundsAcrossUnitBoundary() {
        var result = Format.bytes(1023.9 * 1024, false);
        compare(result.value, local("1.0"));
        compare(result.unit, "MiB");
    }

    function test_bytesOf_data() {
        return [
            { tag: "usedOfTotal", used: 3.2 * 1024 * 1024 * 1024, total: 16 * 1024 * 1024 * 1024,
              value: "3.2", total_: "16", unit: "GiB" },
            { tag: "invalidTotalNaN", used: 5, total: NaN, value: "–", total_: "–", unit: "" },
            { tag: "invalidTotalZero", used: 5, total: 0, value: "–", total_: "–", unit: "" },
            { tag: "invalidTotalNegative", used: 5, total: -5, value: "–", total_: "–", unit: "" },
            { tag: "usedNotUsable", used: NaN, total: 16 * 1024 * 1024 * 1024,
              value: "–", total_: "16", unit: "GiB" },
            { tag: "usedUndefinedBeforeFirstSample", used: undefined, total: 8 * 1024 * 1024 * 1024,
              value: "–", total_: "8", unit: "GiB" }
        ];
    }
    function test_bytesOf(data) {
        var result = Format.bytesOf(data.used, data.total);
        compare(result.value, local(data.value));
        compare(result.total, local(data.total_));
        compare(result.unit, data.unit);
    }

    function test_rate_data() {
        return [
            { tag: "bytesKiB", bytesPerSecond: 2048, bits: false, value: "2.0", unit: "KiB/s" },
            { tag: "bytesSmallStaysWhole", bytesPerSecond: 500, bits: false, value: "500", unit: "B/s" },
            { tag: "bitsSmallStaysWhole", bytesPerSecond: 10, bits: true, value: "80", unit: "b/s" },
            { tag: "bitsKilo", bytesPerSecond: 125, bits: true, value: "1.0", unit: "kb/s" },
            { tag: "bitsMega", bytesPerSecond: 125000, bits: true, value: "1.0", unit: "Mb/s" },
            { tag: "invalidBytes", bytesPerSecond: NaN, bits: false, value: "–", unit: "B/s" },
            { tag: "invalidBits", bytesPerSecond: NaN, bits: true, value: "–", unit: "b/s" }
        ];
    }
    function test_rate(data) {
        var result = Format.rate(data.bytesPerSecond, data.bits);
        compare(result.value, local(data.value));
        compare(result.unit, data.unit);
    }

    // Three figures whatever the size, a point narrower from 100, rounding
    // into the next figure as the value shown would.
    function test_significant_data() {
        return [
            { tag: "zero", v: 0, expected: "0.00" },
            { tag: "under one", v: 0.004, expected: "0.00" },
            { tag: "two decimals", v: 8.4, expected: "8.40" },
            { tag: "just under ten", v: 9.994, expected: "9.99" },
            { tag: "rounds to ten", v: 9.995, expected: "10.0" },
            { tag: "one decimal", v: 62.14, expected: "62.1" },
            { tag: "just under a hundred", v: 99.94, expected: "99.9" },
            { tag: "rounds to a hundred", v: 99.95, expected: "100" },
            { tag: "whole", v: 353.2, expected: "353" },
            { tag: "most", v: 999.4, expected: "999" }
        ];
    }
    function test_significant(data) {
        compare(Format.significant(data.v), local(data.expected));
    }

    // The panel's rates step their unit at 999.5 of the one shown, so no
    // value takes a fourth figure, and start at kb/s or KiB/s, so a quiet
    // link reads "0.00" in the unit a busy one starts from.
    function test_panelRate_data() {
        const kib = 1024;
        const mib = 1024 * kib;
        const gib = 1024 * mib;
        return [
            { tag: "idle bytes", v: 0, bits: false, value: "0.00", unit: "KiB/s" },
            { tag: "idle bits", v: 0, bits: true, value: "0.00", unit: "kb/s" },
            { tag: "a byte", v: 1, bits: false, value: "0.00", unit: "KiB/s" },
            { tag: "999 b/s", v: 999 / 8, bits: true, value: "1.00", unit: "kb/s" },
            { tag: "4.1 KiB/s", v: 4.1 * kib, bits: false, value: "4.10", unit: "KiB/s" },
            { tag: "62.1 kb/s", v: 62.1e3 / 8, bits: true, value: "62.1", unit: "kb/s" },
            { tag: "353 KiB/s", v: 353 * kib, bits: false, value: "353", unit: "KiB/s" },
            { tag: "999.4 kb/s", v: 999.4e3 / 8, bits: true, value: "999", unit: "kb/s" },
            { tag: "999.5 kb/s", v: 999.5e3 / 8, bits: true, value: "1.00", unit: "Mb/s" },
            { tag: "999.4 KiB/s", v: 999.4 * kib, bits: false, value: "999", unit: "KiB/s" },
            { tag: "999.5 KiB/s", v: 999.5 * kib, bits: false, value: "0.98", unit: "MiB/s" },
            { tag: "1000 KiB/s", v: 1000 * kib, bits: false, value: "0.98", unit: "MiB/s" },
            { tag: "1023 KiB/s", v: 1023 * kib, bits: false, value: "1.00", unit: "MiB/s" },
            { tag: "8.4 Mb/s", v: 8.4e6 / 8, bits: true, value: "8.40", unit: "Mb/s" },
            { tag: "5.8 MiB/s", v: 5.8 * mib, bits: false, value: "5.80", unit: "MiB/s" },
            { tag: "99.96 Mb/s", v: 99.96e6 / 8, bits: true, value: "100", unit: "Mb/s" },
            { tag: "900 Mb/s", v: 900e6 / 8, bits: true, value: "900", unit: "Mb/s" },
            { tag: "1023 MiB/s", v: 1023 * mib, bits: false, value: "1.00", unit: "GiB/s" },
            { tag: "1023 GiB/s", v: 1023 * gib, bits: false, value: "1.00", unit: "TiB/s" },
            { tag: "1.1 Tb/s", v: 1.1e12 / 8, bits: true, value: "1.10", unit: "Tb/s" },
            { tag: "no reading in bytes", v: NaN, bits: false, value: "–", unit: "KiB/s" },
            { tag: "no reading in bits", v: NaN, bits: true, value: "–", unit: "kb/s" }
        ];
    }
    function test_panelRate(data) {
        const result = Format.panelRate(data.v, data.bits);
        compare([result.value, result.unit], [local(data.value), data.unit]);
        verify(Format.panelRateUnits(data.bits).includes(result.unit), result.unit + " is one of the units the panel keeps room for");
    }

    // Memory for the panel is one decimal, its unit stepping at 999.95.
    function test_panelBytes_data() {
        const mib = 1024 * 1024;
        const gib = 1024 * mib;
        return [
            { tag: "bytes stay whole", v: 500, value: "500", unit: "B" },
            { tag: "512 KiB", v: 512 * 1024, value: "512.0", unit: "KiB" },
            { tag: "353 MiB", v: 353 * mib, value: "353.0", unit: "MiB" },
            { tag: "512 MiB", v: 512 * mib, value: "512.0", unit: "MiB" },
            { tag: "999.9 MiB", v: 999.9 * mib, value: "999.9", unit: "MiB" },
            { tag: "999.96 MiB", v: 999.96 * mib, value: "1.0", unit: "GiB" },
            { tag: "1023 MiB", v: 1023 * mib, value: "1.0", unit: "GiB" },
            { tag: "9.6 GiB", v: 9.6 * gib, value: "9.6", unit: "GiB" },
            { tag: "9.64 GiB", v: 9.64 * gib, value: "9.6", unit: "GiB" },
            { tag: "24.6 GiB", v: 24.6 * gib, value: "24.6", unit: "GiB" },
            { tag: "128 GiB", v: 128 * gib, value: "128.0", unit: "GiB" },
            { tag: "1023 GiB", v: 1023 * gib, value: "1.0", unit: "TiB" },
            { tag: "no reading", v: NaN, value: "–", unit: "" }
        ];
    }
    function test_panelBytes(data) {
        const result = Format.panelBytes(data.v);
        compare([result.value, result.unit], [local(data.value), data.unit]);
        verify(Format.panelByteUnits().includes(result.unit) || result.unit === "", result.unit + " is one of the units the panel keeps room for");
    }

    function test_frequency_data() {
        return [
            { tag: "mhz", megahertz: 800, value: "800", unit: "MHz" },
            { tag: "ghz", megahertz: 3400, value: "3.40", unit: "GHz" },
            { tag: "boundaryAtOneGhz", megahertz: 1000, value: "1.00", unit: "GHz" },
            { tag: "zeroIsInvalid", megahertz: 0, value: "–", unit: "" },
            { tag: "negativeIsInvalid", megahertz: -5, value: "–", unit: "" },
            { tag: "nan", megahertz: NaN, value: "–", unit: "" }
        ];
    }
    function test_frequency(data) {
        var result = Format.frequency(data.megahertz);
        compare(result.value, local(data.value));
        compare(result.unit, data.unit);
    }

    function test_watts_data() {
        return [
            { tag: "rounds", v: 45.4, value: "45", unit: "W" },
            { tag: "roundsUp", v: 45.6, value: "46", unit: "W" },
            { tag: "zeroIsValid", v: 0, value: "0", unit: "W" },
            { tag: "negativeIsInvalid", v: -1, value: "–", unit: "" },
            { tag: "nan", v: NaN, value: "–", unit: "" }
        ];
    }
    function test_watts(data) {
        var result = Format.watts(data.v);
        compare(result.value, local(data.value));
        compare(result.unit, data.unit);
    }

    function test_load_data() {
        return [
            { tag: "light", value: 1.4213, expected: "1.42" },
            { tag: "tens", value: 14.26, expected: "14.3" },
            { tag: "hundreds", value: 143.93, expected: "144" },
            { tag: "nan", value: NaN, expected: "–" }
        ];
    }
    function test_load(data) {
        compare(Format.load(data.value), local(data.expected));
    }

    function test_cpuModel_data() {
        return [
            { tag: "amdWithGraphicsSuffix", raw: "AMD Ryzen 7 7840HS w/ Radeon 780M Graphics",
              expected: "AMD Ryzen 7 7840HS" },
            { tag: "amdWithCoreCountSuffix", raw: "AMD Ryzen Threadripper 3990X 64-Core Processor",
              expected: "AMD Ryzen Threadripper 3990X" },
            { tag: "intelWithTrademarksAndClock", raw: "Intel(R) Core(TM) i7-1165G7 @ 2.80GHz",
              expected: "Intel Core i7-1165G7" },
            { tag: "intelXeonWithVariantSuffix", raw: "Intel(R) Xeon(R) CPU E5-2670 v3 @ 2.30GHz",
              expected: "Intel Xeon CPU E5-2670 v3" },
            { tag: "armStyleNameIsLeftAlone", raw: "Qualcomm Technologies, Inc SM8350",
              expected: "Qualcomm Technologies, Inc SM8350" },
            { tag: "collapsesInternalWhitespace", raw: "  AMD   Ryzen  9   ", expected: "AMD Ryzen 9" },
            { tag: "undefinedInput", raw: undefined, expected: "" },
            { tag: "nullInput", raw: null, expected: "" }
        ];
    }
    function test_cpuModel(data) {
        compare(Format.cpuModel(data.raw), data.expected);
    }

    function test_gpuModel_data() {
        return [
            { tag: "marketingNameWins", marketing: "AMD Radeon RX 7600", sensorName: "ignored",
              pciName: "ignored", vendor: "1002", expected: "AMD Radeon RX 7600" },
            { tag: "nvidiaWithoutMarketingUsesSensorName", marketing: "", sensorName: "NVIDIA GeForce RTX 4070",
              pciName: "", vendor: "10de", expected: "NVIDIA GeForce RTX 4070" },
            { tag: "nvidiaFallsBackToPciBracket", marketing: "", sensorName: "", pciName: "GA104 [GeForce RTX 3070]",
              vendor: "10de", expected: "GeForce RTX 3070" },
            { tag: "intelRaptorLakeBracket", marketing: "", sensorName: "", pciName: "Raptor Lake-P [Iris Xe Graphics]",
              vendor: "8086", expected: "Intel Iris Xe Graphics" },
            { tag: "amdWithoutMarketingAndSlashInBracketKeepsFullString", marketing: "", sensorName: "",
              pciName: "Navi 33 [Radeon RX 7600/7600 XT/Radeon RX 7900M]", vendor: "1002",
              expected: "AMD Navi 33 [Radeon RX 7600/7600 XT/Radeon RX 7900M]" },
            { tag: "unknownEverythingIsBlank", marketing: "", sensorName: "", pciName: "", vendor: "",
              expected: "" }
        ];
    }
    function test_gpuModel(data) {
        compare(Format.gpuModel(data.marketing, data.sensorName, data.pciName, data.vendor), data.expected);
    }

    // "DDR5-4800" is a part designation and stays in ASCII digits; the
    // count and sizes follow the locale.
    function test_memoryModules_matchedPair() {
        var memory = { type: "DDR5", speed: 4800, modules: [16 * 1024 * 1024 * 1024, 16 * 1024 * 1024 * 1024] };
        compare(Format.memoryModules(memory), "DDR5-4800 · " + local("2 × 16 GiB"));
    }

    function test_memoryModules_mixedSizes() {
        var memory = { type: "DDR4", speed: 3200, modules: [8 * 1024 * 1024 * 1024, 16 * 1024 * 1024 * 1024] };
        compare(Format.memoryModules(memory), "DDR4-3200 · " + local("8 + 16 GiB"));
    }

    // Every module in the largest one's unit, whichever order the slots report.
    function test_memoryModules_mixedUnits_data() {
        return [
            { tag: "smallerFirst", modules: [512 * 1024 * 1024, 1024 * 1024 * 1024], expected: "0.5 + 1 GiB" },
            { tag: "largerFirst", modules: [1024 * 1024 * 1024, 512 * 1024 * 1024], expected: "1 + 0.5 GiB" },
            { tag: "gibAndTib", modules: [512 * 1024 * 1024 * 1024, 1024 * 1024 * 1024 * 1024],
              expected: "0.5 + 1 TiB" }
        ];
    }
    function test_memoryModules_mixedUnits(data) {
        compare(Format.memoryModules({ type: "DDR2", speed: 800, modules: data.modules }), "DDR2-800 · " + local(data.expected));
    }

    function test_memoryModules_missingTypeDropsTheKindPrefix() {
        var memory = { type: "Unknown", speed: 4800, modules: [16 * 1024 * 1024 * 1024, 16 * 1024 * 1024 * 1024] };
        compare(Format.memoryModules(memory), local("2 × 16 GiB"));
    }

    function test_memoryModules_noConfiguredSpeedOmitsIt() {
        var memory = { type: "DDR4", speed: 0, modules: [8 * 1024 * 1024 * 1024] };
        compare(Format.memoryModules(memory), "DDR4 · " + local("1 × 8 GiB"));
    }

    function test_memoryModules_emptyOrMissingModules() {
        compare(Format.memoryModules({ type: "DDR5", speed: 4800, modules: [] }), "");
        compare(Format.memoryModules({ type: "DDR5", speed: 4800, modules: "oops" }), "");
        compare(Format.memoryModules(null), "");
        compare(Format.memoryModules(undefined), "");
    }

    function test_timeLeft_data() {
        const now = 1000000 * 1000;
        const at = seconds => now / 1000 + seconds;
        return [
            { tag: "daysAndHours", resetsAt: at(2 * 86400 + 21 * 3600 + 12 * 60), expected: { days: 2, hours: 21, minutes: 12 } },
            { tag: "hoursAndMinutes", resetsAt: at(5 * 3600 + 12 * 60), expected: { days: 0, hours: 5, minutes: 12 } },
            { tag: "roundsToTheNearestMinute", resetsAt: at(2 * 86400 + 21 * 3600 - 20), expected: { days: 2, hours: 21, minutes: 0 } },
            { tag: "aWholeWeek", resetsAt: at(7 * 86400), expected: { days: 7, hours: 0, minutes: 0 } },
            { tag: "underHalfAMinuteIsPassed", resetsAt: at(20), expected: null },
            { tag: "passed", resetsAt: at(-3600), expected: null },
            { tag: "noTime", resetsAt: null, expected: null }
        ].map(row => Object.assign(row, { now: now }));
    }
    function test_timeLeft(data) {
        compare(Format.timeLeft(data.resetsAt, data.now), data.expected);
    }

    // 11:00 UTC on Sunday 27 September 2026 is 7:00 on the clock in New York
    // (EDT, -4 h) and 20:00 in Tokyo (+9 h), whatever zone the tests run in.
    function test_wallClock_data() {
        const epoch = Date.UTC(2026, 8, 27, 11, 0, 0) / 1000;
        return [
            { tag: "west", epoch: epoch, offset: -4 * 3600, day: 0, date: 27, hours: 7, minutes: 0 },
            { tag: "east", epoch: epoch, offset: 9 * 3600, day: 0, date: 27, hours: 20, minutes: 0 },
            { tag: "acrossMidnight", epoch: epoch + 14 * 3600, offset: -4 * 3600, day: 0, date: 27, hours: 21, minutes: 0 },
            { tag: "nextDay", epoch: epoch + 14 * 3600, offset: 9 * 3600, day: 1, date: 28, hours: 10, minutes: 0 },
            { tag: "halfHourZone", epoch: epoch, offset: 5.5 * 3600, day: 0, date: 27, hours: 16, minutes: 30 }
        ];
    }
    function test_wallClock(data) {
        const wall = Format.wallClock(data.epoch, data.offset);
        compare([wall.getDay(), wall.getDate(), wall.getHours(), wall.getMinutes()],
                [data.day, data.date, data.hours, data.minutes]);
    }

    // KDE's three choices of data units, as Monitor hands them to format.js.
    readonly property var dialects: ({
        iec: { base: 1024, labels: ["B", "KiB", "MiB", "GiB", "TiB", "PiB"] },
        jedec: { base: 1024, labels: ["B", "KB", "MB", "GB", "TB", "PB"] },
        metric: { base: 1000, labels: ["B", "kB", "MB", "GB", "TB", "PB"] }
    })

    function cleanup() {
        Format.setByteUnits(dialects.iec.base, dialects.iec.labels);
    }

    // Every size and byte rate takes the base and the names of the units
    // KDE is set to; bit rates stay in 1000s whatever it is.
    function test_byteUnits_data() {
        const gib = 1024 ** 3;
        const mib = 1024 ** 2;
        const rows = [];
        const add = (what, show, expected) => {
            for (const dialect of Object.keys(expected)) {
                rows.push({ tag: what + " in " + dialect, dialect: dialect, show: show, expected: expected[dialect] });
            }
        };
        const panelBytes = v => () => Format.panelBytes(v);
        // The panel's memory.
        add("9.6 GiB", panelBytes(9.6 * gib), { iec: ["9.6", "GiB"], jedec: ["9.6", "GB"], metric: ["10.3", "GB"] });
        add("900 MiB", panelBytes(900 * mib), { iec: ["900.0", "MiB"], jedec: ["900.0", "MB"], metric: ["943.7", "MB"] });
        // The unit steps up at 999.95 of the one shown, in either base.
        add("999.9 million", panelBytes(999.9e6), { iec: ["953.6", "MiB"], metric: ["999.9", "MB"] });
        add("999.96 million", panelBytes(999.96e6), { iec: ["953.6", "MiB"], metric: ["1.0", "GB"] });
        add("999.96 MiB", panelBytes(999.96 * mib), { iec: ["1.0", "GiB"], jedec: ["1.0", "GB"], metric: ["1.0", "GB"] });
        add("1000 bytes", panelBytes(1000), { iec: ["1.0", "KiB"], metric: ["1.0", "kB"] });
        // A popup's sizes, and a total.
        add("3.2 GiB", () => Format.bytes(3.2 * gib, false), { iec: ["3.2", "GiB"], jedec: ["3.2", "GB"], metric: ["3.4", "GB"] });
        add("16 GiB trimmed", () => Format.bytes(16 * gib, true), { iec: ["16", "GiB"], jedec: ["16", "GB"], metric: ["17.2", "GB"] });
        add("1000 bytes in a popup", () => Format.bytes(1000, false), { iec: ["1000", "B"], metric: ["1.0", "kB"] });
        add("999.6 thousand", () => Format.bytes(999.6e3, false), { iec: ["976", "KiB"], metric: ["1.0", "MB"] });
        add("3.2 of 16 GiB", () => { const b = Format.bytesOf(3.2 * gib, 16 * gib); return { value: b.value + "/" + b.total, unit: b.unit }; },
            { iec: ["3.2/16", "GiB"], jedec: ["3.2/16", "GB"], metric: ["3.4/17.2", "GB"] });
        // Disk rates, and network ones in bytes.
        add("5.8 MiB/s", () => Format.rate(5.8 * mib, false), { iec: ["5.8", "MiB/s"], jedec: ["5.8", "MB/s"], metric: ["6.1", "MB/s"] });
        add("no rate", () => Format.rate(NaN, false), { iec: ["–", "B/s"], metric: ["–", "B/s"] });
        add("8.4 Mb/s", () => Format.rate(8.4e6 / 8, true), { iec: ["8.4", "Mb/s"], metric: ["8.4", "Mb/s"] });
        add("353 KiB/s in the panel", () => Format.panelRate(353 * 1024, false),
            { iec: ["353", "KiB/s"], jedec: ["353", "KB/s"], metric: ["361", "kB/s"] });
        add("999.4 thousand a second in the panel", () => Format.panelRate(999.4e3, false), { iec: ["976", "KiB/s"], metric: ["999", "kB/s"] });
        add("999.5 thousand a second in the panel", () => Format.panelRate(999.5e3, false), { iec: ["976", "KiB/s"], metric: ["1.00", "MB/s"] });
        add("1000 KiB/s in the panel", () => Format.panelRate(1000 * 1024, false), { iec: ["0.98", "MiB/s"], metric: ["1.02", "MB/s"] });
        add("idle in the panel", () => Format.panelRate(0, false), { iec: ["0.00", "KiB/s"], jedec: ["0.00", "KB/s"], metric: ["0.00", "kB/s"] });
        add("8.4 Mb/s in the panel", () => Format.panelRate(8.4e6 / 8, true), { iec: ["8.40", "Mb/s"], metric: ["8.40", "Mb/s"] });
        // Memory modules.
        add("two 16 GiB modules", () => ({ value: Format.memoryModules({ type: "", speed: 0, modules: [16 * gib, 16 * gib] }), unit: "" }),
            { iec: ["2 × 16 GiB", ""], jedec: ["2 × 16 GB", ""], metric: ["2 × 17.2 GB", ""] });
        add("8 and 16 GiB modules", () => ({ value: Format.memoryModules({ type: "", speed: 0, modules: [8 * gib, 16 * gib] }), unit: "" }),
            { iec: ["8 + 16 GiB", ""], metric: ["8.6 + 17.2 GB", ""] });
        return rows;
    }
    function test_byteUnits(data) {
        const units = dialects[data.dialect];
        Format.setByteUnits(units.base, units.labels);
        const result = data.show();
        compare([result.value, result.unit], [local(data.expected[0]), data.expected[1]]);
        if (data.expected[1].endsWith("B")) {
            verify(units.labels.includes(result.unit));
        }
    }

    // The panel keeps room for the units it can show, in the names shown.
    function test_byteUnits_panelRoom_data() {
        return Object.keys(dialects).map(dialect => ({ tag: dialect, dialect: dialect }));
    }
    function test_byteUnits_panelRoom(data) {
        const units = dialects[data.dialect];
        Format.setByteUnits(units.base, units.labels);
        compare(Format.panelByteUnits(), units.labels);
        compare(Format.panelRateUnits(false), units.labels.slice(1).map(label => label + "/s"));
        compare(Format.panelRateUnits(true), ["kb/s", "Mb/s", "Gb/s", "Tb/s"]);
        for (const v of [500, 999.4e3, 999.6e3, 5.8e6, 9.6 * 1024 ** 3, 1.2e12, 2e15]) {
            verify(Format.panelByteUnits().includes(Format.panelBytes(v).unit), "room for " + v + " bytes");
            verify(Format.panelRateUnits(false).includes(Format.panelRate(v, false).unit), "room for " + v + " bytes a second");
        }
    }

    // A unit's name in KDE's words, from two sizes in it.
    function test_unitLabel_data() {
        return [
            { tag: "after the number", one: "1 KiB", two: "2 KiB", label: "KiB" },
            { tag: "French, after a no-break space", one: "1 Kio", two: "2 Kio", label: "Kio" },
            { tag: "narrow no-break space", one: "1 MB", two: "2 MB", label: "MB" },
            { tag: "Arabic digits and name", one: "١ ك.بايت", two: "٢ ك.بايت",
              label: "ك.بايت" },
            { tag: "before the number", one: "KiB 1", two: "KiB 2", label: "KiB" },
            { tag: "before the number, Arabic digits", one: "GB ١", two: "GB ٢", label: "GB" },
            { tag: "no unit", one: "1", two: "2", label: "" },
            { tag: "the same text", one: "1 KiB", two: "1 KiB", label: "" },
            { tag: "nothing", one: "", two: "", label: "" }
        ];
    }
    function test_unitLabel(data) {
        compare(Format.unitLabel(data.one, data.two), data.label);
    }

    // A stand-in for KDE's formatter: whole units, the number in `digits`,
    // between a no-break space and the unit, or after it.
    function kde(base, labels, digits, unitFirst) {
        return size => {
            let n = 0;
            while (n < labels.length - 1 && size >= base ** (n + 1)) {
                ++n;
            }
            const number = String(Math.round(size / base ** n)).replace(/[0-9]/g, d => digits[d]);
            return unitFirst ? labels[n] + " " + number : number + " " + labels[n];
        };
    }

    // KDE's units from its formatter: their base from whether 1000 bytes read
    // as 1024 do, their names from pairs of sizes; nothing from a formatter
    // that doesn't name six different units.
    function test_byteUnitsFrom_data() {
        const ascii = "0123456789";
        const arabic = "٠١٢٣٤٥٦٧٨٩";
        const french = ["o", "Kio", "Mio", "Gio", "Tio", "Pio"];
        const metric = dialects.metric;
        return [
            { tag: "iec", size: kde(1024, dialects.iec.labels, ascii), expected: dialects.iec },
            { tag: "jedec", size: kde(1024, dialects.jedec.labels, ascii), expected: dialects.jedec },
            { tag: "metric", size: kde(1000, metric.labels, ascii), expected: metric },
            { tag: "French", size: kde(1024, french, ascii), expected: { base: 1024, labels: french } },
            { tag: "metric in Arabic digits", size: kde(1000, metric.labels, arabic), expected: metric },
            { tag: "unit first", size: kde(1000, metric.labels, ascii, true), expected: metric },
            { tag: "a number alone", size: size => String(size), expected: null },
            { tag: "always the same", size: size => "1 KiB", expected: null },
            { tag: "nothing", size: size => undefined, expected: null },
            { tag: "two units named alike", size: kde(1024, ["B", "B", "MiB", "GiB", "TiB", "PiB"], ascii), expected: null }
        ];
    }
    function test_byteUnitsFrom(data) {
        compare(Format.byteUnitsFrom(data.size), data.expected);
    }
}
