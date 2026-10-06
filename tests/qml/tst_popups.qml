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

    // What a Text that elides draws of its text.
    TextMetrics {
        id: elideProbe
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
                { tag: "gpuOnlyAsleep", popup: "GpuPopup", monitor: onlyAsleep },
                { tag: "gpuLongNames", popup: "GpuPopup", monitor: longGpuNames },
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

        // A C-locale expectation in the digits and decimal mark Format uses
        // for the test's locale: "8.4" is "8,4" under German.
        function localized(text) {
            return text.replace(/\d+(?:\.(\d+))?/g, (m, decimals) => Format.fixed(Number(m), decimals ? decimals.length : 0));
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
            const edge = Math.round(Kirigami.Units.largeSpacing * 2);
            compare(line.mapToItem(popup, Qt.point(0, 0)).x, edge);
            compare(line.width, popup.width - 2 * edge);
            const headers = all(popup, i => i.visible && i.partsShown !== undefined);
            const tiles = all(popup, i => i.visible && i.graphNote !== undefined);
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
            compare(gpu.map(g => g.value), [12, 3], "a ring per GPU");
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

        function test_popupsSpellTheTemperatureUnit_data() {
            return [{ tag: "celsius", fahrenheit: false, unit: "°C" }, { tag: "fahrenheit", fahrenheit: true, unit: "°F" }];
        }

        function test_popupsSpellTheTemperatureUnit(data) {
            normal.fahrenheit = data.fahrenheit;
            for (const popup of ["CpuPopup", "GpuPopup"]) {
                const found = texts(load(popup, normal));
                verify(found.includes(data.unit), popup + " " + JSON.stringify(found));
            }
            // The disk caption sets the unit against the number, as the readings do.
            const disk = texts(load("NetworkPopup", normal)).filter(t => t.indexOf("°") >= 0);
            compare(disk, [Format.temperature(normal.diskTemperature, data.fahrenheit) + data.unit]);
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

        // Where a Text's ink starts, down from its reading's top.
        function inkTop(text) {
            glyph.font = text.font;
            glyph.text = text.text;
            return text.y + text.baselineOffset + glyph.tightBoundingRect.y;
        }

        // The temperature unit is as small as the caption under it and sits
        // a pixel from the digits, its top level with theirs, in the CPU and
        // GPU headers alike. At one size it is as far from the ink after a
        // tabular "1" (61, 41) as after any other digit (60, 48).
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
                    compare(r.unitSpacing, 1, tag);
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
            normal.cpuTemperature = 61;
            normal.fahrenheit = false;
        }

        // Only the degree sign moves toward a narrow last digit: the digits,
        // the reading's width and the caption under it hold still as the
        // temperature changes, in the CPU header and in a GPU's.
        function test_temperatureDigitsHoldStill() {
            const where = (r, popup) => parts(r).number.mapToItem(popup, Qt.point(0, 0)).x;
            const cpu = [];
            const gpu = [];
            for (const t of [59, 60, 61, 62, 71]) {
                normal.cpuTemperature = t;
                normal.gpuOuter.temperature = t;
                const popup = load("CpuPopup", normal);
                const header = headerOf(popup);
                const headline = readings(header).find(r => r.visible && r.degreeUnit !== "");
                const caption = shownText(header, header.caption);
                verify(headline && caption);
                cpu.push([where(headline, popup), headline.implicitWidth, caption.mapToItem(popup, Qt.point(0, 0)).x].join(" "));
                const gpuPopup = load("GpuPopup", normal);
                const gpuHeader = headerOf(gpuPopup);
                const gpuHeadline = readings(gpuHeader).find(r => r.visible && r.degreeUnit !== "");
                const gpuCaption = shownText(gpuHeader, gpuHeader.caption);
                verify(gpuHeadline && gpuCaption, "the GPU header at " + t);
                compare(gpuHeadline.value, Format.temperature(t, false));
                gpu.push([where(gpuHeadline, gpuPopup), gpuHeadline.implicitWidth,
                          gpuCaption.mapToItem(gpuPopup, Qt.point(0, 0)).x].join(" "));
            }
            normal.cpuTemperature = 61;
            normal.gpuOuter.temperature = Qt.binding(() => normal.gpuOuter.awake ? 48 : NaN);
            compare(cpu.filter(s => s !== cpu[0]), [], "the header at 59, 60, 61, 62, 71: " + cpu.join(", "));
            compare(gpu.filter(s => s !== gpu[0]), [], "the GPU header at 59, 60, 61, 62, 71: " + gpu.join(", "));
        }

        // A degree sign is always at the small font's size, where another
        // unit grows with its digits. The digits here are large enough for
        // the two rules to differ under any theme's fonts.
        function test_degreeUnitAtTheSmallFont() {
            const small = Kirigami.Theme.smallFont.pointSize;
            const pointSize = 3 * small;
            const make = properties => {
                const loader = createTemporaryObject(host, root);
                loader.setSource(Qt.resolvedUrl("../../package/contents/ui/Reading.qml"),
                                 Object.assign({ value: Format.temperature(61, false), pointSize: pointSize }, properties));
                compare(loader.status, Loader.Ready);
                return parts(loader.item).suffix;
            };
            const degree = make({ degreeUnit: "C" });
            compare(degree.text, "°C");
            compare(degree.font.pointSize, small);
            const other = make({ unit: "GHz" });
            compare(other.font.pointSize, Style.unitPointSize(pointSize, small));
            verify(other.font.pointSize > degree.font.pointSize, other.font.pointSize + " against " + degree.font.pointSize);
        }

        // A degree unit hangs from the top of the digits at any size, inside
        // the number's line, where another unit sits on their baseline. A
        // "7" and a "1" have flat tops, which hinting leaves where they are;
        // a round digit's overshoot can round to a pixel more at this size.
        function test_degreeUnitHangsFromTheDigits_data() {
            return [{ tag: "celsius", unit: "C" }, { tag: "fahrenheit", unit: "F" }];
        }

        function test_degreeUnitHangsFromTheDigits(data) {
            const small = Kirigami.Theme.smallFont.pointSize;
            const make = properties => {
                const loader = createTemporaryObject(host, root);
                loader.setSource(Qt.resolvedUrl("../../package/contents/ui/Reading.qml"),
                                 Object.assign({ value: Format.temperature(71, false), pointSize: 3 * small }, properties));
                compare(loader.status, Loader.Ready);
                return loader.item;
            };
            const r = make({ degreeUnit: data.unit });
            const p = parts(r);
            fuzzyCompare(inkTop(p.suffix), inkTop(p.number), 0.5, "level with the digits' top");
            const baseline = p.number.y + p.number.baselineOffset;
            verify(p.suffix.y + p.suffix.baselineOffset < baseline - small,
                   "raised from the baseline: " + (p.suffix.y + p.suffix.baselineOffset) + " against " + baseline);
            verify(p.suffix.y >= 0, "inside the line, at " + p.suffix.y);
            compare(r.implicitHeight, p.number.implicitHeight);
            const other = parts(make({ unit: "GHz" }));
            compare(other.suffix.y + other.suffix.baselineOffset, other.number.y + other.number.baselineOffset, "a unit on the baseline");
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
            // In the locale's own digits and decimal mark.
            const digits = Array.from({ length: 10 }, (_, n) => Format.whole(n));
            const ascii = t => Array.from(t).map(c => digits.indexOf(c) >= 0 ? String(digits.indexOf(c))
                                                    : c === Qt.locale().decimalPoint ? "." : c).join("");
            const numbers = all(popup, i => i.visible && typeof i.text === "string" && /^[0-9.,–]+%?$/.test(ascii(i.text)) && i.font !== undefined, true);
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
                compare(list.Layout.bottomMargin, Math.round(Kirigami.Units.largeSpacing * 1.25));
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
                    compare(label.text, localized("100%"));
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
        // Throughput's peak is in the header's unit, bits or bytes.
        function test_diskPeaksInTheCaption_data() {
            return [{ tag: "bits", bits: true }, { tag: "bytes", bits: false }];
        }

        function test_diskPeaksInTheCaption(data) {
            const peak = (samples, bits) => {
                const r = Format.rate(Math.max(...samples), bits);
                return "peak " + r.value + " " + r.unit;
            };
            const seconds = "THROUGHPUT · 60 s";
            const expected = {
                Throughput: seconds + " · " + peak(normal.networkDownHistory.concat(normal.networkUpHistory), data.bits),
                Read: "READ · " + peak(normal.diskReadHistory, false),
                Write: "WRITE · " + peak(normal.diskWriteHistory, false)
            };
            normal.networkBits = data.bits;
            fresh.networkBits = data.bits;
            try {
                const popup = load("NetworkPopup", normal);
                const found = graphs(popup).map(tileCaption);
                compare(found.map(c => c.text), [expected.Throughput, expected.Read, expected.Write]);
                verify(!texts(popup).some(t => t.indexOf("Peak") >= 0), JSON.stringify(texts(popup)));

                const empty = graphs(load("NetworkPopup", fresh)).map(tileCaption);
                compare(empty.map(c => c.text), [seconds, "READ", "WRITE"]);
            } finally {
                normal.networkBits = true;
                fresh.networkBits = true;
            }
        }

        // Throughput tops out at the higher of its two series, and its
        // caption names that peak, the upload's when it is the higher.
        function test_throughputPeakCoversUpload() {
            const up = Math.max(...uploading.networkUpHistory);
            verify(up > Math.max(...uploading.networkDownHistory), "the upload peaks higher");
            const g = graphs(load("NetworkPopup", uploading))[0];
            compare(g.maximum, up);
            const top = g.secondPoints.reduce((m, p) => Math.min(m, p.y), Infinity);
            fuzzyCompare(top, g.topY, 0.001, "the upload's peak lands at the top");
            verify(g.mainPoints.every(p => p.y > top), "the download stays under it");
            const r = Format.rate(up, uploading.networkBits);
            verify(tileCaption(g).text.endsWith(" · peak " + r.value + " " + r.unit), tileCaption(g).text);
        }

        function test_rateCaptionsKeepTheirLabel_data() {
            const rows = [];
            // A 360 px page at gridUnit 18, as at 1.25 with Breeze, and the
            // 280 px of gridUnit 14, here in the larger font.
            for (const width of [Kirigami.Units.gridUnit * 20, Math.round(Kirigami.Units.gridUnit * 20 * 14 / 18)]) {
                rows.push({ tag: width + " px", width: width, mirrored: false });
                rows.push({ tag: width + " px mirrored", width: width, mirrored: true });
            }
            return rows;
        }

        // A third longer in every string, the rate tiles' captions stay
        // inside their tiles at the page widths a popup takes: where a peak
        // note doesn't fit, it is cut short, never the label before it.
        function test_rateCaptionsKeepTheirLabel(data) {
            root.pseudo = true;
            try {
                const loader = createTemporaryObject(data.mirrored ? mirroredHost : host, root, { width: data.width });
                loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/NetworkPopup.qml"), { monitor: normal });
                const popup = loader.item;
                waitForRendering(popup);
                compare(popup.width, data.width);
                const captions = graphs(popup).map(tileCaption);
                compare(captions.length, 3);
                verify(captions.some(c => c.truncated), "some note is cut short: " + captions.map(c => c.text).join(", "));
                for (const c of captions) {
                    const tile = ancestor(c, i => i.graphNote !== undefined);
                    const left = c.mapToItem(tile, Qt.point(0, 0)).x;
                    const drawn = c.elide !== Text.ElideNone ? c.width : Math.max(c.width, c.contentWidth);
                    verify(left >= tile.horizontalPadding - 0.5 && left + drawn <= tile.width - tile.horizontalPadding + 0.5,
                           c.text + " at " + left + " to " + (left + drawn) + " in a tile " + tile.width + " wide");
                    // Where even the label and an ellipsis are wider than
                    // the caption, nothing can keep the label whole; at the
                    // page's own width every label fits.
                    const label = c.label.toLocaleUpperCase();
                    elideProbe.font = c.font;
                    elideProbe.text = label + "…";
                    if (elideProbe.advanceWidth > c.width) {
                        verify(data.width < Kirigami.Units.gridUnit * 20, label + " is " + elideProbe.advanceWidth + " wide in " + c.width);
                        continue;
                    }
                    elideProbe.text = c.text;
                    elideProbe.elide = c.elide;
                    elideProbe.elideWidth = c.width;
                    verify(elideProbe.elidedText.startsWith(label), "the label whole in " + elideProbe.elidedText);
                }
            } finally {
                root.pseudo = false;
            }
        }

        // A rate graph scales to its floor while the rates stay under it,
        // 1 Mb/s for throughput and 1 MiB/s for a disk, so an idle link or
        // disk draws its noise low rather than at full height.
        function test_rateGraphFloors() {
            const popup = load("NetworkPopup", idle);
            const found = graphs(popup);
            compare(found.map(g => g.maximum), [125000, 1048576, 1048576]);
            found.forEach(g => {
                const top = g.mainPoints.concat(g.secondPoints).reduce((m, p) => Math.min(m, p.y), Infinity);
                verify(top > g.topY + (g.height - g.topY) / 2, "the line keeps low: " + top + " of " + g.height);
            });
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
            return text.mapToItem(popup, Qt.point(0, text.baselineOffset)).y;
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
        // than the padding alone would put it, and the ink at its foot, a
        // graph's floor or the baseline of the text it ends on, as far from
        // the bottom as its capitals are from the top.
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
                const capTop = caption.mapToItem(tile, Qt.point(0, caption.baselineOffset)).y - tile.capHeight;
                // Rounding to whole pixels is the only slack.
                fuzzyCompare(capTop, tile.verticalPadding + leading / 2, 0.5, tile.caption + " cap top");
                const column = caption.parent;
                const last = Array.from(column.children[1].children).filter(c => c.visible).pop();
                let foot;
                if (tile.foot) {
                    verify(all(last, i => i === tile.foot).length === 1, tile.caption + ": the foot is the text it ends on");
                    foot = tile.height - tile.foot.mapToItem(tile, Qt.point(0, tile.foot.baselineOffset)).y;
                } else {
                    verify(last.values !== undefined || last.maxColumns !== undefined, tile.caption + " ends on a graph or names its foot");
                    foot = tile.height - (column.y + column.height);
                }
                fuzzyCompare(foot, capTop, 1, tile.caption + ": the foot's ink " + foot + " from the bottom, the capitals " + capTop + " from the top");
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
            const left = i => i.mapToItem(popup, Qt.point(0, 0)).x;
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

        // A divider is a whole number of the screen's pixels tall, one at
        // 125 %, so wherever it lands it draws as many rows as the others.
        function test_dividers(data) {
            const popup = load(data.popup, data.monitor);
            const found = all(popup, i => i.visible && i.height > 0 && i.height <= 1 && i.radius !== undefined && i.width > 0
                                          && !ancestor(i, a => a.ceiling !== undefined));
            compare(found.length, 1);
            const edge = Math.round(Kirigami.Units.largeSpacing * 2);
            const divider = found[0];
            compare(divider.mapToItem(popup, Qt.point(0, 0)).x, edge);
            compare(divider.width, popup.width - 2 * edge);
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
            normal.networkBits = data.bits;
            try {
                networkHeader(data);
            } finally {
                normal.networkBits = true;
                normal.networkDown = 3.1e6;
            }
        }

        function networkHeader(data) {
            const popup = load("NetworkPopup", normal, data.mirrored);
            const rates = all(popup, i => i.pairWidth !== undefined)[0];
            verify(rates);
            const values = readings(rates);
            compare(values.length, 2);
            const arrows = all(rates, i => i.up !== undefined && i.color !== undefined);
            compare(arrows.map(a => a.up), [false, true]);
            const x = i => i.mapToItem(popup, Qt.point(0, 0)).x;
            const down = Format.rate(normal.networkDown, data.bits);
            const up = Format.rate(normal.networkUp, data.bits);
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

        // Each awake GPU opens with the CPU popup's header: its usage in the
        // ring, its name, its kind and memory, and its temperature over the
        // sensor's name where it has one. Nothing titles the popup "GPU"; a
        // powered-down GPU stays one line after the sections.
        function test_gpuHeaders_data() {
            const amd = ["AMD Radeon RX 7700S", "AMD Radeon 780M Graphics"];
            const kinds = ["dGPU · 8 GiB", "iGPU · shared"];
            const off = ["AMD Radeon RX 7700S · off"];
            return [{ tag: "two", monitor: normal, titles: amd, subtitles: kinds, rings: [12, 3], values: [48, 41],
                      captions: ["chip", "chip"], off: [] },
                    { tag: "outerAsleep", monitor: asleep, titles: [amd[1]], subtitles: [kinds[1]], rings: [3], values: [41],
                      captions: ["chip"], off: off },
                    { tag: "innerAsleep", monitor: innerAsleep, titles: [amd[1]], subtitles: [kinds[1]], rings: [12], values: [48],
                      captions: ["chip"], off: off },
                    { tag: "integratedOnly", monitor: integrated, titles: [amd[1]], subtitles: [kinds[1]], rings: [12], values: [48],
                      captions: ["chip"], off: [] },
                    { tag: "discreteOnly", monitor: discreteOnly, titles: [amd[0]], subtitles: [kinds[0]], rings: [12], values: [48],
                      captions: ["chip"], off: [] },
                    { tag: "intel", monitor: intel, titles: ["NVIDIA GeForce RTX 3060 Laptop GPU", "Intel Iris Xe Graphics"],
                      subtitles: kinds, rings: [12, 3], values: [48, NaN], captions: ["", ""], off: [] },
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
                                          && !ancestor(i, a => a.ceiling !== undefined));
            compare(rules.length, Math.max(0, headers.length - 1) + (headers.length > 0 ? data.off.length : 0));
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
                    { tag: "nvidia", mirrored: false, monitor: intel, shown: [unnamed] },
                    { tag: "nvidiaMirrored", mirrored: true, monitor: intel, shown: [unnamed] }];
        }

        function test_gpuHeadersMatchTheCpu(data) {
            const edge = Math.round(Kirigami.Units.largeSpacing * 2);
            const layout = popup => all(popup, i => i.visible && i.partsShown !== undefined).map(header => {
                const at = i => i.mapToItem(header, Qt.point(0, 0));
                const baseline = t => t.mapToItem(header, Qt.point(0, t.baselineOffset)).y;
                const ring = gauges(header)[0];
                const title = shownText(header, header.title);
                const subtitle = shownText(header, header.subtitle);
                const caption = header.caption !== "" ? shownText(header, header.caption) : null;
                const headline = readings(header).find(r => r.visible);
                const top = header.mapToItem(popup, Qt.point(0, 0)).y;
                const tiles = all(popup, i => i.visible && i.graphNote !== undefined)
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
            compare(cpu[0].edges, [edge, edge]);
            const gpu = layout(load("GpuPopup", data.monitor, data.mirrored));
            compare(gpu.length, 2);
            data.shown.forEach((keys, n) => {
                for (const key in cpu[0]) {
                    const expected = keys.includes(key) ? cpu[0][key] : null;
                    compare(JSON.stringify(gpu[n][key]), JSON.stringify(expected), "GPU " + (n + 1) + ": " + key);
                }
            });
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
            normal.highlightTemperatures = !data.plain;
            normal.fahrenheit = !!data.fahrenheit;
            normal.gpuOuter.temperature = data.celsius;
            normal.gpuInner.temperature = data.celsius;
            try {
                const headers = all(load("GpuPopup", normal), i => i.visible && i.partsShown !== undefined);
                compare(headers.length, 2);
                headers.forEach(h => {
                    const headline = readings(h).find(r => r.visible);
                    compare(headline.value, Format.temperature(data.celsius, !!data.fahrenheit), h.title);
                    compare(String(parts(headline).number.color), String(expected), h.title + ": the digits as drawn");
                });
            } finally {
                normal.highlightTemperatures = true;
                normal.fahrenheit = false;
                normal.gpuOuter.temperature = Qt.binding(() => normal.gpuOuter.awake ? 48 : NaN);
                normal.gpuInner.temperature = Qt.binding(() => normal.gpuInner.awake ? 41 : NaN);
            }
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
            const edge = Math.round(Kirigami.Units.largeSpacing * 2);
            const headers = all(popup, i => i.visible && i.partsShown !== undefined);
            compare(headers.length, 2);
            headers.forEach(h => {
                const title = shownText(h, h.title);
                verify(title.truncated, h.title + " elides");
                const headline = readings(h).find(r => r.visible);
                verify(headline.width >= headline.implicitWidth - 0.5, "the temperature keeps its width");
                const [near, far] = data.mirrored ? [headline, title] : [title, headline];
                verify(left(near) + near.width <= left(far) + 0.5, "the name stops short of the temperature");
                compare(left(h), edge);
                compare(left(h) + h.width, popup.width - edge);
            });
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

        // The CPU and GPU headers' captions show the plain words.
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
            compare(all(gpu, i => i.partsShown !== undefined).map(h => h.caption), data.gpu);
            data.gpu.forEach(name => verify(found.includes(name), name + " in " + JSON.stringify(found)));
            const raw = ["Tctl", "Tccd3", "edge", "junction", "mem"];
            verify(!texts(cpu).concat(found).some(t => raw.includes(t)), "no raw label is shown");
        }

        // A third longer in every string, the page keeps its width and
        // nothing runs past it: long text elides or wraps, and the header's
        // reading keeps its full width while the subtitle gives way.
        // Percentages and counts go through translation, so a language that
        // sets "%1 %" or "%%1" sets every one of them alike, and a count
        // takes the locale's digits: the rings' centres, the per-thread bars'
        // descriptions and a process that runs several times.
        function test_numbersAreTranslated() {
            const sample = normal.processSample;
            normal.processSample = [{ name: "chrome", usage: 8.4 * 16, memory: 3.9 * 1024 ** 3, count: 12 }].concat(sample.slice(1));
            root.pseudo = true;
            try {
                const translated = t => t.endsWith("ß");
                const rings = popup => all(popup, i => i.outerTone !== undefined && i.text !== undefined && i.text !== "–");
                const cpu = load("CpuPopup", normal);
                verify(rings(cpu).length > 0);
                rings(cpu).forEach(r => verify(translated(r.text), r.text));
                const threads = all(cpu, i => i.Accessible.role === Accessible.ProgressBar);
                verify(threads.length > 0);
                threads.forEach(b => verify(translated(b.Accessible.description), b.Accessible.description));
                verify(texts(cpu).some(t => t.startsWith("chrome ×" + Format.whole(12)) && translated(t)), JSON.stringify(texts(cpu)));
                const gpu = load("GpuPopup", normal);
                compare(rings(gpu).length, 2, "each GPU's ring");
                rings(gpu).forEach(r => verify(translated(r.text), r.text));
            } finally {
                root.pseudo = false;
                normal.processSample = sample;
            }
        }

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
            } finally {
                root.pseudo = false;
            }
        }
    }
}
