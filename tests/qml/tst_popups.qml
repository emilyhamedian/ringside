// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui/code/style.js" as Style

// Every popup against FakeMonitor in the states the gallery shows, loaded the
// way main.qml loads them. qmllint can't type the duck-typed monitor, so a
// script error in a popup binding, such as a JavaScript builtin Qt's engine
// lacks, only shows up at run time; any such warning fails the test.

Item {
    id: root
    width: 800
    height: 900

    // A bare qml runtime has no KI18n; the views find these on the root.
    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
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

    // No pressure stall information and no swap.
    FakeMonitor {
        id: bare
        memoryPressure: NaN
        swapUsed: 0
        swapTotal: 0
        swapLabel: ""
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

        // The temperature unit is as small as the caption under it and sits
        // against the digits, in the header and in the GPU rows alike.
        function test_temperatureUnitSizeAndGap_data() {
            return [{ tag: "celsius", fahrenheit: false, unit: "°C" }, { tag: "fahrenheit", fahrenheit: true, unit: "°F" }];
        }

        function test_temperatureUnitSizeAndGap(data) {
            normal.fahrenheit = data.fahrenheit;
            for (const popup of ["CpuPopup", "GpuPopup"]) {
                const temperatures = readings(load(popup, normal)).filter(r => r.visible && r.degreeUnit !== "");
                verify(temperatures.length > 0, popup);
                temperatures.forEach(r => {
                    const p = parts(r);
                    const tag = popup + " " + p.number.text;
                    compare(p.suffix.text, data.unit, tag);
                    compare(p.suffix.font.pointSize, Kirigami.Theme.smallFont.pointSize, tag);
                    const gap = p.suffix.x - (p.number.x + p.number.implicitWidth);
                    verify(gap >= 0 && gap <= 1.5, tag + " gap " + gap);
                    compare(r.implicitWidth, p.number.implicitWidth + gap + p.suffix.implicitWidth, tag);
                    compare(p.suffix.y + p.suffix.baselineOffset, p.number.y + p.number.baselineOffset, tag + " shares the baseline");
                });
            }
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
    }
}
