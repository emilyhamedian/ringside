// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"

// The panel strip with FakeMonitor's readings: its width holds while values
// change, a thin vertical panel's rates fit, and every cell describes its
// readings in words.
Item {
    id: root
    width: 800
    height: 600

    readonly property color hotColor: Kirigami.Theme.negativeTextColor

    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (match, n) => n <= args.length ? String(args[n - 1]) : match);
    }
    function i18nc(context, text, ...args) {
        return substitute(text, args);
    }
    function i18ncp(context, singular, plural, n, ...args) {
        return substitute(n === 1 ? singular : plural, [n].concat(args));
    }

    Component {
        id: monitorComponent
        FakeMonitor {}
    }

    Component {
        id: stripComponent
        Strip {
            items: ["cpu", "gpu", "memory", "network", "disk"]
            vertical: false
            thickness: 46
            ringSize: 30
            ringsOnly: []
        }
    }

    TestCase {
        id: testCase
        name: "Strip"
        when: windowShown

        property var monitor: null
        property var strip: null

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            monitor = monitorComponent.createObject(testCase);
        }

        // The strip goes first, so its bindings never see the monitor gone.
        function cleanup() {
            strip?.destroy();
            wait(0);
            monitor.destroy();
            strip = null;
        }

        function makeStrip(properties) {
            strip = stripComponent.createObject(root, Object.assign({ monitor: monitor }, properties));
            waitForRendering(strip);
            return strip;
        }

        // Layouts settle on the next polish, so read after a render.
        function widthAfter(strip, change) {
            change();
            waitForRendering(strip);
            return strip.implicitWidth;
        }

        function test_widthHoldsAsReadingsChange_data() {
            return [{ tag: "bits", bits: true }, { tag: "bytes", bits: false }];
        }

        function test_widthHoldsAsReadingsChange(data) {
            monitor.networkBits = data.bits;
            const strip = makeStrip({});
            const width = strip.implicitWidth;
            const changes = [
                () => { monitor.networkDown = 0; monitor.networkUp = 0; },
                () => { monitor.networkDown = 60; monitor.networkUp = 20; },
                () => { monitor.networkDown = 130; monitor.networkUp = 300; },
                () => { monitor.networkDown = 1.3e7; monitor.networkUp = 1023; },
                () => { monitor.networkDown = NaN; monitor.networkUp = NaN; },
                () => { monitor.diskRead = 0; monitor.diskWrite = 1e9; },
                () => { monitor.memoryUsed = 9.6 * monitor.gib; },
                () => { monitor.memoryUsed = NaN; },
                () => { monitor.cpuTemperature = NaN; },
                () => { monitor.fahrenheit = true; monitor.cpuTemperature = 38; },
                () => { monitor.cpuTemperature = 140; },
            ];
            for (let i = 0; i < changes.length; ++i) {
                compare(widthAfter(strip, changes[i]), width, "change " + i);
            }
        }

        function test_verticalRatesFit_data() {
            // Breeze gives an applet the panel's thickness less 8 px.
            return [34, 36, 40, 44, 48, 52, 60].map(width => ({ tag: String(width), width: width }));
        }

        function test_verticalRatesFit(data) {
            const strip = makeStrip({ vertical: true, width: data.width, thickness: data.width });
            for (const index of [3, 4]) {
                const rates = strip.cellAt(index).contentItem;
                // It fits, with a pixel of slack for hinting at the shrunk size,
                // or it has shrunk as far as it may. Where the floor lands
                // depends on the font, so the test doesn't pin it.
                const floor = Kirigami.Theme.smallFont.pointSize * 0.6;
                verify(rates.implicitWidth <= rates.availableWidth + 1 || Math.abs(rates.pointSize - floor) < 0.01,
                       rates.item + " " + rates.implicitWidth + " in " + rates.availableWidth + " at " + rates.pointSize);
            }
        }

        function visibleTexts(item) {
            const texts = [];
            const collect = i => {
                if (i.visible && i.text !== undefined && i.text !== "") {
                    texts.push(i.text);
                }
                i.children.forEach(collect);
            };
            collect(item);
            return texts;
        }

        // A sleeping GPU drops out of the panel, whichever ring it is on: the
        // one still awake shows alone, as on a single-GPU machine.
        function test_aSleepingGpuDropsOut_data() {
            return [{ tag: "outer asleep", outer: "asleep", inner: "live", shown: "AMD Radeon 780M Graphics", temp: "41" },
                    { tag: "inner asleep", outer: "live", inner: "asleep", shown: "AMD Radeon RX 7700S", temp: "48" }];
        }

        function test_aSleepingGpuDropsOut(data) {
            monitor.gpuInner.kind = "discrete";
            monitor.gpuOuter.phase = data.outer;
            monitor.gpuInner.phase = data.inner;
            const strip = makeStrip({ items: ["gpu"] });
            const content = strip.cellAt(0).contentItem;
            verify(!content.dual);
            compare(content.primary.name, data.shown);
            const texts = visibleTexts(strip);
            verify(texts.includes(data.temp), JSON.stringify(texts));
            verify(!texts.includes("off"), JSON.stringify(texts));
            verify(strip.cellAt(0).description.indexOf("\n") < 0, "one GPU described");
        }

        function test_theOnlyGpuAsleepSaysOff() {
            monitor.gpuInner.present = false;
            monitor.gpuOuter.phase = "asleep";
            const strip = makeStrip({ items: ["gpu"] });
            verify(visibleTexts(strip).includes("off"));
            verify(!visibleTexts(strip).includes("off°"));
        }

        // A gauge's two arcs as drawn, the outer one first.
        function arcs(gauge) {
            const found = [];
            const pending = [gauge];
            while (pending.length > 0) {
                const item = pending.shift();
                if (item.playReset !== undefined && item.animating !== undefined) {
                    found.push(item);
                }
                pending.push(...Array.from(item.children));
            }
            compare(found.length, 2);
            return found.sort((a, b) => b.radius - a.radius);
        }

        // Rings turn amber from 75 % and red from 90 % of their own reading,
        // in the arcs they draw: the CPU's ring, and with two GPUs the inner
        // ring at its dimmer alpha, while the ring outside it keeps its level.
        function test_ringLevelColours_data() {
            return [{ tag: "74", usage: 74, tone: "text" }, { tag: "75", usage: 75, tone: "neutral" },
                    { tag: "89", usage: 89, tone: "neutral" }, { tag: "90", usage: 90, tone: "negative" }];
        }

        function test_ringLevelColours(data) {
            monitor.cpuUsage = data.usage;
            monitor.cpuTemperature = 50;
            monitor.gpuInner.usage = data.usage;
            const strip = makeStrip({ items: ["cpu", "gpu"] });
            const gauge = strip.cellAt(0).contentItem.children[0];
            const expected = data.tone === "negative" ? Kirigami.Theme.negativeTextColor
                           : data.tone === "neutral" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
            compare(gauge.outerTone, expected);
            compare(arcs(gauge)[0].color, expected, "the CPU ring as drawn");

            const gpu = strip.cellAt(1).contentItem;
            verify(gpu.dual);
            const [outer, inner] = arcs(gpu.children[0]);
            compare(outer.color, Kirigami.Theme.textColor, "the discrete GPU's ring at 12%");
            compare(inner.color, Qt.alpha(expected, 0.55 * Kirigami.Theme.textColor.a), "the integrated GPU's ring");
        }

        function test_intelLeavesTemperatureOut() {
            monitor.gpuInner.reportsTemperature = false;
            monitor.gpuInner.temperature = NaN;
            const strip = makeStrip({ items: ["gpu"] });
            compare(strip.cellAt(0).description.split("\n")[1], "AMD Radeon 780M Graphics: Usage 3%");
        }

        function test_descriptions() {
            monitor.cpuTemperature = 80;
            const strip = makeStrip({});
            compare(strip.cellAt(0).Accessible.description, "Usage 23%, temperature 80 °C, warm");
            compare(strip.cellAt(2).Accessible.description, "13.4 GiB in use, 42%");
            compare(strip.cellAt(3).Accessible.description, "Down 24.8 Mb/s, up 1.2 Mb/s");
            compare(strip.cellAt(4).Accessible.description, "Read 12.0 MiB/s, write 3.4 MiB/s");
            monitor.cpuTemperature = NaN;
            compare(strip.cellAt(0).Accessible.description, "Usage 23%, temperature unavailable");
        }

        // Claude and Codex sit among the rings, named and described like them.
        function test_usageCells() {
            const strip = makeStrip({ items: ["cpu", "claude", "codex", "network"] });
            const claude = strip.cellAt(1);
            compare(claude.Accessible.name, "Claude");
            verify(/^62% used, Opus 78%, resets in 2 days 2\d hours$/.test(claude.Accessible.description),
                   claude.Accessible.description);
            compare(strip.cellAt(2).Accessible.name, "Codex");
            verify(/^34% used, resets in 5 days [34] hours$/.test(strip.cellAt(2).Accessible.description),
                   strip.cellAt(2).Accessible.description);
            verify(visibleTexts(strip).includes("CLAUDE"), JSON.stringify(visibleTexts(strip)));

            const width = strip.implicitWidth;
            const entries = JSON.parse(JSON.stringify(monitor.usage.entries));
            entries.claude.weekly.percent = 100;
            entries.claude.weekly.resetsAt = monitor.usage.createdAt + 600;
            compare(widthAfter(strip, () => monitor.usage.entries = entries), width);
        }

        function test_hiddenTextShowsTooltipAndHeat() {
            monitor.cpuTemperature = 95;
            const strip = makeStrip({ vertical: true, width: 38, thickness: 38 });
            const cell = strip.cellAt(0);
            const area = cell.parent;
            verify(area.active);
            compare(area.mainText, "Processor");
            compare(area.subText, "Usage 23%, temperature 95 °C, hot");
            const gauge = cell.contentItem.children[0];
            compare(gauge.outerTone, root.hotColor);
            verify(!strip.cellAt(3).parent.active, "rates keep their text");

            mouseMove(cell, cell.width / 2, cell.height / 2);
            verify(cell.containsMouse && area.containsMouse, "hover reaches the cell and the tooltip");
            strip.openItem = "cpu";
            verify(!area.active, "no tooltip over an open popup");
        }
    }
}
