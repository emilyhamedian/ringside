// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui/code/format.js" as Format
import "../../package/contents/ui/code/style.js" as Style

// Every popup against FakeMonitor in the states the gallery shows, loaded the
// way main.qml loads them. qmllint can't type the duck-typed monitor, so a
// script error in a popup binding, such as a JavaScript builtin Qt's engine
// lacks, only shows up at run time; any such warning fails the test.

TestRoot {
    id: root
    width: 800
    height: 900

    FakeMonitor {
        id: normal
    }

    FakeMonitor {
        id: hot
        cpuTemperature: 92
    }

    // Enough threads for the per-thread bars to take a second row.
    FakeMonitor {
        id: manyThreads
        cpuCores: 64
        cpuThreads: 128
    }

    FakeMonitor {
        id: asleep
        gpuOuter.phase: "asleep"
    }

    FakeMonitor {
        id: resting
        gpuOuter.phase: "resting"
    }

    FakeMonitor {
        id: integrated
        gpuOuter.kind: "integrated"
        gpuOuter.name: "AMD Radeon 780M Graphics"
        gpuOuter.power: NaN
        gpuInner.present: false
    }

    // The discrete GPU picked for the inner ring, asleep.
    FakeMonitor {
        id: innerAsleep
        gpuOuter.kind: "integrated"
        gpuOuter.name: "AMD Radeon 780M Graphics"
        gpuOuter.power: NaN
        gpuInner.kind: "discrete"
        gpuInner.name: "AMD Radeon RX 7700S"
        gpuInner.phase: "asleep"
        gpuInner.knownVramTotal: 8 * innerAsleep.gib
    }

    // Intel publishes no GPU temperature or VRAM.
    FakeMonitor {
        id: intel
        cpuModel: "Intel Core i7-12700H"
        gpuOuter.name: "NVIDIA GeForce RTX 3060 Laptop GPU"
        gpuOuter.temperatureLabel: ""
        gpuInner.name: "Intel Iris Xe Graphics"
        gpuInner.temperatureLabel: ""
        gpuInner.reportsTemperature: false
        gpuInner.reportsVram: false
        gpuInner.temperature: NaN
        gpuInner.vramUsed: NaN
        gpuInner.knownVramTotal: NaN
    }

    // A CPU that names no temperature sensor, and no memory reading yet.
    FakeMonitor {
        id: uncaptioned
        cpuTemperatureLabel: ""
        memoryUsed: NaN
    }

    // A subtitle longer than the header has room for.
    FakeMonitor {
        id: longModel
        cpuModel: "AMD Ryzen Threadripper PRO 7995WX 96-Cores with a long name"
    }

    FakeMonitor {
        id: discreteOnly
        gpuInner.present: false
    }

    FakeMonitor {
        id: onlyAsleep
        gpuOuter.phase: "asleep"
        gpuInner.present: false
    }

    // Names longer than a header has room for at any popup width.
    FakeMonitor {
        id: longGpuNames
        gpuOuter.name: "NVIDIA GeForce RTX 4090 Laptop GPU with a very long marketing name"
        gpuInner.name: "Advanced Micro Devices Radeon 890M Graphics (Strix Point)"
    }

    // No pressure stall information and no swap.
    FakeMonitor {
        id: bare
        memoryPressure: NaN
        swapUsed: 0
        swapTotal: 0
        swapLabel: ""
    }

    // Sensors other than the usual Tctl and edge.
    FakeMonitor {
        id: otherSensors
        cpuTemperatureLabel: "Tccd3"
        gpuOuter.temperatureLabel: "junction"
        gpuInner.temperatureLabel: "mem"
    }

    // Rates well under the rate graphs' floors.
    FakeMonitor {
        id: idle
        networkDownHistory: Array(historyLength).fill(4000)
        networkUpHistory: Array(historyLength).fill(1000)
        diskReadHistory: Array(historyLength).fill(20000)
        diskWriteHistory: Array(historyLength).fill(8000)
    }

    // An upload, a backup say, above every download in view.
    FakeMonitor {
        id: uploading
        networkUp: 2.4e6
        networkUpHistory: bursts(networkUp, 9e6, 3)
    }

    // Just opened: no rate has a sample yet.
    Component {
        id: unsampled
        FakeMonitor {
            networkDownHistory: []
            networkUpHistory: []
            diskReadHistory: []
            diskWriteHistory: []
        }
    }

    // A drive that reports no temperature.
    FakeMonitor {
        id: diskUnheated
        diskTemperature: NaN
    }

    // A CPU temperature sensor that never answers.
    FakeMonitor {
        id: cpuUnheated
        cpuTemperature: NaN
    }

    // Temperatures climbing from 60 °C to 93 °C across the graph's span,
    // through the warm and hot thresholds.
    Component {
        id: heating
        FakeMonitor {
            readonly property var climb: Array.from({ length: historyLength }, (_, i) => 60 + 33 * i / (historyLength - 1))
            cpuTemperature: 93
            cpuTemperatureHistory: climb
            gpuOuter.temperature: 93
            gpuOuter.temperatureHistory: climb
            diskTemperature: 93
            diskTemperatureHistory: climb
        }
    }

    // A CPU that ran over the hot threshold in one of the day's 10-minute
    // steps, and stayed calm through the last minute and hour.
    Component {
        id: hotDay
        FakeMonitor {
            cpuTemperatureHighs: highsOf(cpuTemperatureHistory, 8, 9, Infinity).map((v, i) => graphSpan === "day" && i === 100 ? 93.4 : v)
            cpuTemperatureExtent: [44, 93.4]
        }
    }

    // The discrete GPU alone, awake for the last 35 s of the graph's span.
    Component {
        id: woken
        FakeMonitor {
            gpuOuter.temperatureHistory: Array.from({ length: historyLength }, (_, i) => i < 25 ? NaN : 48)
            gpuInner.present: false
        }
    }

    // Every whole disk's I/O, and a volume picked by its own name.
    FakeMonitor {
        id: allDisks
        diskDevice: "all"
        volumeLabel: "home"
    }

    // A volume with no name, and no disk size yet.
    FakeMonitor {
        id: unnamedVolume
        volumeLabel: ""
        diskSize: NaN
    }

    // Measures a Text's ink, which a Text doesn't report.
    TextMetrics {
        id: probe
    }

    // What a Text that elides draws of its text.
    TextMetrics {
        id: elideProbe
    }

    Component {
        id: plain
        FakeMonitor {}
    }

    Component {
        id: host
        Loader {}
    }

    // A widget just started at an hour or a day: its first buckets are
    // still open, so those spans have nothing to draw yet.
    Component {
        id: freshStart
        FakeMonitor {
            id: fresh
            cpuHistory: graphSpan === "minute" ? [20, 21] : []
            cpuHighs: []
            cpuTemperatureHistory: graphSpan === "minute" ? [60, 61] : []
            cpuTemperatureHighs: []
            cpuTemperatureExtent: [60, 61]
            gpuOuter.temperatureHistory: fresh.graphSpan === "minute" ? [48, 49] : []
            gpuOuter.temperatureHighs: []
            gpuOuter.temperatureExtent: [48, 49]
            diskTemperatureHistory: graphSpan === "minute" ? [39, 40] : []
            diskTemperatureHighs: []
            diskTemperatureExtent: [39, 40]
        }
    }

    // As main.qml hosts a popup's page: Escape there closes the popup.
    Component {
        id: escapeHost
        Loader {
            property int escapes: 0
            focus: true
            Keys.onEscapePressed: ++escapes
        }
    }

    Component {
        id: mirroredHost
        Loader {
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true
        }
    }

    TestCase {
        name: "Popups"
        when: windowShown

        // A page wide enough for every peak in full: the test's fallback
        // font runs about half as wide again as Breeze's, and a peak with
        // too little room goes (test_rateCaptionsKeepTheirLabel).
        readonly property real widePage: Kirigami.Units.gridUnit * 30
        // Where the content starts and ends, in from either side of the page.
        readonly property real contentEdge: Math.round(Kirigami.Units.largeSpacing * 2)
        // The monitors the last test made for itself.
        property var monitors: []

        function init() {
            monitors.forEach(m => m.destroy());
            monitors = [];
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop|polish loop/);
        }

        function cleanup() {
            root.longStrings = false;
        }

        function cleanupTestCase() {
            monitors.forEach(m => m.destroy());
        }

        // A monitor of the test's own, made from `component` or a plain
        // FakeMonitor, with `values` set on it ("gpuOuter.usage" sets a
        // GPU's), so nothing a test sets reaches another. It outlives the
        // test's popups, which read it until they go, and goes before the
        // next test starts.
        function monitorWith(values, component) {
            const monitor = (component ?? plain).createObject(root);
            monitors.push(monitor);
            for (const [key, value] of Object.entries(values)) {
                const path = key.split(".");
                const name = path.pop();
                path.reduce((o, p) => o[p], monitor)[name] = value;
            }
            return monitor;
        }

        // The CPU's temperature turns red over the hot threshold, as the
        // GPUs' and the drive's do.
        function test_cpuTemperatureTakesTheLevelColours_data() {
            return [{ tag: "61", monitor: normal, celsius: 61, hot: false }, { tag: "92", monitor: hot, celsius: 92, hot: true }];
        }

        function test_cpuTemperatureTakesTheLevelColours(data) {
            const headline = readings(headerOf(load("CpuPopup", data.monitor))).find(r => r.visible && r.degreeUnit !== "");
            compare(headline.value, Format.temperature(data.celsius, false));
            compare(String(parts(headline).number.color),
                    String(data.hot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor), "the digits as drawn");
        }

        // More threads than one row of bars 2 px wide holds take a second
        // row, as long as the first.
        function test_threadBarsTakeASecondRow_data() {
            return [{ tag: "16 threads", monitor: normal, rows: [16] }, { tag: "128 threads", monitor: manyThreads, rows: [64, 64] }];
        }

        function test_threadBarsTakeASecondRow(data) {
            const popup = load("CpuPopup", data.monitor);
            const bars = all(popup, i => i.Accessible.role === Accessible.ProgressBar && i.modelData !== undefined);
            compare(bars.length, data.monitor.cpuThreads);
            const top = b => b.mapToItem(popup, Qt.point(0, 0)).y;
            const rows = Array.from(new Set(bars.map(top))).sort((a, b) => a - b);
            compare(rows.map(y => bars.filter(b => top(b) === y).length), data.rows);
        }

        // Without pressure stall information the Swap tile takes the
        // Pressure tile's place as well, and without swap it reads a dim
        // "none" with no unit.
        function test_memoryWithoutPressureOrSwap() {
            const tile = (popup, caption) => all(popup, i => i.visible && i.graphTop !== undefined && i.caption === caption)[0];
            const full = load("MemoryPopup", normal);
            verify(tile(full, "Pressure"));
            verify(tile(full, "Swap").width < tile(full, "Used").width, "the Swap tile beside the Pressure tile");
            const popup = load("MemoryPopup", bare);
            verify(!tile(popup, "Pressure"), "no Pressure tile");
            const swap = tile(popup, "Swap");
            compare(swap.width, tile(popup, "Used").width, "the Swap tile across the row");
            const reading = readings(swap)[0];
            compare(reading.value, "none");
            compare(reading.unit, "");
            compare(String(parts(reading).number.color), String(Style.dim(Kirigami.Theme.textColor)));
        }

        // A page as wide as the popup makes it, or the given width.
        function load(popup, monitor, mirrored, width) {
            const loader = createTemporaryObject(mirrored ? mirroredHost : host, root, width ? { width: width } : {});
            loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/" + popup + ".qml"), { monitor: monitor });
            waitForRendering(loader.item);
            return loader.item;
        }

        // A C-locale expectation in the digits and decimal mark Format uses
        // for the test's locale: "8.4" is "8,4" under German.
        function localized(text) {
            return text.replace(/\d+(?:\.(\d+))?/g, (m, decimals) => Format.fixed(Number(m), decimals ? decimals.length : 0));
        }

        // A sleeping GPU is one dim line, not a section: under the awake
        // GPU's, or where a header would start when no GPU is awake.
        function test_aSleepingGpuIsOneLine_data() {
            return [{ tag: "underAnAwakeGpu", monitor: asleep }, { tag: "theOnlyGpu", monitor: onlyAsleep }];
        }

        function test_aSleepingGpuIsOneLine(data) {
            const popup = load("GpuPopup", data.monitor);
            const found = texts(popup);
            verify(found.includes("AMD Radeon RX 7700S · off"), JSON.stringify(found));
            verify(!found.some(t => t.indexOf("Powered down") >= 0), JSON.stringify(found));
            const line = shownText(popup, "AMD Radeon RX 7700S · off");
            compare(String(line.color), String(Style.dim(Kirigami.Theme.textColor)));
            const top = i => i.mapToItem(popup, Qt.point(0, 0)).y;
            compare(line.mapToItem(popup, Qt.point(0, 0)).x, contentEdge);
            compare(line.width, popup.width - 2 * contentEdge);
            const headers = all(popup, i => i.visible && i.partsShown !== undefined);
            const tiles = all(popup, i => i.visible && i.graphTop !== undefined);
            if (data.monitor === onlyAsleep) {
                compare(headers.length, 0);
                compare(tiles.length, 0);
                compare(top(line), top(headerOf(load("CpuPopup", normal))), "where a header would start");
            } else {
                compare(headers.length, 1);
                verify(tiles.length > 0 && tiles.every(t => top(t) + t.height < top(line)), "under the awake GPU's section");
            }
        }

        function gauges(item) {
            const found = [];
            const collect = i => {
                if (i.outerTone !== undefined) {
                    found.push(i);
                }
                i.children.forEach(collect);
            };
            collect(item);
            return found;
        }

        // The outer of a gauge's two arcs, the one a popup's ring draws.
        function outerArc(gauge) {
            const arcs = [];
            const pending = [gauge];
            while (pending.length > 0) {
                const item = pending.shift();
                if (item.playReset !== undefined && item.animating !== undefined) {
                    arcs.push(item);
                }
                pending.push(...Array.from(item.children));
            }
            compare(arcs.length, 2);
            return arcs[0].radius > arcs[1].radius ? arcs[0] : arcs[1];
        }

        // The header rings, one per GPU in the GPU popup, take the level
        // colours at 75 % and 90 % of their own reading, in the arc they draw.
        function test_popupRingsTakeTheLevelColours_data() {
            return [{ tag: "74", value: 74, tone: "text" }, { tag: "75", value: 75, tone: "neutral" },
                    { tag: "89", value: 89, tone: "neutral" }, { tag: "90", value: 90, tone: "negative" }];
        }

        function test_popupRingsTakeTheLevelColours(data) {
            const expected = data.tone === "negative" ? Kirigami.Theme.negativeTextColor
                           : data.tone === "neutral" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
            const monitor = monitorWith({ cpuUsage: data.value, "gpuOuter.usage": data.value });
            const cpu = gauges(load("CpuPopup", monitor));
            verify(cpu.length > 0);
            compare(cpu[0].outerTone, expected);
            compare(outerArc(cpu[0]).color, expected, "the header ring as drawn");
            const gpu = gauges(load("GpuPopup", monitor)).filter(g => g.value === data.value);
            verify(gpu.length > 0, "the discrete GPU's ring");
            gpu.forEach(g => {
                compare(g.outerTone, expected);
                compare(outerArc(g).color, expected, "the discrete GPU's ring as drawn");
            });
        }

        // The Text in the middle of a gauge that draws its percentage.
        function centreText(gauge) {
            const pending = [gauge];
            while (pending.length > 0) {
                const item = pending.shift();
                if (item !== gauge && item.text === gauge.text && item.font !== undefined) {
                    return item;
                }
                pending.push(...Array.from(item.children));
            }
            return null;
        }

        // Every name a panel ring might draw inside a gauge, in text or as a
        // RingName.
        function names(gauge) {
            const found = [];
            const pending = [gauge];
            while (pending.length > 0) {
                const item = pending.shift();
                if (item.room !== undefined && item.item !== undefined) {
                    found.push("RingName " + item.item);
                }
                if (["CPU", "GPU", "MEM"].includes(item.text) && item.visible) {
                    found.push(item.text);
                }
                pending.push(...Array.from(item.children));
            }
            return found;
        }

        // Panel rings lost their percentage to a name; the popups' larger
        // rings keep it, with their own strokes, and name nothing inside.
        function test_popupRingsKeepTheirPercentage() {
            const cpu = gauges(load("CpuPopup", normal));
            compare(cpu.length, 1, "the header ring");
            compare(cpu[0].text, localized("23%"));
            compare(cpu[0].strokeWidth, 4);
            const cpuText = centreText(cpu[0]);
            verify(cpuText, "the header ring's centre text");
            verify(cpuText.visible, "the header ring shows its percentage");
            compare(cpuText.text, localized("23%"));
            compare(names(cpu[0]), []);
            // At 52 px the panel's default stroke is also 4; a larger ring
            // tells an explicit stroke from the default.
            cpu[0].Layout.preferredWidth = 80;
            tryCompare(cpu[0], "width", 80);
            compare(cpu[0].strokeWidth, 4, "the header ring's stroke at any size");

            // Each GPU's header has the same ring.
            const gpu = gauges(load("GpuPopup", normal)).filter(g => g.visible);
            compare(gpu.map(g => g.value), [3, 12], "a ring per GPU, the integrated one first");
            gpu.forEach(g => {
                const tag = "the ring at " + g.value + "%";
                compare(g.text, localized(g.value + "%"), tag);
                compare(g.strokeWidth, 4, tag);
                const text = centreText(g);
                verify(text, tag);
                verify(text.visible, tag + " shows its percentage");
                compare(names(g), [], tag);
                g.Layout.preferredWidth = 80;
                tryCompare(g, "width", 80);
                compare(g.strokeWidth, 4, tag + " keeps its stroke at any size");
            });
        }

        function readings(item) {
            return all(item, i => i.unitSpacing !== undefined && i.accessibleIgnored !== undefined);
        }

        // A reading's number and unit, the Texts it draws.
        function parts(reading) {
            const texts = reading.children.filter(c => typeof c.text === "string");
            compare(texts.length, 2);
            return { number: texts[0], suffix: texts[1] };
        }

        TextMetrics {
            id: glyph
        }

        // The room a Text's last character leaves after its ink.
        function trailingRoom(text) {
            glyph.font = text.font;
            glyph.text = text.text.slice(-1);
            return glyph.advanceWidth - glyph.tightBoundingRect.x - glyph.tightBoundingRect.width;
        }

        // Where a Text's ink starts, down from its reading's top.
        function inkTop(text) {
            glyph.font = text.font;
            glyph.text = text.text;
            return text.y + text.baselineOffset + glyph.tightBoundingRect.y;
        }

        // The temperature unit is as small as the caption under it and sits
        // a little apart from the digits, its top level with theirs, in the
        // CPU and GPU headers alike. At one size it is as far from the ink
        // after a tabular "1" (61, 41) as after any other digit (60, 48).
        function test_temperatureUnitSizeAndGap_data() {
            return [{ tag: "celsius", fahrenheit: false, unit: "°C" }, { tag: "fahrenheit", fahrenheit: true, unit: "°F" }];
        }

        function test_temperatureUnitSizeAndGap(data) {
            const inkGaps = { CpuPopup: [], GpuPopup: [], DiskPopup: [] };
            for (const [popup, celsius] of [["CpuPopup", 61], ["CpuPopup", 60], ["GpuPopup", 61], ["DiskPopup", 61]]) {
                const monitor = monitorWith({ fahrenheit: data.fahrenheit, cpuTemperature: celsius, diskTemperature: celsius });
                const temperatures = readings(load(popup, monitor)).filter(r => r.visible && r.degreeUnit !== "");
                verify(temperatures.length > 0, popup);
                temperatures.forEach(r => {
                    const p = parts(r);
                    const tag = popup + " " + p.number.text;
                    compare(p.suffix.text, data.unit, tag);
                    verify(p.suffix.visible, tag);
                    compare(p.suffix.font.pointSize, Kirigami.Theme.smallFont.pointSize, tag);
                    const gap = p.suffix.x - (p.number.x + p.number.implicitWidth);
                    const inkGap = gap + trailingRoom(p.number);
                    verify(r.unitSpacing >= 2, tag + " has a gap of " + r.unitSpacing);
                    verify(inkGap >= r.unitSpacing && inkGap <= r.unitSpacing + 3, tag + " is " + inkGap + " from the ink");
                    inkGaps[popup].push(inkGap);
                    compare(r.implicitWidth, p.number.implicitWidth + r.unitSpacing + p.suffix.implicitWidth, tag);
                    fuzzyCompare(inkTop(p.suffix), inkTop(p.number), 0.5, tag + " level with the digits' top");
                });
            }
            for (const gaps of [inkGaps.CpuPopup, inkGaps.GpuPopup]) {
                compare(gaps.length, 2);
                fuzzyCompare(gaps[1], gaps[0], 0.5);
            }
            compare(inkGaps.DiskPopup.length, 1);
            fuzzyCompare(inkGaps.DiskPopup[0], inkGaps.CpuPopup[0], 0.5, "the disk's as the CPU's");
        }

        // Only the degree sign moves toward a narrow last digit: the digits,
        // the reading's width and the caption under it hold still as the
        // temperature changes, in the CPU header and in a GPU's.
        function test_temperatureDigitsHoldStill() {
            const where = (r, popup) => parts(r).number.mapToItem(popup, Qt.point(0, 0)).x;
            const cpu = [];
            const gpu = [];
            for (const t of [59, 60, 61, 62, 71]) {
                const monitor = monitorWith({ cpuTemperature: t, "gpuOuter.temperature": t });
                const popup = load("CpuPopup", monitor);
                const header = headerOf(popup);
                const headline = readings(header).find(r => r.visible && r.degreeUnit !== "");
                const caption = shownText(header, header.caption);
                verify(headline && caption);
                cpu.push([where(headline, popup), headline.implicitWidth, caption.mapToItem(popup, Qt.point(0, 0)).x].join(" "));
                const gpuPopup = load("GpuPopup", monitor);
                const gpuHeader = all(gpuPopup, i => i.partsShown !== undefined && i.title === monitor.gpuOuter.name)[0];
                const gpuHeadline = readings(gpuHeader).find(r => r.visible && r.degreeUnit !== "");
                const gpuCaption = shownText(gpuHeader, gpuHeader.caption);
                verify(gpuHeadline && gpuCaption, "the GPU header at " + t);
                compare(gpuHeadline.value, Format.temperature(t, false));
                gpu.push([where(gpuHeadline, gpuPopup), gpuHeadline.implicitWidth,
                          gpuCaption.mapToItem(gpuPopup, Qt.point(0, 0)).x].join(" "));
            }
            compare(cpu.filter(s => s !== cpu[0]), [], "the header at 59, 60, 61, 62, 71: " + cpu.join(", "));
            compare(gpu.filter(s => s !== gpu[0]), [], "the GPU header at 59, 60, 61, 62, 71: " + gpu.join(", "));
        }

        // A missing temperature is a bare dash.
        function test_missingTemperatureHasNoUnit() {
            const header = readings(load("CpuPopup", cpuUnheated)).filter(r => r.degreeUnit !== "");
            compare(header.length, 1);
            compare(parts(header[0]).number.text, "–");
            verify(!parts(header[0]).suffix.visible);
            compare(header[0].implicitWidth, parts(header[0]).number.implicitWidth);
        }

        // The header's caption lines up with the reading's digits, the unit
        // hanging past them. Under RTL the reading stays left to right, so
        // the caption starts where the digits do.
        function test_headerCaptionUnderTheDigits_data() {
            return [{ tag: "plain", mirrored: false }, { tag: "mirrored", mirrored: true }];
        }

        function test_headerCaptionUnderTheDigits(data) {
            const popup = load("CpuPopup", otherSensors, data.mirrored);
            const headline = readings(popup).find(r => r.visible && r.degreeUnit !== "" && r.parent.parent.partsShown !== undefined);
            verify(headline);
            const caption = Array.from(headline.parent.children).find(i => i.visible && typeof i.text === "string" && i.text !== "");
            verify(caption);
            const digits = headline.mapToItem(popup, Qt.point(0, 0)).x;
            const left = caption.mapToItem(popup, Qt.point(0, 0)).x;
            if (data.mirrored) {
                fuzzyCompare(left, digits, 1);
            } else {
                fuzzyCompare(left + caption.width, digits + headline.numberWidth, 1);
            }
        }

        // Popup numbers are set in the theme's face with figures of one
        // width; only process names keep the monospace face.
        function test_numbersInSans_data() {
            return [{ tag: "cpu", popup: "CpuPopup" }, { tag: "gpu", popup: "GpuPopup" },
                    { tag: "memory", popup: "MemoryPopup" }, { tag: "network", popup: "NetworkPopup" },
                    { tag: "disk", popup: "DiskPopup" }];
        }

        function test_numbersInSans(data) {
            const popup = load(data.popup, normal);
            const found = readings(popup);
            verify(found.length > 0);
            found.forEach(r => {
                const p = parts(r);
                for (const t of [p.number, p.suffix]) {
                    compare(t.font.family, Kirigami.Theme.defaultFont.family, r.value + " " + t.text);
                    compare(t.font.features.tnum, 1, r.value + " " + t.text);
                }
            });
            // Bare numbers outside readings too: the network rates, the
            // load averages. The header ring's centre is the panel ring's.
            // In the locale's own digits and decimal mark.
            const digits = Array.from({ length: 10 }, (_, n) => Format.whole(n));
            const ascii = t => Array.from(t).map(c => digits.indexOf(c) >= 0 ? String(digits.indexOf(c))
                                                    : c === Qt.locale().decimalPoint ? "." : c).join("");
            const numbers = all(popup, i => i.visible && typeof i.text === "string" && /^[0-9.,–]+%?$/.test(ascii(i.text)) && i.font !== undefined
                                                 && !ancestor(i, a => a.outerTone !== undefined));
            verify(numbers.length > 0);
            numbers.forEach(t => {
                compare(t.font.family, Kirigami.Theme.defaultFont.family, t.text);
                compare(t.font.features.tnum, 1, t.text);
            });
        }

        // The load averages read 1, 5, 15 minutes in the layout's direction,
        // the first large and the others dim, evenly spaced, with no dot that
        // reads as an Arabic zero.
        function test_loadAverageOrder_data() {
            return [{ tag: "plain", mirrored: false }, { tag: "mirrored", mirrored: true }];
        }

        function test_loadAverageOrder(data) {
            const popup = load("CpuPopup", normal, data.mirrored);
            const tile = all(popup, i => i.caption === "Load average")[0];
            verify(tile);
            verify(!texts(tile).some(t => t.indexOf("·") >= 0), JSON.stringify(texts(tile)));
            const first = readings(tile);
            compare(first.length, 1);
            compare(first[0].unit, "");
            const rest = all(tile, i => i.modelData !== undefined && i.modelData.sensorId !== undefined);
            compare(rest.map(t => t.modelData.sensorId), ["cpu/loadaverages/loadaverage5", "cpu/loadaverages/loadaverage15"]);
            // The row speaks for all three, spans included. The sensors are
            // live where ksystemstats runs, so only the form is fixed.
            const row = first[0].parent;
            verify(/^\S+ over 1 minute, \S+ over 5 minutes, \S+ over 15 minutes$/.test(row.Accessible.name), row.Accessible.name);
            // A missing average is a word, never the dash on screen.
            compare(popup.loadAverageName(NaN, 0.5, NaN),
                    "unavailable over 1 minute, " + Format.load(0.5) + " over 5 minutes, unavailable over 15 minutes");
            verify(first[0].accessibleIgnored);
            verify(parts(first[0]).number.Accessible.ignored && parts(first[0]).suffix.Accessible.ignored, "not spoken on its own");
            rest.forEach(t => {
                verify(t.Accessible.ignored);
                compare(t.font.pointSize, Style.unitPointSize(first[0].pointSize, Kirigami.Theme.smallFont.pointSize));
                compare(String(t.color), String(Style.dim(Kirigami.Theme.textColor)));
                compare(t.y + t.baselineOffset, first[0].y + first[0].baselineOffset, "on the reading's baseline");
            });
            const x = i => i.mapToItem(tile, Qt.point(0, 0)).x;
            const order = [first[0], rest[0], rest[1]];
            if (data.mirrored) {
                order.reverse();
            }
            verify(x(order[0]) < x(order[1]) && x(order[1]) < x(order[2]), order.map(x).join(", "));
            const gaps = [x(order[1]) - x(order[0]) - order[0].width, x(order[2]) - x(order[1]) - order[1].width];
            compare(gaps[0], gaps[1], "evenly spaced");
            verify(gaps[0] > 0);
        }

        // Process values are readings: a dim, smaller unit, the percent sign
        // against its number, and the values lined up at the row's end. A
        // screen reader hears each row whole, its name and value together.
        function test_processValuesAreReadings_data() {
            return [{ tag: "cpu", popup: "CpuPopup", units: ["%", "%", "%"], values: ["8.4", "3.1", "2.6"].map(localized),
                      spoken: ["firefox, 8.4%", "plasmashell, 3.1%", "kwin_wayland, 2.6%"].map(localized) },
                    { tag: "memory", popup: "MemoryPopup", units: ["GiB", "MiB", "MiB"], values: ["3.9", "620", "410"].map(localized),
                      spoken: ["firefox, 3.9 GiB", "plasmashell, 620 MiB", "kwin_wayland, 410 MiB"].map(localized) }];
        }

        function test_processValuesAreReadings(data) {
            for (const mirrored of [false, true]) {
                const popup = load(data.popup, normal, mirrored);
                const list = all(popup, i => i.key !== undefined && i.threads !== undefined && i.rows !== undefined)[0];
                verify(list);
                const values = readings(list);
                compare(values.map(r => r.value), data.values);
                compare(values.map(r => r.unit), data.units);
                const edge = r => r.mapToItem(list, Qt.point(0, 0)).x + (mirrored ? 0 : r.width);
                values.forEach(r => {
                    const p = parts(r);
                    compare(p.suffix.font.pointSize, Style.unitPointSize(r.pointSize, Kirigami.Theme.smallFont.pointSize), r.value);
                    compare(String(p.suffix.color), String(Style.dim(Kirigami.Theme.textColor)), "a dim unit");
                    if (r.unit === "%") {
                        compare(p.suffix.x, p.number.implicitWidth, "the percent sign against its number");
                    }
                    compare(edge(r), edge(values[0]), "lined up");
                });
                compare(values.map(r => r.parent.Accessible.name), data.spoken);
                values.forEach(r => {
                    compare(r.parent.Accessible.role, Accessible.StaticText);
                    verify(r.accessibleIgnored, "the value isn't spoken apart from its row");
                    verify(r.parent.children.every(c => c === r || c.Accessible.ignored), "nor is the name");
                });
            }
        }

        // The nearest of `item` and its ancestors that `test` accepts.
        function ancestor(item, test) {
            for (let i = item; i; i = i.parent) {
                if (test(i)) {
                    return i;
                }
            }
            return null;
        }

        function graphs(item) {
            return all(item, i => i.ceiling !== undefined && i.drawn !== undefined);
        }

        function ruleOf(graph) {
            return graph.children.filter(c => c.lineColor !== undefined && c.limitY !== undefined)[0];
        }

        // A graph tile's caption line: its caption, and what the graph's top
        // stands for at its far end.
        function tileCaption(graph) {
            const tile = ancestor(graph, i => i.graphTop !== undefined);
            return all(tile, i => i.label !== undefined && i.detail !== undefined)[0];
        }

        function tileTop(graph) {
            const tile = ancestor(graph, i => i.graphTop !== undefined);
            return all(tile, i => i.label !== undefined && i.detail !== undefined)[1];
        }

        // The span on a graph tile's caption line (SpanButton).
        function spanOf(item) {
            const tile = item.graphTop !== undefined ? item : ancestor(item, i => i.graphTop !== undefined);
            return all(tile, i => i.objectName === "span")[0];
        }

        // A graph tile's caption as it reads, its span included:
        // "USAGE · 1 min".
        function heading(item) {
            const tile = item.graphTop !== undefined ? item : ancestor(item, i => i.graphTop !== undefined);
            const caption = all(tile, i => i.label !== undefined && i.detail !== undefined)[0];
            const span = spanOf(tile);
            return caption.text + (span && span.visible ? " · " + span.text : "");
        }

        // Where `item` draws across `tile`, from its left to its right: a
        // Text that doesn't elide can run past its own width.
        function box(tile, item) {
            const left = item.mapToItem(tile, Qt.point(0, 0)).x;
            const elides = item.elide !== undefined && item.elide !== Text.ElideNone;
            return [left, left + (elides ? item.width : Math.max(item.width, item.contentWidth ?? 0))];
        }

        // A caption line keeps its span whole, inside the tile and clear of
        // the caption before it and the top after it, and its label whole
        // wherever the label and the span fit the line together.
        function checkSpanLine(tile, caption, top, mirrored) {
            const span = spanOf(tile);
            verify(span && span.visible, tile.caption + " has its span");
            const [left, right] = box(tile, span);
            verify(span.width >= span.implicitWidth - 0.5, "the span whole");
            verify(left >= tile.horizontalPadding - 0.5 && right <= tile.width - tile.horizontalPadding + 0.5,
                   span.text + " at " + left + " to " + right + " in a tile " + tile.width + " wide");
            const order = mirrored ? [span, caption] : [caption, span];
            verify(box(tile, order[0])[1] <= box(tile, order[1])[0] + 0.5, caption.text + " before " + span.text);
            if (top.visible) {
                const after = mirrored ? [box(tile, top), box(tile, span)] : [box(tile, span), box(tile, top)];
                verify(after[0][1] <= after[1][0], span.text + " clear of " + top.text);
            }
            const label = caption.label.toLocaleUpperCase();
            elideProbe.font = caption.font;
            elideProbe.text = label;
            const room = caption.parent.width - caption.parent.spanWidth;
            if (elideProbe.advanceWidth <= room) {
                elideProbe.text = caption.text;
                elideProbe.elide = caption.elide;
                elideProbe.elideWidth = caption.width;
                verify(elideProbe.elidedText === caption.text, "the label whole: " + elideProbe.elidedText);
            }
        }

        // A whole caption line inside its tile: the caption and the top at
        // its end inside and apart, the top whole or not shown at all, never
        // as a stub or a bare ellipsis, and the span as checkSpanLine has it.
        function checkCaptionLine(tile, caption, top, mirrored) {
            for (const t of [caption, top].filter(t => t.visible)) {
                const [left, right] = box(tile, t);
                verify(left >= tile.horizontalPadding - 0.5 && right <= tile.width - tile.horizontalPadding + 0.5,
                       t.text + " at " + left + " to " + right + " in a tile " + tile.width + " wide");
            }
            verify(!top.visible || !top.truncated && top.width >= Math.ceil(top.implicitWidth),
                   top.text + " whole: " + top.width + " for " + top.implicitWidth);
            if (top.visible) {
                const [a, b] = mirrored ? [box(tile, top), box(tile, caption)] : [box(tile, caption), box(tile, top)];
                verify(a[1] <= b[0], caption.text + " clear of " + top.text + ": " + a + " " + b);
            }
            checkSpanLine(tile, caption, top, mirrored);
        }

        // A percentage graph has its 100 % rule, and a rate graph, which has
        // no natural top, rises to its peak where that rule would be. The
        // caption line names the top at its end, "100%" or the peak.
        function test_graphsHaveARuleOrAPeak_data() {
            return [{ tag: "cpu", popup: "CpuPopup", ceilings: 1, peaks: 0 },
                    { tag: "gpu", popup: "GpuPopup", ceilings: 2, peaks: 0 },
                    { tag: "memory", popup: "MemoryPopup", ceilings: 1, peaks: 0 },
                    { tag: "network", popup: "NetworkPopup", ceilings: 0, peaks: 1 },
                    { tag: "disk", popup: "DiskPopup", ceilings: 0, peaks: 2 }];
        }

        function test_graphsHaveARuleOrAPeak(data) {
            const found = graphs(load(data.popup, normal, false, widePage)).filter(g => g.visible);
            compare(found.filter(g => g.ceiling).length, data.ceilings);
            compare(found.filter(g => !g.ceiling).length, data.peaks);
            found.forEach(g => {
                const rule = ruleOf(g);
                verify(rule, "a LimitRule");
                compare(g.topY, rule.limitY, "the top is where the rule goes");
                const caption = tileCaption(g);
                verify(caption.text.indexOf("peak") < 0 && caption.text.indexOf("%") < 0, caption.text);
                const top = tileTop(g);
                verify(top.visible);
                if (g.ceiling) {
                    verify(rule.visible);
                    compare(top.text, localized("100%"));
                } else {
                    verify(!rule.visible);
                    const peak = g.drawn.main.concat(g.drawn.second).reduce((m, p) => Math.min(m, p.y), Infinity);
                    fuzzyCompare(peak, g.topY, 0.001, "the peak lands where 100 % would");
                    verify(/^peak \S+ \S+$/.test(top.text), top.text);
                }
            });
        }

        // "100%" names each percentage graph's top, and a temperature graph
        // names its peak, at the far end of its tile's caption line, level
        // with the caption and over the end of the rule. Mirrored, the
        // caption line reads from the right and the top ends it at the left.
        function test_scaleOnTheCaptionLine_data() {
            const rows = [];
            for (const popup of ["CpuPopup", "GpuPopup", "MemoryPopup"]) {
                rows.push({ tag: popup, popup: popup, mirrored: false });
                rows.push({ tag: popup + " mirrored", popup: popup, mirrored: true });
            }
            return rows;
        }

        function test_scaleOnTheCaptionLine(data) {
            const popup = load(data.popup, normal, data.mirrored);
            const left = i => i.mapToItem(popup, Qt.point(0, 0)).x;
            const top = i => i.mapToItem(popup, Qt.point(0, 0)).y;
            const rules = all(popup, i => i.visible && i.lineColor !== undefined && i.limitY !== undefined);
            verify(rules.length > 0, "a percentage graph");
            for (const rule of rules) {
                const g = rule.parent;
                const [caption, scale] = captionLine(ancestor(g, i => i.graphTop !== undefined));
                if (g.plot !== undefined) {
                    verify(scale.text.startsWith(localized("peak ")), scale.text);
                } else {
                    compare(scale.text, localized("100%"));
                }
                verify(scale.visible && !scale.truncated);
                verify(top(scale) + scale.height <= top(g), "on the caption line, over the graph");
                verify(caption.visible && caption.text !== "");
                fuzzyCompare(top(scale) + scale.baselineOffset, top(caption) + caption.baselineOffset, 0.5);
                // The text's box at the graph's far end; its ink is right-aligned in it.
                if (data.mirrored) {
                    compare(left(scale), left(g));
                    verify(left(caption) >= left(scale) + scale.width, "the caption after it");
                } else {
                    compare(left(scale) + scale.width, left(g) + g.width);
                    verify(left(caption) + caption.width <= left(scale), "the caption before it");
                }
                compare(left(rule), left(g));
                compare(rule.width, g.width, "the rule spans the graph, under the scale's end");
            }
        }

        // The rate tiles name their peak on the caption line and nowhere
        // else; before the first sample they say nothing. Throughput's peak
        // is in the header's unit, bits or bytes; a disk's always in bytes.
        function test_ratePeaksInTheCaption_data() {
            return [{ tag: "bits", bits: true }, { tag: "bytes", bits: false }];
        }

        function test_ratePeaksInTheCaption(data) {
            const peak = (samples, bits) => {
                const r = Format.rate(Math.max(...samples), bits);
                return "peak " + r.value + " " + r.unit;
            };
            const seconds = "THROUGHPUT · 1 min";
            const monitor = monitorWith({ networkBits: data.bits });
            const before = monitorWith({ networkBits: data.bits }, unsampled);
            for (const [popupName, captions, expected] of [
                    ["NetworkPopup", [seconds], [peak(monitor.networkDownHistory.concat(monitor.networkUpHistory), data.bits)]],
                    ["DiskPopup", ["READ · 1 min", "WRITE · 1 min"], [peak(monitor.diskReadHistory, false), peak(monitor.diskWriteHistory, false)]]]) {
                const popup = load(popupName, monitor, false, widePage);
                compare(graphs(popup).map(heading), captions, popupName);
                const tops = graphs(popup).map(tileTop);
                compare(tops.map(c => c.text), expected, popupName);
                verify(tops.every(c => c.visible), popupName);
                verify(!texts(popup).some(t => t.indexOf("Peak") >= 0), JSON.stringify(texts(popup)));

                const empty = graphs(load(popupName, before));
                compare(empty.map(heading), captions, popupName + " before a sample");
                verify(empty.map(tileTop).every(c => !c.visible && c.text === ""), popupName + " before a sample");
            }
        }

        // Throughput tops out at the higher of its two series, and its
        // caption names that peak, the upload's when it is the higher.
        function test_throughputPeakCoversUpload() {
            const up = Math.max(...uploading.networkUpHistory);
            verify(up > Math.max(...uploading.networkDownHistory), "the upload peaks higher");
            const g = graphs(load("NetworkPopup", uploading))[0];
            compare(g.maximum, up);
            const top = g.drawn.second.reduce((m, p) => Math.min(m, p.y), Infinity);
            fuzzyCompare(top, g.topY, 0.001, "the upload's peak lands at the top");
            verify(g.drawn.main.every(p => p.y > top), "the download stays under it");
            const r = Format.rate(up, uploading.networkBits);
            compare(tileTop(g).text, "peak " + r.value + " " + r.unit);
        }

        function test_rateCaptionsKeepTheirLabel_data() {
            const rows = [];
            // A 360 px page at gridUnit 18, as at 1.25 with Breeze, and the
            // 280 px of gridUnit 14, here in the larger font. Every rate
            // tile spans the page, and at its own width can have room for
            // everything; on the narrow page throughput, the longest
            // caption, always cuts something, where read and write may fit
            // in a smaller font.
            const widths = [Kirigami.Units.gridUnit * 20, Math.round(Kirigami.Units.gridUnit * 20 * 14 / 18)];
            for (const [tag, popup, count] of [["network", "NetworkPopup", 1], ["disk", "DiskPopup", 2]]) {
                for (const width of widths) {
                    const squeezed = popup === "NetworkPopup" && width === widths[1];
                    rows.push({ tag: tag + " " + width + " px", popup: popup, count: count, width: width, squeezed: squeezed,
                                mirrored: false });
                    rows.push({ tag: tag + " " + width + " px mirrored", popup: popup, count: count, width: width, squeezed: squeezed,
                                mirrored: true });
                }
            }
            return rows;
        }

        // A third longer in every string, the rate tiles' caption lines stay
        // inside their tiles at the page widths a popup takes, the peak
        // apart from the caption: where they don't fit, the caption's span
        // is cut short and then the peak goes, never the caption's label.
        // The peak shows whole or not at all, never as a stub or a bare
        // ellipsis.
        function test_rateCaptionsKeepTheirLabel(data) {
            root.longStrings = true;
            const popup = load(data.popup, normal, data.mirrored, data.width);
            compare(popup.width, data.width);
            const captions = graphs(popup).map(tileCaption);
            const tops = graphs(popup).map(tileTop);
            compare(captions.length, data.count);
            if (data.squeezed) {
                verify(captions.some(c => c.truncated) || tops.some(t => !t.visible),
                       "something is cut short: " + captions.concat(tops).map(c => c.text).join(", "));
            }
            captions.forEach((c, i) => checkCaptionLine(ancestor(c, a => a.graphTop !== undefined), c, tops[i], data.mirrored));
        }

        // A rate graph scales to its floor while the rates stay under it,
        // 1 Mb/s for throughput and 1 MiB/s for a disk, so an idle link or
        // disk draws its noise low rather than at full height.
        function test_rateGraphFloors() {
            const found = graphs(load("NetworkPopup", idle)).concat(graphs(load("DiskPopup", idle)));
            compare(found.map(g => g.maximum), [125000, 1048576, 1048576]);
            found.forEach(g => {
                const top = g.drawn.main.concat(g.drawn.second).reduce((m, p) => Math.min(m, p.y), Infinity);
                verify(top > g.topY + (g.height - g.topY) / 2, "the line keeps low: " + top + " of " + g.height);
            });
        }

        // The memory legend spans its bar with even gaps: Used at the bar's
        // start, Free flush with its end, plain and mirrored. The test's
        // fallback font is wide enough to wrap Free at the popup's own width,
        // so the popup is widened until the entries fit.
        function test_memoryLegendSpread_data() {
            return [{ tag: "plain", mirrored: false }, { tag: "mirrored", mirrored: true }];
        }

        function test_memoryLegendSpread(data) {
            const popup = load("MemoryPopup", normal, data.mirrored);
            const bar = all(popup, i => i.usedColor !== undefined)[0];
            const entries = all(popup, i => i.swatch !== undefined && i.text !== undefined);
            compare(entries.length, 3);
            popup.width = popup.implicitWidth + Kirigami.Units.gridUnit * 6;
            waitForRendering(popup);
            tryVerify(() => entries[0].y === entries[2].y, 1000, "one line");
            // The bar's own mapping would include its mirroring flip.
            const left = i => i.parent.mapToItem(popup, Qt.point(i.x, 0)).x;
            const right = i => left(i) + i.width;
            // In reading order, each entry's far edge to the next one's near edge.
            const [start, end] = data.mirrored ? [right, left] : [left, right];
            const gap = (a, b) => Math.abs(start(b) - end(a));
            compare(start(entries[0]), start(bar));
            verify(Math.abs(end(entries[2]) - end(bar)) <= 1, "Free ends at the bar's end: " + end(entries[2]) + " " + end(bar));
            compare(gap(entries[0], entries[1]), gap(entries[1], entries[2]));
            verify(gap(entries[0], entries[1]) > Kirigami.Units.largeSpacing, "spread wider than the minimum spacing");
        }

        function headerOf(popup) {
            return all(popup, i => i.partsShown !== undefined)[0];
        }

        function shownText(item, text) {
            return all(item, i => i.visible && i.text === text && i.font !== undefined)[0];
        }

        function baselineY(text, popup) {
            return text.mapToItem(popup, Qt.point(0, text.baselineOffset)).y;
        }

        // The header's columns centre each by its own height on the tallest
        // of the ring, the name and the reading; the caption still shares
        // the subtitle's baseline.
        function test_headerBaselines_data() {
            return [{ tag: "cpu", popup: "CpuPopup", mirrored: false },
                    { tag: "cpuMirrored", popup: "CpuPopup", mirrored: true },
                    { tag: "memory", popup: "MemoryPopup", mirrored: false }];
        }

        function test_headerBaselines(data) {
            const popup = load(data.popup, normal, data.mirrored);
            const header = headerOf(popup);
            const subtitle = shownText(header, header.subtitle);
            const caption = shownText(header, header.caption);
            verify(subtitle && caption);
            fuzzyCompare(baselineY(caption, popup), baselineY(subtitle, popup), 1);
        }

        // The ink at a tile's foot, a graph's floor or the baseline of the
        // text it ends on, sits as far from the bottom as the caption's
        // capitals are from the top.
        function test_tilePadding_data() {
            return [{ tag: "cpu", popup: "CpuPopup" }, { tag: "gpu", popup: "GpuPopup" },
                    { tag: "memory", popup: "MemoryPopup" }, { tag: "network", popup: "NetworkPopup" },
                    { tag: "disk", popup: "DiskPopup" }];
        }

        function test_tilePadding(data) {
            const tiles = all(load(data.popup, normal), i => i.visible && i.graphTop !== undefined);
            verify(tiles.length > 0);
            tiles.forEach(tile => {
                const caption = all(tile, i => i.label !== undefined && i.detail !== undefined)[0];
                verify(caption.visible, tile.caption);
                probe.font = caption.font;
                probe.text = "H";
                // Qt 6.9 and later give the font's own capital height, which
                // can differ a little from the ink of an "H".
                fuzzyCompare(tile.capHeight, probe.tightBoundingRect.height, 1, tile.caption + " cap height");
                const capTop = caption.mapToItem(tile, Qt.point(0, caption.baselineOffset)).y - tile.capHeight;
                const column = caption.parent.parent;
                const last = Array.from(column.children[1].children).filter(c => c.visible).pop();
                let foot;
                if (tile.foot) {
                    verify(all(last, i => i === tile.foot).length === 1, tile.caption + ": the foot is the text it ends on");
                    foot = tile.height - tile.foot.mapToItem(tile, Qt.point(0, tile.foot.baselineOffset)).y;
                } else {
                    verify(last.values !== undefined || last.plot !== undefined || last.maxColumns !== undefined, tile.caption + " ends on a graph or names its foot");
                    foot = tile.height - (column.y + column.height);
                }
                fuzzyCompare(foot, capTop, 1, tile.caption + ": the foot's ink " + foot + " from the bottom, the capitals " + capTop + " from the top");
            });
        }

        // The header, the tiles' boxes, the dividers and the process list
        // all start and end on one edge.
        function test_contentEdges_data() {
            const popups = [["cpu", "CpuPopup"], ["gpu", "GpuPopup"], ["memory", "MemoryPopup"], ["network", "NetworkPopup"],
                            ["disk", "DiskPopup"]];
            const rows = [];
            popups.forEach(([tag, popup]) => {
                rows.push({ tag: tag, popup: popup, monitor: normal, mirrored: false });
                rows.push({ tag: tag + "Mirrored", popup: popup, monitor: normal, mirrored: true });
            });
            // A divider before a sleeping GPU's line.
            rows.push({ tag: "gpuAsleep", popup: "GpuPopup", monitor: asleep, mirrored: false });
            return rows;
        }

        function test_contentEdges(data) {
            const popup = load(data.popup, data.monitor, data.mirrored);
            const left = i => i.mapToItem(popup, Qt.point(0, 0)).x;
            const right = i => left(i) + i.width;
            const spanning = [headerOf(popup)]
                .concat(all(popup, i => i.visible && i.key !== undefined && i.threads !== undefined))
                .concat(all(popup, i => i.visible && i.ratio !== undefined && i.radius !== undefined));
            spanning.forEach(i => {
                compare(left(i), contentEdge, String(i));
                compare(right(i), popup.width - contentEdge, String(i));
            });
            const tiles = all(popup, i => i.visible && i.graphTop !== undefined);
            compare(Math.min(...tiles.map(left)), contentEdge, "the tiles' near edge");
            compare(Math.max(...tiles.map(right)), popup.width - contentEdge, "the tiles' far edge");
        }

        function test_dividers_data() {
            return [{ tag: "cpu", popup: "CpuPopup", monitor: normal },
                    { tag: "memory", popup: "MemoryPopup", monitor: normal },
                    { tag: "gpu", popup: "GpuPopup", monitor: normal },
                    { tag: "gpuAsleep", popup: "GpuPopup", monitor: asleep }];
        }

        // A divider is faint, and a whole number of the screen's pixels
        // tall, one at 125 %, so wherever it lands it draws as many rows as
        // the others.
        function test_dividers(data) {
            const popup = load(data.popup, data.monitor);
            const found = all(popup, i => i.visible && i.height > 0 && i.height <= 1 && i.radius !== undefined && i.width > 0
                                          && !ancestor(i, a => a.limitY !== undefined));
            compare(found.length, 1);
            const divider = found[0];
            compare(String(divider.color), String(Qt.alpha(Kirigami.Theme.textColor, 0.08)));
            const ratio = divider.Window.window.devicePixelRatio ?? divider.Screen.devicePixelRatio;
            fuzzyCompare(divider.height * ratio, Math.max(1, Math.floor(ratio)), 1e-9, "device pixels at " + ratio);
        }

        // The rates in the header at the tiles' size: the arrows in a column
        // that follows the layout, and each number and its unit left to right,
        // the numbers ending on one line and the units starting on one, in
        // bits or in bytes.
        function test_networkHeader_data() {
            return [{ tag: "plain", mirrored: false, bits: true }, { tag: "mirrored", mirrored: true, bits: true },
                    { tag: "bytes", mirrored: false, bits: false }];
        }

        function test_networkHeader(data) {
            const monitor = monitorWith({ networkBits: data.bits });
            const popup = load("NetworkPopup", monitor, data.mirrored);
            const rates = all(popup, i => i.pairWidth !== undefined)[0];
            verify(rates);
            const values = readings(rates);
            compare(values.length, 2);
            const arrows = all(rates, i => i.up !== undefined && i.color !== undefined);
            compare(arrows.map(a => a.up), [false, true]);
            const x = i => i.mapToItem(popup, Qt.point(0, 0)).x;
            const down = Format.rate(monitor.networkDown, data.bits);
            const up = Format.rate(monitor.networkUp, data.bits);
            compare(values.map(r => r.value + " " + r.unit), [down.value + " " + down.unit, up.value + " " + up.unit]);
            compare(rates.Accessible.name, "Down " + down.value + " " + down.unit + ", up " + up.value + " " + up.unit);
            const rate = monitor.networkDown;
            monitor.networkDown = NaN;
            compare(rates.Accessible.name, "Down unavailable, up " + up.value + " " + up.unit);
            monitor.networkDown = rate;
            const ends = [];
            const starts = [];
            values.forEach((r, n) => {
                compare(r.pointSize, Kirigami.Theme.defaultFont.pointSize * 1.38);
                verify(r.accessibleIgnored);
                const p = parts(r);
                verify(p.number.Accessible.ignored && p.suffix.Accessible.ignored, "not spoken on its own");
                verify(x(p.number) < x(p.suffix), "the number before its unit");
                ends.push(x(p.number) + p.number.implicitWidth);
                starts.push(x(p.suffix));
                if (data.mirrored) {
                    verify(x(arrows[n]) > x(p.suffix) + p.suffix.width, "the arrow after the unit");
                } else {
                    verify(x(arrows[n]) + arrows[n].width < x(p.number), "the arrow before the number");
                }
            });
            compare(ends[0], ends[1], "numbers end on one line");
            compare(starts[0], starts[1], "units start on one line");
            // The rates, at the tiles' size, never make the header taller than
            // one with a ring; the connection's name and address take the two
            // lines they need beside them.
            const cpu = headerOf(load("CpuPopup", monitor));
            verify(rates.implicitHeight <= cpu.implicitHeight, "rates no taller than a header with a ring");
            // They centre on the band the CPU header centres its ring, name
            // and reading on, within the half pixel rounding leaves.
            const header = headerOf(popup);
            compare(header.bandHeight, cpu.bandHeight, "the CPU header's band");
            const centre = rates.mapToItem(header, Qt.point(0, rates.height / 2)).y;
            verify(Math.abs(centre - cpu.bandHeight / 2) <= 0.5,
                   "the rates centred on the band: " + centre + " against " + cpu.bandHeight / 2);
        }

        // The connection's name and its address sit on lines of their own, so
        // a long name elides alone and the address stays whole beneath it,
        // with the interface's name after it.
        function test_networkHeaderLines() {
            const monitor = monitorWith({ networkConnection: "Framework 10G Ethernet Expansion Card on the left rear port" });
            const header = all(load("NetworkPopup", monitor), i => i.detail !== undefined)[0];
            compare(header.subtitle, monitor.networkConnection);
            compare(header.detail, [monitor.networkAddress, monitor.networkInterface].filter(s => s !== "").join(" · "));
            const nameLine = shownText(header, header.subtitle);
            const addressLine = shownText(header, header.detail);
            verify(nameLine && addressLine);
            verify(nameLine.truncated, "the long name elides");
            verify(!addressLine.truncated, "the address shows whole");
            verify(addressLine.mapToItem(header, Qt.point(0, 0)).y >= nameLine.mapToItem(header, Qt.point(0, nameLine.height)).y,
                   "the address under the name");
        }

        // The totals since boot lead with their arrows, as the rates do.
        function test_sinceBoot() {
            const down = Format.bytes(normal.networkTotalDown);
            const up = Format.bytes(normal.networkTotalUp);
            const expected = "Since boot ↓ " + down.value + " " + down.unit + " · ↑ " + up.value + " " + up.unit;
            const found = texts(load("NetworkPopup", normal));
            verify(found.includes(expected), JSON.stringify(found));
        }

        // The disk popup opens on its graphs as the others open on theirs:
        // read and write each across the page, drawn as the throughput graph
        // is, with its span and its peak on its caption line at the page's
        // own width. A third longer in every string, in the test's wider
        // font, the span and the label stay whole and a peak with no room
        // goes (test_rateCaptionsKeepTheirLabel).
        function test_diskGraphsMatchThroughput() {
            const look = g => JSON.stringify([g.width, g.height, String(g.color), g.fillOpacity]);
            const throughput = graphs(load("NetworkPopup", normal));
            const disk = graphs(load("DiskPopup", normal));
            compare(disk.length, 2);
            disk.forEach((g, n) => compare(look(g), look(throughput[0]), ["read", "write"][n]));
            compare(disk.map(heading), ["READ · 1 min", "WRITE · 1 min"]);
            verify(disk.map(tileTop).every(t => t.visible && t.text !== ""), "the peaks shown");
            root.longStrings = true;
            graphs(load("DiskPopup", normal)).forEach(g => checkSpanLine(ancestor(g, i => i.graphTop !== undefined),
                                                                         tileCaption(g), tileTop(g), false));
        }

        // Every object under `item` that `test` accepts, found through what
        // each holds in `data`: a Sensor is there but not in `children`,
        // which lists Items only. A model's `data` is a method instead.
        function held(item, test) {
            const found = [];
            const walk = o => {
                const list = o.data;
                if (!list || typeof list === "function") {
                    return;
                }
                for (let i = 0; i < list.length; ++i) {
                    if (test(list[i])) {
                        found.push(list[i]);
                    }
                    walk(list[i]);
                }
            };
            walk(item);
            return found;
        }

        // The popups read everything from the Monitor, which keeps one Sensor
        // per ksystemstats id; neither subscribes anything of its own.
        function test_ratePopupsSubscribeNothing_data() {
            return [{ tag: "network", popup: "NetworkPopup" }, { tag: "disk", popup: "DiskPopup" }];
        }

        function test_ratePopupsSubscribeNothing(data) {
            compare(held(load(data.popup, normal), o => o.sensorId !== undefined || o.connectedSources !== undefined).length, 0);
        }

        // The disk header names the device, then its size and the volume's
        // free space on the line under it, and has the drive's temperature
        // where the CPU header has its own, or nothing there when the drive
        // reports none.
        function test_diskHeader_data() {
            const bytes = v => { const b = Format.bytes(v, true); return b.value + " " + b.unit; };
            return [{ tag: "nvme", monitor: normal, subtitle: "nvme0n1",
                      detail: bytes(normal.diskSize) + " · " + bytes(normal.volumeFree) + " free on /", temperature: 39 },
                    { tag: "noTemperature", monitor: diskUnheated, subtitle: "nvme0n1",
                      detail: bytes(diskUnheated.diskSize) + " · " + bytes(diskUnheated.volumeFree) + " free on /", temperature: NaN },
                    { tag: "allDisks", monitor: allDisks, subtitle: "all disks",
                      detail: bytes(allDisks.diskSize) + " · " + bytes(allDisks.volumeFree) + " free on home", temperature: 39 },
                    { tag: "unnamedVolume", monitor: unnamedVolume, subtitle: "nvme0n1",
                      detail: bytes(unnamedVolume.volumeFree) + " free", temperature: 39 }];
        }

        function test_diskHeader(data) {
            const header = headerOf(load("DiskPopup", data.monitor));
            compare(header.title, "Disk");
            compare(header.subtitle, data.subtitle);
            compare(header.detail, data.detail);
            verify(shownText(header, header.subtitle), "the device is shown");
            verify(shownText(header, header.detail), "the size and free space are shown");
            compare(gauges(header).filter(g => g.visible).length, 0, "no ring");
            const headline = readings(header).filter(r => r.visible);
            if (Number.isFinite(data.temperature)) {
                compare(headline.length, 1);
                compare(headline[0].value, Format.temperature(data.temperature, false));
                compare(headline[0].degreeUnit, "C");
                compare(headline[0].pointSize, Kirigami.Theme.defaultFont.pointSize * 1.7, "the CPU header's size");
            } else {
                compare(headline.length, 0, "nothing in place of a temperature");
                verify(!texts(header).some(t => t.indexOf("°") >= 0 || t === "–"), JSON.stringify(texts(header)));
            }
            // A caption line kept with nothing in it says nothing to a screen reader.
            compare(all(header, i => i.visible && i.text === "" && i.font !== undefined && !i.Accessible.ignored).length, 0);
        }

        // The disk's temperature sits where the CPU's does: on the content's
        // far edge, its digits as far below the title's baseline, though the
        // disk header has a third line and no ring. Plain and mirrored.
        function test_diskHeadlineWhereTheCpuHasIts_data() {
            return [{ tag: "plain", mirrored: false }, { tag: "mirrored", mirrored: true }];
        }

        function test_diskHeadlineWhereTheCpuHasIts(data) {
            const place = popupName => {
                const popup = load(popupName, normal, data.mirrored);
                const header = headerOf(popup);
                const title = shownText(header, header.title);
                const headline = readings(header).find(r => r.visible && r.degreeUnit !== "");
                verify(title && headline, popupName);
                const x = i => i.mapToItem(popup, Qt.point(0, 0)).x;
                return { below: headline.mapToItem(header, Qt.point(0, headline.baselineOffset)).y - baselineY(title, header),
                         edge: data.mirrored ? x(headline) : popup.width - x(headline) - headline.width,
                         titleEdge: data.mirrored ? popup.width - x(title) - title.width : x(title) };
            };
            const cpu = place("CpuPopup");
            const disk = place("DiskPopup");
            fuzzyCompare(disk.below, cpu.below, 1, "the digits against the title");
            compare(disk.edge, cpu.edge, "on the far edge");
            compare(disk.titleEdge, contentEdge, "the title on the near edge");
        }

        // Every header's title and digits sit as far below its top as the CPU
        // header's do, with a ring or without, with a third line, without a
        // reading, or with the countdown's parts, so the popups read level
        // with each other. A third line hangs below; a header with a ring is
        // as tall as the CPU's, which is as tall as its tallest part. Plain
        // and mirrored.
        function test_headersLevel_data() {
            return [{ tag: "plain", mirrored: false }, { tag: "mirrored", mirrored: true }];
        }

        function test_headersLevel(data) {
            const headers = (popup, monitor, item) => {
                const loader = createTemporaryObject(data.mirrored ? mirroredHost : host, root);
                loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/" + popup + ".qml"),
                                 item ? { monitor: monitor, item: item } : { monitor: monitor });
                compare(loader.status, Loader.Ready, popup);
                waitForRendering(loader.item);
                return all(loader.item, i => i.visible && i.partsShown !== undefined);
            };
            const found = [].concat(headers("CpuPopup", normal), headers("GpuPopup", normal), headers("GpuPopup", intel),
                                    headers("MemoryPopup", normal), headers("MemoryPopup", uncaptioned),
                                    headers("NetworkPopup", normal), headers("DiskPopup", normal),
                                    headers("UsagePopup", normal, "claude"), headers("UsagePopup", normal, "codex"));
            const place = header => {
                const title = shownText(header, header.title);
                const digits = readings(header).find(r => r.visible && r.pointSize === Kirigami.Theme.defaultFont.pointSize * 1.7);
                const ring = gauges(header).find(g => g.visible);
                return { title: baselineY(title, header),
                         digits: digits ? digits.mapToItem(header, Qt.point(0, digits.baselineOffset)).y : null,
                         ring: ring ? ring.mapToItem(header, Qt.point(0, 0)).y : null,
                         height: header.height,
                         tallest: Math.max(...header.children.filter(c => c.visible).map(c => c.height)) };
            };
            const cpu = place(found[0]);
            compare(found[0].title, "CPU");
            verify(cpu.digits !== null && cpu.ring !== null);
            compare(cpu.height, cpu.tallest, "the CPU header as tall as its tallest part");
            const withoutDigits = [];
            found.forEach(header => {
                const tag = header.title + (header.detail !== "" ? " (three lines)" : "");
                const p = place(header);
                compare(p.title, cpu.title, tag + ": the title's baseline");
                if (p.digits === null) {
                    withoutDigits.push(header.title);
                } else {
                    compare(p.digits, cpu.digits, tag + ": the digits' baseline");
                }
                if (p.ring !== null) {
                    compare(p.ring, cpu.ring, tag + ": the ring");
                    compare(p.height, cpu.height, tag + ": the height of a header with a ring");
                } else {
                    const detail = shownText(header, header.detail);
                    verify(detail, tag + ": a third line");
                    const subtitle = shownText(header, header.subtitle);
                    compare(detail.mapToItem(header, Qt.point(0, 0)).y, subtitle.mapToItem(header, Qt.point(0, subtitle.height)).y,
                            tag + ": the third line under the subtitle");
                    compare(p.height, Math.max(cpu.height, detail.mapToItem(header, Qt.point(0, detail.height)).y),
                            tag + ": as tall as the CPU's or down to the third line");
                }
            });
            compare(found.map(h => h.title), ["CPU", "AMD Radeon 780M Graphics", "AMD Radeon RX 7700S", "Intel Iris Xe Graphics",
                                              "NVIDIA GeForce RTX 3060 Laptop GPU", "Memory", "Memory", "Network", "Disk", "Claude", "Codex"]);
            compare(withoutDigits, ["Intel Iris Xe Graphics", "Network"]);
        }

        // The drive's temperature takes the level colours, judged in Celsius,
        // as the CPU's and the GPUs' do.
        function test_diskTemperatureTakesTheLevelColours_data() {
            return [{ tag: "74", celsius: 74, tone: "text" }, { tag: "75", celsius: 75, tone: "neutral" },
                    { tag: "90", celsius: 90, tone: "negative" }, { tag: "90 plain", celsius: 90, plain: true, tone: "text" },
                    { tag: "96 in Fahrenheit", celsius: 96, fahrenheit: true, tone: "negative" }];
        }

        function test_diskTemperatureTakesTheLevelColours(data) {
            const expected = data.tone === "negative" ? Kirigami.Theme.negativeTextColor
                           : data.tone === "neutral" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
            const monitor = monitorWith({ highlightTemperatures: !data.plain, fahrenheit: !!data.fahrenheit, diskTemperature: data.celsius });
            const headline = readings(headerOf(load("DiskPopup", monitor))).find(r => r.visible);
            compare(headline.value, Format.temperature(data.celsius, !!data.fahrenheit));
            compare(headline.degreeUnit, data.fahrenheit ? "F" : "C");
            compare(String(parts(headline).number.color), String(expected), "the digits as drawn");
        }

        // Each awake GPU opens with the CPU popup's header: its usage in the
        // ring, its name, its kind and memory, and its temperature over the
        // sensor's name where it has one. Nothing titles the popup "GPU"; a
        // powered-down GPU stays one line after the sections.
        function test_gpuHeaders_data() {
            const amd = ["AMD Radeon RX 7700S", "AMD Radeon 780M Graphics"];
            const kinds = ["dGPU · 8 GiB", "iGPU · shared"];
            const off = ["AMD Radeon RX 7700S · off"];
            // The integrated GPU first, so a discrete one waking opens below it.
            return [{ tag: "two", monitor: normal, titles: [amd[1], amd[0]], subtitles: [kinds[1], kinds[0]], rings: [3, 12], values: [41, 48],
                      captions: ["", ""], off: [] },
                    { tag: "outerAsleep", monitor: asleep, titles: [amd[1]], subtitles: [kinds[1]], rings: [3], values: [41],
                      captions: [""], off: off },
                    { tag: "innerAsleep", monitor: innerAsleep, titles: [amd[1]], subtitles: [kinds[1]], rings: [12], values: [48],
                      captions: [""], off: off },
                    { tag: "integratedOnly", monitor: integrated, titles: [amd[1]], subtitles: [kinds[1]], rings: [12], values: [48],
                      captions: [""], off: [] },
                    { tag: "discreteOnly", monitor: discreteOnly, titles: [amd[0]], subtitles: [kinds[0]], rings: [12], values: [48],
                      captions: [""], off: [] },
                    { tag: "intel", monitor: intel, titles: ["Intel Iris Xe Graphics", "NVIDIA GeForce RTX 3060 Laptop GPU"],
                      subtitles: [kinds[1], kinds[0]], rings: [3, 12], values: [NaN, 48], captions: ["", ""], off: [] },
                    { tag: "onlyAsleep", monitor: onlyAsleep, titles: [], subtitles: [], rings: [], values: [], captions: [], off: off }];
        }

        function test_gpuHeaders(data) {
            const cpuRing = gauges(headerOf(load("CpuPopup", normal)))[0];
            const popup = load("GpuPopup", data.monitor);
            const headers = all(popup, i => i.visible && i.partsShown !== undefined);
            compare(headers.map(h => h.title), data.titles);
            compare(headers.map(h => h.subtitle), data.subtitles.map(localized));
            compare(headers.map(h => h.caption), data.captions);
            headers.forEach((h, n) => {
                const tag = h.title;
                const rings = gauges(h).filter(g => g.visible);
                compare(rings.length, 1, tag);
                compare(rings[0].value, data.rings[n], tag);
                compare(rings[0].width, cpuRing.width, tag + ": the CPU popup's ring size");
                compare(rings[0].strokeWidth, cpuRing.strokeWidth, tag);
                compare(rings[0].Accessible.name, h.title, tag + " names its ring");
                verify(shownText(h, h.title), tag + ": the title");
                verify(shownText(h, h.subtitle), tag + ": the subtitle");
                const headline = readings(h).filter(r => r.visible);
                if (Number.isFinite(data.values[n])) {
                    compare(headline.length, 1, tag);
                    compare(headline[0].value, Format.temperature(data.values[n], false), tag);
                    compare(headline[0].degreeUnit, "C", tag);
                } else {
                    compare(headline.length, 0, tag + " has no temperature");
                }
                if (h.caption !== "") {
                    verify(shownText(h, h.caption), tag + ": the caption");
                }
                // A caption line kept with nothing in it says nothing to a screen reader.
                compare(all(h, i => i.visible && i.text === "" && i.font !== undefined && !i.Accessible.ignored).length, 0, tag);
            });
            const found = texts(popup);
            verify(!found.some(t => ["GPU", "Discrete", "Integrated"].includes(t)), JSON.stringify(found));
            compare(found.filter(t => t.endsWith(" · off")), data.off);
            // A rule before every section but the first, and before a
            // powered-down GPU under an awake one.
            const rules = all(popup, i => i.visible && i.height > 0 && i.height <= 1 && i.radius !== undefined && i.width > 0
                                          && !ancestor(i, a => a.limitY !== undefined));
            compare(rules.length, Math.max(0, headers.length - 1) + (headers.length > 0 ? data.off.length : 0));
        }

        // The CPU popup's own readings, the average frequency and each
        // thread's bar, are read as often as the graph above them, so at a
        // long update interval the whole popup still moves together.
        function test_cpuPopupReadsWithItsGraph() {
            const monitor = monitorWith({ interval: 5000 });
            const own = held(load("CpuPopup", monitor),
                             o => o.sensorId === "cpu/all/averageFrequency" || /^cpu\/cpu\d+\/usage$/.test(o.sensorId));
            verify(own.length > 2, "the frequency and the threads: " + own.length);
            verify(own.every(s => s.updateRateLimit === monitor.readInterval), own.map(s => s.updateRateLimit).join());
        }

        // Every GPU header is laid out as the CPU popup's is, on the
        // content's edges and with its tiles as far under it, plain and
        // mirrored. Each section's parts sit where the CPU header's do. An
        // NVIDIA GPU names no sensor, yet its temperature stays level with
        // its name; the Intel GPU after it has no reading to line up.
        function test_gpuHeadersMatchTheCpu_data() {
            const every = ["edges", "height", "ring", "title", "subtitle", "headline", "caption", "tiles"];
            const unnamed = every.filter(key => key !== "caption");
            return [{ tag: "plain", mirrored: false, monitor: normal, shown: [every, every] },
                    { tag: "mirrored", mirrored: true, monitor: normal, shown: [every, every] },
                    { tag: "nvidia", mirrored: false, monitor: intel, shown: [null, unnamed] },
                    { tag: "nvidiaMirrored", mirrored: true, monitor: intel, shown: [null, unnamed] }];
        }

        function test_gpuHeadersMatchTheCpu(data) {
            const layout = popup => all(popup, i => i.visible && i.partsShown !== undefined).map(header => {
                const at = i => i.mapToItem(header, Qt.point(0, 0));
                const baseline = t => t.mapToItem(header, Qt.point(0, t.baselineOffset)).y;
                const ring = gauges(header)[0];
                const title = shownText(header, header.title);
                const subtitle = shownText(header, header.subtitle);
                const caption = header.caption !== "" ? shownText(header, header.caption) : null;
                const headline = readings(header).find(r => r.visible);
                const top = header.mapToItem(popup, Qt.point(0, 0)).y;
                const tiles = all(popup, i => i.visible && i.graphTop !== undefined)
                    .map(t => t.mapToItem(popup, Qt.point(0, 0)).y).filter(y => y > top);
                return {
                    edges: [header.mapToItem(popup, Qt.point(0, 0)).x, popup.width - header.mapToItem(popup, Qt.point(header.width, 0)).x],
                    height: header.height,
                    ring: [at(ring).x, at(ring).y, ring.width],
                    title: [at(title).x, baseline(title), title.font.pointSize],
                    subtitle: [at(subtitle).x, baseline(subtitle)],
                    headline: headline ? [at(headline).x + (data.mirrored ? 0 : headline.width), baseline(headline), headline.pointSize] : null,
                    caption: caption ? [at(caption).x + (data.mirrored ? 0 : caption.width), baseline(caption)] : null,
                    tiles: Math.min(...tiles) - top - header.height
                };
            });
            const cpu = layout(load("CpuPopup", normal, data.mirrored));
            compare(cpu.length, 1);
            compare(cpu[0].edges, [contentEdge, contentEdge]);
            const gpu = layout(load("GpuPopup", data.monitor, data.mirrored));
            compare(gpu.length, 2);
            data.shown.forEach((keys, n) => {
                if (!keys) {
                    return;
                }
                for (const key in cpu[0]) {
                    const expected = keys.includes(key) ? cpu[0][key] : null;
                    compare(JSON.stringify(gpu[n][key]), JSON.stringify(expected), "GPU " + (n + 1) + ": " + key);
                }
            });
        }

        // A headline with no caption under it sits where it does with one,
        // level with the title, and the header keeps its height.
        function test_headlineWithoutCaptionStaysLevel_data() {
            return [{ tag: "cpu", popup: "CpuPopup" }, { tag: "memory", popup: "MemoryPopup" }];
        }

        function test_headlineWithoutCaptionStaysLevel(data) {
            const place = monitor => {
                const header = all(load(data.popup, monitor), i => i.visible && i.partsShown !== undefined)[0];
                const headline = readings(header).find(r => r.visible);
                return { caption: header.caption, height: header.height,
                         baseline: headline.mapToItem(header, Qt.point(0, headline.baselineOffset)).y };
            };
            const captioned = place(data.popup === "CpuPopup" ? otherSensors : normal);
            const bare = place(uncaptioned);
            verify(captioned.caption !== "" && bare.caption === "", JSON.stringify([captioned.caption, bare.caption]));
            compare(bare.baseline, captioned.baseline, "the headline's baseline");
            compare(bare.height, captioned.height, "the header's height");
        }

        // Each GPU's temperature takes the level colours at 75 °C and 90 °C,
        // judged in Celsius whatever unit it is shown in, and stays the text
        // colour with highlighting off.
        function test_gpuTemperatureTakesTheLevelColours_data() {
            return [{ tag: "74", celsius: 74, tone: "text" }, { tag: "75", celsius: 75, tone: "neutral" },
                    { tag: "90", celsius: 90, tone: "negative" }, { tag: "90 plain", celsius: 90, plain: true, tone: "text" },
                    { tag: "50 in Fahrenheit", celsius: 50, fahrenheit: true, tone: "text" },
                    { tag: "96 in Fahrenheit", celsius: 96, fahrenheit: true, tone: "negative" }];
        }

        function test_gpuTemperatureTakesTheLevelColours(data) {
            const expected = data.tone === "negative" ? Kirigami.Theme.negativeTextColor
                           : data.tone === "neutral" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
            const monitor = monitorWith({ highlightTemperatures: !data.plain, fahrenheit: !!data.fahrenheit,
                                          "gpuOuter.temperature": data.celsius, "gpuInner.temperature": data.celsius });
            const headers = all(load("GpuPopup", monitor), i => i.visible && i.partsShown !== undefined);
            compare(headers.length, 2);
            headers.forEach(h => {
                const headline = readings(h).find(r => r.visible);
                compare(headline.value, Format.temperature(data.celsius, !!data.fahrenheit), h.title);
                compare(String(parts(headline).number.color), String(expected), h.title + ": the digits as drawn");
            });
        }

        // The second GPU's usage graph is drawn as the first's and the CPU's
        // are, at full strength and height, since it has a header of its own.
        function test_gpuGraphsMatchTheCpu() {
            const look = g => JSON.stringify([g.height, String(g.color), g.fillOpacity]);
            const cpu = graphs(load("CpuPopup", normal));
            compare(cpu.length, 1);
            const gpu = graphs(load("GpuPopup", normal)).filter(g => g.visible);
            compare(gpu.length, 2);
            gpu.forEach((g, n) => compare(look(g), look(cpu[0]), "GPU " + (n + 1)));
        }

        // A long name elides in its header at the page widths a popup
        // takes, short of the temperature, which keeps its full width.
        function test_gpuLongNamesFit_data() {
            const rows = [];
            for (const width of [Kirigami.Units.gridUnit * 20, Math.round(Kirigami.Units.gridUnit * 20 * 14 / 18)]) {
                rows.push({ tag: width + " px", width: width, mirrored: false });
                rows.push({ tag: width + " px mirrored", width: width, mirrored: true });
            }
            return rows;
        }

        function test_gpuLongNamesFit(data) {
            const loader = createTemporaryObject(data.mirrored ? mirroredHost : host, root, { width: data.width });
            loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/GpuPopup.qml"), { monitor: longGpuNames });
            const popup = loader.item;
            waitForRendering(popup);
            compare(popup.width, data.width);
            const left = i => i.mapToItem(popup, Qt.point(0, 0)).x;
            const headers = all(popup, i => i.visible && i.partsShown !== undefined);
            compare(headers.length, 2);
            headers.forEach(h => {
                const title = shownText(h, h.title);
                verify(title.truncated, h.title + " elides");
                const headline = readings(h).find(r => r.visible);
                verify(headline.width >= headline.implicitWidth - 0.5, "the temperature keeps its width");
                const [near, far] = data.mirrored ? [headline, title] : [title, headline];
                verify(left(near) + near.width <= left(far) + 0.5, "the name stops short of the temperature");
                compare(left(h), contentEdge);
                compare(left(h) + h.width, popup.width - contentEdge);
            });
        }

        // The CPU and GPU headers' captions show the plain words, and none
        // for the whole chip's own sensor.
        function test_popupsNameTheirSensors_data() {
            return [{ tag: "usual", monitor: normal, cpu: "", gpu: ["", ""] },
                    { tag: "other", monitor: otherSensors, cpu: "chiplet " + Format.whole(3), gpu: ["memory", "hotspot"] }];
        }

        function test_popupsNameTheirSensors(data) {
            const cpu = load("CpuPopup", data.monitor);
            const header = headerOf(cpu);
            compare(header.caption, data.cpu);
            if (data.cpu !== "") {
                verify(shownText(header, data.cpu), "the caption is shown");
            }
            const gpu = load("GpuPopup", data.monitor);
            const found = texts(gpu);
            compare(all(gpu, i => i.partsShown !== undefined).map(h => h.caption), data.gpu);
            data.gpu.filter(name => name !== "").forEach(name => verify(found.includes(name), name + " in " + JSON.stringify(found)));
            verify(!found.includes("chip") && !texts(cpu).includes("chip"), "no chip caption");
            const raw = ["Tctl", "Tccd3", "edge", "junction", "mem"];
            verify(!texts(cpu).concat(found).some(t => raw.includes(t)), "no raw label is shown");
        }

        // Percentages and counts go through translation, so a language that
        // sets "%1 %" or "%%1" sets every one of them alike, and a count
        // takes the locale's digits: the rings' centres, the per-thread bars'
        // descriptions and a process that runs several times.
        function test_numbersAreTranslated() {
            const monitor = monitorWith({ processSample: [{ name: "chrome", usage: 8.4 * 16, memory: 3.9 * 1024 ** 3, count: 12 }]
                                                             .concat(normal.processSample.slice(1)) });
            root.longStrings = true;
            const translated = t => t.endsWith("ß");
            const rings = popup => all(popup, i => i.outerTone !== undefined && i.text !== undefined && i.text !== "–");
            const cpu = load("CpuPopup", monitor);
            verify(rings(cpu).length > 0);
            rings(cpu).forEach(r => verify(translated(r.text), r.text));
            const threads = all(cpu, i => i.Accessible.role === Accessible.ProgressBar);
            verify(threads.length > 0);
            threads.forEach(b => verify(translated(b.Accessible.description), b.Accessible.description));
            verify(texts(cpu).some(t => t.startsWith("chrome ×" + Format.whole(12)) && translated(t)), JSON.stringify(texts(cpu)));
            const gpu = load("GpuPopup", monitor);
            compare(rings(gpu).length, 2, "each GPU's ring");
            rings(gpu).forEach(r => verify(translated(r.text), r.text));
        }

        // The system popups' footers keep the System Monitor link and the
        // configure button on one line, with no switch: the session
        // starter's belongs to the Claude and Codex popups only. The link's
        // text and the icon's drawing sit on the readings' edges, plain and
        // mirrored.
        function test_systemFooters_data() {
            const rows = [];
            for (const [tag, popup] of [["cpu", "CpuPopup"], ["gpu", "GpuPopup"], ["memory", "MemoryPopup"], ["network", "NetworkPopup"],
                                        ["disk", "DiskPopup"]]) {
                rows.push({ tag: tag, popup: popup, mirrored: false });
                rows.push({ tag: tag + "Mirrored", popup: popup, mirrored: true });
            }
            return rows;
        }

        function test_systemFooters(data) {
            const popup = load(data.popup, normal, data.mirrored);
            const footer = all(popup, i => i.systemMonitorShown !== undefined && i.position !== undefined)[0];
            verify(footer.systemMonitorShown);
            compare(all(footer, i => i.visualPosition !== undefined).length, 0, "no switch");
            const link = all(footer, i => i.visible && i.text === "Open System Monitor")[0];
            const button = all(footer, i => i.visible && i.icon !== undefined && i.icon.name === "configure")[0];
            verify(link && button);
            compare(footer.height, footer.topPadding + footer.bottomPadding + Math.max(link.implicitHeight, button.implicitHeight));
            const middle = i => i.mapToItem(footer, Qt.point(0, i.height / 2)).y;
            fuzzyCompare(middle(button), middle(link), 0.5);
            // On the readings' edges: the link's text, and the icon's drawing
            // inside the button's padding and the 3 px Breeze's 22 px icon
            // keeps free around it.
            const slack = Kirigami.Units.iconSizes.smallMedium * 3 / 22;
            const x = (i, at) => i.mapToItem(footer, Qt.point(at, 0)).x;
            if (data.mirrored) {
                compare(x(link, link.width), footer.width - contentEdge);
                compare(x(button, button.leftPadding + slack), contentEdge);
            } else {
                compare(x(link, 0), contentEdge);
                compare(x(button, button.width - button.rightPadding - slack), footer.width - contentEdge);
            }
        }

        function temperatureTiles(popup) {
            return all(popup, i => i.visible && i.hasReading !== undefined);
        }

        function temperatureGraph(tile) {
            return all(tile, i => i.pieces !== undefined && i.areas !== undefined)[0];
        }

        // A tile's caption and the scale at the far end of its line.
        function captionLine(tile) {
            return all(tile, i => i.label !== undefined && i.detail !== undefined);
        }

        // A temperature graph wherever the header has a temperature that has
        // given a reading in the graph's span, none for a sensor that never
        // answers, an Intel GPU, which publishes none, a sleeping GPU, which
        // keeps to its one line, or an integrated GPU beside a discrete one.
        // The caption gives the span, and its far end the hot threshold,
        // under a faint rule at the top as 100% is, as these run cooler.
        function test_temperatureGraphs_data() {
            return [
                { tag: "cpu", popup: "CpuPopup", monitor: normal, count: 1 },
                { tag: "cpuWithoutReading", popup: "CpuPopup", monitor: cpuUnheated, count: 0 },
                { tag: "gpu", popup: "GpuPopup", monitor: normal, count: 1 },
                { tag: "gpuResting", popup: "GpuPopup", monitor: resting, count: 1 },
                { tag: "gpuAsleep", popup: "GpuPopup", monitor: asleep, count: 0 },
                { tag: "gpuInnerAsleep", popup: "GpuPopup", monitor: innerAsleep, count: 0 },
                { tag: "gpuIntegratedOnly", popup: "GpuPopup", monitor: integrated, count: 1 },
                { tag: "gpuOnlyAsleep", popup: "GpuPopup", monitor: onlyAsleep, count: 0 },
                { tag: "gpuIntel", popup: "GpuPopup", monitor: intel, count: 1 },
                { tag: "disk", popup: "DiskPopup", monitor: normal, count: 1 },
                { tag: "diskWithoutTemperature", popup: "DiskPopup", monitor: diskUnheated, count: 0 }
            ];
        }

        function test_temperatureGraphs(data) {
            const popup = load(data.popup, data.monitor, false, widePage);
            const tiles = temperatureTiles(popup);
            compare(tiles.length, data.count);
            // The usage or write rate graph over it, whose shape it shares.
            const above = all(popup, i => i.visible && i.fillOpacity !== undefined && i.ceiling !== undefined).pop();
            tiles.forEach(t => {
                const [caption, top] = captionLine(t);
                compare(heading(t), "TEMPERATURE · 1 min");
                const peak = Math.max(...t.history.filter(c => Number.isFinite(c)));
                compare(top.text, localized("peak " + Math.round(peak) + " °C"));
                verify(top.visible);
                const g = temperatureGraph(t);
                const rules = all(g, i => i.limitY !== undefined);
                compare(rules.length, 1);
                verify(rules[0].visible, "a faint rule at the hot threshold");
                fuzzyCompare(rules[0].mapToItem(g, Qt.point(0, rules[0].limitY)).y, g.topY, 1e-6, "at the top");
                compare(rules[0].width, g.width);
                compare(g.areas.length, 1, "one unbroken line");
                compare(g.plot.points.length, data.monitor.historyLength);
                // The newest reading stands where the scale puts it, and
                // every reading stays inside the scale.
                const newest = g.plot.values[g.plot.values.length - 1];
                compare(t.scaleTop, 90);
                fuzzyCompare(g.plot.points[g.plot.points.length - 1].y,
                             g.topY + (1 - (newest - t.floor) / (t.scaleTop - t.floor)) * (g.height - g.topY - 0.75), 1e-6);
                const ys = g.plot.points.map(p => p.y);
                verify(Math.min(...ys) >= g.topY && Math.max(...ys) < g.height - 1, ys.join());
                // Filled down to the floor of the graph, in the usage graph's
                // shade, and as tall as it.
                const area = g.areas[0];
                compare(area[0].y, g.height);
                compare(area[area.length - 1].y, g.height);
                compare(area[0].x, area[1].x);
                compare(area[area.length - 1].x, area[area.length - 2].x);
                // The band under the area, empty at a minute.
                const paths = all(g, i => i.preferredRendererType !== undefined)[0].data;
                compare(paths[0].pathElements[0].paths.length, 0, "no band at a minute");
                fuzzyCompare(paths[1].fillColor.a, above.fillOpacity, 0.005);
                compare(g.implicitHeight, above.implicitHeight);
                compare(g.height, above.height);
                paths.slice(2).forEach(p => compare(p.capStyle, ShapePath.RoundCap, "pieces meet in round ends"));
            });
        }

        // Highlighting off, the thresholds mean nothing on screen, so there
        // is no rule, the top is the hottest reading of any span rounded up
        // to a five, and the caption names the peak of the span shown, as a
        // rate graph's does: the calm minute's, then the day's.
        function test_temperatureCaptionIsThePeakWithoutHighlighting() {
            const monitor = monitorWith({ highlightTemperatures: false }, hotDay);
            const tile = temperatureTiles(load("CpuPopup", monitor, false, widePage))[0];
            const g = temperatureGraph(tile);
            for (const span of ["minute", "day"]) {
                monitor.chooseSpan(span);
                const peak = Math.max(...monitor.cpuTemperatureHistory.concat(monitor.cpuTemperatureHighs).filter(Number.isFinite));
                compare(tile.scaleTop, 95, span);
                compare(captionLine(tile)[1].text, localized("peak " + Math.round(peak) + " °C"), span);
                verify(!all(g, i => i.limitY !== undefined)[0].visible, span + ": no rule");
            }
            compare(captionLine(tile)[1].text, localized("peak 93 °C"));
        }

        // A lone reading, the first say, draws no line, so there is no graph
        // until a second one comes.
        function test_aLoneReadingHasNoGraph() {
            const monitor = monitorWith({ cpuTemperatureHistory: [61] });
            compare(temperatureTiles(load("CpuPopup", monitor)).length, 0);
            monitor.cpuTemperatureHistory = [NaN, 60, NaN, 61];
            compare(temperatureTiles(load("CpuPopup", monitor)).length, 0, "nor from readings apart");
            monitor.cpuTemperatureHistory = [60, 61];
            compare(temperatureTiles(load("CpuPopup", monitor)).length, 1);
        }

        // At an hour or a day a bucket between gaps is a mark of its own, so
        // it has a graph where a lone reading at a minute has none, and the
        // tile stays while the sensor has read anything, though its first
        // bucket is still open.
        function test_aLoneBucketHasAGraph() {
            const monitor = monitorWith({ cpuTemperatureHistory: [61] });
            const popup = load("CpuPopup", monitor);
            monitor.chooseSpan("day");
            monitor.cpuTemperatureHistory = [NaN, 60, NaN];
            monitor.cpuTemperatureHighs = [NaN, 62, NaN];
            compare(temperatureTiles(popup).length, 1, "a lone bucket");
            monitor.cpuTemperatureHistory = [];
            monitor.cpuTemperatureHighs = [];
            compare(temperatureTiles(popup).length, 0, "nothing read");
            monitor.cpuTemperatureExtent = [60, 61];
            compare(temperatureTiles(popup).length, 1, "read, in a bucket still open");
            monitor.chooseSpan("minute");
            monitor.cpuTemperatureHistory = [NaN, 60, NaN];
            compare(temperatureTiles(popup).length, 0, "a lone reading at a minute");
        }

        // Picking a day from the temperature's own caption, on a widget
        // whose first buckets are still open, keeps the tile where it was,
        // and the focus on its span.
        function test_aFreshTileStaysAsTheSpanChanges() {
            const fresh = monitorWith({}, freshStart);
            const host = createTemporaryObject(escapeHost, root, { width: widePage });
            host.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/CpuPopup.qml"), { monitor: fresh });
            const popup = host.item;
            waitForRendering(popup);
            const tile = temperatureTiles(popup)[0];
            verify(tile);
            const height = popup.implicitHeight;
            const span = spanOf(tile);
            span.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            tryVerify(() => span.menu.opened, 2000);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            tryVerify(() => !span.menu.visible, 2000);
            compare(fresh.graphSpan, "day");
            compare(fresh.cpuTemperatureHistory, []);
            verify(tile.visible, "the tile stays");
            compare(popup.implicitHeight, height, "and the popup's height");
            tryVerify(() => span.activeFocus && span.visualFocus, 2000, "the focus is back on its span");
        }

        // At an hour, on a widget whose first buckets are still open, every
        // popup keeps its temperature tile, and the span control in it.
        function test_freshTemperatureTileAtAnHour_data() {
            return [{ tag: "cpu", popup: "CpuPopup" }, { tag: "gpu", popup: "GpuPopup" }, { tag: "disk", popup: "DiskPopup" }];
        }

        function test_freshTemperatureTileAtAnHour(data) {
            const fresh = monitorWith({}, freshStart);
            const popup = load(data.popup, fresh, false, widePage);
            fresh.chooseSpan("hour");
            const tiles = temperatureTiles(popup);
            compare(tiles.length, 1);
            verify(!tiles[0].hasReading, "nothing to draw yet");
            verify(spanOf(tiles[0]).visible);
        }

        // A reading dipping under a round number lowers the floor, which then
        // stays down as the dip leaves the span, so the line moves once.
        function test_temperatureFloorHoldsInTheTile() {
            const monitor = monitorWith({ cpuTemperatureHistory: [46, 45, 46] });
            const tile = temperatureTiles(load("CpuPopup", monitor))[0];
            compare(tile.floor, 40);
            monitor.cpuTemperatureHistory = [45, 46, 44.9];
            compare(tile.floor, 30);
            monitor.cpuTemperatureHistory = [46, 44.9, 46];
            monitor.cpuTemperatureHistory = [44.9, 46, 45];
            monitor.cpuTemperatureHistory = [46, 45, 46];
            compare(tile.floor, 30, "kept as the dip leaves");
            const g = temperatureGraph(tile);
            fuzzyCompare(g.plot.points[2].y, g.topY + (1 - (46 - 30) / (90 - 30)) * (g.height - g.topY - 0.75), 1e-6);
            monitor.cpuTemperatureHistory = [52, 51, 53];
            compare(tile.floor, 40, "raised once well clear");
        }

        // Two GPUs, the integrated one without a temperature graph, fit a
        // 1920 × 1080 screen at 150%, 720 px, under a 44 px panel, with 10 px
        // for the dialog's margins, at Plasma's usual grid unit of 18 px.
        function test_twoGpusFitASmallScreen() {
            const popup = load("GpuPopup", normal);
            verify(popup.implicitHeight <= (720 - 44 - 10) * Kirigami.Units.gridUnit / 18, popup.implicitHeight + " px at a grid unit of "
                   + Kirigami.Units.gridUnit);
        }

        // Each temperature graph comes straight under the usage graph it
        // follows, as wide, so a burst of load lines up with the rise it
        // causes; the disk's after its write rate.
        function test_temperatureGraphPlacement_data() {
            return [{ tag: "cpu", popup: "CpuPopup", above: "Usage", count: 1 },
                    { tag: "gpu", popup: "GpuPopup", above: "Usage", count: 1 },
                    { tag: "disk", popup: "DiskPopup", above: "Write", count: 1 },
                    { tag: "cpuMirrored", popup: "CpuPopup", above: "Usage", count: 1, mirrored: true }];
        }

        function test_temperatureGraphPlacement(data) {
            const popup = load(data.popup, normal, data.mirrored);
            const top = i => i.mapToItem(popup, Qt.point(0, 0)).y;
            const left = i => i.mapToItem(popup, Qt.point(0, 0)).x;
            const tiles = all(popup, i => i.visible && i.graphTop !== undefined).sort((a, b) => top(a) - top(b));
            const found = tiles.filter(t => t.hasReading !== undefined);
            compare(found.length, data.count);
            found.forEach(t => {
                const above = tiles[tiles.indexOf(t) - 1];
                compare(above.caption, data.above);
                compare(left(t), left(above));
                compare(t.width, above.width);
                compare(top(t) - (top(above) + above.height), Kirigami.Units.largeSpacing, "the tiles' usual gap");
            });
            if (data.popup === "DiskPopup") {
                compare(tiles[tiles.length - 1], found[0], "the disk's comes last");
            }
        }

        // In °F the samples, the scale and the peak are in °F, the hot
        // threshold the top as it is in °C.
        function test_temperatureGraphsInFahrenheit() {
            const tile = temperatureTiles(load("CpuPopup", monitorWith({ fahrenheit: true }), false, widePage))[0];
            const g = temperatureGraph(tile);
            fuzzyCompare(g.plot.values[g.plot.values.length - 1], 61 * 9 / 5 + 32, 1e-9);
            const peak = Math.max(...tile.history.filter(c => Number.isFinite(c))) * 9 / 5 + 32;
            compare(captionLine(tile)[1].text, localized("peak " + Math.round(peak) + " °F"));
        }

        // The line turns amber from the warm threshold and red from the hot
        // one, as the header's reading does, in either unit, and stays plain
        // with the highlighting off. The caption names the peak, over hot.
        function test_temperatureLineTakesTheLevelColours_data() {
            return [{ tag: "cpu", popup: "CpuPopup", f: false, top: "peak 93 °C" },
                    { tag: "gpu", popup: "GpuPopup", f: false, top: "peak 93 °C" },
                    { tag: "disk", popup: "DiskPopup", f: false, top: "peak 93 °C" },
                    { tag: "cpuF", popup: "CpuPopup", f: true, top: "peak 199 °F" },
                    { tag: "diskF", popup: "DiskPopup", f: true, top: "peak 199 °F" }];
        }

        function test_temperatureLineTakesTheLevelColours(data) {
            // The line's pieces at each level, the paths that take a list of lines.
            const strokes = g => all(g, i => i.preferredRendererType !== undefined)[0].data.filter(p => p.lines !== undefined);
            const check = (highlighted, levels, counts) => {
                const monitor = monitorWith({ fahrenheit: data.f, highlightTemperatures: highlighted }, heating);
                const tile = temperatureTiles(load(data.popup, monitor, false, widePage)).pop();
                compare(captionLine(tile)[1].text, localized(data.top));
                const g = temperatureGraph(tile);
                compare(g.pieces.map(p => p.level), levels);
                // The climb passes 75 °C 26.8 samples in and 90 °C 53.6 in.
                const step = g.width / (monitor.historyLength - 1);
                g.pieces.slice(1).forEach((p, n) => fuzzyCompare(p.points[0].x, ([75, 90][n] - 60) * 59 / 33 * step, 1e-6,
                                                                 "where it turns"));
                const paths = strokes(g);
                compare(paths.map(p => String(p.strokeColor)),
                        [Kirigami.Theme.textColor, Kirigami.Theme.neutralTextColor, Kirigami.Theme.negativeTextColor].map(String));
                compare(paths.map(p => p.pathElements[0].paths.length), counts);
            };
            check(true, [0, 1, 2], [1, 1, 1]);
            check(false, [0], [1, 0, 0]);
        }

        // A GPU that woke during the graph's span has no line before it woke.
        function test_aGpuThatWokeLeavesAGap() {
            const monitor = monitorWith({}, woken);
            const g = temperatureGraph(temperatureTiles(load("GpuPopup", monitor))[0]);
            const step = g.width / (monitor.historyLength - 1);
            compare(g.areas.length, 1);
            fuzzyCompare(g.areas[0][0].x, 25 * step, 1e-6);
            compare(g.pieces.length, 1);
            fuzzyCompare(g.pieces[0].points[0].x, 25 * step, 1e-6);
        }

        // A third longer in every string, at the page widths a popup takes,
        // plain and mirrored: the caption keeps its label, the scale shows
        // whole or not at all, both inside the tile and apart. Mirrored, the
        // line still runs from the oldest sample on the left to the newest on
        // the right, as the usage graph's does.
        function test_temperatureCaptionsFit_data() {
            const rows = [];
            for (const popup of ["CpuPopup", "GpuPopup", "DiskPopup"]) {
                for (const width of [Kirigami.Units.gridUnit * 20, Math.round(Kirigami.Units.gridUnit * 20 * 14 / 18)]) {
                    for (const mirrored of [false, true]) {
                        rows.push({ tag: popup + " " + width + " px" + (mirrored ? " mirrored" : ""), popup: popup, width: width,
                                    mirrored: mirrored });
                    }
                }
            }
            return rows;
        }

        function test_temperatureCaptionsFit(data) {
            root.longStrings = true;
            const popup = load(data.popup, monitorWith({ fahrenheit: true }), data.mirrored, data.width);
            const tiles = temperatureTiles(popup);
            verify(tiles.length > 0);
            tiles.forEach(tile => {
                const [caption, top] = captionLine(tile);
                checkCaptionLine(tile, caption, top, data.mirrored);
                const g = temperatureGraph(tile);
                const newest = g.plot.points[g.plot.points.length - 1];
                fuzzyCompare(newest.x, g.width, 1e-6, "the newest sample at the right");
                verify(g.plot.points[0].x < newest.x);
            });
        }

        // Every graph tile in every popup with a moving graph, at every span:
        // its caption names the span, which is its span control, and its
        // graph spans the points of that span from edge to edge, whatever
        // the pace of its readings. A minute draws its readings; an hour and
        // a day each bucket's average under a fainter band up to its highest
        // reading, and break off where the machine slept. No grid, and
        // nothing written on a graph, where a line could run through it.
        function test_graphsAtEachSpan_data() {
            const rows = [];
            for (const [popup, count] of [["CpuPopup", 2], ["GpuPopup", 3], ["MemoryPopup", 1], ["NetworkPopup", 1], ["DiskPopup", 3]]) {
                for (const span of ["minute", "hour", "day"]) {
                    rows.push({ tag: popup + " " + span, popup: popup, count: count, span: span, values: {},
                                length: { minute: 60, hour: 120, day: 144 }[span] });
                }
            }
            rows.push({ tag: "CpuPopup minute at 500 ms", popup: "CpuPopup", count: 2, span: "minute", values: { interval: 500 }, length: 120 });
            return rows;
        }

        function test_graphsAtEachSpan(data) {
            const label = { minute: "1 min", hour: "1 h", day: "1 day" }[data.span];
            const name = { minute: "1 minute", hour: "1 hour", day: "1 day" }[data.span];
            const monitor = monitorWith(data.values);
            monitor.chooseSpan(data.span);
            const popup = load(data.popup, monitor, false, widePage);
            const tiles = all(popup, i => i.visible && i.graphTop !== undefined && i.spans !== undefined && i.spans !== null);
            compare(tiles.length, data.count);
            for (const tile of tiles) {
                const span = spanOf(tile);
                verify(span.visible);
                compare(heading(tile), tile.caption.toLocaleUpperCase() + " · " + label);
                compare(span.Accessible.role, Accessible.ButtonMenu);
                compare(span.Accessible.name, "Graph span: " + name);
                const g = graphs(tile)[0] ?? temperatureGraph(tile);
                const points = g.drawn ? g.drawn.main : g.plot.points;
                const bands = g.drawn ? g.drawn.bands : g.bands;
                compare(points.length, data.length, tile.caption + " spans its points");
                fuzzyCompare(points[0].x, 0, 1e-6, "the oldest at the left");
                fuzzyCompare(points[points.length - 1].x, g.width, 1e-6, "the newest at the right");
                compare(all(g, i => i.visible && i.border !== undefined && i.radius !== undefined
                                    && !ancestor(i, a => a.limitY !== undefined)).length, 0, tile.caption + ": no grid");
                compare(all(g, i => typeof i.text === "string").length, 0, tile.caption + ": nothing written on the graph");
                if (data.span === "minute") {
                    compare(bands.length, 0, tile.caption + ": no band at a minute");
                } else {
                    verify(bands.length >= 2, tile.caption + ": a band either side of the gap, " + bands.length);
                    const runs = g.drawn ? g.drawn.runs : g.areas;
                    verify(runs.length >= 2, tile.caption + ": the line breaks off where the machine slept");
                }
            }
        }

        // At an hour or a day a rate graph's top is the highest one-second
        // reading behind any bucket, which the band reaches and the caption
        // names, so the peak holds as the span changes; the line is the
        // buckets' averages, under it.
        function test_ratePeaksAtLongSpansAreTheHighestSecond_data() {
            return [{ tag: "hour", span: "hour" }, { tag: "day", span: "day" }];
        }

        function test_ratePeaksAtLongSpansAreTheHighestSecond(data) {
            const monitor = monitorWith({});
            monitor.chooseSpan(data.span);
            const popup = load("DiskPopup", monitor, false, widePage);
            const read = graphs(popup)[0];
            const high = Math.max(...monitor.diskReadHighs.filter(v => Number.isFinite(v)));
            verify(high > Math.max(...monitor.diskReadHistory.filter(v => Number.isFinite(v))), "the highs run over the averages");
            compare(read.maximum, high);
            const r = Format.rate(high, false);
            compare(tileTop(read).text, "peak " + r.value + " " + r.unit);
            const bandTop = read.drawn.bands.reduce((m, b) => Math.min(m, ...b.map(p => p.y)), Infinity);
            fuzzyCompare(bandTop, read.topY, 1e-6, "the band reaches the top it names");
            const lineTop = read.drawn.runs.reduce((m, run) => Math.min(m, ...run.map(p => p.y)), Infinity);
            verify(lineTop > read.topY + 1, "the averages stay under it");

            const throughput = graphs(load("NetworkPopup", monitor, false, widePage))[0];
            const both = Math.max(...monitor.networkDownHighs.concat(monitor.networkUpHighs).filter(v => Number.isFinite(v)));
            compare(throughput.maximum, both, "the upload's highs count too");
            compare(throughput.drawn.secondRuns.length > 0, true, "the upload drawn");
        }

        // Upload is as strong as download and told from it by longer
        // dashes, and the legend draws a sample of each line by its name.
        function test_uploadLineAndLegend() {
            const popup = load("NetworkPopup", normal, false, widePage);
            const g = graphs(popup)[0];
            const dashed = [];
            for (const shape of all(g, i => i.preferredRendererType !== undefined)) {
                for (const path of shape.data) {
                    if (path.strokeStyle === ShapePath.DashLine) {
                        dashed.push(path);
                    }
                }
            }
            compare(dashed.length, 1, "the upload alone is dashed");
            compare(dashed[0].strokeColor, g.color, "at full strength");
            compare([...dashed[0].dashPattern], [3, 2]);
            const keys = all(popup, i => i.visible && i.dashed !== undefined && i.area !== undefined);
            compare(keys.map(k => [k.text, k.dashed, k.area]), [["Down", false, true], ["Up", true, false]]);
            keys.forEach(k => verify(all(k, i => i.preferredRendererType !== undefined)[0].width > 0, k.text + " has a sample"));
        }

        // A bucket alone between gaps, a GPU awake for ten minutes say, is a
        // level mark at least 3 px across rather than a speck, at an hour or
        // a day; at a minute a lone reading still draws nothing.
        function test_aLoneBucketIsAMark() {
            const lone = Array.from({ length: 144 }, (_, i) => i === 100 ? 40 : NaN);
            const monitor = monitorWith({ "gpuOuter.history": lone, "gpuOuter.highs": lone.map(v => v + 30) }, woken);
            monitor.chooseSpan("day");
            const g = graphs(load("GpuPopup", monitor))[0];
            compare(g.drawn.runs.length, 1);
            const run = g.drawn.runs[0];
            verify(run[1].x - run[0].x >= 3 - 1e-6, "at least 3 px: " + (run[1].x - run[0].x));
            compare(run[0].y, run[1].y, "level");
            compare(g.drawn.bands.length, 1, "with its band");
            monitor.chooseSpan("minute");
            monitor.gpuOuter.history = Array.from({ length: 60 }, (_, i) => i === 40 ? 40 : NaN);
            monitor.gpuOuter.highs = [];
            compare(graphs(load("GpuPopup", monitor))[0].drawn.runs.length, 0);
        }

        // A temperature graph's scale comes from every reading the three
        // spans keep, so it holds still when the span changes: up to the hot
        // threshold while every reading stays under it, to the hottest
        // rounded up to a five once one runs over. The caption names the
        // peak of the span on screen, its band's top included, and the rule
        // marks the hot threshold at every span, wherever it falls.
        function test_temperatureScaleHoldsAcrossSpans_data() {
            return [{ tag: "underHot", component: plain, extent: [44, 80], scaleTop: 90 },
                    { tag: "dayOverHot", component: hotDay, extent: [44, 93.4], scaleTop: 95, dayPeak: 93 }];
        }

        function test_temperatureScaleHoldsAcrossSpans(data) {
            const monitor = monitorWith({ cpuTemperatureExtent: data.extent }, data.component);
            const popup = load("CpuPopup", monitor, false, widePage);
            const tile = temperatureTiles(popup)[0];
            const g = temperatureGraph(tile);
            const rule = all(g, i => i.limitY !== undefined)[0];
            const hotY = g.topY + (1 - (90 - 30) / (data.scaleTop - 30)) * (g.height - g.topY - 0.75);
            for (const span of ["minute", "hour", "day", "minute"]) {
                monitor.chooseSpan(span);
                compare(tile.scaleTop, data.scaleTop, span);
                compare(tile.floor, 30, span);
                const peak = Math.max(...tile.history.concat(tile.highs).filter(c => Number.isFinite(c)));
                compare(captionLine(tile)[1].text, localized("peak " + Math.round(peak) + " °C"), span);
                if (span === "day" && data.dayPeak !== undefined) {
                    compare(Math.round(peak), data.dayPeak, "the day's peak, from its band");
                }
                verify(rule.visible, span + ": the rule");
                fuzzyCompare(rule.mapToItem(g, Qt.point(0, rule.limitY)).y, hotY, 1e-6, span + ": the rule at 90 °C");
                compare(g.bands.length > 0, span !== "minute", span + ": the band");
                const ys = g.plot.points.filter(p => Number.isFinite(p.y)).map(p => p.y);
                verify(Math.min(...ys) >= g.topY - 1e-6 && Math.max(...ys) <= g.height, span + ": inside the scale");
            }
        }

        // An hour's or a day's temperature takes the band too, in the
        // graph's own colour, fainter than the area under the line.
        function test_temperatureBand() {
            const monitor = monitorWith({});
            monitor.chooseSpan("hour");
            const tile = temperatureTiles(load("CpuPopup", monitor, false, widePage))[0];
            const g = temperatureGraph(tile);
            verify(g.bands.length > 0);
            const paths = all(g, i => i.preferredRendererType !== undefined)[0].data;
            compare(paths[0].pathElements[0].paths.length, g.bands.length);
            compare(String(Qt.alpha(paths[0].fillColor, 1)), String(Qt.alpha(Kirigami.Theme.textColor, 1)));
            verify(paths[0].fillColor.a < paths[1].fillColor.a, "fainter than the area");
            // The band's top is each bucket's highest reading.
            const run = g.bands[0];
            const top = Math.min(...run.map(p => p.y));
            verify(top < Math.min(...g.plot.points.filter(p => Number.isFinite(p.y)).map(p => p.y)) + 1e-6);
        }

        // The span opens its menu at a click: the three spans, the one shown
        // checked. Picking one changes every graph in the popup.
        function test_spanMenuByPointer_data() {
            return ["CpuPopup", "GpuPopup", "MemoryPopup", "NetworkPopup", "DiskPopup"].map(p => ({ tag: p, popup: p }));
        }

        function test_spanMenuByPointer(data) {
            const monitor = monitorWith({});
            const popup = load(data.popup, monitor, false, widePage);
            const span = spanOf(graphs(popup)[0]);
            const menu = span.menu;
            verify(!menu.visible);
            mouseClick(span);
            tryVerify(() => menu.opened, 2000, "the menu opens");
            compare(menu.count, 3);
            compare([0, 1, 2].map(i => menu.itemAt(i).text), ["1 minute", "1 hour", "1 day"]);
            compare([0, 1, 2].map(i => menu.itemAt(i).checked), [true, false, false]);
            mouseClick(menu.itemAt(2));
            tryVerify(() => !menu.visible, 2000, "it closes on a pick");
            compare(monitor.graphSpan, "day");
            const tiles = all(popup, i => i.visible && i.spans !== undefined && i.spans !== null);
            verify(tiles.length > 0);
            tiles.forEach(t => compare(spanOf(t).text, "1 day", t.caption));
            mouseClick(span);
            tryVerify(() => menu.opened, 2000);
            compare([0, 1, 2].map(i => menu.itemAt(i).checked), [false, false, true]);
            mouseClick(span);
            tryVerify(() => !menu.visible, 2000, "a second click closes it");
            compare(monitor.graphSpan, "day", "unchanged");
        }

        // From the keyboard: Space, Return or Down opens the menu on the span
        // shown, the arrows move, Return picks, Escape closes it unchanged,
        // and the focus comes back to the span with its ring.
        function test_spanMenuByKeyboard_data() {
            return [{ tag: "space", key: Qt.Key_Space }, { tag: "return", key: Qt.Key_Return }, { tag: "down", key: Qt.Key_Down }];
        }

        function test_spanMenuByKeyboard(data) {
            const monitor = monitorWith({});
            const host = createTemporaryObject(escapeHost, root, { width: widePage });
            host.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/CpuPopup.qml"), { monitor: monitor });
            const popup = host.item;
            waitForRendering(popup);
            const span = spanOf(graphs(popup)[0]);
            const menu = span.menu;
            span.forceActiveFocus(Qt.TabFocusReason);
            verify(span.visualFocus);
            keyClick(data.key);
            tryVerify(() => menu.opened, 2000, "opened from the keyboard");
            compare(menu.currentIndex, 0, "on the span shown");
            keyClick(Qt.Key_Down);
            compare(menu.currentIndex, 1);
            keyClick(Qt.Key_Return);
            tryVerify(() => !menu.visible, 2000);
            compare(monitor.graphSpan, "hour");
            tryVerify(() => span.activeFocus && span.visualFocus, 2000, "the focus is back, with its ring");
            compare(span.text, "1 h");
            keyClick(data.key);
            tryVerify(() => menu.opened, 2000);
            compare(menu.currentIndex, 1);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !menu.visible, 2000, "Escape closes it");
            compare(host.escapes, 0, "and not the popup");
            compare(monitor.graphSpan, "hour", "unchanged");
            tryVerify(() => span.activeFocus && span.visualFocus, 2000);
            keyClick(Qt.Key_Escape);
            compare(host.escapes, 1, "the next Escape is the popup's");
        }

        // Every graph's span is a stop in the popup's Tab order.
        function test_spansAreInTheTabOrder() {
            const popup = load("CpuPopup", normal, false, widePage);
            const spans = all(popup, i => i.objectName === "span" && i.visible);
            compare(spans.length, 2);
            spans.forEach(s => compare(s.focusPolicy, Qt.StrongFocus));
            spans[0].forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Tab);
            verify(spans[1].activeFocus, "Tab goes on to the temperature's");
        }

        // A third longer in every string, the page keeps its width and
        // nothing runs past it: long text elides or wraps, and the header's
        // reading keeps its full width while the subtitle gives way.
        function test_longTranslationsFit_data() {
            return [{ tag: "cpu", popup: "CpuPopup", monitor: normal }, { tag: "gpu", popup: "GpuPopup", monitor: normal },
                    { tag: "memory", popup: "MemoryPopup", monitor: normal }, { tag: "network", popup: "NetworkPopup", monitor: normal },
                    { tag: "disk", popup: "DiskPopup", monitor: normal }, { tag: "allDisks", popup: "DiskPopup", monitor: allDisks },
                    { tag: "cpuLongModel", popup: "CpuPopup", monitor: longModel }];
        }

        function test_longTranslationsFit(data) {
            const width = load(data.popup, normal).implicitWidth;
            root.longStrings = true;
            const popup = load(data.popup, data.monitor);
            verify(texts(popup).some(t => t.endsWith("ß")), "the pseudo-locale is on");
            compare(popup.implicitWidth, width, "the page keeps its width");
            compare(popup.width, width);
            const left = i => i.mapToItem(popup, Qt.point(0, 0)).x;
            all(popup, i => i.visible && typeof i.text === "string" && i.text !== "" && i.contentWidth !== undefined)
                .forEach(t => {
                    const drawn = t.elide !== Text.ElideNone || t.wrapMode !== Text.NoWrap ? t.width : Math.max(t.width, t.contentWidth);
                    verify(left(t) >= -0.5 && left(t) + drawn <= popup.width + 0.5,
                           t.text + " at " + left(t) + " to " + (left(t) + drawn) + " of " + popup.width);
                });
            readings(popup).filter(r => r.visible).forEach(r => {
                verify(r.width >= r.implicitWidth - 0.5, r.value + " " + r.unit + " squeezed to " + r.width);
            });
            const header = headerOf(popup);
            const subtitle = shownText(header, header.subtitle);
            const value = readings(header).find(r => r.visible);
            if (subtitle && value) {
                verify(left(subtitle) + subtitle.width <= left(value) + 0.5, "the subtitle stops short of the reading");
            }
        }
    }
}
