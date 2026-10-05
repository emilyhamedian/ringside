// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui/code/format.js" as Format
import "../../package/contents/ui/code/style.js" as Style

// Every popup against FakeMonitor in the states the gallery shows, loaded the
// way main.qml loads them. qmllint can't type the duck-typed monitor, so a
// script error in a popup binding, such as a JavaScript builtin Qt's engine
// lacks, only shows up at run time; any such warning fails the test.

Item {
    id: root
    width: 800
    height: 900

    // Set by the long-translations test: every string comes back about a
    // third longer, as German and the Romance languages often run.
    property bool pseudo: false

    // A bare qml runtime has no KI18n; the views find these on the root.
    function substitute(text, args) {
        const s = text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
        return pseudo ? s + "ß".repeat(Math.round(s.length * 0.35)) : s;
    }
    function i18n(text, ...args) { return substitute(text, args); }
    function i18nc(context, text, ...args) { return substitute(text, args); }
    function i18np(s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }
    function i18ncp(c, s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }

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
        gpuInner.vramTotal: NaN
        gpuInner.knownVramTotal: NaN
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

    // Just opened: no rate has a sample yet.
    FakeMonitor {
        id: fresh
        networkDownHistory: []
        networkUpHistory: []
        diskReadHistory: []
        diskWriteHistory: []
    }

    // Measures a Text's ink, which a Text doesn't report.
    TextMetrics {
        id: probe
    }

    FontMetrics {
        id: fontProbe
    }

    Component {
        id: host
        Loader {}
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

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }

        function test_popup_data() {
            return [
                { tag: "cpu", popup: "CpuPopup", monitor: normal },
                { tag: "cpuHot", popup: "CpuPopup", monitor: hot },
                { tag: "cpuManyThreads", popup: "CpuPopup", monitor: manyThreads },
                { tag: "gpu", popup: "GpuPopup", monitor: normal },
                { tag: "gpuAsleep", popup: "GpuPopup", monitor: asleep },
                { tag: "gpuResting", popup: "GpuPopup", monitor: resting },
                { tag: "gpuIntegratedOnly", popup: "GpuPopup", monitor: integrated },
                { tag: "gpuInnerAsleep", popup: "GpuPopup", monitor: innerAsleep },
                { tag: "gpuIntel", popup: "GpuPopup", monitor: intel },
                { tag: "memory", popup: "MemoryPopup", monitor: normal },
                { tag: "memoryWithoutPressureOrSwap", popup: "MemoryPopup", monitor: bare },
                { tag: "network", popup: "NetworkPopup", monitor: normal }
            ];
        }
        function test_popup(data) {
            const loader = createTemporaryObject(host, root);
            verify(loader);
            loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/" + data.popup + ".qml"),
                             { monitor: data.monitor });
            compare(loader.status, Loader.Ready);
            waitForRendering(loader.item);
            verify(loader.item.implicitWidth > 0);
            verify(loader.item.implicitHeight > 0);
        }

        function load(popup, monitor, mirrored) {
            const loader = createTemporaryObject(mirrored ? mirroredHost : host, root);
            loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/" + popup + ".qml"), { monitor: monitor });
            waitForRendering(loader.item);
            return loader.item;
        }

        function texts(item) {
            const found = [];
            const collect = i => {
                if (i.visible && typeof i.text === "string" && i.text !== "") {
                    found.push(i.text);
                }
                i.children.forEach(collect);
            };
            collect(item);
            return found;
        }

        // A sleeping GPU is one line under the awake one, not a section.
        function test_aSleepingGpuIsOneLine() {
            const found = texts(load("GpuPopup", asleep));
            verify(found.includes("AMD Radeon RX 7700S · off"), JSON.stringify(found));
            verify(!found.some(t => t.indexOf("Powered down") >= 0), JSON.stringify(found));
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

        // The header ring, and the GPU popup's ring per GPU, take the level
        // colours at 75 % and 90 % of their own reading, in the arc they draw.
        function test_popupRingsTakeTheLevelColours_data() {
            return [{ tag: "74", value: 74, tone: "text" }, { tag: "75", value: 75, tone: "neutral" },
                    { tag: "89", value: 89, tone: "neutral" }, { tag: "90", value: 90, tone: "negative" }];
        }

        function test_popupRingsTakeTheLevelColours(data) {
            const expected = data.tone === "negative" ? Kirigami.Theme.negativeTextColor
                           : data.tone === "neutral" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
            normal.cpuUsage = data.value;
            normal.gpuOuter.usage = data.value;
            const cpu = gauges(load("CpuPopup", normal));
            verify(cpu.length > 0);
            compare(cpu[0].outerTone, expected);
            compare(outerArc(cpu[0]).color, expected, "the header ring as drawn");
            const gpu = gauges(load("GpuPopup", normal)).filter(g => g.value === data.value);
            verify(gpu.length > 0, "the discrete GPU's ring");
            gpu.forEach(g => {
                compare(g.outerTone, expected);
                compare(outerArc(g).color, expected, "the discrete GPU's ring as drawn");
            });
            normal.cpuUsage = 23;
            normal.gpuOuter.usage = Qt.binding(() => normal.gpuOuter.live ? 12 : normal.gpuOuter.resting ? 0 : NaN);
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
            compare(cpu[0].text, "23%");
            compare(cpu[0].strokeWidth, 4);
            const cpuText = centreText(cpu[0]);
            verify(cpuText, "the header ring's centre text");
            verify(cpuText.visible, "the header ring shows its percentage");
            compare(cpuText.text, "23%");
            compare(names(cpu[0]), []);
            // At 52 px the panel's default stroke is also 4; a larger ring
            // tells an explicit stroke from the default.
            cpu[0].Layout.preferredWidth = 80;
            tryCompare(cpu[0], "width", 80);
            compare(cpu[0].strokeWidth, 4, "the header ring's stroke at any size");

            // The GPU popup's header hides its ring.
            const gpu = gauges(load("GpuPopup", normal)).filter(g => g.visible);
            compare(gpu.map(g => g.value), [12, 3], "a ring per GPU");
            gpu.forEach(g => {
                const tag = "the ring at " + g.value + "%";
                compare(g.text, g.value + "%", tag);
                compare(g.strokeWidth, 3.5, tag);
                const text = centreText(g);
                verify(text, tag);
                verify(text.visible, tag + " shows its percentage");
                compare(names(g), [], tag);
                g.Layout.preferredWidth = 80;
                tryCompare(g, "width", 80);
                compare(g.strokeWidth, 3.5, tag + " keeps its stroke at any size");
            });
        }

        function test_popupsSpellTheTemperatureUnit_data() {
            return [{ tag: "celsius", fahrenheit: false, unit: "°C" }, { tag: "fahrenheit", fahrenheit: true, unit: "°F" }];
        }

        function test_popupsSpellTheTemperatureUnit(data) {
            normal.fahrenheit = data.fahrenheit;
            for (const popup of ["CpuPopup", "GpuPopup"]) {
                const found = texts(load(popup, normal));
                verify(found.includes(data.unit), popup + " " + JSON.stringify(found));
            }
            const disk = texts(load("NetworkPopup", normal));
            verify(disk.some(t => t.endsWith(" " + data.unit)), JSON.stringify(disk));
            normal.fahrenheit = false;
        }

        // Every item under `item` that `test` accepts, outside any gauge when
        // `skipGauges` is set.
        function all(item, test, skipGauges) {
            const found = [];
            const collect = i => {
                if (skipGauges && i.outerTone !== undefined) {
                    return;
                }
                if (test(i)) {
                    found.push(i);
                }
                i.children.forEach(collect);
            };
            collect(item);
            return found;
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

        // The temperature unit is as small as the caption under it and sits
        // against the digits, in the header and in the GPU rows alike. At one
        // size it is as far from the ink after a tabular "1" (61, 41) as
        // after any other digit (60, 48).
        function test_temperatureUnitSizeAndGap_data() {
            return [{ tag: "celsius", fahrenheit: false, unit: "°C" }, { tag: "fahrenheit", fahrenheit: true, unit: "°F" }];
        }

        function test_temperatureUnitSizeAndGap(data) {
            normal.fahrenheit = data.fahrenheit;
            const inkGaps = { CpuPopup: [], GpuPopup: [] };
            for (const [popup, cpuTemperature] of [["CpuPopup", 61], ["CpuPopup", 60], ["GpuPopup", 61]]) {
                normal.cpuTemperature = cpuTemperature;
                const temperatures = readings(load(popup, normal)).filter(r => r.visible && r.degreeUnit !== "");
                verify(temperatures.length > 0, popup);
                temperatures.forEach(r => {
                    const p = parts(r);
                    const tag = popup + " " + p.number.text;
                    compare(p.suffix.text, data.unit, tag);
                    compare(p.suffix.font.pointSize, Kirigami.Theme.smallFont.pointSize, tag);
                    const gap = p.suffix.x - (p.number.x + p.number.implicitWidth);
                    const inkGap = gap + trailingRoom(p.number);
                    verify(inkGap >= 0 && inkGap <= 3, tag + " is " + inkGap + " from the ink");
                    inkGaps[popup].push(inkGap);
                    compare(r.implicitWidth, p.number.implicitWidth + gap + p.suffix.implicitWidth, tag);
                    compare(p.suffix.y + p.suffix.baselineOffset, p.number.y + p.number.baselineOffset, tag + " shares the baseline");
                });
            }
            for (const gaps of [inkGaps.CpuPopup, inkGaps.GpuPopup]) {
                compare(gaps.length, 2);
                fuzzyCompare(gaps[1], gaps[0], 0.5);
            }
            normal.cpuTemperature = 61;
            normal.fahrenheit = false;
        }

        // A missing temperature is a bare dash.
        function test_missingTemperatureHasNoUnit() {
            normal.cpuTemperature = NaN;
            const header = readings(load("CpuPopup", normal)).filter(r => r.degreeUnit !== "");
            compare(header.length, 1);
            compare(parts(header[0]).number.text, "–");
            verify(!parts(header[0]).suffix.visible);
            compare(header[0].implicitWidth, parts(header[0]).number.implicitWidth);
            normal.cpuTemperature = 61;
        }

        // The header's caption lines up with the reading's digits, the unit
        // hanging past them. Under RTL the reading stays left to right, so
        // the caption starts where the digits do.
        function test_headerCaptionUnderTheDigits_data() {
            return [{ tag: "plain", mirrored: false }, { tag: "mirrored", mirrored: true }];
        }

        function test_headerCaptionUnderTheDigits(data) {
            const popup = load("CpuPopup", normal, data.mirrored);
            const headline = readings(popup).find(r => r.visible && r.degreeUnit !== "" && r.parent.parent.partsShown !== undefined);
            verify(headline);
            const caption = Array.from(headline.parent.children).find(i => i.visible && typeof i.text === "string" && i.text !== "");
            verify(caption);
            const digits = headline.mapToItem(popup, 0, 0).x;
            const left = caption.mapToItem(popup, 0, 0).x;
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
                    { tag: "memory", popup: "MemoryPopup" }, { tag: "network", popup: "NetworkPopup" }];
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
            const numbers = all(popup, i => i.visible && typeof i.text === "string" && /^[0-9.,–]+%?$/.test(i.text) && i.font !== undefined, true);
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
            rest.forEach(t => {
                verify(t.Accessible.ignored);
                compare(t.font.pointSize, Style.unitPointSize(first[0].pointSize, Kirigami.Theme.smallFont.pointSize));
                compare(String(t.color), String(Style.dim(Kirigami.Theme.textColor)));
                compare(t.y + t.baselineOffset, first[0].y + first[0].baselineOffset, "on the reading's baseline");
            });
            const x = i => i.mapToItem(tile, 0, 0).x;
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
        // against its number, and the values lined up at the row's end.
        function test_processValuesAreReadings_data() {
            return [{ tag: "cpu", popup: "CpuPopup", units: ["%", "%", "%"], values: ["8.4", "3.1", "2.6"] },
                    { tag: "memory", popup: "MemoryPopup", units: ["GiB", "MiB", "MiB"], values: ["3.9", "620", "410"] }];
        }

        function test_processValuesAreReadings(data) {
            for (const mirrored of [false, true]) {
                const popup = load(data.popup, normal, mirrored);
                const list = all(popup, i => i.key !== undefined && i.threads !== undefined && i.rows !== undefined)[0];
                verify(list);
                compare(list.Layout.bottomMargin, Math.round(Kirigami.Units.largeSpacing * 1.25));
                const values = readings(list);
                compare(values.map(r => r.value), data.values);
                compare(values.map(r => r.unit), data.units);
                const edge = r => r.mapToItem(list, 0, 0).x + (mirrored ? 0 : r.width);
                values.forEach(r => {
                    const p = parts(r);
                    compare(p.suffix.font.pointSize, Style.unitPointSize(r.pointSize, Kirigami.Theme.smallFont.pointSize), r.value);
                    compare(String(p.suffix.color), String(Style.dim(Kirigami.Theme.textColor)), "a dim unit");
                    if (r.unit === "%") {
                        compare(p.suffix.x, p.number.implicitWidth, "the percent sign against its number");
                    }
                    compare(edge(r), edge(values[0]), "lined up");
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
            return all(item, i => i.ceiling !== undefined && i.mainPoints !== undefined);
        }

        function ruleOf(graph) {
            return graph.children.filter(c => c.preferEnd !== undefined && c.limitY !== undefined)[0];
        }

        function ruleLabel(rule) {
            return rule.children.filter(c => typeof c.text === "string")[0];
        }

        function tileCaption(graph) {
            const tile = ancestor(graph, i => i.graphNote !== undefined);
            return all(tile, i => i.label !== undefined && i.detail !== undefined)[0];
        }

        // No grid: a percentage graph has its labelled 100 % rule, with a
        // full smallSpacing over the label, and a rate graph, which has no
        // natural top, rises to its peak where that rule would be and names
        // the peak in its caption.
        function test_graphsHaveARuleOrAPeak_data() {
            return [{ tag: "cpu", popup: "CpuPopup", ceilings: 1, peaks: 0 },
                    { tag: "gpu", popup: "GpuPopup", ceilings: 2, peaks: 0 },
                    { tag: "memory", popup: "MemoryPopup", ceilings: 1, peaks: 0 },
                    { tag: "network", popup: "NetworkPopup", ceilings: 0, peaks: 3 }];
        }

        function test_graphsHaveARuleOrAPeak(data) {
            const found = graphs(load(data.popup, normal)).filter(g => g.visible);
            compare(found.filter(g => g.ceiling).length, data.ceilings);
            compare(found.filter(g => !g.ceiling).length, data.peaks);
            found.forEach(g => {
                const rule = ruleOf(g);
                verify(rule, "a LimitRule");
                compare(g.topY, rule.limitY, "the top is where the rule goes");
                const lines = all(g, i => i.visible && i.border !== undefined && i.radius !== undefined
                                          && !ancestor(i, a => a === rule));
                compare(lines.length, 0, "no grid");
                const caption = tileCaption(g);
                if (g.ceiling) {
                    verify(rule.visible);
                    const label = ruleLabel(rule);
                    compare(label.text, "100%");
                    probe.font = label.font;
                    probe.text = label.text;
                    const inkTop = label.y + label.baselineOffset + probe.tightBoundingRect.y;
                    verify(inkTop >= Kirigami.Units.smallSpacing - 1, "room over the label: " + inkTop);
                    verify(caption.text.indexOf("peak") < 0, caption.text);
                } else {
                    verify(!rule.visible);
                    const top = g.mainPoints.concat(g.secondPoints).reduce((m, p) => Math.min(m, p.y), Infinity);
                    fuzzyCompare(top, g.topY, 0.001, "the peak lands where 100 % would");
                    verify(/ · peak \S+ \S+$/.test(caption.text), caption.text);
                }
            });
        }

        // The disk tiles name their peak in the caption, the way Throughput
        // does, and nowhere else; before the first sample they say nothing.
        function test_diskPeaksInTheCaption() {
            const peak = (samples, bits) => {
                const r = Format.rate(Math.max(...samples), bits);
                return "peak " + r.value + " " + r.unit;
            };
            const expected = {
                Throughput: "THROUGHPUT · 60 s · " + peak(normal.networkDownHistory.concat(normal.networkUpHistory), true),
                Read: "READ · " + peak(normal.diskReadHistory, false),
                Write: "WRITE · " + peak(normal.diskWriteHistory, false)
            };
            const popup = load("NetworkPopup", normal);
            const found = graphs(popup).map(tileCaption);
            compare(found.map(c => c.text), [expected.Throughput, expected.Read, expected.Write]);
            verify(!texts(popup).some(t => t.indexOf("Peak") >= 0), JSON.stringify(texts(popup)));

            const empty = graphs(load("NetworkPopup", fresh)).map(tileCaption);
            compare(empty.map(c => c.text), ["THROUGHPUT · 60 s", "READ", "WRITE"]);
        }

        // The rule's label keeps to its end unless a line runs through it
        // there; preferEnd starts it at the right.
        function test_ruleLabelEnd_data() {
            const high = 2;
            const low = 38;
            return [{ tag: "empty", preferEnd: false, series: [], atStart: true },
                    { tag: "emptyPreferEnd", preferEnd: true, series: [], atStart: false },
                    { tag: "highAtTheStart", preferEnd: false, series: [[{ x: 0, y: high }, { x: 200, y: low }]], atStart: false },
                    { tag: "highAtTheEnd", preferEnd: true, series: [[{ x: 0, y: low }, { x: 200, y: high }]], atStart: true },
                    { tag: "highAtBothEnds", preferEnd: true, series: [[{ x: 0, y: high }, { x: 100, y: low }, { x: 200, y: high }]], atStart: false }];
        }

        function test_ruleLabelEnd(data) {
            const loader = createTemporaryObject(host, root, { width: 200, height: 40 });
            loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/LimitRule.qml"),
                             { preferEnd: data.preferEnd, series: data.series });
            const rule = loader.item;
            compare(rule.width, 200);
            compare(rule.atStart, data.atStart);
            const label = ruleLabel(rule);
            compare(label.x, data.atStart ? 0 : rule.width - label.implicitWidth);
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
            tryVerify(() => entries[0].y === entries[2].y, 1000, "one line");
            // The bar's own mapping would include its mirroring flip.
            const left = i => i.parent.mapToItem(popup, i.x, 0).x;
            const right = i => left(i) + i.width;
            // In reading order, each entry's far edge to the next one's near edge.
            const [start, end] = data.mirrored ? [right, left] : [left, right];
            const gap = (a, b) => Math.abs(start(b) - end(a));
            compare(start(entries[0]), start(bar));
            verify(Math.abs(end(entries[2]) - end(bar)) <= 1, "Free ends at the bar's end: " + end(entries[2]) + " " + end(bar));
            compare(gap(entries[0], entries[1]), gap(entries[1], entries[2]));
            verify(gap(entries[0], entries[1]) > Kirigami.Units.largeSpacing, "spread wider than the minimum spacing");
        }

        // A sparse line can run over the label between two points of which
        // only the low one lies under it.
        function test_ruleLabelSegment() {
            const loader = createTemporaryObject(host, root, { width: 200, height: 40 });
            loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/LimitRule.qml"));
            const rule = loader.item;
            const x = rule.span + 4;
            rule.series = [[{ x: 0, y: rule.height }, { x: x, y: 0 }]];
            verify(rule.height * (x - rule.span) / x < rule.labelBottom, "the segment crosses the label's end above it");
            compare(rule.atStart, false);
            rule.series = [[{ x: 0, y: rule.height }, { x: x, y: rule.labelBottom * x / rule.span }]];
            compare(rule.atStart, true, "a line that stays below keeps the label at the start");
        }

        function headerOf(popup) {
            return all(popup, i => i.partsShown !== undefined)[0];
        }

        function shownText(item, text) {
            return all(item, i => i.visible && i.text === text && i.font !== undefined)[0];
        }

        function baselineY(text, popup) {
            return text.mapToItem(popup, 0, text.baselineOffset).y;
        }

        // The header's two columns centre on the ring each by its own height;
        // the caption still shares the subtitle's baseline.
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

        // A tile's caption sits half its line's leading closer to the top
        // than the padding alone would put it, so its capitals are about as
        // far from the top as the content from the bottom.
        function test_tilePadding_data() {
            return [{ tag: "cpu", popup: "CpuPopup" }, { tag: "gpu", popup: "GpuPopup" },
                    { tag: "memory", popup: "MemoryPopup" }, { tag: "network", popup: "NetworkPopup" }];
        }

        function test_tilePadding(data) {
            const tiles = all(load(data.popup, normal), i => i.visible && i.graphNote !== undefined);
            verify(tiles.length > 0);
            tiles.forEach(tile => {
                const caption = all(tile, i => i.label !== undefined && i.detail !== undefined)[0];
                verify(caption.visible, tile.caption);
                fontProbe.font = caption.font;
                probe.font = caption.font;
                probe.text = "H";
                // Qt 6.9 and later give the font's own capital height, which
                // can differ a little from the ink of an "H".
                fuzzyCompare(tile.capHeight, probe.tightBoundingRect.height, 1, tile.caption + " cap height");
                const leading = fontProbe.ascent - tile.capHeight;
                verify(leading / 2 > 1, "enough leading to tell: " + leading);
                const capTop = caption.mapToItem(tile, 0, caption.baselineOffset).y - tile.capHeight;
                // Rounding to whole pixels is the only slack.
                fuzzyCompare(capTop, tile.verticalPadding + leading / 2, 0.5, tile.caption + " cap top");
                const column = caption.parent;
                compare(tile.height - (column.y + column.height), tile.verticalPadding, tile.caption + " bottom");
            });
        }

        // The header, the tiles' boxes, the Disk caption, the dividers and
        // the process list all start and end on one edge.
        function test_contentEdges_data() {
            const popups = [["cpu", "CpuPopup"], ["gpu", "GpuPopup"], ["memory", "MemoryPopup"], ["network", "NetworkPopup"]];
            const rows = [];
            popups.forEach(([tag, popup]) => {
                rows.push({ tag: tag, popup: popup, mirrored: false });
                rows.push({ tag: tag + "Mirrored", popup: popup, mirrored: true });
            });
            return rows;
        }

        function test_contentEdges(data) {
            const popup = load(data.popup, normal, data.mirrored);
            const edge = Math.round(Kirigami.Units.largeSpacing * 2);
            const left = i => i.mapToItem(popup, 0, 0).x;
            const right = i => left(i) + i.width;
            const spanning = [headerOf(popup)]
                .concat(all(popup, i => i.visible && i.key !== undefined && i.threads !== undefined))
                .concat(all(popup, i => i.visible && i.height === 1 && i.radius !== undefined && i.parent === popup.children[0]))
                .concat(all(popup, i => i.visible && i.height === 1 && i.radius !== undefined && i.inner !== undefined));
            spanning.forEach(i => {
                compare(left(i), edge, String(i));
                compare(right(i), popup.width - edge, String(i));
            });
            const tiles = all(popup, i => i.visible && i.graphNote !== undefined);
            compare(Math.min(...tiles.map(left)), edge, "the tiles' near edge");
            compare(Math.max(...tiles.map(right)), popup.width - edge, "the tiles' far edge");
            const disk = all(popup, i => i.visible && i.label === "Disk")[0];
            if (data.popup === "NetworkPopup") {
                verify(disk);
                compare(data.mirrored ? right(disk) : left(disk), data.mirrored ? popup.width - edge : edge, "the Disk caption");
            }
        }

        // Dividers in a popup's body are inset to the content's edge and
        // equally faint.
        function test_dividers_data() {
            return [{ tag: "cpu", popup: "CpuPopup", monitor: normal },
                    { tag: "memory", popup: "MemoryPopup", monitor: normal },
                    { tag: "gpu", popup: "GpuPopup", monitor: normal },
                    { tag: "gpuAsleep", popup: "GpuPopup", monitor: asleep }];
        }

        function test_dividers(data) {
            const popup = load(data.popup, data.monitor);
            const found = all(popup, i => i.visible && i.height === 1 && i.radius !== undefined && i.width > 0
                                          && !ancestor(i, a => a.ceiling !== undefined));
            compare(found.length, 1);
            const edge = Math.round(Kirigami.Units.largeSpacing * 2);
            const divider = found[0];
            compare(divider.mapToItem(popup, 0, 0).x, edge);
            compare(divider.width, popup.width - 2 * edge);
            compare(String(divider.color), String(Qt.alpha(Kirigami.Theme.textColor, 0.08)));
        }

        // The rates in the header at the tiles' size: the arrows in a column
        // that follows the layout, and each number and its unit left to right,
        // the numbers ending on one line and the units starting on one.
        function test_networkHeader_data() {
            return [{ tag: "plain", mirrored: false }, { tag: "mirrored", mirrored: true }];
        }

        function test_networkHeader(data) {
            const popup = load("NetworkPopup", normal, data.mirrored);
            const rates = all(popup, i => i.pairWidth !== undefined)[0];
            verify(rates);
            const values = readings(rates);
            compare(values.length, 2);
            const arrows = all(rates, i => i.up !== undefined && i.color !== undefined);
            compare(arrows.map(a => a.up), [false, true]);
            const x = i => i.mapToItem(popup, 0, 0).x;
            const down = Format.rate(normal.networkDown, true);
            const up = Format.rate(normal.networkUp, true);
            compare(values.map(r => r.value + " " + r.unit), [down.value + " " + down.unit, up.value + " " + up.unit]);
            compare(rates.Accessible.name, "Down " + down.value + " " + down.unit + ", up " + up.value + " " + up.unit);
            normal.networkDown = NaN;
            compare(rates.Accessible.name, "Down unavailable, up " + up.value + " " + up.unit);
            normal.networkDown = 3.1e6;
            const ends = [];
            const starts = [];
            values.forEach((r, n) => {
                compare(r.pointSize, Kirigami.Theme.defaultFont.pointSize * 1.38);
                verify(r.accessibleIgnored);
                const p = parts(r);
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
            const cpu = headerOf(load("CpuPopup", normal));
            verify(headerOf(popup).implicitHeight <= cpu.implicitHeight, "no taller than a header with a ring");
        }

        // The totals since boot lead with their arrows, as the rates do.
        function test_sinceBoot() {
            const down = Format.bytes(normal.networkTotalDown);
            const up = Format.bytes(normal.networkTotalUp);
            const expected = "Since boot ↓ " + down.value + " " + down.unit + " · ↑ " + up.value + " " + up.unit;
            const found = texts(load("NetworkPopup", normal));
            verify(found.includes(expected), JSON.stringify(found));
        }

        // With two GPUs each section names its kind, so the header doesn't.
        function test_gpuSubtitle_data() {
            return [{ tag: "two", monitor: normal, subtitle: "" },
                    { tag: "twoOneAsleep", monitor: innerAsleep, subtitle: "" },
                    { tag: "intel", monitor: intel, subtitle: "" },
                    { tag: "integratedOnly", monitor: integrated, subtitle: "Integrated" },
                    { tag: "discreteOnly", monitor: discreteOnly, subtitle: "Discrete" }];
        }

        function test_gpuSubtitle(data) {
            const popup = load("GpuPopup", data.monitor);
            compare(headerOf(popup).subtitle, data.subtitle);
            const found = texts(popup);
            verify(!found.some(t => t.indexOf("Discrete · ") >= 0 || t.indexOf("Integrated · ") >= 0), JSON.stringify(found));
        }

        // Temperature sensors go by plain words, not their hwmon labels;
        // labels Words doesn't know are shown as they are.
        function test_sensorNamesInWords_data() {
            return [{ tag: "Tctl", raw: "Tctl", shown: "chip" },
                    { tag: "Tdie", raw: "Tdie", shown: "chip" },
                    { tag: "Package id 0", raw: "Package id 0", shown: "chip" },
                    { tag: "Package id 1", raw: "Package id 1", shown: "chip" },
                    { tag: "edge", raw: "edge", shown: "chip" },
                    { tag: "Tccd1", raw: "Tccd1", shown: "chiplet " + Format.whole(1) },
                    { tag: "Tccd12", raw: "Tccd12", shown: "chiplet " + Format.whole(12) },
                    { tag: "junction", raw: "junction", shown: "hotspot" },
                    { tag: "mem", raw: "mem", shown: "memory" },
                    { tag: "Composite", raw: "Composite", shown: "Composite" },
                    { tag: "Core 0", raw: "Core 0", shown: "Core 0" },
                    { tag: "Tccd", raw: "Tccd", shown: "Tccd" },
                    { tag: "edges", raw: "edges", shown: "edges" },
                    { tag: "hottest core", raw: "hottest core", shown: "hottest core" },
                    { tag: "none", raw: "", shown: "" }];
        }

        function test_sensorNamesInWords(data) {
            const component = Qt.createComponent(Qt.resolvedUrl("../../package/contents/ui/Words.qml"));
            compare(component.status, Component.Ready, component.errorString());
            const words = createTemporaryObject(component, root, { monitor: normal });
            compare(words.sensorName(data.raw), data.shown);
        }

        // The CPU caption and the GPU rows show the plain words.
        function test_popupsNameTheirSensors_data() {
            return [{ tag: "usual", monitor: normal, cpu: "chip", gpu: ["chip", "chip"] },
                    { tag: "other", monitor: otherSensors, cpu: "chiplet " + Format.whole(3), gpu: ["hotspot", "memory"] }];
        }

        function test_popupsNameTheirSensors(data) {
            const cpu = load("CpuPopup", data.monitor);
            const header = headerOf(cpu);
            compare(header.caption, data.cpu);
            verify(shownText(header, data.cpu), "the caption is shown");
            const gpu = load("GpuPopup", data.monitor);
            const found = texts(gpu);
            compare(found.filter(t => t === data.gpu[0] || t === data.gpu[1]).length, 2, JSON.stringify(found));
            data.gpu.forEach(name => verify(found.includes(name), name + " in " + JSON.stringify(found)));
            const raw = ["Tctl", "Tccd3", "edge", "junction", "mem"];
            verify(!texts(cpu).concat(found).some(t => raw.includes(t)), "no raw label is shown");
        }

        // A third longer in every string, the page keeps its width and
        // nothing runs past it: long text elides or wraps, and the header's
        // reading keeps its full width while the subtitle gives way.
        function test_longTranslationsFit_data() {
            return [{ tag: "cpu", popup: "CpuPopup", monitor: normal }, { tag: "gpu", popup: "GpuPopup", monitor: normal },
                    { tag: "memory", popup: "MemoryPopup", monitor: normal }, { tag: "network", popup: "NetworkPopup", monitor: normal },
                    { tag: "cpuLongModel", popup: "CpuPopup", monitor: longModel }];
        }

        function test_longTranslationsFit(data) {
            const width = load(data.popup, normal).implicitWidth;
            root.pseudo = true;
            try {
                const popup = load(data.popup, data.monitor);
                verify(texts(popup).some(t => t.endsWith("ß")), "the pseudo-locale is on");
                compare(popup.implicitWidth, width, "the page keeps its width");
                compare(popup.width, width);
                const left = i => i.mapToItem(popup, 0, 0).x;
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
            } finally {
                root.pseudo = false;
            }
        }
    }
}
