import QtQuick
import QtTest
import "../../package/contents/ui/code/format.js" as Format

TestCase {
    name: "Format"

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
        compare(Format.percent(data.input), data.expected);
    }

    function test_temperature_data() {
        return [
            { tag: "whole", celsius: 37, fahrenheit: false, expected: "37" },
            { tag: "fahrenheitConversion", celsius: 37, fahrenheit: true, expected: "99" },
            { tag: "zeroIsUninitialisedNotAReading", celsius: 0, fahrenheit: false, expected: "–" },
            { tag: "hugeNegativeGarbage", celsius: -1.397e62, fahrenheit: false, expected: "–" },
            // A subnormal double near zero is technically > 0 and < 150, so the
            // range check alone doesn't reject it: it prints as "0", the same as
            // a real freezing-point reading. See the report for a proposed fix.
            { tag: "tinySubnormalGarbageIsDash", celsius: 6.92e-310, fahrenheit: false, expected: "–" },
            { tag: "nan", celsius: NaN, fahrenheit: false, expected: "–" },
            { tag: "atUpperBoundaryIsInvalid", celsius: 150, fahrenheit: false, expected: "–" },
            { tag: "justBelowUpperBoundaryRoundsToIt", celsius: 149.6, fahrenheit: false, expected: "150" }
        ];
    }
    function test_temperature(data) {
        compare(Format.temperature(data.celsius, data.fahrenheit), data.expected);
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
        compare(result.value, data.value);
        compare(result.unit, data.unit);
    }

    // The 0.9995 fudge factor in byteScale() means a value just a hair under
    // the next unit already rounds up into it once formatted to one decimal.
    function test_bytes_roundsAcrossUnitBoundary() {
        var result = Format.bytes(1023.9 * 1024, false);
        compare(result.value, "1.0");
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
        compare(result.value, data.value);
        compare(result.total, data.total_);
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
        compare(result.value, data.value);
        compare(result.unit, data.unit);
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
        compare(result.value, data.value);
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
        compare(result.value, data.value);
        compare(result.unit, data.unit);
    }

    function test_duration_data() {
        return [
            { tag: "underAMinute", seconds: 30, expected: "30 s" },
            { tag: "notAMultipleOfAMinute", seconds: 90, expected: "90 s" },
            { tag: "oneMinuteInSeconds", seconds: 60, expected: "60 s" },
            { tag: "twoMinutes", seconds: 120, expected: "2 min" },
            { tag: "tenMinutes", seconds: 600, expected: "10 min" }
        ];
    }
    function test_duration(data) {
        compare(Format.duration(data.seconds), data.expected);
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
        compare(Format.load(data.value), data.expected);
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

    function test_memoryModules_matchedPair() {
        var memory = { type: "DDR5", speed: 4800, modules: [16 * 1024 * 1024 * 1024, 16 * 1024 * 1024 * 1024] };
        compare(Format.memoryModules(memory), "DDR5-4800 · 2 × 16 GiB");
    }

    function test_memoryModules_mixedSizes() {
        var memory = { type: "DDR4", speed: 3200, modules: [8 * 1024 * 1024 * 1024, 16 * 1024 * 1024 * 1024] };
        compare(Format.memoryModules(memory), "DDR4-3200 · 8 + 16 GiB");
    }

    function test_memoryModules_missingTypeDropsTheKindPrefix() {
        var memory = { type: "Unknown", speed: 4800, modules: [16 * 1024 * 1024 * 1024, 16 * 1024 * 1024 * 1024] };
        compare(Format.memoryModules(memory), "2 × 16 GiB");
    }

    function test_memoryModules_noConfiguredSpeedOmitsIt() {
        var memory = { type: "DDR4", speed: 0, modules: [8 * 1024 * 1024 * 1024] };
        compare(Format.memoryModules(memory), "DDR4 · 1 × 8 GiB");
    }

    function test_memoryModules_emptyOrMissingModules() {
        compare(Format.memoryModules({ type: "DDR5", speed: 4800, modules: [] }), "");
        compare(Format.memoryModules({ type: "DDR5", speed: 4800, modules: "oops" }), "");
        compare(Format.memoryModules(null), "");
        compare(Format.memoryModules(undefined), "");
    }
}
