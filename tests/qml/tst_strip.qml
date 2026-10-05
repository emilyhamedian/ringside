// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"

// The panel strip with FakeMonitor's readings: rings follow the panel's
// thickness inside the hover wash, with the item's name inside them and their
// readings on the rows the rates use; its width holds while values change, a
// thin vertical panel's rates fit, mirrored layouts read right to left, and
// every cell describes its readings in words.
Item {
    id: root
    width: 1200
    height: 600

    readonly property color hotColor: Kirigami.Theme.negativeTextColor
    readonly property var ringItems: ["cpu", "gpu", "memory", "claude", "codex"]
    readonly property var names: ({ cpu: "CPU", gpu: "GPU", memory: "MEM" })

    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (match, n) => n <= args.length ? String(args[n - 1]) : match);
    }
    function i18nc(context, text, ...args) {
        return substitute(text, args);
    }
    function i18ncp(context, singular, plural, n, ...args) {
        return substitute(n === 1 ? singular : plural, [n].concat(args));
    }

    // A name at the smallest size it may shrink to, measured here rather
    // than read from RingName.
    TextMetrics {
        id: smallestName
        font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.7
        font.letterSpacing: Kirigami.Theme.smallFont.pointSize * 0.08
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
            ringsOnly: []
        }
    }

    Component {
        id: mirroredComponent
        Strip {
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true
            items: ["cpu", "gpu", "memory", "claude", "network", "disk"]
            vertical: false
            thickness: 38
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

        function makeStrip(properties, component) {
            strip = (component ?? stripComponent).createObject(root, Object.assign({ monitor: monitor }, properties));
            waitForRendering(strip);
            return strip;
        }

        // A horizontal strip as main.qml places it: as tall as the panel.
        function makePanel(thickness, properties) {
            return makeStrip(Object.assign({ thickness: thickness, height: thickness }, properties));
        }

        // Layouts settle on the next polish, so read after a render.
        function sizeAfter(strip, change) {
            change();
            waitForRendering(strip);
            return { width: strip.implicitWidth, height: strip.implicitHeight };
        }

        function visibleTexts(item) {
            const texts = [];
            const collect = i => {
                if (i.visible && i.text !== undefined && i.text !== "") {
                    texts.push(i.text);
                }
                Array.from(i.children).forEach(collect);
            };
            collect(item);
            return texts;
        }

        // Every item under `item`, itself included, that `test` accepts.
        function all(item, test) {
            const found = [];
            const collect = i => {
                if (test(i)) {
                    found.push(i);
                }
                Array.from(i.children).forEach(collect);
            };
            collect(item);
            return found;
        }

        function find(item, test) {
            return all(item, test)[0] ?? null;
        }

        // Only a Rectangle has both; a RingArc has a radius and no border.
        function isRectangle(item) {
            return item.radius !== undefined && item.border !== undefined;
        }

        // An item's box in the strip's coordinates.
        function box(item) {
            const p = item.mapToItem(strip, 0, 0);
            return { x: p.x, y: p.y, width: item.width, height: item.height,
                     right: p.x + item.width, bottom: p.y + item.height,
                     centreX: p.x + item.width / 2, centreY: p.y + item.height / 2 };
        }

        function gaugeAt(index) {
            return strip.cellAt(index).contentItem.children[0];
        }

        function line(index, which) {
            const found = findChild(strip.cellAt(index).contentItem, which);
            verify(found, strip.items[index] + " has a line " + which);
            return found;
        }

        // The texts of a rate cell's two rows, down then up or read then write.
        function rateRows(index) {
            const rates = strip.cellAt(index).contentItem;
            return [0, 1].map(row => {
                const value = rates.lines[row].value;
                const found = find(rates, i => i.visible && i.text === value);
                verify(found, rates.item + " shows " + value);
                return found;
            });
        }

        // Every text drawn fits the room its line keeps: a reserve too narrow
        // lets a reading spill over its neighbour without moving anything.
        function checkFits(what) {
            const texts = all(strip, i => i.visible && typeof i.text === "string" && i.text !== "" && i.contentWidth !== undefined);
            verify(texts.length > 0);
            for (const text of texts) {
                verify(text.contentWidth <= text.width, what + ": " + text.text + " " + text.contentWidth + " in " + text.width);
            }
        }

        // A gauge's two arcs as drawn, the outer one first.
        function arcs(gauge) {
            const found = all(gauge, i => i.playReset !== undefined && i.animating !== undefined);
            compare(found.length, 2);
            return found.sort((a, b) => b.radius - a.radius);
        }

        // Each ring's name shows exactly where `active` lets it and it fits
        // the clear middle at its smallest size: the chord of the hole at the
        // name's ink height, a round hole being narrower above and below its
        // middle. A name or mark that shows sits inside the hole, centred,
        // and is all the ring holds: its percentage is beside it. Claude's and
        // Codex's marks are small enough to show at every ring size tested.
        function checkNames(active) {
            for (let i = 0; i < strip.items.length; ++i) {
                const item = strip.items[i];
                if (!root.ringItems.includes(item)) {
                    continue;
                }
                const gauge = gaugeAt(i);
                const name = find(gauge, n => n.room !== undefined && n.fits !== undefined);
                verify(name, item + " has a name");
                const hole = gauge.centreWidth;
                const centre = box(gauge);
                compare(gauge.text, "", item + " has no percentage inside");
                const inside = visibleTexts(gauge);
                verify(inside.length === 0 || inside.length === 1 && inside[0] === root.names[item],
                       item + " holds " + JSON.stringify(inside));
                let shown;
                if (item === "claude" || item === "codex") {
                    shown = find(name, m => m.isMask !== undefined);
                    verify(String(shown.source).endsWith(item === "claude" ? "claude.svg" : "openai.svg"), shown.source);
                    compare(shown.visible, active, item + "'s mark");
                    compare(name.visible, active, item + "'s mark");
                } else {
                    smallestName.text = root.names[item];
                    const ink = smallestName.tightBoundingRect.height;
                    const chord = 2 * Math.sqrt(Math.max(0, hole * hole / 4 - ink * ink / 4));
                    const fits = smallestName.advanceWidth <= chord;
                    compare(name.visible, active && fits,
                            item + ": " + smallestName.advanceWidth + " in a chord of " + chord + " across " + hole);
                    shown = find(name, t => t.text === root.names[item]);
                    verify(shown, item + "'s name");
                }
                if (shown.visible) {
                    const drawn = box(shown);
                    verify((shown.contentWidth ?? shown.width) <= hole, item + " " + shown.width + " in " + hole);
                    verify(Math.abs(drawn.centreX - centre.centreX) <= 0.5 && Math.abs(drawn.centreY - centre.centreY) <= 0.5,
                           item + " centred: " + JSON.stringify(drawn) + " in " + JSON.stringify(centre));
                }
            }
        }

        function test_widthHoldsAsReadingsChange_data() {
            return [{ tag: "bits", bits: true, thickness: 46 }, { tag: "bytes", bits: false, thickness: 46 },
                    { tag: "thin bits", bits: true, thickness: 30 }, { tag: "thin bytes", bits: false, thickness: 30 }];
        }

        // Each change is checked to show the reading it sets, so the widest
        // ones are really drawn (100%, 302°, 1023M, "off"), and to fit.
        function test_widthHoldsAsReadingsChange(data) {
            monitor.networkBits = data.bits;
            const strip = makeStrip({ thickness: data.thickness });
            compare(strip.twoLines, data.thickness >= 46);
            const size = { width: strip.implicitWidth, height: strip.implicitHeight };
            checkFits("at first");
            const changes = [
                { what: "no traffic", change: () => { monitor.networkDown = 0; monitor.networkUp = 0; } },
                { what: "slow traffic", change: () => { monitor.networkDown = 60; monitor.networkUp = 20; } },
                { what: "three digits", change: () => { monitor.networkDown = 130; monitor.networkUp = 300; } },
                { what: "fast traffic", change: () => { monitor.networkDown = 1.3e7; monitor.networkUp = 1023; } },
                { what: "no network", change: () => { monitor.networkDown = NaN; monitor.networkUp = NaN; } },
                { what: "disk", change: () => { monitor.diskRead = 0; monitor.diskWrite = 1e9; } },
                { what: "memory 9.6 GiB", change: () => { monitor.memoryUsed = 9.6 * monitor.gib; }, shows: "9.6G" },
                { what: "memory 1023 MiB", change: () => { monitor.memoryUsed = 1023 * 1048576; }, shows: "1023M" },
                { what: "no memory", change: () => { monitor.memoryUsed = NaN; } },
                { what: "CPU 5%", change: () => { monitor.cpuUsage = 5; }, shows: "5%" },
                { what: "CPU 11%", change: () => { monitor.cpuUsage = 11; }, shows: "11%" },
                { what: "CPU 88%", change: () => { monitor.cpuUsage = 88; }, shows: "88%" },
                { what: "CPU 100%", change: () => { monitor.cpuUsage = 100; }, shows: "100%" },
                { what: "no CPU usage", change: () => { monitor.cpuUsage = NaN; } },
                { what: "11 °C", change: () => { monitor.cpuTemperature = 11; }, shows: "11°" },
                { what: "88 °C", change: () => { monitor.cpuTemperature = 88; }, shows: "88°" },
                { what: "no temperature", change: () => { monitor.cpuTemperature = NaN; } },
                { what: "100 °F", change: () => { monitor.fahrenheit = true; monitor.cpuTemperature = 38; }, shows: "100°" },
                { what: "302 °F", change: () => { monitor.cpuTemperature = 149.9; }, shows: "302°" },
                { what: "GPU 100%", change: () => { monitor.gpuOuter.usage = 100; }, shows: "100%" },
                { what: "discrete GPU asleep", change: () => { monitor.gpuOuter.phase = "asleep"; }, shows: "3%" },
                { what: "the only GPU asleep", change: () => { monitor.gpuInner.present = false; }, shows: "off" },
                { what: "GPU awake", change: () => { monitor.gpuOuter.phase = "live"; }, shows: "100%" },
            ];
            for (const step of changes) {
                compare(sizeAfter(strip, step.change), size, step.what);
                checkFits(step.what);
                if (step.shows) {
                    verify(visibleTexts(strip).includes(step.shows), step.what + ": " + JSON.stringify(visibleTexts(strip)));
                }
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

        // Rings fill the panel inside the wash, which leaves half a small
        // spacing above and below across a horizontal panel; along a vertical
        // one a small spacing either side. They stop at two and a half grid
        // units, a pixel less where that would leave the panel's parity, and
        // the stroke is about a thirteenth of the ring in half pixels.
        function test_ringFollowsThickness_data() {
            return [18, 22, 30, 36, 38, 46, 60, 100].map(t => ({ tag: "horizontal " + t, vertical: false, thickness: t }))
                .concat([34, 38, 46, 60].map(t => ({ tag: "vertical " + t, vertical: true, thickness: t })));
        }

        function test_ringFollowsThickness(data) {
            const items = root.ringItems.concat(["network", "disk"]);
            const strip = data.vertical
                ? makeStrip({ items: items, vertical: true, width: data.thickness, thickness: data.thickness })
                : makePanel(data.thickness, { items: items });
            const inset = data.vertical ? Kirigami.Units.smallSpacing : Math.round(Kirigami.Units.smallSpacing / 2);
            const cap = Math.round(Kirigami.Units.gridUnit * 2.5);
            const size = Math.max(16, Math.min(cap, data.thickness - 2 * inset));
            const ring = (data.thickness - size) % 2 !== 0 ? size - 1 : size;
            compare(strip.ring, ring);
            compare((data.thickness - strip.ring) % 2, 0, "the ring keeps the panel's parity");
            if (!data.vertical && data.thickness === 38) {
                compare(strip.ring, 34, "a 38 px panel");
            }
            if (data.thickness >= 60) {
                compare(strip.ring, (data.thickness - cap) % 2 !== 0 ? cap - 1 : cap, "capped");
            }
            if (data.thickness - 2 * inset < 16) {
                compare(strip.ring, data.thickness % 2 !== 0 ? 15 : 16, "never smaller");
            }
            for (let i = 0; i < root.ringItems.length; ++i) {
                const gauge = gaugeAt(i);
                compare(gauge.width, ring, items[i]);
                compare(gauge.height, ring, items[i]);
                compare(gauge.strokeWidth, Math.max(2, Math.round(ring / 6.5) / 2), items[i]);
                compare(arcs(gauge)[0].strokeWidth, gauge.strokeWidth, items[i] + " as drawn");
            }
        }

        // The ring sits inside the hover wash, centred on it.
        // 37: two lines taller than the ring; 50 and 52: a ring held at its
        // largest size.
        function test_ringFitsTheWash_data() {
            return [22, 30, 37, 38, 46, 50, 52, 60].map(t => ({ tag: String(t), thickness: t }));
        }

        function test_ringFitsTheWash(data) {
            const strip = makePanel(data.thickness, { items: root.ringItems });
            for (let i = 0; i < root.ringItems.length; ++i) {
                strip.openItem = root.ringItems[i];
                waitForRendering(strip);
                const cell = strip.cellAt(i);
                const washes = Array.from(cell.children).filter(isRectangle);
                compare(washes.length, 1);
                const wash = washes[0];
                verify(wash.visible, "an open item shows its wash");
                compare(wash.y, Math.round(Kirigami.Units.smallSpacing / 2));
                compare(cell.height, data.thickness);
                const gauge = box(gaugeAt(i));
                const washBox = box(wash);
                verify(washBox.height >= gauge.height, strip.items[i] + ": " + washBox.height + " < " + gauge.height);
                verify(Math.abs(washBox.centreY - gauge.centreY) <= 0.5,
                       strip.items[i] + ": " + washBox.centreY + " vs " + gauge.centreY);
            }
        }

        // Rings and rates sit side by side, cell against cell: nothing is
        // drawn between them, and the only rectangles are the cells' washes.
        function test_noSeparator_data() {
            return [{ tag: "two lines", thickness: 38 }, { tag: "thin", thickness: 30 }];
        }

        function test_noSeparator(data) {
            const items = ["cpu", "network", "gpu", "disk", "memory", "claude"];
            const strip = makePanel(data.thickness, { items: items });
            let sum = 0;
            for (let i = 0; i < items.length; ++i) {
                sum += strip.cellAt(i).implicitWidth;
                if (i > 0) {
                    compare(box(strip.cellAt(i)).x, box(strip.cellAt(i - 1)).right, items[i] + " follows " + items[i - 1]);
                }
            }
            compare(strip.implicitWidth, sum);
            const rectangles = all(strip, isRectangle);
            compare(rectangles.length, items.length);
            for (const rectangle of rectangles) {
                verify(rectangle.parent.inset !== undefined && rectangle.parent.contentItem !== undefined,
                       "a wash, in a cell");
                verify(rectangle.width > 1 && rectangle.height > 1, rectangle.width + "×" + rectangle.height);
            }
        }

        // A ring's lines share the rates' rows, so the panel reads as two
        // lines of text across, or one on a thin panel.
        // Odd and even panels, two lines taller than the ring (37), and rings
        // held at their largest size (50 to 53).
        function test_rowsAlignWithRates_data() {
            return [30, 31, 36, 37, 38, 39, 46, 50, 51, 52, 53]
                .map(t => ({ tag: (t >= Kirigami.Units.gridUnit * 2 ? "two lines " : "thin ") + t, thickness: t }));
        }

        function test_rowsAlignWithRates(data) {
            const items = ["cpu", "gpu", "memory", "claude", "network", "disk"];
            const strip = makePanel(data.thickness, { items: items });
            compare(strip.twoLines, data.thickness >= Kirigami.Units.gridUnit * 2);
            for (const rateIndex of [4, 5]) {
                const rows = rateRows(rateIndex);
                if (!strip.twoLines) {
                    compare(box(rows[1]).y, box(rows[0]).y, "one row");
                }
                for (let i = 0; i < 4; ++i) {
                    const lines = [line(i, "first"), line(i, "second")];
                    for (let row = 0; row < 2; ++row) {
                        verify(lines[row].visible);
                        const drawn = box(lines[row]);
                        const rate = box(rows[row]);
                        const what = items[i] + " line " + (row + 1) + " by " + items[rateIndex] + ": ";
                        verify(Math.abs(drawn.y - rate.y) <= 0.5, what + drawn.y + " vs " + rate.y);
                        compare(drawn.height, rate.height, what + "height");
                        const baseline = drawn.y + lines[row].baselineOffset;
                        const rateBaseline = rate.y + rows[row].baselineOffset;
                        verify(Math.abs(baseline - rateBaseline) <= 0.5, what + "baseline " + baseline + " vs " + rateBaseline);
                    }
                }
            }
        }

        // Two lines fit wherever the strip gives them: from two grid units of
        // panel up.
        function test_twoLinesFitTheApplet_data() {
            return [Math.ceil(Kirigami.Units.gridUnit * 2), 38, 46].map(t => ({ tag: String(t), thickness: t }));
        }

        function test_twoLinesFitTheApplet(data) {
            const strip = makePanel(data.thickness, { items: root.ringItems });
            verify(strip.twoLines);
            for (let i = 0; i < root.ringItems.length; ++i) {
                const cell = box(strip.cellAt(i));
                const first = box(line(i, "first"));
                const second = box(line(i, "second"));
                verify(first.y >= cell.y, root.ringItems[i] + ": " + first.y + " above " + cell.y);
                verify(second.y >= first.bottom, root.ringItems[i] + ": the second line under the first");
                verify(second.bottom <= cell.bottom, root.ringItems[i] + ": " + second.bottom + " below " + cell.bottom);
            }
        }

        // A vertical panel shows rings with their names, and the readings
        // move to the tooltip; the rates shorten their units to a prefix.
        function test_verticalIsRingsWithNames() {
            const items = root.ringItems.concat(["network", "disk"]);
            const strip = makeStrip({ items: items, vertical: true, width: 46, thickness: 46 });
            for (let i = 0; i < root.ringItems.length; ++i) {
                verify(!line(i, "first").visible, items[i]);
                verify(!line(i, "second").visible, items[i]);
                verify(strip.cellAt(i).parent.active, items[i] + "'s tooltip");
            }
            checkNames(true);
            const network = strip.cellAt(5).contentItem;
            const disk = strip.cellAt(6).contentItem;
            compare(visibleTexts(network), network.whole ? ["25M", "1M"] : ["24.8M", "1.2M"]);
            compare(visibleTexts(disk), disk.whole ? ["R", "W", "12M", "3M"] : ["R", "W", "12.0M", "3.4M"]);
        }

        // Names sit inside the rings beside two lines of readings, and where
        // the rings stand alone; beside one line the rings are too small.
        function test_namesInsideRings_data() {
            return [{ tag: "two lines", thickness: 38, ringsOnly: [], active: true },
                    { tag: "thin", thickness: 30, ringsOnly: [], active: false },
                    { tag: "thin rings only", thickness: 30, ringsOnly: root.ringItems, active: true }];
        }

        function test_namesInsideRings(data) {
            const strip = makePanel(data.thickness, { items: root.ringItems, ringsOnly: data.ringsOnly });
            const gpu = strip.cellAt(1).contentItem;
            verify(gpu.dual);
            verify(gaugeAt(1).centreWidth < gaugeAt(0).centreWidth, "the inner ring narrows the middle");
            checkNames(data.active);
        }

        // A sleeping GPU drops out of the panel, whichever ring it is on: the
        // one still awake shows alone, as on a single-GPU machine.
        function test_aSleepingGpuDropsOut_data() {
            return [{ tag: "outer asleep", outer: "asleep", inner: "live", shown: "AMD Radeon 780M Graphics",
                      usage: "3%", temp: "41°", other: "48°" },
                    { tag: "inner asleep", outer: "live", inner: "asleep", shown: "AMD Radeon RX 7700S",
                      usage: "12%", temp: "48°", other: "41°" }];
        }

        function test_aSleepingGpuDropsOut(data) {
            monitor.gpuInner.kind = "discrete";
            monitor.gpuOuter.phase = data.outer;
            monitor.gpuInner.phase = data.inner;
            const strip = makeStrip({ items: ["gpu"] });
            const content = strip.cellAt(0).contentItem;
            verify(!content.dual);
            compare(content.primary.name, data.shown);
            compare(line(0, "first").text, data.usage);
            compare(line(0, "second").text, data.temp);
            const texts = visibleTexts(strip);
            verify(!texts.includes(data.other), JSON.stringify(texts));
            verify(!texts.includes("off"), JSON.stringify(texts));
            verify(strip.cellAt(0).description.indexOf("\n") < 0, "one GPU described");
        }

        // "off" stands alone, and the blank line under it keeps its place:
        // both stay on the rows the CPU's readings use.
        function test_theOnlyGpuAsleepSaysOff() {
            monitor.gpuInner.present = false;
            monitor.gpuOuter.phase = "asleep";
            const strip = makeStrip({ items: ["cpu", "gpu"] });
            verify(visibleTexts(strip).includes("off"));
            verify(!visibleTexts(strip).includes("off°"));
            compare(line(1, "first").text, "off");
            compare(line(1, "second").text, "");
            for (const which of ["first", "second"]) {
                verify(line(1, which).visible, which);
                compare(box(line(1, which)).y, box(line(0, which)).y, which);
                compare(line(1, which).height, line(0, which).height, which);
            }
        }

        // With two GPUs the panel reads the outer one; the integrated GPU's
        // temperature is left to the tooltip and the popup.
        function test_integratedTemperatureStaysInWords() {
            const strip = makeStrip({ items: ["gpu"] });
            verify(strip.cellAt(0).contentItem.dual);
            const texts = visibleTexts(strip);
            verify(texts.includes("12%") && texts.includes("48°"), JSON.stringify(texts));
            verify(!texts.includes("3%") && !texts.includes("41°"), JSON.stringify(texts));
            compare(gaugeAt(0).innerValue, 3);
            compare(strip.cellAt(0).description.split("\n")[1], "AMD Radeon 780M Graphics: Usage 3%, temperature 41 °C");
        }

        // Rings turn amber from 75 % and red from 90 % of their own reading,
        // in the arcs they draw and in the reading beside them: the CPU's
        // ring, and with two GPUs the inner ring at its dimmer alpha, while
        // the ring outside it and the GPU's reading keep their level.
        function test_ringLevelColours_data() {
            return [{ tag: "74", usage: 74, tone: "text" }, { tag: "75", usage: 75, tone: "neutral" },
                    { tag: "89", usage: 89, tone: "neutral" }, { tag: "90", usage: 90, tone: "negative" }];
        }

        function test_ringLevelColours(data) {
            monitor.cpuUsage = data.usage;
            monitor.cpuTemperature = 50;
            monitor.gpuInner.usage = data.usage;
            const strip = makeStrip({ items: ["cpu", "gpu"] });
            const gauge = gaugeAt(0);
            const expected = data.tone === "negative" ? Kirigami.Theme.negativeTextColor
                           : data.tone === "neutral" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
            compare(gauge.outerTone, expected);
            compare(arcs(gauge)[0].color, expected, "the CPU ring as drawn");
            compare(line(0, "first").text, data.usage + "%");
            compare(line(0, "first").color, gauge.outerTone, "the CPU's reading");

            const gpu = strip.cellAt(1).contentItem;
            verify(gpu.dual);
            const [outer, inner] = arcs(gpu.children[0]);
            compare(outer.color, Kirigami.Theme.textColor, "the discrete GPU's ring at 12%");
            compare(inner.color, Qt.alpha(expected, 0.55 * Kirigami.Theme.textColor.a), "the integrated GPU's ring");
            compare(line(1, "first").color, Kirigami.Theme.textColor, "the discrete GPU's reading");
        }

        function test_intelLeavesTemperatureOut() {
            monitor.gpuInner.reportsTemperature = false;
            monitor.gpuInner.temperature = NaN;
            const strip = makeStrip({ items: ["gpu"] });
            compare(strip.cellAt(0).description.split("\n")[1], "AMD Radeon 780M Graphics: Usage 3%");

            // Alone in the panel it shows its usage over a blank line, which
            // keeps its row.
            const first = box(line(0, "first"));
            const second = box(line(0, "second"));
            monitor.gpuOuter.phase = "asleep";
            waitForRendering(strip);
            compare(strip.cellAt(0).contentItem.primary.name, "AMD Radeon 780M Graphics");
            compare(line(0, "first").text, "3%");
            compare(line(0, "second").text, "");
            verify(line(0, "second").visible);
            compare(box(line(0, "first")), first);
            compare(box(line(0, "second")), second);
            compare(strip.cellAt(0).description, "Usage 3%");
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

        // Claude and Codex sit among the rings, marked and described like
        // them: the weekly percentage over the time to the reset.
        function test_usageCells() {
            const strip = makeStrip({ items: ["cpu", "claude", "codex", "network"] });
            const claude = strip.cellAt(1);
            compare(claude.Accessible.name, "Claude");
            verify(/^52% used, Fable 78%, resets in 2 days 2\d hours$/.test(claude.Accessible.description),
                   claude.Accessible.description);
            compare(strip.cellAt(2).Accessible.name, "Codex");
            verify(/^24% used, resets in 5 days [34] hours$/.test(strip.cellAt(2).Accessible.description),
                   strip.cellAt(2).Accessible.description);
            const mark = find(gaugeAt(1), i => i.isMask !== undefined);
            verify(String(mark.source).endsWith("claude.svg"), mark.source);
            verify(mark.visible, "the Claude mark");
            verify(!visibleTexts(strip).includes("CLAUDE"), JSON.stringify(visibleTexts(strip)));
            compare([line(1, "first").text, line(1, "second").text], ["52%", "2d 21h"]);
            compare([line(2, "first").text, line(2, "second").text], ["24%", "5d 4h"]);

            const width = strip.implicitWidth;
            const entries = JSON.parse(JSON.stringify(monitor.usage.entries));
            entries.claude.weekly.percent = 100;
            entries.claude.weekly.resetsAt = monitor.usage.createdAt + 600;
            compare(sizeAfter(strip, () => monitor.usage.entries = entries).width, width);
            compare([line(1, "first").text, line(1, "second").text], ["100%", "10m"]);
        }

        // Right to left the strip runs from the right edge, each reading on
        // the ring's left, hugging it; on one line the ring's own reading
        // comes first, nearest the ring. A reading is one text, so a number
        // never parts from its sign.
        function test_mirrored_data() {
            return [{ tag: "two lines", thickness: 38 }, { tag: "thin", thickness: 30 }];
        }

        function test_mirrored(data) {
            const strip = makeStrip({ thickness: data.thickness, height: data.thickness }, mirroredComponent);
            for (let i = 1; i < strip.items.length; ++i) {
                compare(box(strip.cellAt(i)).right, box(strip.cellAt(i - 1)).x, strip.items[i] + " left of " + strip.items[i - 1]);
            }
            for (let i = 0; i < 4; ++i) {
                const gauge = box(gaugeAt(i));
                const first = line(i, "first");
                const second = line(i, "second");
                verify(box(first).right <= gauge.x && box(second).right <= gauge.x, strip.items[i] + "'s readings left of its ring");
                if (strip.twoLines) {
                    compare(first.effectiveHorizontalAlignment, Text.AlignRight, strip.items[i]);
                    compare(second.effectiveHorizontalAlignment, Text.AlignRight, strip.items[i]);
                } else {
                    compare(box(first).y, box(second).y, strip.items[i] + " on one line");
                    verify(box(second).right <= box(first).x, strip.items[i] + ": " + second.text + " left of " + first.text);
                }
            }
            compare([line(0, "first").text, line(0, "second").text], ["23%", "61°"]);
            compare([line(2, "first").text, line(2, "second").text], ["42%", "13.4G"]);
            const texts = visibleTexts(strip);
            verify(!texts.includes("%") && !texts.includes("°"), JSON.stringify(texts));
        }

        function test_hiddenTextShowsTooltipAndHeat() {
            monitor.cpuTemperature = 95;
            const strip = makeStrip({ vertical: true, width: 38, thickness: 38 });
            const cell = strip.cellAt(0);
            const area = cell.parent;
            verify(area.active);
            compare(area.mainText, "Processor");
            compare(area.subText, "Usage 23%, temperature 95 °C, hot");
            verify(!line(0, "first").visible && !line(0, "second").visible, "the readings are in the tooltip");
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
