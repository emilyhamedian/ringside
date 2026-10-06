// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/code/style.js" as Style

// The panel's cells on their own, with FakeMonitor's readings: the
// ring and its stroke, the name or mark inside it, the readings beside it in
// every state, their faces and colours, the width each line takes, and the
// rates on the same lines. It names no Strip, popup or settings page, so it
// loads on Plasma 6.0, and it runs again in German and Egyptian Arabic.
Item {
    id: root
    width: 800
    height: 600

    // Source text to translated text, for a test that needs a long one, and
    // source text to the context the views gave translators with it.
    property var translations: ({})
    property var contexts: ({})

    // A bare qml runtime has no KI18n; the views find these on the root.
    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }
    function i18n(text, ...args) { return substitute(root.translations[text] ?? text, args); }
    function i18nc(context, text, ...args) {
        root.contexts[text] = context;
        return substitute(root.translations[text] ?? text, args);
    }
    function i18np(s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }
    function i18ncp(c, s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }

    readonly property real gib: 1073741824
    readonly property real mib: 1048576
    readonly property int day: 86400
    readonly property string fixedFamily: Kirigami.Theme.fixedWidthFont?.family ?? "monospace" // qmllint disable redundant-optional-chaining

    // Numbers as the locale writes them, independently of format.js.
    function digits(v) {
        return Number(v).toLocaleString(Qt.locale(), "f", 0);
    }
    function decimal(v) {
        return Number(v).toLocaleString(Qt.locale(), "f", 1);
    }
    function percent(v) {
        return digits(v) + "%";
    }
    function degrees(v) {
        return digits(v) + "°";
    }

    // As "#aarrggbb": Text keeps 8 bits a channel, Qt.alpha() more.
    function tone(name) {
        return String(name === "negative" ? Kirigami.Theme.negativeTextColor
                    : name === "neutral" ? Kirigami.Theme.neutralTextColor
                    : name === "dim" ? Style.dim(Kirigami.Theme.textColor)
                    : Kirigami.Theme.textColor);
    }

    // Every visible text under an item.
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

    // Every item under `item`, itself included, that `test` accepts.
    function findAll(item, test) {
        const found = [];
        const collect = i => {
            if (test(i)) {
                found.push(i);
            }
            i.children.forEach(collect);
        };
        collect(item);
        return found;
    }

    function find(item, test) {
        return findAll(item, test)[0] ?? null;
    }

    // Texts with their digits, in any locale, as "0", so readings that
    // differ only in their digits read the same.
    function shape(texts) {
        return texts.join(" ").replace(/[0-9\u0660-\u0669\u06f0-\u06f9]/g, "0");
    }

    Component {
        id: monitorComponent
        FakeMonitor {}
    }

    Component {
        id: ringComponent
        RingCellContent {
            ring: 34
            textShown: true
            twoLines: true
        }
    }

    Component {
        id: usageComponent
        UsageCellContent {
            ring: 34
            textShown: true
            twoLines: true
        }
    }

    Component {
        id: mirrorComponent
        Item {
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true
            width: 400
            height: 100
        }
    }

    Component {
        id: readoutComponent
        Readout {
            lines: ({ first: "40%", level: 0, second: "", heat: 0, parts: [] })
        }
    }

    // A text of its own, to compare a drawn one with.
    Component {
        id: probeComponent
        Text {}
    }

    Component {
        id: rateComponent
        RateCellContent {
            vertical: false
        }
    }

    // A ring cell and the network's rates side by side in a panel of
    // `thickness`, each centred across it as the strip centres a cell's
    // content.
    Component {
        id: pairComponent
        Item {
            id: pair

            required property var monitor
            required property real thickness
            required property real ring
            required property bool twoLines
            readonly property alias rings: ringsContent
            readonly property alias rates: ratesContent

            width: 400
            height: thickness

            // Centred as the strip centres a cell's content.
            RingCellContent {
                id: ringsContent
                y: Math.round((parent.height - height) / 2)
                monitor: pair.monitor
                item: "cpu"
                ring: pair.ring
                textShown: true
                twoLines: pair.twoLines
            }

            RateCellContent {
                id: ratesContent
                x: 200
                y: Math.round((parent.height - height) / 2)
                monitor: pair.monitor
                item: "network"
                vertical: false
                singleRow: !pair.twoLines
            }
        }
    }

    Component {
        id: panelCellComponent
        PanelCell {
            item: "cpu"
            open: true
        }
    }

    // Kirigami's own theme has the highlight colour for focus; a colour of
    // its own shows which one the cell draws.
    Component {
        id: focusCellComponent
        PanelCell {
            item: "cpu"
            Kirigami.Theme.inherit: false
            Kirigami.Theme.focusColor: "#ff00ff"
        }
    }

    // A cell with its content declared inside it, as the strip's would be
    // without a Loader.
    Component {
        id: declaredCellComponent
        PanelCell {
            item: "cpu"
            contentItem: declaredBlock
            settleDelay: 400
            relayoutWindow: 1

            Item {
                id: declaredBlock
                implicitWidth: 50
                implicitHeight: 34
            }
        }
    }

    Component {
        id: signalSpyComponent
        SignalSpy {}
    }

    Component {
        id: blockComponent
        Item {
            implicitWidth: 50
            implicitHeight: 34
        }
    }

    Component {
        id: faceComponent
        ReadoutFont {}
    }

    Component {
        id: gaugeComponent
        RingGauge {}
    }

    // A Claude mark in a middle `room` wide.
    Component {
        id: markComponent
        Item {
            id: holder

            property real room: 0
            readonly property alias name: inside

            width: 34
            height: 34

            RingName {
                id: inside
                item: "claude"
                room: holder.room
            }
        }
    }

    Component {
        id: figureComponent
        TextMetrics {
            text: "0"
        }
    }

    // Noto Sans has figures of both kinds, so the features show in its widths.
    Component {
        id: probeMetricsComponent
        TextMetrics {
            property var features: ({})
            font.family: "Noto Sans"
            font.pointSize: 10
            font.features: features
        }
    }

    Component {
        id: probeTextComponent
        Text {
            property var features: ({})
            font.family: "Noto Sans"
            font.pointSize: 10
            font.features: features
            textFormat: Text.PlainText
        }
    }

    Component {
        id: proportionalComponent
        FontMetrics {
            font.family: "Noto Sans"
            font.pointSize: 10
            font.features: ({ "pnum": 1 })
        }
    }

    // Name, ring, readings and rates, with every state each can show.
    TestCase {
        name: "Cells"
        when: windowShown

        property var monitor: null
        property var made: []

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            monitor = monitorComponent.createObject(root);
        }

        // The cells go first, so their bindings never see the monitor gone.
        function cleanup() {
            made.forEach(c => c.destroy());
            made = [];
            wait(0);
            monitor.destroy();
            root.translations = {};
        }

        function keep(object) {
            made.push(object);
            return object;
        }

        // Layouts size themselves when polished, before the next frame.
        function settle() {
            verify(waitForPolish(root.Window.window), "polished");
        }

        function cell(item, properties) {
            const component = item === "claude" || item === "codex" ? usageComponent
                            : item === "network" || item === "disk" ? rateComponent : ringComponent;
            const c = keep(component.createObject(root, Object.assign({ monitor: monitor, item: item }, properties)));
            waitForRendering(c);
            return c;
        }

        function gauge(c) {
            return root.find(c, i => i.centreWidth !== undefined);
        }

        function nameIn(c) {
            return root.find(gauge(c), i => i.fits !== undefined);
        }

        function label(name) {
            return root.find(name, i => i.fontSizeMode !== undefined);
        }

        // The Claude or Codex mark, loaded for those items alone.
        function mark(name) {
            return root.find(name, i => i.markName !== undefined);
        }

        function line(c, which) {
            return root.find(c, i => i.objectName === which);
        }

        // qmltestrunner's theme has a 12 pt small font beside a 9 pt default
        // one, too large to name a 34 px ring; Breeze has 8 pt beside 10.
        // The name's own scale stands in for Breeze's size.
        function breezeSized(c) {
            nameIn(c).animated = false;
            nameIn(c).sizeFactor = 8 / Kirigami.Theme.smallFont.pointSize;
            settle();
            return c;
        }

        // A Claude or Codex weekly window at `week` = [percent, seconds left]
        // with no model limit, or an entry without one for null.
        function setWeek(item, week) {
            const usage = monitor.usage;
            const entry = { status: "ok", fetchedAt: usage.createdAt, scoped: [] };
            if (week) {
                entry.weekly = usage.window(week[0], week[1], []);
            }
            const entries = Object.assign({}, usage.entries);
            entries[item] = entry;
            usage.entries = entries;
        }

        // { set: monitor properties, outer and inner: GPU slot properties,
        // week: see setWeek }, for `item`.
        function apply(item, state) {
            for (const key in state.set ?? {}) {
                monitor[key] = state.set[key];
            }
            for (const key in state.outer ?? {}) {
                monitor.gpuOuter[key] = state.outer[key];
            }
            for (const key in state.inner ?? {}) {
                monitor.gpuInner[key] = state.inner[key];
            }
            if (state.week !== undefined) {
                setWeek(item, state.week);
            }
        }

        // The readings beside the ring, or the rates: the visible texts
        // outside the ring.
        function readingsIn(c) {
            const g = gauge(c);
            const inRing = t => {
                for (let i = t; i; i = i.parent) {
                    if (i === g) {
                        return true;
                    }
                }
                return false;
            };
            return root.findAll(c, i => i.visible && typeof i.text === "string" && i.text !== "" && !inRing(i));
        }

        function centreY(item, c) {
            return item.mapToItem(c, Qt.point(0, item.height / 2)).y;
        }

        function baselineIn(text, scene) {
            return text.mapToItem(scene, Qt.point(0, text.baselineOffset)).y;
        }

        function checkFace(text, weight, what) {
            compare(text.font.weight, weight, what + " weight");
            compare(text.font.family, Kirigami.Theme.defaultFont.family, what + " is in the theme's sans");
            verify(text.font.family !== root.fixedFamily, what + " is not monospace");
            compare(text.font.features.tnum, 1, what + " has figures of one width");
        }

        function test_ringDiameterAndStroke_data() {
            const rows = [];
            for (const [ring, stroke] of [[16, 2], [26, 2], [34, 2.5], [45, 3.5], [52, 4]]) {
                rows.push({ tag: ring + " cpu", item: "cpu", ring: ring, stroke: stroke, inner: false });
                rows.push({ tag: ring + " dual gpu", item: "gpu", ring: ring, stroke: stroke, inner: true });
                rows.push({ tag: ring + " claude", item: "claude", ring: ring, stroke: stroke, inner: true });
            }
            return rows;
        }

        // About a thirteenth of the ring in half pixels, never under 2, and
        // the middle a pixel clear of the innermost ring.
        function test_ringDiameterAndStroke(data) {
            const g = gauge(cell(data.item, { ring: data.ring }));
            compare(g.width, data.ring);
            compare(g.height, data.ring);
            compare(g.strokeWidth, data.stroke);
            compare(g.strokeWidth, Math.max(2, Math.round(data.ring / 6.5) / 2));
            compare(g.inner, data.inner);
            const arcs = root.findAll(g, i => i.animating !== undefined && i.visible);
            compare(arcs.length, data.inner ? 2 : 1);
            arcs.forEach(arc => verify(arc.radius + arc.strokeWidth / 2 <= data.ring / 2, "the ring stays in its square"));
            const hole = Math.min(...arcs.map(arc => arc.radius - arc.strokeWidth / 2));
            compare(g.centreWidth, 2 * (hole - 1));
        }

        function test_noPercentageInsideTheRing_data() {
            const rows = [];
            for (const item of ["cpu", "memory", "gpu", "claude", "codex"]) {
                rows.push({ tag: item, item: item, textShown: true });
                rows.push({ tag: item + " ring only", item: item, textShown: false });
            }
            return rows;
        }

        function test_noPercentageInsideTheRing(data) {
            const c = breezeSized(cell(data.item, { textShown: data.textShown }));
            const g = gauge(c);
            compare(g.text, "");
            if (data.item === "gpu") {
                verify(g.inner, "both GPUs are drawn");
            }
            const number = new RegExp("[0-9%" + [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map(root.digits).join("") + "]");
            const inside = root.texts(g);
            verify(!inside.some(text => number.test(text)), JSON.stringify(inside));
        }

        function test_nameInsideTheRing_data() {
            const names = [{ item: "cpu", text: "CPU" }, { item: "memory", text: "MEM" }, { item: "gpu", text: "GPU" },
                           { item: "claude", mark: "claude" }, { item: "codex", mark: "codex" }];
            const rows = [];
            for (const n of names) {
                rows.push(Object.assign({ tag: n.item + " 34", ring: 34, textShown: true, twoLines: true, shown: true }, n));
                rows.push(Object.assign({ tag: n.item + " 16", ring: 16, textShown: true, twoLines: true, shown: false }, n));
                rows.push(Object.assign({ tag: n.item + " ring only", ring: 34, textShown: false, twoLines: true, shown: true }, n));
                rows.push(Object.assign({ tag: n.item + " ring only, thin", ring: 34, textShown: false, twoLines: false, shown: true }, n));
                rows.push(Object.assign({ tag: n.item + " one line", ring: 34, textShown: true, twoLines: false, shown: false }, n));
            }
            return rows;
        }

        // Inside the ring, inside the inner ring where there is one (both
        // GPUs, Claude with its model limit); left out where it can't be
        // read or beside readings that share a line.
        function test_nameInsideTheRing(data) {
            const c = breezeSized(cell(data.item, { ring: data.ring, textShown: data.textShown, twoLines: data.twoLines }));
            const g = gauge(c);
            const name = nameIn(c);
            if (data.item === "gpu" || data.item === "claude") {
                verify(g.inner, "drawn with its inner ring");
            }
            compare(name.visible, data.shown);
            verify(name.Accessible.ignored, "the cell's description names the item");
            if (data.text) {
                compare(label(name).text, data.text);
                compare(label(name).visible, data.shown);
                compare(String(label(name).color), root.tone("dim"));
                verify(!mark(name), "a system ring loads no mark");
            } else {
                compare(mark(name).markName, data.mark);
                compare(mark(name).visible, data.shown);
                verify(!label(name).visible);
            }
            if (data.shown && data.text) {
                // The label is laid out across the round middle's chord,
                // its text centred in it.
                compare(label(name).width, name.chord);
                verify(label(name).paintedWidth <= label(name).width + 0.5, "drawn within the chord");
            }
            if (data.shown) {
                // The label by its capitals' middle, without the letter
                // space after its last glyph; the mark by its artwork's
                // middle, through its scale.
                // Mapped as a point: Qt 6.6 drops the fraction of an x and y
                // given apart.
                const middle = data.text
                    ? label(name).mapToItem(g, Qt.point(label(name).width / 2 - label(name).font.letterSpacing / 2,
                                                        label(name).baselineOffset - name.capHeight / 2))
                    : mark(name).mapToItem(g, Qt.point(mark(name).art.box[0] + mark(name).art.box[2] / 2,
                                                       mark(name).art.box[1] + mark(name).art.box[2] / 2));
                verify(Math.abs(middle.x - g.width / 2) <= 0.5 && Math.abs(middle.y - g.height / 2) <= 0.5,
                       "centred: " + middle.x + ", " + middle.y);
            }
            if (data.shown && data.text) {
                // Across, the drawn advance less its trailing letter space
                // is held closer: half that space is about a third of a
                // pixel, inside the half pixel above.
                const l = label(name);
                const left = (l.width - l.contentWidth) / 2;
                const across = l.mapToItem(g, Qt.point(left + (l.contentWidth - l.font.letterSpacing) / 2, 0)).x;
                verify(l.font.letterSpacing / 2 > 0.25, "a letter space worth checking: " + l.font.letterSpacing);
                fuzzyCompare(across, g.width / 2, 0.05, "the advance's middle on the ring's");
            }
        }

        function test_nameFitsTheHole_data() {
            const rows = [];
            for (let ring = 16; ring <= 52; ring += 2) {
                rows.push({ tag: String(ring), ring: ring });
            }
            return rows;
        }

        // At the theme's size and at Breeze's, a name that shows fits the
        // middle, and one left out would not fit the round middle's chord at
        // its smallest size.
        function test_nameFitsTheHole(data) {
            const cases = [{ item: "cpu" }, { item: "memory" },
                           { item: "gpu", inner: true }, { item: "gpu", inner: false },
                           { item: "claude", inner: true }, { item: "claude", inner: false },
                           { item: "codex", inner: false }, { item: "codex", inner: true }];
            const metrics = keep(probeMetricsComponent.createObject(root));
            metrics.font.family = Kirigami.Theme.defaultFont.family;
            for (const k of cases) {
                monitor.gpuInner.present = !(k.item === "gpu" && !k.inner);
                monitor.usage.innerChoices = { claude: k.item === "claude" && !k.inner ? "none" : "", codex: "" };
                if (k.item === "codex" && k.inner) {
                    const entries = Object.assign({}, monitor.usage.entries);
                    entries.codex = Object.assign({}, entries.codex, { scoped: [Object.assign({ id: "Spark", label: "Spark" },
                                                                                               monitor.usage.window(20, day, []))] });
                    monitor.usage.entries = entries;
                }
                const c = cell(k.item, { ring: data.ring });
                const g = gauge(c);
                const name = nameIn(c);
                name.animated = false;
                compare(g.inner, k.inner === true, k.item + " inner ring");
                for (const factor of [1, 8 / Kirigami.Theme.smallFont.pointSize]) {
                    name.sizeFactor = factor;
                    settle();
                    const what = k.item + (k.inner ? " with inner ring" : "") + " at " + factor.toFixed(2) + ": ";
                    if (name.usage) {
                        const size = name.markSize;
                        const fits = size >= Kirigami.Units.iconSizes.small / 2 && size <= g.centreWidth;
                        compare(name.visible, fits, what + "mark " + size + " in " + g.centreWidth);
                        continue;
                    }
                    const small = Kirigami.Theme.smallFont.pointSize * factor;
                    metrics.font.pointSize = small * 0.7;
                    metrics.font.letterSpacing = small * 0.08;
                    metrics.text = label(name).text;
                    const chord = 2 * Math.sqrt(Math.max(0, (g.centreWidth / 2) ** 2 - (metrics.tightBoundingRect.height / 2) ** 2));
                    if (name.visible) {
                        verify(label(name).paintedWidth <= g.centreWidth + 0.5,
                               what + "drawn " + label(name).paintedWidth + " in " + g.centreWidth);
                        verify(metrics.advanceWidth <= chord, what + metrics.advanceWidth + " in chord " + chord);
                    } else {
                        verify(metrics.advanceWidth > chord, what + "left out, yet " + metrics.advanceWidth + " fits chord " + chord);
                    }
                }
                made.splice(made.indexOf(c), 1);
                c.destroy();
            }
        }

        function test_ringsShareTheCentre_data() {
            const rows = [];
            for (const size of [33, 34, 45, 52]) {
                rows.push({ tag: size + " one ring", size: size, inner: false });
                rows.push({ tag: size + " two rings", size: size, inner: true });
            }
            return rows;
        }

        // Each arc is drawn about the gauge's exact middle, an odd size's
        // half pixel included, so the two rings sit in each other evenly.
        function test_ringsShareTheCentre(data) {
            const g = keep(gaugeComponent.createObject(root, { width: data.size, height: data.size, inner: data.inner,
                                                               value: 40, innerValue: 20 }));
            waitForRendering(g);
            const arcs = root.findAll(g, i => i.animating !== undefined && i.visible);
            compare(arcs.length, data.inner ? 2 : 1);
            for (const arc of arcs) {
                const middle = arc.mapToItem(g, Qt.point(arc.width / 2, arc.height / 2));
                compare(middle.x, data.size / 2, "across");
                compare(middle.y, data.size / 2, "down");
                verify(arc.radius + arc.strokeWidth / 2 <= data.size / 2, "the ring stays in its square");
            }
        }

        function test_centrePercentage_data() {
            const rows = [];
            for (const size of [33, 34, 50]) {
                rows.push({ tag: size + " 62%", size: size, text: root.percent(62) });
                rows.push({ tag: size + " 100%", size: size, text: root.percent(100) });
            }
            return rows;
        }

        // The popups' percentage in the middle of a ring is in the theme's
        // sans with figures of one width, and its figures, not its line box
        // or rounded width, sit on the ring's middle.
        function test_centrePercentage(data) {
            const g = keep(gaugeComponent.createObject(root, { width: data.size, height: data.size, value: 62,
                                                               text: data.text, textScale: 0.29 }));
            waitForRendering(g);
            const t = root.find(g, i => i !== g && i.text === data.text);
            verify(t && t.visible, "the percentage shows");
            compare(t.font.family, Kirigami.Theme.defaultFont.family, "the theme's sans");
            verify(t.font.family !== root.fixedFamily, "not monospace");
            compare(t.font.features.tnum, 1, "figures of one width");
            const figure = keep(figureComponent.createObject(root, { font: t.font }));
            const middle = t.mapToItem(g, Qt.point(t.width / 2, t.baselineOffset - figure.tightBoundingRect.height / 2));
            verify(Math.abs(middle.x - data.size / 2) <= 0.01 && Math.abs(middle.y - data.size / 2) <= 0.5,
                   "centred: " + middle.x + ", " + middle.y + " in " + data.size);
        }

        // A middle too small for a mark leaves it out rather than sizing it
        // below nothing.
        function test_noRoomNoMark() {
            for (const room of [0, 1, 2, 3]) {
                const holder = keep(markComponent.createObject(root, { room: room }));
                waitForRendering(holder);
                verify(holder.name.markSize >= 0, room + ": " + holder.name.markSize);
                verify(!holder.name.visible, room + " px holds no mark");
            }
        }

        function test_longTranslationHidesTheName() {
            root.translations = { "MEM": "ARBEITSSPEICHER" };
            const memory = breezeSized(cell("memory"));
            const cpu = breezeSized(cell("cpu"));
            compare(label(nameIn(memory)).text, "ARBEITSSPEICHER");
            verify(!nameIn(memory).fits, "too long for the ring");
            verify(!nameIn(memory).visible);
            verify(nameIn(cpu).visible);
            compare(label(nameIn(cpu)).text, "CPU");
            cell("gpu");
            for (const text of ["CPU", "GPU", "MEM"]) {
                verify(root.contexts[text].includes("at most 3 characters"),
                       text + " tells translators its limit: " + root.contexts[text]);
            }
        }

        function test_lines_data() {
            const asleep = { phase: "asleep" };
            return [
                { tag: "cpu", item: "cpu", lines: [percent(23), degrees(61)], tones: ["text", "dim"] },
                { tag: "cpu 80 °C", item: "cpu", set: { cpuTemperature: 80 }, lines: [percent(23), degrees(80)], tones: ["text", "neutral"] },
                { tag: "cpu 95 °C", item: "cpu", set: { cpuTemperature: 95 }, lines: [percent(23), degrees(95)], tones: ["text", "negative"] },
                { tag: "cpu 74 %", item: "cpu", set: { cpuUsage: 74 }, lines: [percent(74), degrees(61)], tones: ["text", "dim"] },
                { tag: "cpu 75 %", item: "cpu", set: { cpuUsage: 75 }, lines: [percent(75), degrees(61)], tones: ["neutral", "dim"] },
                { tag: "cpu 89 %", item: "cpu", set: { cpuUsage: 89 }, lines: [percent(89), degrees(61)], tones: ["neutral", "dim"] },
                { tag: "cpu 90 %", item: "cpu", set: { cpuUsage: 90 }, lines: [percent(90), degrees(61)], tones: ["negative", "dim"] },
                { tag: "cpu no reading", item: "cpu", set: { cpuUsage: NaN, cpuTemperature: NaN }, lines: ["–", "–"], tones: ["text", "dim"] },
                { tag: "fahrenheit", item: "cpu", set: { fahrenheit: true, cpuTemperature: 38 }, lines: [percent(23), degrees(100)], tones: ["text", "dim"] },
                { tag: "fahrenheit hot", item: "cpu", set: { fahrenheit: true, cpuTemperature: 95 }, lines: [percent(23), degrees(203)], tones: ["text", "negative"] },
                { tag: "memory", item: "memory", lines: [percent(42), decimal(13.4) + "G"], tones: ["text", "dim"] },
                { tag: "memory 77 %", item: "memory", set: { memoryPercent: 77 }, lines: [percent(77), decimal(13.4) + "G"], tones: ["neutral", "dim"] },
                { tag: "memory in MiB", item: "memory", set: { memoryUsed: 900 * mib, memoryPercent: 3 }, lines: [percent(3), digits(900) + "M"], tones: ["text", "dim"] },
                { tag: "dual gpu", item: "gpu", lines: [percent(12), degrees(48)], tones: ["text", "dim"], absent: degrees(41) },
                { tag: "dual gpu hot", item: "gpu", outer: { usage: 90, temperature: 92 }, lines: [percent(90), degrees(92)], tones: ["negative", "negative"] },
                { tag: "dual gpu warm", item: "gpu", outer: { temperature: 80 }, lines: [percent(12), degrees(80)], tones: ["text", "neutral"] },
                { tag: "outer asleep", item: "gpu", outer: asleep, lines: [percent(3), degrees(41)], tones: ["text", "dim"] },
                { tag: "only gpu asleep", item: "gpu", outer: asleep, inner: { present: false }, lines: ["off", ""], tones: ["dim", "dim"] },
                { tag: "intel only", item: "gpu", outer: { reportsTemperature: false, kind: "integrated" }, inner: { present: false },
                  lines: [percent(12), ""], tones: ["text", "dim"] },
                { tag: "claude", item: "claude", lines: [percent(52), digits(2) + "d"], tones: ["text", "dim"] },
                { tag: "claude 81 %", item: "claude", week: [81, 5 * 3600 + 12 * 60], lines: [percent(81), digits(5) + "h " + digits(12) + "m"],
                  tones: ["neutral", "dim"] },
                // At this pace the week runs out before its reset.
                { tag: "claude 81 % runs out", item: "claude", week: [81, 2 * day + 21 * 3600], lines: [percent(81), digits(2) + "d"],
                  tones: ["negative", "dim"] },
                { tag: "claude last day", item: "claude", week: [40, 23 * 3600 + 5 * 60], lines: [percent(40), digits(23) + "h " + digits(5) + "m"],
                  tones: ["text", "dim"] },
                { tag: "claude 95 %", item: "claude", week: [95, 5 * 3600 + 12 * 60], lines: [percent(95), digits(5) + "h " + digits(12) + "m"],
                  tones: ["negative", "dim"] },
                { tag: "claude minutes", item: "claude", week: [40, 12 * 60], lines: [percent(40), digits(12) + "m"], tones: ["text", "dim"] },
                { tag: "claude reset passed", item: "claude", week: [40, -600], lines: [percent(40), "–"], tones: ["text", "dim"] },
                { tag: "claude no weekly", item: "claude", week: null, lines: ["–", "–"], tones: ["text", "dim"] },
                { tag: "codex", item: "codex", lines: [percent(24), digits(5) + "d"], tones: ["text", "dim"] }
            ];
        }

        // The ring's own reading, heavier and in the ring's colour, over a
        // dimmer one in its own heat colour. A countdown is a day count from
        // a day out, then hours and minutes.
        function test_lines(data) {
            apply(data.item, data);
            const c = cell(data.item);
            const first = line(c, "first");
            const second = line(c, "second");
            compare([first.text, second.text], data.lines);
            compare(String(first.color), root.tone(data.tones[0]), "line 1 colour");
            compare(String(second.color), root.tone(data.tones[1]), "line 2 colour");
            checkFace(first, Font.DemiBold, "line 1");
            checkFace(second, Font.Normal, "line 2");
            if (data.absent) {
                verify(!root.texts(c).includes(data.absent), JSON.stringify(root.texts(c)));
            }
        }

        function test_line2KeepsItsSpace_data() {
            return [{ tag: "two lines", twoLines: true }, { tag: "one line", twoLines: false }];
        }

        // An asleep GPU or an Intel one has no second reading; the cell
        // keeps its height and its first line stays put. Stacked, the blank
        // second line keeps its row; on one line it goes with its dot. Only
        // the width follows the text.
        function test_line2KeepsItsSpace(data) {
            const c = cell("gpu", { twoLines: data.twoLines, ring: data.twoLines ? 34 : 26 });
            const measure = () => {
                const first = line(c, "first");
                const second = line(c, "second");
                const at = first.mapToItem(c, Qt.point(0, 0));
                return { height: c.implicitHeight, firstX: at.x, firstY: at.y, firstHeight: first.height,
                         second: data.twoLines ? [second.visible, second.mapToItem(c, Qt.point(0, 0)).y, second.height] : [] };
            };
            const awake = measure();
            compare(line(c, "second").text, degrees(48));
            // Layout only: the readings change at once (see tst_motion).
            c.animated = false;
            monitor.gpuInner.present = false;
            monitor.gpuOuter.phase = "asleep";
            settle();
            compare([line(c, "first").text, line(c, "second").text], ["off", ""]);
            compare(readingsIn(c).map(t => t.text), ["off"], "no dot beside nothing");
            compare(line(c, "second").visible, data.twoLines);
            compare(measure(), awake, "asleep");
            monitor.gpuOuter.phase = "live";
            monitor.gpuOuter.reportsTemperature = false;
            settle();
            compare([line(c, "first").text, line(c, "second").text], [percent(12), ""]);
            compare(measure(), awake, "Intel");
        }

        function test_thinPanelIsOneLine_data() {
            return [
                { tag: "cpu", item: "cpu", texts: [percent(23), "·", degrees(61)] },
                { tag: "memory", item: "memory", texts: [percent(42), "·", decimal(13.4) + "G"] },
                { tag: "claude", item: "claude", texts: [percent(52), "·", digits(2) + "d"] },
                { tag: "claude last day", item: "claude", week: [52, 5 * 3600 + 12 * 60], texts: [percent(52), "·", digits(5) + "h " + digits(12) + "m"] },
                { tag: "gpu asleep", item: "gpu", asleep: true, texts: ["off"] }
            ];
        }

        // On a thin panel the readings share one line, centred on the ring,
        // and the ring goes unnamed.
        function test_thinPanelIsOneLine(data) {
            apply(data.item, data);
            const c = breezeSized(cell(data.item, { ring: 26, twoLines: false }));
            if (data.asleep) {
                c.animated = false;
                monitor.gpuInner.present = false;
                monitor.gpuOuter.phase = "asleep";
                settle();
            }
            compare(root.texts(c), data.texts);
            verify(!nameIn(c).visible);
            const middle = centreY(gauge(c), c);
            const shown = root.findAll(c, i => i.visible && typeof i.text === "string" && i.text !== "");
            shown.forEach(t => verify(Math.abs(centreY(t, c) - middle) <= 0.5, t.text + " at " + centreY(t, c) + ", ring at " + middle));
            const dot = shown.find(t => t.text === "·");
            if (dot) {
                compare(String(dot.color), root.tone("dim"));
            }
        }

        function test_mirroredCountdownReadsFromTheRight_data() {
            const set = zero => text => text.replace(/[0-9]/g, d => String.fromCharCode(zero + Number(d)));
            return [{ tag: "Arabic-Indic digits, as in Egypt", digits: set(0x660) },
                    { tag: "Latin digits, as in Israel", digits: set(0x30) },
                    { tag: "Extended Arabic-Indic digits, as in Iran", digits: set(0x6f0) }];
        }

        // Mirrored, the countdown's first part is rightmost, read first as in
        // the popup's header, whatever digits the locale has. A probe draws
        // each part as a link, so linkAt() says which one lies where.
        function test_mirroredCountdownReadsFromTheRight(data) {
            const holder = keep(mirrorComponent.createObject(root));
            const parts = [{ value: data.digits("23"), unit: "h" }, { value: data.digits("5"), unit: "m" }];
            const readout = keep(readoutComponent.createObject(holder, {
                lines: { first: "40%", level: 0, second: "", heat: 0, parts: parts }
            }));
            waitForRendering(readout);
            const second = line(readout, "second");
            const probe = keep(probeComponent.createObject(holder, { font: second.font, y: 50, width: 200, textFormat: Text.StyledText }));
            probe.text = second.text.split(" ").map((part, i) => '<a href="' + i + '">' + part + "</a>").join(" ");
            waitForRendering(probe);
            const order = [];
            for (let x = 0; x < probe.width; x += 0.5) {
                const link = probe.linkAt(x, probe.height / 2);
                if (link !== "" && order[order.length - 1] !== link) {
                    order.push(link);
                }
            }
            compare(order.join(","), "1,0", "the parts from left to right");
        }

        function test_countdownText_data() {
            const rows = [];
            for (const [what, left, parts] of [["days", 6 * day + 23 * 3600, [[6, "d"]]],
                                               ["last day", 23 * 3600 + 5 * 60, [[23, "h"], [5, "m"]]],
                                               ["minutes", 12 * 60, [[12, "m"]]]]) {
                for (const mirrored of [false, true]) {
                    rows.push({ tag: what + (mirrored ? " mirrored" : ""), left: left, parts: parts, mirrored: mirrored });
                }
            }
            return rows;
        }

        // A countdown is plain text in the face of the other second lines,
        // its units as large as its digits, as in "11.2G" or "61°", and its
        // parts a space apart. Mirrored, a right-to-left mark leads it and
        // the space, so the days come first from the right. Its room counts
        // every digit as the widest, as every line's does.
        function test_countdownText(data) {
            setWeek("claude", [52, data.left]);
            const holder = data.mirrored ? keep(mirrorComponent.createObject(root)) : root;
            const c = keep(usageComponent.createObject(holder, { monitor: monitor, item: "claude" }));
            waitForRendering(c);
            const second = line(c, "second");
            const mark = data.mirrored ? "\u200f" : "";
            compare(second.textFormat, Text.PlainText);
            compare(second.text, mark + data.parts.map(([value, unit]) => root.digits(value) + unit).join(mark + " "));
            verify(second.contentWidth <= second.width, second.contentWidth + " in " + second.width);

            const readout = root.find(c, i => i.textWidth !== undefined);
            const face = readout.face.plain.font;
            compare([second.font.family, second.font.pointSize, second.font.weight], [face.family, face.pointSize, face.weight],
                    "the face of a temperature or memory line");
            compare(readout.rooms[1], readout.face.room(readout.face.plain, [second.text]), "the room of its widest digits");
            const probe = keep(probeComponent.createObject(root, { font: second.font, textFormat: Text.PlainText,
                                                                   text: readout.face.widestDigits(readout.face.plain, second.text) }));
            verify(readout.rooms[1] >= Math.ceil(probe.implicitWidth), "the widest digits take " + probe.implicitWidth + " in " + readout.rooms[1]);
            compare(root.findAll(readout, i => i.textFormat !== undefined).length, 3, "the two lines and the dot, nothing hidden to measure");
        }

        function test_widthFollowsCharacters_data() {
            const states = {
                cpu: [{ set: { cpuUsage: 5 } }, { set: { cpuUsage: 8 } }, { set: { cpuUsage: 11, cpuTemperature: 11 } },
                      { set: { cpuUsage: 88, cpuTemperature: 88 } }, { set: { cpuUsage: 100, cpuTemperature: 1 } },
                      { set: { cpuUsage: 100, cpuTemperature: 9 } }, { set: { cpuUsage: NaN, cpuTemperature: NaN } },
                      { set: { fahrenheit: true, cpuUsage: 100, cpuTemperature: 149 } }],
                memory: [{ set: { memoryPercent: 11, memoryUsed: 1.11 * gib } }, { set: { memoryPercent: 88, memoryUsed: 8.88 * gib } },
                         { set: { memoryPercent: 1, memoryUsed: 111 * mib } }, { set: { memoryPercent: 8, memoryUsed: 888 * mib } },
                         { set: { memoryPercent: 100, memoryUsed: 1023 * mib } }, { set: { memoryPercent: NaN, memoryUsed: NaN } }],
                gpu: [{ outer: { usage: 11, temperature: 11 } }, { outer: { usage: 88, temperature: 88 } },
                      { outer: { usage: 5 } }, { outer: { usage: 9 } }, { outer: { phase: "asleep" }, inner: { present: false } },
                      { outer: { phase: "live", reportsTemperature: false } }],
                claude: [{ week: [11, 6 * day + 23 * 3600] }, { week: [88, day + 11 * 3600] }, { week: [5, 5 * 3600 + 12 * 60] },
                         { week: [8, 9 * 3600 + 59 * 60] }, { week: [100, 59 * 60] }, { week: [100, 10 * 60] },
                         { week: [NaN, 2 * day] }, { week: null }],
                network: [{ set: { networkDown: 111e3 / 8, networkUp: 888e3 / 8 } }, { set: { networkDown: 888e3 / 8, networkUp: 111e3 / 8 } },
                          { set: { networkDown: 11.1e6 / 8, networkUp: 88.8e6 / 8 } }, { set: { networkDown: 88.8e6 / 8, networkUp: 11.1e6 / 8 } },
                          { set: { networkDown: 999 / 8, networkUp: 1 / 8 } }, { set: { networkDown: 0, networkUp: NaN } },
                          { set: { networkDown: 888e9 / 8, networkUp: 1.1e12 / 8 } }],
                disk: [{ set: { diskRead: 11.1 * mib, diskWrite: 88.8 * mib } }, { set: { diskRead: 88.8 * mib, diskWrite: 11.1 * mib } },
                       { set: { diskRead: 1023, diskWrite: 1023 * 1024 } }, { set: { diskRead: 1000, diskWrite: 1000 * 1024 } },
                       { set: { diskRead: 0, diskWrite: NaN } }, { set: { diskRead: 99.9 * gib, diskWrite: 1023 * 1024 ** 4 } }]
            };
            const rows = [];
            for (const item in states) {
                rows.push({ tag: item + " two lines", item: item, twoLines: true, states: states[item] });
                rows.push({ tag: item + " one line", item: item, twoLines: false, states: states[item] });
            }
            return rows;
        }

        // A cell is as wide as its readings, with every digit counted as the
        // widest: readings that differ only in their digits take the same
        // width, the text ends where the cell does, give or take the dim
        // line's overhang, and every text fits the box it is drawn in.
        function test_widthFollowsCharacters(data) {
            const rate = data.item === "network" || data.item === "disk";
            const c = cell(data.item, rate ? { singleRow: !data.twoLines } : { twoLines: data.twoLines, ring: data.twoLines ? 34 : 26 });
            const height = c.implicitHeight;
            const readout = root.find(c, i => i.textWidth !== undefined);
            const widths = {};
            for (const state of data.states) {
                apply(data.item, state);
                settle();
                const shown = readingsIn(c);
                const key = root.shape(shown.map(t => t.text));
                const what = "showing " + shown.map(t => t.text).join(" ");
                compare(c.implicitHeight, height, what);
                shown.forEach(t => verify(t.contentWidth <= t.width, what + ": " + t.text + " is " + t.contentWidth + " wide in " + t.width));
                // Where the text ends: a right-aligned one at its box's end.
                // Rounding up, the room's and the layout's, and the last
                // glyph's ink counted a pixel high leave under three pixels.
                const end = Math.max(...shown.map(t => t.mapToItem(c, Qt.point(0, 0)).x
                                                      + (t.effectiveHorizontalAlignment === Text.AlignRight ? t.width : t.contentWidth)));
                verify(c.implicitWidth - end < 3 && end - c.implicitWidth <= Kirigami.Units.smallSpacing,
                       what + ": the text ends at " + end + ", the cell at " + c.implicitWidth);
                if (readout) {
                    compare(c.implicitWidth, gauge(c).width + Kirigami.Units.largeSpacing + readout.implicitWidth - readout.overhang,
                            what + ": the width the layout gives the readings");
                }
                widths[key] = widths[key] ?? c.implicitWidth;
                compare(c.implicitWidth, widths[key], what + " is as wide as " + key + " was");
            }
            verify(Object.keys(widths).length < data.states.length, "some readings differ only in their digits: " + JSON.stringify(widths));
        }

        function test_dimLineOverhang_data() {
            return [{ tag: "long dim line", item: "memory", state: { set: { memoryPercent: 1, memoryUsed: 1023 * mib } }, capped: true },
                    { tag: "first line longer", item: "cpu", state: { set: { cpuUsage: 100, cpuTemperature: 5 } } },
                    { tag: "one line", item: "memory", twoLines: false, state: { set: { memoryPercent: 1, memoryUsed: 1023 * mib } } },
                    { tag: "coloured", item: "cpu", state: { set: { fahrenheit: true, cpuUsage: 5, cpuTemperature: 92 } },
                      dim: { cpuTemperature: 50 } }];
        }

        // A dim second line longer than the first runs past the readings
        // into the gap after them, by at most smallSpacing: any closer and
        // it reads as the next item's. The cell's width leaves that much
        // out. A coloured line, or one on a thin panel, stays inside.
        function test_dimLineOverhang(data) {
            const c = cell(data.item, { twoLines: data.twoLines ?? true, ring: 34 });
            const readout = root.find(c, i => i.textWidth !== undefined);
            const second = line(c, "second");
            if (data.dim) {
                apply(data.item, { set: Object.assign({}, data.state.set, data.dim) });
                settle();
                compare(String(second.color), root.tone("dim"), "dim at " + second.text);
                verify(readout.overhang > 0, second.text + " runs over");
            }
            apply(data.item, data.state);
            settle();
            if (data.dim) {
                compare(String(second.color), root.tone("negative"), "coloured at " + second.text);
            }
            const longer = readout.rooms[1] - readout.rooms[0];
            const what = line(c, "first").text + " over " + second.text + ", " + longer + " px longer";
            if (data.capped) {
                verify(Math.round(longer * 0.4) > Kirigami.Units.smallSpacing, what + ": long enough to reach the cap");
                compare(readout.overhang, Kirigami.Units.smallSpacing, what);
            } else {
                compare(readout.overhang, 0, what);
            }
            compare(c.implicitWidth, gauge(c).width + Kirigami.Units.largeSpacing + readout.textWidth, what);
            const end = Math.max(...readingsIn(c).map(t => t.mapToItem(c, Qt.point(t.width, 0)).x));
            fuzzyCompare(end - c.implicitWidth, readout.overhang, 0.01, what + ": the readings end past the cell");
        }

        function test_ratesHugTheirText_data() {
            const states = {
                network: [{ networkDown: 0, networkUp: 0 }, { networkDown: 99.9e6 / 8, networkUp: 999e3 / 8 },
                          { networkDown: 999e6 / 8, networkUp: 99.9e9 / 8 }, { networkDown: 1.3e6, networkUp: 1023 },
                          { networkDown: NaN, networkUp: NaN }, { networkDown: 999e12 / 8, networkUp: 5 }],
                disk: [{ diskRead: 0, diskWrite: 0 }, { diskRead: 1023, diskWrite: 1023 * 1024 },
                       { diskRead: 99.9 * mib, diskWrite: 1023 * gib }, { diskRead: 1023 * 1024 ** 5, diskWrite: 9.9 * 1024 ** 4 },
                       { diskRead: NaN, diskWrite: 1 }]
            };
            const rows = [];
            for (const [item, bits] of [["network", true], ["network", false], ["disk", false]]) {
                for (const singleRow of [false, true]) {
                    rows.push({ tag: item + (item === "network" ? (bits ? " bits" : " bytes") : "") + (singleRow ? " one row" : " two rows"),
                                item: item, bits: bits, singleRow: singleRow, states: states[item] });
                }
            }
            return rows;
        }

        // Rates hug their text, so short ones take less room than long ones.
        // Each marker sits a small spacing from its value, at least the gap
        // before the unit, so an arrow never touches a long value; stacked,
        // the values end at one edge and the units start at one.
        function test_ratesHugTheirText(data) {
            monitor.networkBits = data.bits;
            const c = cell(data.item, { singleRow: data.singleRow });
            verify(Kirigami.Units.smallSpacing >= c.unitGap, "the marker's gap is at least the unit's");
            const widths = [];
            for (const state of data.states) {
                apply(data.item, { set: state });
                settle();
                const what = "showing " + root.texts(c).join(" ");
                widths.push(c.implicitWidth);
                // Each rate: its marker, then its value and unit.
                const rates = root.findAll(c, i => i.reading !== undefined).sort((a, b) => a.index - b.index);
                compare(rates.length, 2);
                const values = rates.map(r => root.find(r, i => i.visible && i.horizontalAlignment === Text.AlignRight));
                const units = rates.map((r, row) => root.find(r, i => i.visible && i !== values[row] && i.text === c.lines[row].unit));
                for (let row = 0; row < 2; ++row) {
                    const value = values[row];
                    const unit = units[row];
                    compare([value.text, unit.text], [c.lines[row].value, c.lines[row].unit], what);
                    verify(value.contentWidth <= value.width && unit.contentWidth <= unit.width, what + " fits");
                    const marker = rates[row].children[0];
                    const markerEnd = marker.mapToItem(c, Qt.point(marker.width, 0)).x;
                    const valueAt = value.mapToItem(c, Qt.point(0, 0)).x;
                    const unitAt = unit.mapToItem(c, Qt.point(0, 0)).x;
                    compare(valueAt - markerEnd, Kirigami.Units.smallSpacing, what + ": the marker's gap");
                    compare(unitAt - (valueAt + value.width), c.unitGap, what + ": the unit's gap");
                    // Side by side, a letter's marker is as wide as the
                    // letter, so "R" leaves no gap before the disk's rates.
                    if (data.item === "disk" && data.singleRow) {
                        const letter = root.find(marker, i => i.visible && typeof i.text === "string");
                        verify(letter.mapToItem(marker, Qt.point(0, 0)).x < 1, what + ": " + letter.text + " fills its marker");
                    }
                }
                if (!data.singleRow) {
                    compare(values[0].mapToItem(c, Qt.point(values[0].width, 0)).x, values[1].mapToItem(c, Qt.point(values[1].width, 0)).x,
                            what + ": the values end at one edge");
                    compare(units[0].mapToItem(c, Qt.point(0, 0)).x, units[1].mapToItem(c, Qt.point(0, 0)).x, what + ": the units line up");
                }
            }
            verify(Math.min(...widths) < Math.max(...widths), "short rates take less room: " + widths.join(", "));
        }

        function test_ratesKeepSpareRoomInside_data() {
            return [{ tag: "network two rows", item: "network", singleRow: false },
                    { tag: "network one row", item: "network", singleRow: true },
                    { tag: "disk two rows", item: "disk", singleRow: false },
                    { tag: "disk one row", item: "disk", singleRow: true }];
        }

        // Given more room than their text needs, as a cell holding its width
        // gives them, the rates keep it inside in whole pixels, before their
        // markers: each marker keeps its usual gap to its value, each rate's
        // readings end at its end and the last at the rates' end. Stacked,
        // the markers, values and units still line up. Side by side only the
        // first rate takes the room, so the two rates stay together.
        function test_ratesKeepSpareRoomInside(data) {
            const c = cell(data.item, { singleRow: data.singleRow });
            const rates = root.findAll(c, i => i.reading !== undefined).sort((a, b) => a.index - b.index);
            const secondWidth = rates[1].width;
            // The strip gives a cell whole pixels.
            c.width = Math.ceil(c.implicitWidth) + 40;
            settle();
            const x = i => i.mapToItem(c, Qt.point(0, 0)).x;
            const right = i => i.mapToItem(c, Qt.point(i.width, 0)).x;
            const inWholePixels = (room, what) => verify(room > 0 && Math.abs(room - Math.round(room)) < 1e-6, what + ", in whole pixels: " + room);
            compare(x(rates[0]), 0, "the first rate at the start");
            const ends = [];
            for (const rate of rates) {
                const what = "rate " + rate.index + ": ";
                const marker = rate.children[0];
                const value = root.find(rate, i => i.visible && i.horizontalAlignment === Text.AlignRight);
                const pair = value.parent;
                fuzzyCompare(x(value) - right(marker), Kirigami.Units.smallSpacing, 1e-6, what + "the marker by its value");
                if (data.singleRow && rate.index === 1) {
                    compare(x(marker), x(rate), what + "the marker at the rate's start");
                } else {
                    inWholePixels(x(marker) - x(rate), what + "room before the marker");
                }
                const end = right(pair);
                verify(end > right(rate) - 1 && end <= right(rate), what + "the readings end at the rate's end: " + end + ", " + right(rate));
                ends.push(end);
            }
            verify(ends[1] > c.width - 1 && ends[1] <= c.width, "the last readings end at the rates' end: " + ends[1] + " in " + c.width);
            if (data.singleRow) {
                compare(rates[1].width, secondWidth, "the second rate keeps its width");
            } else {
                compare(x(rates[0].children[0]), x(rates[1].children[0]), "stacked, the markers line up");
                compare(ends[0], ends[1], "stacked, the values and units end at one edge");
                const units = rates.map((r, row) => root.find(r, i => i.visible && i.text === c.lines[row].unit && i.horizontalAlignment !== Text.AlignRight));
                compare(units[0].mapToItem(c, Qt.point(0, 0)).x, units[1].mapToItem(c, Qt.point(0, 0)).x, "the units line up");
            }
        }

        function test_ratesShareTheGrid_data() {
            return [{ tag: "38", thickness: 38, ring: 34, twoLines: true },
                    { tag: "46", thickness: 46, ring: 42, twoLines: true },
                    { tag: "31", thickness: 31, ring: 27, twoLines: false },
                    { tag: "30", thickness: 30, ring: 26, twoLines: false }];
        }

        // Rates beside a ring sit on the ring's lines, in the same face.
        function test_ratesShareTheGrid(data) {
            const pair = keep(pairComponent.createObject(root, { monitor: monitor, thickness: data.thickness, ring: data.ring,
                                                                 twoLines: data.twoLines }));
            waitForRendering(pair);
            const rates = pair.rates;
            // Row by row, then left to right: down before up.
            const inOrder = (a, b) => baselineIn(a, pair) - baselineIn(b, pair) || a.mapToItem(pair, Qt.point(0, 0)).x - b.mapToItem(pair, Qt.point(0, 0)).x;
            const shown = root.findAll(rates, i => i.visible && typeof i.text === "string" && i.text !== "");
            const values = shown.filter(t => t.horizontalAlignment === Text.AlignRight).sort(inOrder);
            const units = shown.filter(t => t.horizontalAlignment !== Text.AlignRight).sort(inOrder);
            compare(values.map(t => t.text), rates.lines.map(reading => reading.value));
            compare(units.map(t => t.text), rates.lines.map(reading => reading.unit));
            for (let row = 0; row < 2; ++row) {
                checkFace(values[row], Font.Normal, "rate " + row);
                checkFace(units[row], Font.Normal, "unit " + row);
                compare(String(values[row].color), root.tone("text"));
                compare(String(units[row].color), root.tone("dim"), "units are dim");
                compare(values[row].font.pointSize, line(pair.rings, "second").font.pointSize, "the ring lines' size");
            }
            const first = baselineIn(line(pair.rings, "first"), pair);
            const second = baselineIn(line(pair.rings, "second"), pair);
            if (!data.twoLines) {
                verify(Math.abs(second - first) <= 0.5, "one line: " + first + ", " + second);
            }
            const lines = data.twoLines ? [first, second] : [first, first];
            for (let row = 0; row < 2; ++row) {
                verify(Math.abs(baselineIn(values[row], pair) - lines[row]) <= 0.5,
                       "rate " + row + " at " + baselineIn(values[row], pair) + ", ring line at " + lines[row]);
                verify(Math.abs(baselineIn(units[row], pair) - lines[row]) <= 0.5,
                       "unit " + row + " at " + baselineIn(units[row], pair) + ", ring line at " + lines[row]);
            }
        }

        function test_hoverInset_data() {
            return [{ tag: "horizontal", vertical: false, inset: Math.round(Kirigami.Units.smallSpacing / 2),
                      across: 2 * Math.round(Kirigami.Units.smallSpacing / 2), along: 2 * Kirigami.Units.largeSpacing },
                    { tag: "vertical", vertical: true, inset: 0, across: 2 * Kirigami.Units.smallSpacing,
                      along: 2 * Kirigami.Units.smallSpacing }];
        }

        // Across a horizontal panel the wash leaves a sliver of panel above
        // and below; along a vertical one it spans the cell. Along a
        // horizontal panel a large spacing either side of the content makes
        // the gap between items.
        function test_hoverInset(data) {
            const block = keep(blockComponent.createObject(root));
            const c = keep(panelCellComponent.createObject(root, { vertical: data.vertical, contentItem: block, width: 60, height: 50 }));
            waitForRendering(c);
            compare(c.inset, data.inset);
            compare(c.implicitHeight, 34 + data.across);
            compare(c.implicitWidth, 50 + data.along);
            const wash = root.find(c, i => i !== c && i.radius !== undefined);
            verify(wash.visible, "open shows the wash");
            compare([wash.x, wash.y, wash.width, wash.height], [0, data.inset, 60, 50 - 2 * data.inset]);
        }

        // Keyboard focus draws a line round the wash in the theme's focus
        // colour, and Tab moves it from item to item. The pointer and an open
        // popup show the wash alone, so the focused item stands apart.
        function test_focusShowsARing() {
            const cells = [];
            for (let i = 0; i < 2; ++i) {
                const block = keep(blockComponent.createObject(root));
                cells.push(keep(focusCellComponent.createObject(root, { contentItem: block, x: 400 + 100 * i, y: 400 })));
            }
            const washes = cells.map(c => root.find(c, i => i !== c && i.radius !== undefined));
            waitForRendering(cells[1]);
            verify(!washes[0].visible, "no wash at rest");

            cells[0].forceActiveFocus(Qt.TabFocusReason);
            verify(cells[0].activeFocus);
            verify(washes[0].visible, "focus shows the wash");
            compare(washes[0].border.width, 1);
            compare(String(washes[0].border.color), "#ff00ff");

            keyClick(Qt.Key_Tab);
            verify(cells[1].activeFocus, "Tab moves to the next item");
            compare(washes[1].border.width, 1);
            compare(washes[0].border.width, 0, "the line goes with focus");
            verify(!washes[0].visible);

            cells[1].open = true;
            compare(washes[1].border.width, 1, "an open item keeps its line while focused");
            cells[0].open = true;
            verify(washes[0].visible);
            compare(washes[0].border.width, 0, "open without focus: the wash alone");
            cells[0].open = false;
            mouseMove(cells[0]);
            tryVerify(() => cells[0].containsMouse);
            verify(washes[0].visible);
            compare(washes[0].border.width, 0, "under the pointer: the wash alone");
            mouseMove(root, 10, 10);

            cells[1].focus = false;
            verify(!cells[1].activeFocus);
            compare(washes[1].border.width, 0, "the line goes with focus");
        }

        // Along a horizontal panel a cell grows with its content at once and
        // keeps its width through a narrower content until that has lasted
        // the settle delay, so a reading that comes and goes moves nothing.
        // A change of layout, and the moments after the cell is made, apply
        // at once.
        function test_settleHold() {
            const block = keep(blockComponent.createObject(root));
            const c = keep(panelCellComponent.createObject(root, { contentItem: block, settleDelay: 400, relayoutWindow: 100 }));
            const outside = 2 * Kirigami.Units.largeSpacing;
            const digit = c.digitWidth;
            compare(c.implicitWidth, 50 + outside, "as wide as its content");
            verify(digit > 1 && digit < 20, "a digit's width: " + digit);

            // Content given at creation holds through its first shrink.
            const declared = keep(declaredCellComponent.createObject(root));
            wait(20);
            declared.contentItem.implicitWidth = 50 - digit;
            compare(declared.implicitWidth, 50 + outside, "holds what it was made with");

            block.implicitWidth = 45;
            compare(c.implicitWidth, 45 + outside, "just made, it follows its content");
            wait(200);

            block.implicitWidth = 60.2;
            compare(c.implicitWidth, 61 + outside, "grows at once, to a whole pixel");
            block.implicitWidth = 61 - digit;
            compare(c.implicitWidth, 61 + outside, "holds through a digit's shrink");
            wait(200);
            compare(c.implicitWidth, 61 + outside, "still holding");
            block.implicitWidth = 40;
            compare(c.implicitWidth, 61 + outside, "and through a bigger one");
            tryCompare(c, "implicitWidth", 40 + outside, 2000, "settles after the delay");

            // A reading that comes back in time moves nothing.
            block.implicitWidth = 50;
            block.implicitWidth = 50 - digit;
            wait(200);
            block.implicitWidth = 50;
            wait(400);
            compare(c.implicitWidth, 50 + outside, "came back before the delay");

            // A change of layout applies at once, and so does a narrower
            // content for a moment after it.
            block.implicitWidth = 50 - digit;
            compare(c.implicitWidth, 50 + outside, "held");
            c.layoutKey = "thin";
            compare(c.implicitWidth, 50 - digit + outside, "a new layout applies at once");
            block.implicitWidth = 25;
            compare(c.implicitWidth, 25 + outside, "and so does its content, for a moment");
            wait(200);
            block.implicitWidth = 25 - digit;
            compare(c.implicitWidth, 25 + outside, "then it holds again");
        }

        // Through a hold the cell keeps the widest it showed, whatever its
        // content passes through; the hold ends at the content's width then.
        // Ended any wider, the cell would keep the difference as a gap until
        // its content next changed, as nothing would start another hold.
        function test_settleEndsAtTheContentWidth() {
            const block = keep(blockComponent.createObject(root));
            const c = keep(panelCellComponent.createObject(root, { contentItem: block, settleDelay: 400, relayoutWindow: 1 }));
            const outside = 2 * Kirigami.Units.largeSpacing;
            wait(20);
            block.implicitWidth = 60;
            compare(c.implicitWidth, 60 + outside);
            const moves = keep(signalSpyComponent.createObject(root, { target: c, signalName: "implicitWidthChanged" }));
            const digit = c.digitWidth;
            for (const width of [60 - digit, 60 - digit / 2, 60 - digit]) {
                block.implicitWidth = width;
                wait(50);
            }
            compare(c.implicitWidth, 60 + outside, "holding");
            tryCompare(c, "implicitWidth", 60 - digit + outside, 2000, "settles at the content's width");
            wait(2 * c.settleDelay);
            compare(c.implicitWidth, 60 - digit + outside, "and stays there");
            compare(moves.count, 1, "moved once");
        }

        // Every trim delay a held cell gives up all but a digit more than the
        // widest content it had in that time, so a reading that came back
        // within it keeps its room, and one that stayed down leaves a digit.
        function test_trimToADigit() {
            const block = keep(blockComponent.createObject(root));
            const c = keep(panelCellComponent.createObject(root, { contentItem: block, settleDelay: 60000, trimDelay: 600, relayoutWindow: 1 }));
            const outside = 2 * Kirigami.Units.largeSpacing;
            const digit = c.digitWidth;
            wait(20);
            block.implicitWidth = 60;
            block.implicitWidth = 40;
            compare(c.implicitWidth, 60 + outside, "holds at first");
            wait(100);
            block.implicitWidth = 50;
            wait(50);
            block.implicitWidth = 40;
            verify(50 + digit < 60, "a digit's width: " + digit);
            tryVerify(() => c.implicitWidth < 60 + outside, 3000, "trims");
            compare(c.implicitWidth, 50 + digit + outside, "to a digit more than the widest in that time");
            tryCompare(c, "implicitWidth", 40 + digit + outside, 3000, "then to a digit more than one that stayed down");
            wait(2 * c.trimDelay);
            compare(c.implicitWidth, 40 + digit + outside, "and stays there");
            block.implicitWidth = 40 + Math.floor(digit);
            compare(c.implicitWidth, 40 + digit + outside, "a digit back moves nothing");
        }

        // Font features have to reach both what measures and what draws, or
        // the rooms kept don't match the text drawn in them.
        function test_fontFeaturesReachMeasurement() {
            const width = (features, text) => {
                const metrics = keep(probeMetricsComponent.createObject(root, { features: features, text: text }));
                const drawn = keep(probeTextComponent.createObject(root, { features: features, text: text }));
                return [metrics.advanceWidth, drawn.implicitWidth];
            };
            const narrow = width({ "pnum": 1 }, "111");
            const wide = width({ "pnum": 1 }, "888");
            if (narrow[0] === wide[0] && narrow[1] === wide[1]) {
                skip("Noto Sans is missing or has no proportional figures here");
            }
            verify(narrow[0] < wide[0], "TextMetrics: " + narrow[0] + " vs " + wide[0]);
            verify(narrow[1] < wide[1], "Text: " + narrow[1] + " vs " + wide[1]);
            const tabular = [width({ "tnum": 1 }, "111"), width({ "tnum": 1 }, "888")];
            compare(tabular[0][0], tabular[1][0], "TextMetrics with tnum");
            compare(tabular[0][1], tabular[1][1], "Text with tnum");
        }

        // A room counts every digit, ASCII or the locale's, as the widest of
        // the locale's, so "1%" keeps the room "8%" needs in any font.
        // A room is the width a Text takes for its widest digits, rounded up
        // to a whole pixel. Never less, or the text would overrun the room;
        // and where the last glyph's ink reaches less than half a pixel past
        // its advance, as an "s", a "%" or most digits do, no more, since a
        // Text adds nothing for that and the cell would end in a gap of its
        // own. A text ending in a digit keeps room for whichever digit
        // reaches furthest.
        function test_roomIsTheTextsWidth() {
            const face = keep(faceComponent.createObject(root));
            const probe = keep(probeComponent.createObject(root, { textFormat: Text.PlainText }));
            const texts = ["b/s", "Mb/s", "kb/s", "KiB/s", "MiB/s", "B/s", root.decimal(99.9), root.digits(1000),
                           root.digits(27) + "%", root.digits(100) + "%", root.digits(61) + "°", "R", "W", "off", "f", "–"];
            let exact = 0;
            for (const [what, metrics] of [["strong", face.strong], ["plain", face.plain]]) {
                probe.font = metrics.font;
                const reach = glyph => {
                    const ink = metrics.boundingRect(glyph);
                    return ink.x + ink.width - metrics.advanceWidth(glyph);
                };
                for (const text of texts) {
                    const widest = face.widestDigits(metrics, text);
                    const lasts = face.digits.includes(text.slice(-1)) ? face.digits : [text.slice(-1)];
                    const drawn = Math.max(...lasts.map(last => {
                        probe.text = widest.slice(0, -1) + last;
                        return Math.ceil(probe.implicitWidth);
                    }));
                    const room = face.room(metrics, [text]);
                    verify(room >= drawn, what + " " + text + ": " + room + " holds " + drawn);
                    if (Math.max(...lasts.map(reach)) < 0.5) {
                        compare(room, drawn, what + " " + text + " ends no further than its text");
                        ++exact;
                    }
                }
            }
            verify(exact > 0, "some texts tell");
        }

        function test_roomCountsWidestDigit() {
            const face = keep(faceComponent.createObject(root));
            const proportional = keep(proportionalComponent.createObject(root));
            const all = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
            for (const [what, metrics] of [["strong", face.strong], ["plain", face.plain], ["proportional", proportional]]) {
                const room = face.room(metrics, [root.digits(1) + "%"]);
                verify(room > 0, what);
                compare(face.room(metrics, [root.digits(8) + "%"]), room, what + ": locale 8");
                compare(face.room(metrics, ["1%"]), room, what + ": ASCII 1");
                compare(face.room(metrics, ["8%"]), room, what + ": ASCII 8");
                for (const d of all) {
                    verify(metrics.advanceWidth(root.digits(d) + "%") <= room, what + ": " + root.digits(d) + "% fits " + room);
                }
                compare(face.room(metrics, [root.digits(11) + "%", root.digits(100) + "%"]),
                        face.room(metrics, [root.digits(888) + "%"]), what + ": the widest text counts");
            }
            // Where the font's figures differ, "1%" alone is narrower than
            // its room, so the room really did count the widest digit.
            const widths = all.map(d => proportional.advanceWidth(root.digits(d)));
            if (Math.min(...widths) < Math.max(...widths)) {
                const narrowest = root.digits(widths.indexOf(Math.min(...widths)));
                verify(proportional.advanceWidth(narrowest + "%") < face.room(proportional, [narrowest + "%"]));
            }
        }
    }
}
