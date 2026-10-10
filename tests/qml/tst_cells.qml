// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/code/style.js" as Style

// The panel's cells on their own, with FakeMonitor's readings: the
// ring and its stroke, the name or mark inside it, the readings beside it in
// every state, their faces and colours, the room each line keeps whatever it
// reads, and the rates on the same lines in their fixed slots. It names no Strip, popup or settings page, so it
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
    function fixed(v, decimals) {
        return Number(v).toLocaleString(Qt.locale(), "f", decimals);
    }
    // A C-locale text, "8.40 Mb/s", in the locale's digits and decimal mark.
    function localized(text) {
        return text.replace(/\d+(?:\.(\d+))?/g, (m, decimals) => fixed(Number(m), decimals ? decimals.length : 0));
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

    Component {
        id: metricsComponent
        FontMetrics {}
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

        // Where its ring has the room, the Codex cloud is drawn 1.15 times a
        // name's line, larger than the Claude star, and hollow: its outline,
        // filled by the nonzero rule, leaves the cloud's middle clear round
        // the prompt. Under 16 device pixels, where its line breaks up, it is
        // left out though the room would take it.
        function test_codexMarkIsALargerOutline() {
            const small = nameIn(breezeSized(cell("codex", { ring: 22, textShown: true, twoLines: true })));
            verify(small.markSize >= Kirigami.Units.iconSizes.small / 2 && small.markSize <= small.room
                   && small.markSize * root.Screen.devicePixelRatio < 16, "a mark the room would take: " + small.markSize);
            verify(!small.visible, "too small to read");

            const name = nameIn(breezeSized(cell("codex", { ring: 46, textShown: true, twoLines: true })));
            const shape = mark(name);
            verify(name.visible);
            const metrics = createTemporaryObject(metricsComponent, root, { font: label(name).font });
            const scaled = Math.round(metrics.height * 1.2 * 1.15);
            verify(scaled < Math.floor(name.room) - 2, "room for the scale: " + scaled + " in " + name.room);
            compare(name.markSize, scaled);
            // Whether the mark draws at a point in its viewBox units: the
            // ring with and without it differ there.
            const drawn = grabImage(name);
            shape.visible = false;
            const bare = grabImage(name);
            shape.visible = true;
            const draws = (x, y) => {
                const p = shape.mapToItem(name, Qt.point(x, y));
                return !Qt.colorEqual(drawn.pixel(Math.floor(p.x), Math.floor(p.y)), bare.pixel(Math.floor(p.x), Math.floor(p.y)));
            };
            verify(draws(11.5, 0.05), "the cloud's line");
            verify(!draws(12, 5), "the cloud's middle, clear");
            verify(draws(15, 15.4), "the prompt");
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
                        const fits = size >= Kirigami.Units.iconSizes.small / 2 && size <= g.centreWidth
                                     && size * root.Screen.devicePixelRatio >= (name.art.minimum ?? 0);
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

        function test_systemRingsDontWait_data() {
            return [{ tag: "cpu", item: "cpu", set: { cpuUsage: NaN, cpuTemperature: NaN } },
                    { tag: "memory", item: "memory", set: { memoryPercent: NaN, memoryUsed: NaN } },
                    { tag: "gpu", item: "gpu", outer: { usage: NaN, temperature: NaN }, inner: { present: false } }];
        }

        // CPU, GPU and memory keep today's look before their first reading,
        // the whole track and a plain dash, even while Claude's first check
        // runs beside them: no dots, and nothing moves.
        function test_systemRingsDontWait(data) {
            monitor.usage.entries = {};
            monitor.usage.pending = ["claude"];
            apply(data.item, data);
            const c = cell(data.item);
            const g = gauge(c);
            const claude = gauge(cell("claude"));
            verify(claude.loading);
            verify(!g.loading);
            compare([g.sweep, g.dotsShown], [1, 0]);
            verify(!root.find(g, i => i.covered !== undefined).visible);
            const arc = root.find(g, i => i.playReset !== undefined);
            compare(arc.trackColor, Qt.alpha(Kirigami.Theme.textColor, 0.16 * Kirigami.Theme.textColor.a));
            compare(arc.trackSweep, 1);
            compare(line(c, "first").text, "–");
            compare(line(c, "first").color, Kirigami.Theme.textColor);
            tryCompare(claude, "moving", true, 3000);
            verify(!g.moving && g.motion === 0);
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
                { tag: "memory", item: "memory", lines: [percent(42), decimal(13.4) + " GiB"], tones: ["text", "dim"] },
                { tag: "memory 77 %", item: "memory", set: { memoryPercent: 77 }, lines: [percent(77), decimal(13.4) + " GiB"], tones: ["neutral", "dim"] },
                { tag: "memory in MiB", item: "memory", set: { memoryUsed: 900 * mib, memoryPercent: 3 }, lines: [percent(3), decimal(900) + " MiB"], tones: ["text", "dim"] },
                { tag: "memory to one decimal", item: "memory", set: { memoryUsed: 9.64 * gib, memoryPercent: 60 }, lines: [percent(60), decimal(9.6) + " GiB"],
                  tones: ["text", "dim"] },
                { tag: "dual gpu", item: "gpu", lines: [percent(12), degrees(48)], tones: ["text", "dim"], absent: degrees(41) },
                { tag: "dual gpu hot", item: "gpu", outer: { usage: 90, temperature: 92 }, lines: [percent(90), degrees(92)], tones: ["negative", "negative"] },
                { tag: "dual gpu warm", item: "gpu", outer: { temperature: 80 }, lines: [percent(12), degrees(80)], tones: ["text", "neutral"] },
                { tag: "outer asleep", item: "gpu", outer: asleep, lines: [percent(3), degrees(41)], tones: ["text", "dim"] },
                { tag: "only gpu asleep", item: "gpu", outer: asleep, inner: { present: false }, lines: ["off", ""], tones: ["dim", "dim"] },
                { tag: "intel only", item: "gpu", outer: { reportsTemperature: false, kind: "integrated" }, inner: { present: false },
                  lines: [percent(12), ""], tones: ["text", "dim"] },
                { tag: "claude", item: "claude", lines: [percent(52), digits(2) + "d"], tones: ["text", "dim"] },
                { tag: "claude 81 %", item: "claude", week: [81, 5 * 3600 + 12 * 60], lines: [percent(81), digits(5) + "h"],
                  tones: ["neutral", "dim"] },
                // At this pace the week runs out before its reset, and its
                // colour is still its reading's.
                { tag: "claude 81 % runs out", item: "claude", week: [81, 2 * day + 21 * 3600], lines: [percent(81), digits(2) + "d"],
                  tones: ["neutral", "dim"] },
                { tag: "claude last day", item: "claude", week: [40, 23 * 3600 + 5 * 60], lines: [percent(40), digits(23) + "h"],
                  tones: ["text", "dim"] },
                { tag: "claude 95 %", item: "claude", week: [95, 5 * 3600 + 12 * 60], lines: [percent(95), digits(5) + "h"],
                  tones: ["negative", "dim"] },
                { tag: "claude minutes", item: "claude", week: [40, 12 * 60], lines: [percent(40), digits(12) + "m"], tones: ["text", "dim"] },
                { tag: "claude reset passed", item: "claude", week: [40, -600], lines: [percent(40), "–"], tones: ["text", "dim"] },
                { tag: "claude no weekly", item: "claude", week: null, lines: ["–", "–"], tones: ["text", "dim"] },
                { tag: "codex", item: "codex", lines: [percent(24), digits(5) + "d"], tones: ["text", "dim"] }
            ];
        }

        // The ring's own reading, heavier and in the ring's colour, over a
        // dimmer one in its own heat colour. A countdown keeps to its largest
        // unit, and memory to one decimal and its unit.
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

        // The panel shows the readings Monitor holds for it, which move once
        // per update interval, not the live ones the popups and graphs show:
        // in its rings, its text and its words.
        function test_panelShowsItsHeldReadings_data() {
            return [
                { tag: "cpu", item: "cpu", ring: 40, texts: [percent(40), degrees(70)], words: "Usage " + percent(40) },
                { tag: "memory", item: "memory", ring: 60, texts: [percent(60), decimal(20.0) + " GiB"], words: percent(60) },
                { tag: "gpu", item: "gpu", ring: 55, inner: 7, texts: [percent(55), degrees(66)], words: "Usage " + percent(55) },
                { tag: "network", item: "network", texts: [decimal(64.0), decimal(16.0)], words: "Down " + decimal(64.0) + " Mb/s" },
                { tag: "disk", item: "disk", texts: [decimal(50.0), fixed(1, 2)], words: "Read " + decimal(50.0) + " MiB/s" }
            ];
        }
        function test_panelShowsItsHeldReadings(data) {
            const gib = monitor.gib;
            monitor.panel = { cpuUsage: 40, cpuTemperature: 70, memoryPercent: 60, memoryUsed: 20 * gib,
                              networkDown: 8e6, networkUp: 2e6, diskRead: 50 * 1048576, diskWrite: 1048576 };
            monitor.gpuOuter.panelUsage = 55;
            monitor.gpuOuter.panelTemperature = 66;
            monitor.gpuInner.panelUsage = 7;
            const c = cell(data.item);
            const shown = root.texts(c);
            for (const text of data.texts) {
                verify(shown.includes(text), text + " in " + JSON.stringify(shown));
            }
            if (data.ring !== undefined) {
                compare(gauge(c).value, data.ring);
            }
            if (data.inner !== undefined) {
                compare(gauge(c).innerValue, data.inner);
            }
            verify(c.accessibleDescription.includes(data.words), c.accessibleDescription);
        }

        function test_line2KeepsItsSpace_data() {
            return [{ tag: "two lines", twoLines: true }, { tag: "one line", twoLines: false }];
        }

        // An asleep GPU or an Intel one has no second reading; the cell
        // keeps its size and its first line stays put. The blank second line
        // keeps its room, and on one line its dot goes.
        function test_line2KeepsItsSpace(data) {
            const c = cell("gpu", { twoLines: data.twoLines, ring: data.twoLines ? 34 : 26 });
            const measure = () => {
                const first = line(c, "first");
                const second = line(c, "second");
                const at = first.mapToItem(c, Qt.point(0, 0));
                const secondAt = second.mapToItem(c, Qt.point(0, 0));
                return { width: c.implicitWidth, height: c.implicitHeight, firstX: at.x, firstY: at.y, firstHeight: first.height,
                         second: [second.visible, secondAt.x, secondAt.y, second.width, second.height] };
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
                { tag: "memory", item: "memory", texts: [percent(42), "·", decimal(13.4) + " GiB"] },
                { tag: "claude", item: "claude", texts: [percent(52), "·", digits(2) + "d"] },
                { tag: "claude last day", item: "claude", week: [52, 5 * 3600 + 12 * 60], texts: [percent(52), "·", digits(5) + "h"] },
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

        function test_countdownText_data() {
            const rows = [];
            for (const [what, left, text] of [["days", 6 * day + 23 * 3600, [6, "d"]],
                                              ["last day", 23 * 3600 + 5 * 60, [23, "h"]],
                                              ["minutes", 12 * 60, [12, "m"]]]) {
                for (const mirrored of [false, true]) {
                    rows.push({ tag: what + (mirrored ? " mirrored" : ""), left: left, text: text, mirrored: mirrored });
                }
            }
            return rows;
        }

        // A countdown is plain text in the face of the other second lines,
        // its largest unit alone, as large as its digits, as in "11.2 GiB" or
        // "61°", mirrored or not. Its room is that of two of the widest
        // digits and the widest unit, whatever it reads.
        function test_countdownText(data) {
            setWeek("claude", [52, data.left]);
            const holder = data.mirrored ? keep(mirrorComponent.createObject(root)) : root;
            const c = keep(usageComponent.createObject(holder, { monitor: monitor, item: "claude" }));
            waitForRendering(c);
            const second = line(c, "second");
            compare(second.textFormat, Text.PlainText);
            compare(second.text, root.digits(data.text[0]) + data.text[1]);
            verify(second.contentWidth <= second.width, second.contentWidth + " in " + second.width);

            const readout = root.find(c, i => i.textWidth !== undefined);
            const face = readout.face.plain.font;
            compare([second.font.family, second.font.pointSize, second.font.weight], [face.family, face.pointSize, face.weight],
                    "the face of a temperature or memory line");
            compare(readout.rooms[1], readout.face.room(readout.face.plain, ["d", "h", "m"].map(unit => root.digits(10) + unit)),
                    "the room of two figures and a unit");
            compare(root.findAll(readout, i => i.textFormat !== undefined).length, 3, "the two lines and the dot, nothing hidden to measure");
        }

        // Readings at their extremes, item by item: { set, outer, inner,
        // week (see apply), shows: texts drawn, in ASCII }.
        function extremes() {
            return {
                cpu: [{ set: { cpuUsage: 0, cpuTemperature: 9 }, shows: ["0%", "9°"] },
                      { set: { cpuUsage: 5, cpuTemperature: 105 }, shows: ["5%", "105°"] },
                      { set: { cpuUsage: 100, cpuTemperature: 1 }, shows: ["100%", "1°"] },
                      { set: { cpuUsage: NaN, cpuTemperature: NaN }, shows: ["–"] },
                      { set: { fahrenheit: true, cpuUsage: 100, cpuTemperature: 149 }, shows: ["100%", "300°"] },
                      { set: { fahrenheit: false, cpuUsage: 11, cpuTemperature: 48 }, shows: ["11%", "48°"] }],
                memory: [{ set: { memoryPercent: 0, memoryUsed: 0 }, shows: ["0%", "0 B"] },
                         { set: { memoryPercent: 1, memoryUsed: 999 * mib }, shows: ["1%", "999.0 MiB"] },
                         { set: { memoryPercent: 6, memoryUsed: 1000 * mib }, shows: ["6%", "1.0 GiB"] },
                         { set: { memoryPercent: 60, memoryUsed: 9.6 * gib }, shows: ["60%", "9.6 GiB"] },
                         { set: { memoryPercent: 88, memoryUsed: 13.4 * gib }, shows: ["88%", "13.4 GiB"] },
                         { set: { memoryPercent: 100, memoryUsed: 1023 * gib }, shows: ["100%", "1.0 TiB"] },
                         { set: { memoryPercent: NaN, memoryUsed: NaN }, shows: ["–"] }],
                gpu: [{ outer: { usage: 0, temperature: 9 }, shows: ["0%", "9°"] },
                      { outer: { usage: 100, temperature: 105 }, shows: ["100%", "105°"] },
                      { outer: { phase: "asleep" }, shows: ["3%", "41°"] },
                      { inner: { phase: "asleep" }, shows: ["off"] },
                      { outer: { phase: "live", usage: 7 }, inner: { phase: "live" }, shows: ["7%"] },
                      { outer: { reportsTemperature: false }, inner: { present: false }, shows: ["7%"] }],
                claude: [{ week: [0, 6 * day + 23 * 3600], shows: ["0%", "6d"] },
                         { week: [5, day + 11 * 3600], shows: ["5%", "1d"] },
                         { week: [88, 23 * 3600 + 59 * 60], shows: ["88%", "23h"] },
                         { week: [100, 59 * 60], shows: ["100%", "59m"] },
                         { week: [100, 5 * 60], shows: ["100%", "5m"] },
                         { week: [40, -600], shows: ["40%", "–"] },
                         { week: [NaN, 2 * day], shows: ["–", "2d"] },
                         { week: null, shows: ["–"] }],
                network: [{ set: { networkDown: 0, networkUp: 0 }, shows: ["0.00"] },
                          { set: { networkDown: 999 / 8, networkUp: 62.1e3 / 8 }, shows: ["1.00", "62.1"] },
                          { set: { networkDown: 999.4e3 / 8, networkUp: 999.5e3 / 8 }, shows: ["999", "1.00"] },
                          { set: { networkDown: 8.4e6 / 8, networkUp: 900e6 / 8 }, shows: ["8.40", "900"] },
                          { set: { networkDown: 1023 * 1024 ** 3, networkUp: NaN }, shows: ["–"] }],
                disk: [{ set: { diskRead: 0, diskWrite: 0 }, shows: ["0.00", "KiB/s"] },
                       { set: { diskRead: 4.1 * 1024, diskWrite: 353 * 1024 }, shows: ["4.10", "353"] },
                       { set: { diskRead: 1000 * 1024, diskWrite: 1023 * 1024 }, shows: ["0.98", "1.00", "MiB/s"] },
                       { set: { diskRead: 412 * mib, diskWrite: 1023 * mib }, shows: ["412", "GiB/s"] },
                       { set: { diskRead: 1023 * gib, diskWrite: NaN }, shows: ["TiB/s", "–"] }]
            };
        }

        function test_widthIsFixed_data() {
            const rows = [];
            const states = extremes();
            for (const item of ["cpu", "memory", "gpu", "claude", "codex", "network", "disk"]) {
                for (const twoLines of [true, false]) {
                    for (const mirrored of [false, true]) {
                        rows.push({ tag: item + (twoLines ? " two lines" : " one line") + (mirrored ? " mirrored" : ""),
                                    item: item, twoLines: twoLines, mirrored: mirrored, states: states[item === "codex" ? "claude" : item] });
                    }
                }
            }
            return rows;
        }

        // A cell keeps one width whatever its readings: each line takes the
        // room of the widest text it can show, "100%" for every ring and
        // "off" too for the GPU, one decimal and a unit for memory, three figures for the rates, and
        // two for a countdown, so no text in it moves or overruns its box
        // from 0 to 100 %, 9 to 105 degrees, an idle link to 1023 GiB/s, a
        // GPU asleep or handing over, or a countdown from 6d to its reset.
        function test_widthIsFixed(data) {
            const rate = data.item === "network" || data.item === "disk";
            const holder = data.mirrored ? mirrorComponent.createObject(root) : root;
            const component = rate ? rateComponent : data.item === "claude" || data.item === "codex" ? usageComponent : ringComponent;
            const c = keep(component.createObject(holder, Object.assign({ monitor: monitor, item: data.item },
                rate ? { singleRow: !data.twoLines } : { twoLines: data.twoLines, ring: data.twoLines ? 34 : 26 })));
            if (data.mirrored) {
                keep(holder);
            }
            waitForRendering(c);
            if (data.item === "cpu" || data.item === "memory" || data.item === "gpu") {
                // Layout only: the GPU's readings change at once (see tst_motion).
                c.animated = false;
            }
            const readout = root.find(c, i => i.textWidth !== undefined);
            if (readout) {
                const face = readout.face;
                const percent = root.percent(100);
                const firsts = data.item === "gpu" ? [percent, "off"] : [percent];
                const seconds = data.item === "cpu" || data.item === "gpu" ? [root.degrees(100)]
                              : data.item === "memory" ? ["B", "KiB", "MiB", "GiB", "TiB", "PiB"].map(unit => root.decimal(100) + " " + unit)
                              : ["d", "h", "m"].map(unit => root.digits(10) + unit);
                compare(readout.rooms[0], face.room(face.strong, firsts), "the first line keeps room for " + firsts.join(", "));
                verify(readout.rooms[1] >= face.room(face.plain, seconds), "the second line keeps room for " + seconds.join(", "));
                compare(c.implicitWidth, gauge(c).width + Kirigami.Units.largeSpacing + readout.textWidth, "the ring, its gap and the readings' room");
            }
            // Where each reading is anchored: a text's start, end or middle,
            // as it is aligned, and its row.
            const texts = readingsIn(c);
            const place = t => {
                const align = t.effectiveHorizontalAlignment;
                const p = t.mapToItem(c, Qt.point(align === Text.AlignRight ? t.width : align === Text.AlignHCenter ? t.width / 2 : 0, 0));
                return [p.x, p.y, t.height].join(",");
            };
            const places = texts.map(place);
            const width = c.implicitWidth;
            const height = c.implicitHeight;
            const seen = [];
            for (const state of data.states) {
                apply(data.item, state);
                settle();
                const shown = readingsIn(c);
                const what = "showing " + shown.map(t => t.text).join(" ");
                seen.push(...shown.map(t => t.text));
                compare(c.implicitWidth, width, what + ": the width");
                compare(c.implicitHeight, height, what + ": the height");
                texts.forEach((t, i) => compare(place(t), places[i], what + ": " + (t.objectName || t.text) + " stays put"));
                shown.forEach(t => verify(texts.includes(t), what + ": " + t.text + " was there from the start"));
                shown.forEach(t => verify(t.contentWidth <= t.width, what + ": " + t.text + " is " + t.contentWidth + " wide in " + t.width));
                // Stacked, a ring's readings keep to the ring, so a short
                // one leaves its room after it.
                if (readout && data.twoLines) {
                    const first = line(c, "first");
                    compare(first.effectiveHorizontalAlignment, data.mirrored ? Text.AlignRight : Text.AlignLeft, what);
                }
            }
            for (const text of data.states.reduce((all, state) => all.concat(state.shows), [])) {
                verify(seen.includes(root.localized(text)), root.localized(text) + " was drawn: " + JSON.stringify(seen));
            }
        }

        // The GPU keeps room for "off" as translated, however long, so a
        // sleeping GPU moves nothing either.
        function test_longOffKeepsItsRoom() {
            root.translations = { "off": "ausgeschaltet" };
            monitor.gpuInner.present = false;
            const c = cell("gpu");
            c.animated = false;
            const readout = root.find(c, i => i.textWidth !== undefined);
            const width = c.implicitWidth;
            verify(readout.rooms[0] >= readout.face.room(readout.face.strong, ["ausgeschaltet"]), "room for the translation");
            monitor.gpuOuter.phase = "asleep";
            settle();
            compare(line(c, "first").text, "ausgeschaltet");
            compare(c.implicitWidth, width, "asleep, as wide as awake");
            verify(line(c, "first").contentWidth <= line(c, "first").width, "it fits");
        }

        function test_ratesKeepFixedSlots_data() {
            const rows = [];
            for (const [item, bits] of [["network", true], ["network", false], ["disk", false]]) {
                for (const singleRow of [false, true]) {
                    for (const mirrored of [false, true]) {
                        rows.push({ tag: item + (item === "network" ? (bits ? " bits" : " bytes") : "") + (singleRow ? " one row" : " two rows")
                                         + (mirrored ? " mirrored" : ""),
                                    item: item, bits: bits, singleRow: singleRow, mirrored: mirrored });
                    }
                }
            }
            return rows;
        }

        // Each rate is its arrow or letter, 6 px (one and a half small
        // spacings) from a slot that fits any value in three figures, then
        // its unit in a column that fits the widest. Values end at the
        // slot's end and units start at the column's, whatever they read;
        // stacked, both rows share them. Mirrored, the marker moves to the
        // other side and the value still comes before its unit.
        function test_ratesKeepFixedSlots(data) {
            monitor.networkBits = data.bits;
            const holder = data.mirrored ? mirrorComponent.createObject(root) : root;
            const c = keep(rateComponent.createObject(holder, { monitor: monitor, item: data.item, singleRow: data.singleRow }));
            // The rates go before their holder, so they never see its
            // mirroring go.
            if (data.mirrored) {
                keep(holder);
            }
            waitForRendering(c);
            const gap = Math.round(Kirigami.Units.smallSpacing * 1.5);
            if (Kirigami.Units.smallSpacing === 4) {
                compare(gap, 6, "6 px at the usual spacing");
            }
            compare(c.markerGap, gap, "the marker's gap");
            compare(c.unitGap, Math.round(Kirigami.Units.smallSpacing * 0.75), "the unit's gap");
            const face = keep(faceComponent.createObject(root));
            compare(c.valuesWidth, face.room(face.plain, [root.decimal(10), root.digits(100)]), "the values' slot");
            compare(c.unitsWidth, face.room(face.plain, data.bits ? ["kb/s", "Mb/s", "Gb/s", "Tb/s"] : ["KiB/s", "MiB/s", "GiB/s", "TiB/s", "PiB/s"]),
                    "the units' column");
            const x = i => i.mapToItem(c, Qt.point(0, 0)).x;
            const right = i => i.mapToItem(c, Qt.point(i.width, 0)).x;
            const rates = root.findAll(c, i => i.index !== undefined && i.reading !== undefined).sort((a, b) => a.index - b.index);
            compare(rates.length, 2);
            const values = rates.map(r => root.find(r, i => i.horizontalAlignment === Text.AlignRight && i.text !== undefined));
            const units = rates.map(r => root.find(r, i => i.text !== undefined && i !== values[rates.indexOf(r)] && i.visible
                                                     && i.parent === values[rates.indexOf(r)].parent));
            const ends = values.map(right);
            const starts = units.map(x);
            const width = c.implicitWidth;
            const shape = new RegExp("^([0-9]" + "\\" + Qt.locale().decimalPoint + "[0-9][0-9]|[0-9][0-9]" + "\\" + Qt.locale().decimalPoint
                                     + "[0-9]|[0-9][0-9][0-9]|–)$");
            for (const state of extremes()[data.item]) {
                apply(data.item, state);
                settle();
                const what = "showing " + root.texts(c).join(" ");
                compare(c.implicitWidth, width, what + ": the width");
                for (let row = 0; row < 2; ++row) {
                    const value = values[row];
                    const unit = units[row];
                    const marker = rates[row].children[0];
                    compare([value.text, unit.text], [c.lines[row].value, c.lines[row].unit], what);
                    verify(shape.test(value.text.replace(/[٠-٩]/g, d => String(d.charCodeAt(0) - 0x660))),
                           what + ": " + value.text + " in three figures");
                    verify(value.contentWidth <= value.width && unit.contentWidth <= c.unitsWidth, what + ": row " + row + " fits");
                    compare(right(value), ends[row], what + ": row " + row + "'s value ends where it did");
                    compare(x(unit), starts[row], what + ": row " + row + "'s unit starts where it did");
                    compare(x(unit) - right(value), c.unitGap, what + ": the unit's gap");
                    if (data.mirrored) {
                        compare(x(marker) - (x(value) + value.width + c.unitGap + c.unitsWidth), gap, what + ": row " + row + "'s marker to the right");
                    } else {
                        compare(x(value) - right(marker), gap, what + ": row " + row + "'s marker to the left");
                    }
                }
                if (!data.singleRow) {
                    compare(ends[0], ends[1], what + ": the values end at one edge");
                    compare(starts[0], starts[1], what + ": the units line up");
                }
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
                      across: 2 * Math.round(Kirigami.Units.smallSpacing / 2), along: 2 * Math.round(Kirigami.Units.smallSpacing * 1.5) },
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

        // A cell is as wide as its content and its padding, rounded up to a
        // whole pixel across a horizontal panel, and follows it at once
        // either way: the readings' rooms are what keep it still.
        function test_cellFollowsItsContent() {
            const block = keep(blockComponent.createObject(root));
            const c = keep(panelCellComponent.createObject(root, { contentItem: block }));
            const outside = 2 * Math.round(Kirigami.Units.smallSpacing * 1.5);
            compare(c.implicitWidth, 50 + outside, "as wide as its content");
            block.implicitWidth = 60.2;
            compare(c.implicitWidth, 61 + outside, "wider, to a whole pixel");
            block.implicitWidth = 40;
            compare(c.implicitWidth, 40 + outside, "narrower, at once");
            c.vertical = true;
            block.implicitWidth = 40.5;
            compare(c.implicitWidth, 40.5 + 2 * Kirigami.Units.smallSpacing, "along a vertical panel, as it is");
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
