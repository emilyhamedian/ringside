// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami

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

        function load(popup, monitor) {
            const loader = createTemporaryObject(host, root);
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
    }
}
