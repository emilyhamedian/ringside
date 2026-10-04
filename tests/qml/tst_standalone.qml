// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/code/items.js" as Items
import "../../package/contents/ui/code/style.js" as Style

// The Standalone strip with FakeMonitor's readings: folding to the tab and
// back with a fake panel window, the chevron lane, dials on every edge at
// any scale, readouts that hold their width, and what each dial says.
Item {
    id: root
    width: 800
    height: 800

    // A bare qml runtime has no KI18n; the views find these on the root.
    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }
    function i18n(text, ...args) { return substitute(text, args); }
    function i18nc(context, text, ...args) { return substitute(text, args); }
    function i18np(s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }
    function i18ncp(c, s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }

    readonly property var usageItems: ["claude", "codex"]
    readonly property var mixedItems: ["cpu", "gpu", "memory", "network", "disk", "claude", "codex"]

    Component {
        id: monitorComponent
        FakeMonitor {}
    }

    Component {
        id: stripComponent
        StandaloneStrip {
            width: 80
            // Across a horizontal strip, its own size would feed back into the
            // dials' scale.
            height: vertical ? implicitHeight : minimumThickness
            vertical: true
            location: PlasmaCore.Types.RightEdge
            items: root.usageItems
            enabledItems: root.usageItems
            onVisibilityModeRequested: mode => visibilityMode = mode
        }
    }

    Component {
        id: nativeButtonComponent
        QQC2.Button { y: 350; width: 100; height: 40; text: "Reference" }
    }

    // A panel holding only Ringside: the window's thickness is set at once,
    // the applet's geometry follows, optionally a frame later as Wayland
    // commits it, and the theme pads the content by `chrome` across the
    // thickness.
    Component {
        id: panelSceneComponent
        Item {
            id: scene
            width: 800
            height: 800
            required property var monitor
            property var items: root.usageItems
            property int edge: PlasmaCore.Types.RightEdge
            property bool delayGeometry: false
            property bool stuckGeometry: false
            property int geometryDelay: 16
            property int chrome: 16
            property int renderedThickness: 160
            property alias drawer: panelStrip
            property alias panel: fakePanelWindow
            property alias sizing: panelSizing

            QtObject {
                id: fakePanelWindow
                property int thickness: 160
                property bool userConfiguring: false
                property int thicknessChanges: 0
                onThicknessChanged: {
                    thicknessChanges++;
                    if (scene.stuckGeometry) {
                        return;
                    }
                    if (scene.delayGeometry) {
                        if (!geometryTimer.running) {
                            geometryTimer.start();
                        }
                    } else {
                        scene.renderedThickness = thickness;
                    }
                }
            }

            Timer {
                id: geometryTimer
                interval: scene.geometryDelay
                onTriggered: scene.renderedThickness = fakePanelWindow.thickness
            }

            PanelSizeController {
                id: panelSizing
                panelWindow: fakePanelWindow
                dedicated: true
                collapsed: panelStrip.compactLayout
                chrome: scene.chrome
                minimumContentThickness: panelStrip.minimumThickness
                expandedThickness: 160
                onRememberThickness: thickness => expandedThickness = thickness
            }

            StandaloneStrip {
                id: panelStrip
                monitor: scene.monitor
                items: scene.items
                enabledItems: scene.items
                location: scene.edge
                vertical: scene.edge === PlasmaCore.Types.LeftEdge || scene.edge === PlasmaCore.Types.RightEdge
                width: vertical ? scene.renderedThickness - scene.chrome : implicitWidth
                height: vertical ? implicitHeight : scene.renderedThickness - scene.chrome
                x: vertical ? (scene.edge === PlasmaCore.Types.RightEdge ? 700 - width : 40)
                            : 400 - width / 2
                y: vertical ? 400 - height / 2
                            : (scene.edge === PlasmaCore.Types.BottomEdge ? 700 - height : 40)
                expandedThickness: panelSizing.expandedThickness - scene.chrome
                compactThickness: panelSizing.tabThickness - scene.chrome
                editing: fakePanelWindow.userConfiguring
                onVisibilityModeRequested: mode => visibilityMode = mode
            }
        }
    }

    Component {
        id: clickSpyComponent
        SignalSpy { signalName: "clicked" }
    }

    TestCase {
        id: testCase
        name: "Standalone"
        when: windowShown

        property var monitor: null
        property var strip: null
        property var defaultStrip: null
        property var scene: null

        SignalSpy {
            id: modeRequests
            target: testCase.strip
            signalName: "visibilityModeRequested"
        }

        SignalSpy {
            id: activations
            target: testCase.strip
            signalName: "activated"
        }

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            monitor = monitorComponent.createObject(root);
            makeStrip({});
        }

        // The views go first, so their bindings never see the monitor gone.
        function cleanup() {
            scene?.destroy();
            defaultStrip?.destroy();
            wait(0);
            monitor.destroy();
            scene = null;
            defaultStrip = null;
            strip = null;
        }

        function makeStrip(properties) {
            defaultStrip?.destroy();
            defaultStrip = stripComponent.createObject(root, Object.assign({ monitor: monitor }, properties));
            verify(defaultStrip !== null);
            strip = defaultStrip;
            if (strip.vertical) {
                strip.width = strip.minimumThickness;
            }
            modeRequests.clear();
            activations.clear();
            outsideWidget();
            waitForRendering(strip);
            return strip;
        }

        function setEntry(id, entry) {
            const entries = Object.assign({}, monitor.usage.entries);
            entries[id] = entry;
            monitor.usage.entries = entries;
        }

        function handle() {
            const result = findChild(strip, "drawerHandle");
            verify(result !== null);
            return result;
        }

        function grid() {
            const result = findChild(strip, "dials");
            verify(result !== null);
            return result;
        }

        function shownDials() {
            return Array.from(grid().children).filter(child => child.visible && child.dial !== undefined)
                .map(entry => entry.dial);
        }

        function dialFor(item) {
            const result = shownDials().find(dial => dial.item === item);
            verify(result !== undefined, item + " dial must be shown");
            return result;
        }

        function emptyRing() {
            return Array.from(grid().children).find(child => child.reason !== undefined);
        }

        // The dial's ink, ring over readout, without the cell's wash.
        function face(dial) {
            const result = findChild(dial, "face");
            verify(result !== null);
            return result;
        }

        function gauge(dial) {
            return face(dial).item.children[0];
        }

        // The hover summary wrapping the dial.
        function toolTip(dial) {
            return dial.parent;
        }

        // The inner of the gauge's two arcs.
        function innerArc(dial) {
            const arcs = [];
            const pending = [gauge(dial)];
            while (pending.length > 0) {
                const item = pending.shift();
                if (item.playReset !== undefined && item.animating !== undefined) {
                    arcs.push(item);
                }
                pending.push(...Array.from(item.children));
            }
            compare(arcs.length, 2);
            return arcs[0].radius < arcs[1].radius ? arcs[0] : arcs[1];
        }

        // Texts a dial's readout shows, in layout order, without a blank line.
        function shownReadout(dial) {
            const texts = [];
            const pending = [findChild(dial, "readout") ?? face(dial)];
            while (pending.length > 0) {
                const item = pending.shift();
                if (!item.visible) {
                    continue;
                }
                if (item.text !== undefined && item.contentWidth !== undefined && item.text !== "") {
                    texts.push(item.text);
                }
                pending.push(...Array.from(item.children));
            }
            return texts;
        }

        // The readout's texts in layout order: the ring's own reading, the
        // dot a thin panel puts between the two, hidden under a dial, and the
        // second reading.
        function readoutParts(dial) {
            const parts = Array.from(findChild(dial, "readout").children[0].children);
            compare(parts.map(part => part.objectName), ["first", "", "second"]);
            compare(parts[1].visible, false, "a dial stacks its lines, without the dot");
            return parts;
        }

        // Text keeps its colour in 8 bits a channel, so a translucent one is
        // compared as drawn.
        function compareColour(actual, expected, message) {
            compare(String(actual), String(expected), message);
        }

        // Where each line of a dial's readout sits in the strip, and the box
        // around them.
        function readoutGeometry(dial) {
            const box = findChild(dial, "readout");
            const place = item => {
                const at = item.mapToItem(strip, 0, 0);
                return [at.x, at.y, item.width, item.height];
            };
            const parts = readoutParts(dial);
            return { item: dial.item, box: place(box), first: place(parts[0]), second: place(parts[2]) };
        }

        function revealByKeyboard() {
            handle().forceActiveFocus(Qt.TabFocusReason);
            tryCompare(handle(), "visualFocus", true);
            tryCompare(strip, "handleProgress", 1);
        }

        function hoverDial() {
            const dial = shownDials()[0];
            mouseMove(dial, dial.width / 2, dial.height / 2);
            tryCompare(strip, "handleProgress", 1);
        }

        function outsideWidget() {
            mouseMove(root, root.width - 1, root.height - 1);
        }

        function settleExpansion(progress) {
            tryCompare(strip, "expansionProgress", progress);
            tryCompare(strip, "compactLayout", progress === 0 && strip.collapsed);
            tryCompare(grid(), "visible", progress > 0);
        }

        function createPanelScene(edge, properties) {
            defaultStrip.visible = false;
            scene = panelSceneComponent.createObject(root,
                Object.assign({ monitor: monitor, edge: edge }, properties || {}));
            verify(scene !== null);
            strip = scene.drawer;
            modeRequests.clear();
            outsideWidget();
            settleExpansion(1);
            tryCompare(strip, "handleProgress", 0);
            tryCompare(scene.panel, "thickness", scene.sizing.expandedThickness);
            tryCompare(scene, "renderedThickness", scene.panel.thickness);
            return scene;
        }

        // Rendered size of the dial group, through its scale transform.
        function renderedSize(group) {
            const origin = group.mapToItem(root, 0, 0);
            const right = group.mapToItem(root, group.width, 0);
            const bottom = group.mapToItem(root, 0, group.height);
            return { width: Math.hypot(right.x - origin.x, right.y - origin.y),
                     height: Math.hypot(bottom.x - origin.x, bottom.y - origin.y) };
        }

        // Rendered centre of the dial group in the strip, through its scale and slide.
        function renderedCentre(group) {
            return group.mapToItem(strip, group.width / 2, group.height / 2);
        }

        function test_automaticCoverage() {
            compare(strip.visibilityMode, 0);
            compare(strip.collapsed, false);
            strip.covered = true;
            compare(strip.collapsed, true);
            strip.covered = false;
            compare(strip.collapsed, false);
            compare(modeRequests.count, 0);
        }

        function test_manualModesPersist_data() {
            return [
                { tag: "expanded", mode: 1, collapsed: false },
                { tag: "folded", mode: 2, collapsed: true }
            ];
        }

        function test_manualModesPersist(data) {
            strip.visibilityMode = data.mode;
            for (const covered of [true, false, true, false]) {
                strip.covered = covered;
                compare(strip.collapsed, data.collapsed);
                compare(strip.visibilityMode, data.mode);
            }
            strip.covered = true;
            strip.visibilityMode = 0;
            compare(strip.collapsed, true);
            strip.covered = false;
            compare(strip.collapsed, false);
            compare(modeRequests.count, 0);
        }

        function test_pointerToggleWhileRestored() {
            hoverDial();
            const button = handle();
            mouseClick(button, button.width / 2, button.height / 2);
            compare(modeRequests.count, 1);
            compare(modeRequests.signalArguments[0][0], 2);
            compare(strip.visibilityMode, 2);
            compare(strip.collapsed, true);
            settleExpansion(0);
            mouseClick(button, button.width / 2, button.height / 2);
            compare(modeRequests.count, 2);
            compare(modeRequests.signalArguments[1][0], 1);
            compare(strip.visibilityMode, 1);
            compare(strip.collapsed, false);
        }

        function test_keyboardToggleOncePerPress() {
            const button = handle();
            button.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(strip, "handleProgress", 1);
            tryCompare(button, "activeFocus", true);
            keyClick(Qt.Key_Space);
            compare(modeRequests.count, 1);
            compare(strip.collapsed, true);
            waitForRendering(strip);
            keyClick(Qt.Key_Space);
            compare(modeRequests.count, 2);
            compare(strip.collapsed, false);
        }

        function test_accessibleAction() {
            const button = handle();
            compare(button.Accessible.role, Accessible.Button);
            compare(button.Accessible.name, "Fold Ringside");
            compare(button.expanded, true);
            strip.visibilityMode = 2;
            compare(button.Accessible.name, "Unfold Ringside");
            compare(button.expanded, false);
            compare(button.visible, true);
            compare(button.enabled, true);
            settleExpansion(0);
            compare(grid().visible, false);
            button.Accessible.pressAction();
            compare(modeRequests.count, 1);
            compare(strip.collapsed, false);
            button.Accessible.pressAction();
            compare(modeRequests.count, 2);
            compare(strip.collapsed, true);
        }

        function test_nativeEnterActivation_data() {
            return [
                { tag: "return", key: Qt.Key_Return },
                { tag: "keypad-enter", key: Qt.Key_Enter }
            ];
        }

        function test_nativeEnterActivation(data) {
            // Whether Enter clicks a button depends on the platform. The handle
            // must do what a stock button does, and toggle at most once.
            const reference = createTemporaryObject(nativeButtonComponent, root);
            const clicks = createTemporaryObject(clickSpyComponent, root, { target: reference });
            reference.forceActiveFocus();
            keyClick(data.key);
            const nativeCount = clicks.count;
            verify(nativeCount <= 1);
            handle().forceActiveFocus(Qt.TabFocusReason);
            tryCompare(strip, "handleProgress", 1);
            keyClick(data.key);
            compare(modeRequests.count, nativeCount);
            compare(strip.collapsed, nativeCount === 1);
        }

        function test_chevronFollowsIntent() {
            const button = handle();
            const collapseGlyph = findChild(button, "collapseGlyph");
            const expandGlyph = findChild(button, "expandGlyph");
            verify(collapseGlyph !== null && expandGlyph !== null);
            compare(collapseGlyph.opacity, 1);
            compare(expandGlyph.opacity, 0);
            strip.visibilityMode = 2;
            // The glyph switches as soon as the request is made, ahead of the motion.
            tryCompare(expandGlyph, "opacity", 1);
            tryCompare(collapseGlyph, "opacity", 0);
            strip.visibilityMode = 1;
            tryCompare(collapseGlyph, "opacity", 1);
            tryCompare(expandGlyph, "opacity", 0);
        }

        // System and usage dials together, on every edge at two scales: each
        // face centred across the strip and inside it, one after another
        // along it, and the handle after the last.
        function test_handleAfterDialsAlongLength_data() {
            const cases = [];
            for (const scale of [1, 2]) {
                for (const edge of [
                    { name: "right", location: PlasmaCore.Types.RightEdge, vertical: true },
                    { name: "left", location: PlasmaCore.Types.LeftEdge, vertical: true },
                    { name: "top", location: PlasmaCore.Types.TopEdge, vertical: false },
                    { name: "bottom", location: PlasmaCore.Types.BottomEdge, vertical: false }
                ]) {
                    cases.push({ tag: edge.name + "-" + scale, location: edge.location,
                                 vertical: edge.vertical, scale: scale });
                }
            }
            return cases;
        }

        function test_handleAfterDialsAlongLength(data) {
            makeStrip({ items: root.mixedItems, enabledItems: root.mixedItems,
                        location: data.location, vertical: data.vertical });
            // The scaled length follows the layout's polish, so bind it.
            if (data.vertical) {
                strip.width = strip.minimumThickness * data.scale;
                strip.height = Qt.binding(() => strip.implicitHeight);
            } else {
                strip.height = strip.minimumThickness * data.scale;
                strip.width = Qt.binding(() => strip.implicitWidth);
            }
            waitForRendering(strip);
            tryCompare(strip, "sizeFactor", data.scale);
            revealByKeyboard();
            const button = handle();
            const b = button.mapToItem(strip, 0, 0);
            verify(button.width > 0 && button.height > 0);
            const dials = shownDials();
            compare(dials.map(dial => dial.item), root.mixedItems);
            let previousEnd = -Infinity;
            for (const dial of dials) {
                const ink = face(dial);
                const r = ink.mapToItem(strip, 0, 0);
                if (dial.item !== "network" && dial.item !== "disk") {
                    compare(gauge(dial).width, 52 * data.scale);
                }
                const geometry = JSON.stringify({ item: dial.item, x: r.x, y: r.y, width: ink.width,
                    height: ink.height, stripWidth: strip.width, stripHeight: strip.height,
                    buttonX: b.x, buttonY: b.y, buttonWidth: button.width, buttonHeight: button.height });
                verify(r.x >= -0.5 && r.y >= -0.5, "Face outside the strip: " + geometry);
                verify(r.x + ink.width <= strip.width + 0.5, "Face exceeds width: " + geometry);
                verify(r.y + ink.height <= strip.height + 0.5, "Face exceeds height: " + geometry);
                // Centred across the thickness: the lane lives along the length.
                const centre = data.vertical ? r.x + ink.width / 2 - strip.width / 2
                                             : r.y + ink.height / 2 - strip.height / 2;
                verify(Math.abs(centre) <= 0.5, "Face off-centre by " + centre + ": " + geometry);
                const start = data.vertical ? r.y : r.x;
                verify(start >= previousEnd + strip.gap - 0.5, "Faces keep the gap between them: " + geometry);
                previousEnd = start + (data.vertical ? ink.height : ink.width);
                // The cell spans the strip's thickness.
                const cell = dial.mapToItem(strip, 0, 0);
                if (data.vertical) {
                    compare(cell.x, 0);
                    compare(dial.width, strip.width);
                } else {
                    compare(cell.y, 0);
                    compare(dial.height, strip.height);
                }
            }
            if (data.vertical) {
                verify(previousEnd + strip.laneGap <= b.y + 0.5, "The handle must sit after the dials");
                verify(Math.abs((b.x + button.width / 2) - strip.width / 2) <= 0.5, "Handle centred across the strip");
            } else {
                verify(previousEnd + strip.laneGap <= b.x + 0.5, "The handle must sit after the dials");
                verify(Math.abs((b.y + button.height / 2) - strip.height / 2) <= 0.5, "Handle centred across the strip");
            }
        }

        // An item coming or going changes the strip's length, never the
        // dials' scale: the reserve covers every item switched on.
        function test_dialsComingAndGoing() {
            makeStrip({ items: ["cpu", "claude", "codex"], enabledItems: ["cpu", "claude", "codex"] });
            compare(shownDials().map(dial => dial.item), ["cpu", "claude", "codex"]);
            const thickness = strip.minimumThickness;
            const threeLong = strip.implicitHeight;
            strip.items = ["cpu", "codex"];
            waitForRendering(strip);
            compare(shownDials().map(dial => dial.item), ["cpu", "codex"]);
            verify(strip.implicitHeight < threeLong);
            compare(strip.minimumThickness, thickness);
            compare(emptyRing().visible, false);
            strip.items = [];
            waitForRendering(strip);
            compare(shownDials().length, 0);
            compare(emptyRing().visible, true);
            verify(strip.implicitWidth > 0 && strip.implicitHeight > 0);
            compare(strip.minimumThickness, thickness);
            strip.items = ["claude"];
            waitForRendering(strip);
            compare(shownDials().map(dial => dial.item), ["claude"]);
            compare(emptyRing().visible, false);
            compare(strip.cellAt(0), shownDials()[0]);
            compare(strip.cellAt(1), null);
        }

        function test_minimumThickness_data() {
            const cases = [];
            for (const edge of [{ name: "right", location: PlasmaCore.Types.RightEdge, vertical: true },
                                { name: "bottom", location: PlasmaCore.Types.BottomEdge, vertical: false }]) {
                for (const set of [{ name: "usage", items: root.usageItems }, { name: "mixed", items: root.mixedItems }]) {
                    cases.push({ tag: edge.name + "-" + set.name, location: edge.location, vertical: edge.vertical,
                                 items: set.items });
                }
            }
            return cases;
        }

        // The panel's least thickness: whole pixels, room across it for every
        // face at the base size, the ring's padding on a vertical panel, and
        // the same while the panel folds and unfolds, so each makes one
        // native change.
        function test_minimumThickness(data) {
            // Bound to this strip, which stays while the panel scene below
            // takes over `strip`.
            const flat = makeStrip({ items: data.items, enabledItems: data.items, vertical: data.vertical,
                                     location: data.location });
            const minimum = flat.minimumThickness;
            verify(Number.isInteger(minimum), "whole pixels, got " + minimum);
            if (data.vertical) {
                flat.width = minimum;
                flat.height = Qt.binding(() => flat.implicitHeight);
            } else {
                flat.height = minimum;
                flat.width = Qt.binding(() => flat.implicitWidth);
            }
            waitForRendering(strip);
            compare(strip.sizeFactor, 1);
            compare(shownDials().map(dial => dial.item), data.items);
            for (const dial of shownDials()) {
                const ink = face(dial);
                const across = data.vertical ? ink.width : ink.height;
                verify(across > 0 && minimum >= Math.ceil(across),
                       dial.item + " face " + across + "px across a " + minimum + "px strip");
            }
            if (data.vertical) {
                // A 52px ring with 8px either side, or the widest face if a
                // readout is wider than that.
                const widest = Math.max(...shownDials().map(dial => face(dial).width));
                compare(minimum, Math.max(68, Math.ceil(widest)));
            } else {
                verify(minimum >= 72, "the ring, its gap and two lines, got " + minimum);
            }

            createPanelScene(data.location, { items: data.items });
            compare(strip.minimumThickness, minimum);
            const nativeChangesBefore = scene.panel.thicknessChanges;
            strip.visibilityMode = 2;
            for (let sample = 0; sample < 100 && strip.expansionProgress > 0; sample++) {
                wait(5);
                compare(strip.minimumThickness, minimum, "while folding");
            }
            settleExpansion(0);
            tryCompare(scene.panel, "thickness", 44);
            compare(strip.minimumThickness, minimum, "folded");
            strip.visibilityMode = 1;
            for (let sample = 0; sample < 100 && strip.expansionProgress < 1; sample++) {
                wait(5);
                compare(strip.minimumThickness, minimum, "while unfolding");
            }
            settleExpansion(1);
            tryCompare(scene.panel, "thickness", scene.sizing.expandedThickness);
            compare(strip.minimumThickness, minimum, "unfolded");
            compare(scene.panel.thicknessChanges - nativeChangesBefore, 2,
                    "Folding and unfolding must each make one native thickness change");
        }

        // Every reading at 100 %, with the countdown at its widest, in days,
        // and unknown. Seconds past the minute keep the rounding clear of the
        // test's own running time.
        function test_readoutFitsMinimumThickness_data() {
            return [
                { tag: "widest-countdown", left: 23 * 3600 + 59 * 60 + 30, countdown: "23h 59m" },
                { tag: "days", left: 6 * 86400 + 23 * 3600 + 30 * 60, countdown: "6d 23h" },
                { tag: "no-reset", left: NaN, countdown: "–" }
            ];
        }

        // Every readout fits the strip at its minimum thickness, each ring's
        // in two lines, and neither 100 % nor a countdown changes the reserve.
        function test_readoutFitsMinimumThickness(data) {
            makeStrip({ items: root.mixedItems, enabledItems: root.mixedItems });
            const reservedThickness = strip.minimumThickness;
            const weekly = { percent: 100 };
            if (Number.isFinite(data.left)) {
                weekly.resetsAt = monitor.usage.createdAt + data.left;
            }
            setEntry("claude", { status: "ok", weekly: weekly,
                                 scoped: [{ id: "Fable", label: "Fable", percent: 100 }] });
            setEntry("codex", { status: "ok", weekly: weekly,
                                scoped: [{ id: "codex_spark", label: "Spark", percent: 100 }] });
            monitor.cpuUsage = 100;
            monitor.cpuTemperature = 140;
            monitor.gpuOuter.usage = 100;
            monitor.gpuOuter.temperature = 140;
            monitor.memoryUsed = 1023 * 1048576;
            monitor.networkDown = 999.9e6 / 8;
            waitForRendering(strip);
            compare(strip.minimumThickness, reservedThickness);
            compare(strip.width, reservedThickness);
            compare(shownReadout(dialFor("cpu")), ["100%", "140°"]);
            compare(shownReadout(dialFor("gpu")), ["100%", "140°"]);
            compare(shownReadout(dialFor("memory")), ["3%", "1023M"]);
            for (const dial of shownDials()) {
                if (Items.isRing(dial.item)) {
                    compare(shownReadout(dial).length, 2, dial.item + " shows two lines");
                }
                if (dial.usage) {
                    compare(shownReadout(dial), ["100%", data.countdown]);
                }
                // Each line within the room the strip keeps for it.
                if (Items.isRing(dial.item)) {
                    const parts = readoutParts(dial);
                    for (const line of [0, 1]) {
                        const text = parts[2 * line];
                        verify(text.width >= dial.parts[line] - 0.5,
                               dial.item + " line " + line + " is " + text.width + "px, its room " + dial.parts[line] + "px");
                        verify(text.contentWidth <= dial.parts[line] + 0.5,
                               dial.item + " " + text.text + " is " + text.contentWidth + "px, its room "
                               + dial.parts[line] + "px");
                    }
                }
                const pending = [face(dial)];
                while (pending.length > 0) {
                    const child = pending.pop();
                    if (!child.visible) {
                        continue;
                    }
                    if (child.text !== undefined && child.contentWidth !== undefined) {
                        const left = child.mapToItem(strip, 0, 0).x
                            + (child.horizontalAlignment === Text.AlignRight ? child.width - child.contentWidth
                               : child.horizontalAlignment === Text.AlignHCenter ? (child.width - child.contentWidth) / 2 : 0);
                        verify(left >= -0.5 && left + child.contentWidth <= strip.width + 0.5,
                               dial.item + " readout " + child.text + " must stay inside the strip: "
                               + JSON.stringify({ left: left, width: child.contentWidth, strip: strip.width }));
                        compare(child.truncated, false);
                    }
                    pending.push(...Array.from(child.children));
                }
            }
        }

        // As readings change, every dial keeps its size and each readout line
        // its place, a blank one included, so a row of dials never shifts.
        function test_readoutWidthsHoldAsValuesChange() {
            makeStrip({ items: root.mixedItems, enabledItems: root.mixedItems, vertical: false,
                        location: PlasmaCore.Types.BottomEdge });
            strip.height = strip.minimumThickness;
            strip.width = Qt.binding(() => strip.implicitWidth);
            waitForRendering(strip);
            const length = strip.implicitWidth;
            const sizes = () => JSON.stringify(shownDials().map(dial => [dial.item, dial.width, dial.height,
                dial.mapToItem(strip, 0, 0).x]));
            const lines = () => JSON.stringify(shownDials().filter(dial => findChild(dial, "readout"))
                .map(dial => readoutGeometry(dial)));
            const before = sizes();
            const linesBefore = lines();
            const codex = dialFor("codex");
            const created = monitor.usage.createdAt;
            const codexReset = created + 5 * 86400 + 4 * 3600;
            // Seconds past the minute keep the rounding clear of the test's
            // own running time.
            const claudeLeft = left => () => setEntry("claude", { status: "ok",
                weekly: { percent: 62, resetsAt: created + left }, scoped: [{ id: "Opus", label: "Opus", percent: 78 }] });
            const codexLeft = left => () => { codex.nowMs = (codexReset - left) * 1000; };
            // Each change, and what the dial it reaches reads after it.
            const changes = [
                { run: () => { monitor.cpuUsage = 5; monitor.cpuTemperature = 38; }, dial: "cpu", readout: ["5%", "38°"] },
                { run: () => { monitor.cpuUsage = 100; monitor.cpuTemperature = 140; }, dial: "cpu", readout: ["100%", "140°"] },
                { run: () => { monitor.fahrenheit = true; }, dial: "cpu", readout: ["100%", "284°"] },
                { run: () => { monitor.cpuTemperature = NaN; monitor.cpuUsage = NaN; }, dial: "cpu", readout: ["–", "–"] },
                { run: () => { monitor.gpuOuter.usage = 100; monitor.gpuOuter.temperature = 99; },
                  dial: "gpu", readout: ["100%", "210°"] },
                { run: () => { monitor.memoryUsed = 1023 * 1048576; }, dial: "memory", readout: ["3%", "1023M"] },
                { run: () => { monitor.memoryUsed = 9.6 * monitor.gib; }, dial: "memory", readout: ["30%", "9.6G"] },
                { run: () => { monitor.networkDown = 0; monitor.networkUp = 1.3e7; } },
                { run: () => { monitor.diskRead = NaN; monitor.diskWrite = 1e9; } },
                { run: () => { setEntry("claude", { status: "ok", weekly: { percent: 100 },
                                                    scoped: [{ id: "Opus", label: "Opus", percent: 100 }] }); },
                  dial: "claude", readout: ["100%", "–"] },
                { run: () => { setEntry("codex", { status: "ok", weekly: { percent: 3 } }); },
                  dial: "codex", readout: ["3%", "–"] },
                { run: () => { monitor.usage.innerChoices = { claude: "none", codex: "" }; },
                  dial: "claude", readout: ["100%", "–"] },
                { run: () => { monitor.usage.innerChoices = { claude: "", codex: "" }; },
                  dial: "claude", readout: ["100%", "–"] },
                // The countdown through its forms, by the reset moving and by
                // the clock.
                { run: claudeLeft(2 * 86400 + 21 * 3600 + 30 * 60), dial: "claude", readout: ["62%", "2d 21h"] },
                { run: claudeLeft(5 * 3600 + 12 * 60 + 30), dial: "claude", readout: ["62%", "5h 12m"] },
                { run: claudeLeft(12 * 60 + 30), dial: "claude", readout: ["62%", "12m"] },
                { run: claudeLeft(-60), dial: "claude", readout: ["62%", "–"] },
                { run: () => { setEntry("codex", { status: "ok", weekly: { percent: 34, resetsAt: codexReset } });
                               codexLeft(5 * 86400 + 4 * 3600)(); },
                  dial: "codex", readout: ["34%", "5d 4h"] },
                { run: codexLeft(2 * 86400 + 21 * 3600), dial: "codex", readout: ["34%", "2d 21h"] },
                { run: codexLeft(5 * 3600 + 12 * 60), dial: "codex", readout: ["34%", "5h 12m"] },
                { run: codexLeft(12 * 60), dial: "codex", readout: ["34%", "12m"] },
                { run: codexLeft(0), dial: "codex", readout: ["34%", "–"] },
                // A blank second line, for the only GPU asleep and for Intel.
                { run: () => { monitor.gpuInner.present = false; monitor.gpuOuter.phase = "asleep"; },
                  dial: "gpu", readout: ["off"] },
                { run: () => { monitor.gpuOuter.phase = "live"; monitor.gpuOuter.reportsTemperature = false; },
                  dial: "gpu", readout: ["100%"] }
            ];
            for (let i = 0; i < changes.length; ++i) {
                changes[i].run();
                waitForRendering(strip);
                if (changes[i].dial) {
                    compare(shownReadout(dialFor(changes[i].dial)), changes[i].readout, "change " + i);
                }
                compare(strip.implicitWidth, length, "change " + i);
                compare(sizes(), before, "change " + i);
                compare(lines(), linesBefore, "change " + i);
            }
        }

        // The inner ring follows the chosen limit; the readout under it keeps
        // the weekly share and the time to its reset whichever limit shows.
        function test_innerLimitFollowsSettings() {
            const claude = dialFor("claude");
            const codex = dialFor("codex");
            compare(claude.limit.id, "Opus", "The only limit shows by default");
            compare(gauge(claude).inner, true);
            compare(gauge(claude).innerValue, 78);
            compare(shownReadout(claude), ["62%", "2d 21h"]);
            compare(codex.limit, null, "No scoped limit, no inner ring");
            compare(gauge(codex).inner, false);
            compare(shownReadout(codex), ["34%", "5d 4h"]);

            setEntry("codex", { status: "ok", weekly: { percent: 34 },
                                scoped: [{ id: "codex_spark", label: "GPT-5.3-Codex-Spark", percent: 5 }] });
            compare(codex.limit.id, "codex_spark", "A new limit is picked up");
            compare(gauge(codex).inner, true);
            compare(gauge(codex).innerValue, 5);
            compare(shownReadout(codex), ["34%", "–"]);

            const fable = { id: "Fable", label: "Fable", percent: 78 };
            const opus = { id: "Opus", label: "Opus", percent: 9 };
            setEntry("claude", { status: "ok", weekly: { percent: 62 }, scoped: [fable, opus] });
            compare(claude.limit, null, "Several and none picked: all models only");
            compare(gauge(claude).inner, false);
            compare(shownReadout(claude), ["62%", "–"]);
            monitor.usage.innerChoices = { claude: "Opus", codex: "" };
            compare(claude.limit.id, "Opus");
            compare(gauge(claude).inner, true);
            compare(gauge(claude).innerValue, 9);
            compare(shownReadout(claude), ["62%", "–"]);
            monitor.usage.innerChoices = { claude: "none", codex: "" };
            compare(claude.limit, null);
            compare(gauge(claude).inner, false);
            compare(shownReadout(claude), ["62%", "–"]);
            monitor.usage.innerChoices = { claude: "Opus", codex: "" };
            setEntry("claude", { status: "ok", weekly: { percent: 62 }, scoped: [fable] });
            compare(claude.limit, null, "A picked limit that goes away leaves one circle");
            compare(gauge(claude).inner, false);

            // A reading without a weekly window yet, after a failed first poll.
            setEntry("codex", { status: "error", lastError: "timed out", lastErrorAt: 1 });
            compare(shownReadout(codex), ["–", "–"]);
            verify(!Number.isFinite(gauge(codex).value));
        }

        function test_resetsReachOnlyTheShownLimit() {
            const fable = { id: "Fable", label: "Fable", percent: 78 };
            const opus = { id: "Opus", label: "Opus", percent: 9 };
            setEntry("claude", { status: "ok", weekly: { percent: 62 }, scoped: [fable, opus] });
            monitor.usage.innerChoices = { claude: "Fable", codex: "" };
            const claude = dialFor("claude");
            const inner = innerArc(claude);
            monitor.usage.resetsDetected({ "claude.scoped.Opus": { from: 92, early: true } });
            compare(inner.animating, false, "A limit that is not shown plays nothing");
            monitor.usage.resetsDetected({ "claude.scoped.Fable": { from: 92, early: true } });
            verify(inner.animating, "The shown limit plays its reset");
            tryCompare(inner, "animating", false);
            // Events are handed over once, so changing the pick replays nothing.
            monitor.usage.innerChoices = { claude: "Opus", codex: "" };
            monitor.usage.innerChoices = { claude: "Fable", codex: "" };
            compare(inner.animating, false);
            compare(inner.head, 78);
            monitor.usage.innerChoices = { claude: "none", codex: "" };
            monitor.usage.resetsDetected({ "claude.scoped.Fable": { from: 92, early: true } });
            compare(inner.animating, false, "No reset plays on a hidden arc");
            // The weekly arc plays its own, and only on its own dial.
            monitor.usage.resetsDetected({ "codex.weekly": { from: 97, early: false } });
            const outers = dial => {
                const arcs = [];
                const pending = [gauge(dial)];
                while (pending.length > 0) {
                    const item = pending.shift();
                    if (item.playReset !== undefined) {
                        arcs.push(item);
                    }
                    pending.push(...Array.from(item.children));
                }
                return arcs.reduce((a, b) => a.radius > b.radius ? a : b);
            };
            verify(outers(dialFor("codex")).animating);
            compare(outers(claude).animating, false);
            tryCompare(outers(dialFor("codex")), "animating", false, 5000);
        }

        // Choosing an inner limit changes nothing but the arc and its
        // readout: every dial keeps its scale and its place, and the native
        // panel is untouched.
        function test_innerLimitKeepsDialsInPlace() {
            createPanelScene(PlasmaCore.Types.RightEdge);
            scene.sizing.expandedThickness = strip.minimumThickness + scene.chrome;
            tryCompare(scene.panel, "thickness", scene.sizing.expandedThickness);
            tryCompare(scene, "renderedThickness", scene.panel.thickness);
            compare(strip.sizeFactor, 1);
            // Layouts settle their implicit size on the next polish.
            waitForRendering(strip);
            const nativeChangesBefore = scene.panel.thicknessChanges;
            const length = strip.implicitHeight;
            // Where each dial is drawn: its gauge's centre and size on screen.
            const dials = () => shownDials().map(dial => {
                const ring = gauge(dial);
                const centre = ring.mapToItem(root, ring.width / 2, ring.height / 2);
                return { item: dial.item, x: centre.x, y: centre.y, diameter: ring.width };
            });
            const shown = dials();

            monitor.usage.innerChoices = { claude: "none", codex: "" };
            setEntry("codex", { status: "ok", weekly: { percent: 34 },
                                scoped: [{ id: "codex_spark", label: "Spark", percent: 100 }] });
            wait(0);
            waitForRendering(strip);
            compare(strip.sizeFactor, 1);
            compare(strip.implicitHeight, length);
            compare(JSON.stringify(dials()), JSON.stringify(shown));

            monitor.usage.innerChoices = { claude: "", codex: "" };
            wait(0);
            waitForRendering(strip);
            compare(JSON.stringify(dials()), JSON.stringify(shown));
            compare(scene.panel.thicknessChanges - nativeChangesBefore, 0,
                    "Switching inner limits never resizes the native panel");
        }

        function test_foldedDimensions_data() {
            return [
                { tag: "vertical", vertical: true },
                { tag: "horizontal", vertical: false }
            ];
        }

        function test_foldedDimensions(data) {
            strip.height = 220;
            strip.vertical = data.vertical;
            strip.width = data.vertical ? strip.minimumThickness : 280;
            strip.height = data.vertical ? 220 : strip.minimumThickness;
            waitForRendering(strip);
            const expandedLength = data.vertical ? strip.implicitHeight : strip.implicitWidth;
            strip.visibilityMode = 2;
            strip.width = data.vertical ? strip.minimumThickness : 52;
            strip.height = data.vertical ? 52 : strip.minimumThickness;
            settleExpansion(0);
            tryCompare(strip, "compactLayout", true);
            tryVerify(() => (data.vertical ? strip.implicitHeight : strip.implicitWidth) < expandedLength,
                      5000, "The compact layout must settle to a shorter length");
            const foldedLength = data.vertical ? strip.implicitHeight : strip.implicitWidth;
            verify(foldedLength > 0);
            verify(foldedLength < expandedLength,
                   "Folded length " + foldedLength + " must be below expanded length " + expandedLength);
            compare(grid().visible, false);
            compare(handle().visible, true);
            tryCompare(handle(), "opacity", 1);
            verify(grid().width >= 0 && grid().height >= 0);
            const button = handle();
            const b = button.mapToItem(strip, 0, 0);
            verify(b.x >= -0.5 && b.y >= -0.5);
            verify(b.x + button.width <= strip.width + 0.5);
            verify(b.y + button.height <= strip.height + 0.5);
        }

        function test_hoverRevealsWithoutResizing() {
            createPanelScene(PlasmaCore.Types.RightEdge);
            const width = scene.panel.thickness;
            const nativeChangesBefore = scene.panel.thicknessChanges;
            compare(handle().opacity, strip.restingHandleOpacity);
            hoverDial();
            tryCompare(handle(), "opacity", 1);
            compare(scene.panel.thickness, width);

            // Entering the control itself keeps it shown long enough to click it.
            const button = handle();
            mouseMove(button, button.width / 2, button.height / 2);
            wait(400);
            compare(strip.handleProgress, 1);

            outsideWidget();
            wait(80);
            compare(strip.handleProgress, 1);
            tryCompare(strip, "handleProgress", 0);
            compare(handle().opacity, strip.restingHandleOpacity);
            compare(scene.panel.thickness, width);
            compare(scene.sizing.expandedThickness, width);
            compare(scene.panel.thicknessChanges - nativeChangesBefore, 0,
                    "Revealing the control must never resize the native panel");
        }

        function test_pointerOnChevronLightsItAtOnce() {
            createPanelScene(PlasmaCore.Types.RightEdge);
            const button = handle();
            compare(button.opacity, strip.restingHandleOpacity);
            mouseMove(button, button.width / 2, button.height / 2);
            tryCompare(button, "hovered", true);
            compare(button.opacity, 1, "No reveal fade when the pointer is on the control itself");
            const dials = shownDials();
            const lastFace = face(dials[dials.length - 1]);
            const lane = button.mapToItem(strip, 0, 0);
            const last = lastFace.mapToItem(strip, 0, lastFace.height);
            verify(lane.y - last.y >= strip.laneGap - 0.5, "The lane keeps the dials' spacing before the control");
        }

        function test_keyboardFocusRevealsUntilFocusLeaves() {
            createPanelScene(PlasmaCore.Types.RightEdge);
            revealByKeyboard();
            outsideWidget();
            wait(400);
            compare(strip.handleProgress, 1);
            verify(handle().visualFocus);
            root.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(strip, "handleProgress", 0);
        }

        // Tab visits each dial, then the retracted control, which it reveals.
        function test_tabTraversalReachesTheControl() {
            createPanelScene(PlasmaCore.Types.RightEdge);
            compare(handle().opacity, strip.restingHandleOpacity);
            root.forceActiveFocus(Qt.TabFocusReason);
            for (const dial of shownDials()) {
                keyClick(Qt.Key_Tab);
                tryCompare(dial, "activeFocus", true);
                compare(strip.handleProgress, 0);
            }
            keyClick(Qt.Key_Tab);
            tryCompare(handle(), "activeFocus", true);
            tryCompare(handle(), "visualFocus", true);
            tryCompare(strip, "handleProgress", 1);
            compare(modeRequests.count, 0);
            compare(activations.count, 0);
        }

        function test_collapsedHoverNeverExpands() {
            createPanelScene(PlasmaCore.Types.RightEdge);
            strip.visibilityMode = 2;
            settleExpansion(0);
            tryCompare(scene.panel, "thickness", 44);
            tryCompare(handle(), "opacity", 1);
            const button = handle();
            mouseMove(button, button.width / 2, button.height / 2);
            wait(400);
            compare(strip.collapsed, true);
            compare(scene.panel.thickness, 44);
            compare(grid().visible, false);
            outsideWidget();
            wait(400);
            compare(button.opacity, 1);
            compare(scene.panel.thickness, 44);
        }

        function test_mouseToggleRoundTrip() {
            createPanelScene(PlasmaCore.Types.RightEdge);
            const width = scene.panel.thickness;
            hoverDial();
            const button = handle();
            mouseClick(button, button.width / 2, button.height / 2);
            settleExpansion(0);
            tryCompare(scene.panel, "thickness", 44);
            compare(strip.collapsed, true);
            mouseClick(button, button.width / 2, button.height / 2);
            compare(strip.collapsed, false);
            compare(button.visualFocus, false);
            settleExpansion(1);
            tryCompare(scene.panel, "thickness", width);
            outsideWidget();
            tryCompare(strip, "handleProgress", 0);
            compare(scene.sizing.expandedThickness, width);
            compare(modeRequests.count, 2);
        }

        function test_restingChevronAcceptsClick() {
            createPanelScene(PlasmaCore.Types.RightEdge);
            const button = handle();
            compare(button.opacity, strip.restingHandleOpacity);
            const position = button.mapToItem(root, button.width / 2, button.height / 2);
            mouseClick(root, position.x, position.y);
            compare(modeRequests.count, 1);
            compare(strip.collapsed, true);
            settleExpansion(0);
            tryCompare(scene.panel, "thickness", 44);
        }

        function test_editModeKeepsControlShown() {
            createPanelScene(PlasmaCore.Types.RightEdge);
            scene.panel.userConfiguring = true;
            tryCompare(strip, "handleProgress", 1);
            compare(scene.panel.thickness, scene.sizing.expandedThickness);
            scene.panel.thickness = 200;
            tryCompare(scene.sizing, "expandedThickness", 200);
            scene.panel.userConfiguring = false;
            tryCompare(strip, "handleProgress", 0);
            compare(scene.panel.thickness, 200);
            hoverDial();
            compare(scene.panel.thickness, 200);
            outsideWidget();
            tryCompare(strip, "handleProgress", 0);
            compare(scene.sizing.expandedThickness, 200);
        }

        function test_revealKeepsDialsInPlace() {
            outsideWidget();
            tryCompare(strip, "handleProgress", 0);
            const before = shownDials().map(dial => dial.mapToItem(root, 0, 0));
            revealByKeyboard();
            const dials = shownDials();
            for (let i = 0; i < dials.length; i++) {
                const position = dials[i].mapToItem(root, 0, 0);
                compare(position.x, before[i].x);
                compare(position.y, before[i].y);
            }
        }

        function test_dialsCentredForAnyChrome_data() {
            return [
                { tag: "breeze", chrome: 8 },
                { tag: "wide", chrome: 16 }
            ];
        }

        function test_dialsCentredForAnyChrome(data) {
            createPanelScene(PlasmaCore.Types.RightEdge, { chrome: data.chrome, items: root.mixedItems });
            // At the base scale, so all seven dials fit the test window.
            scene.sizing.expandedThickness = strip.minimumThickness + data.chrome;
            tryCompare(scene, "renderedThickness", scene.sizing.expandedThickness);
            compare(strip.sizeFactor, 1);
            compare(strip.width, scene.panel.thickness - data.chrome);
            const offCentre = () => shownDials().map(dial => {
                const ink = face(dial);
                return ink.mapToItem(strip, 0, 0).x + ink.width / 2 - strip.width / 2;
            });
            for (const offset of offCentre()) {
                verify(Math.abs(offset) <= 0.5, "Face off-centre by " + offset + "px with chrome " + data.chrome);
            }
            hoverDial();
            for (const offset of offCentre()) {
                verify(Math.abs(offset) <= 0.5);
            }
        }

        function test_collapseShrinksAndFades_data() {
            return [
                { tag: "right", edge: PlasmaCore.Types.RightEdge },
                { tag: "left", edge: PlasmaCore.Types.LeftEdge },
                { tag: "top", edge: PlasmaCore.Types.TopEdge },
                { tag: "bottom", edge: PlasmaCore.Types.BottomEdge }
            ];
        }

        function test_collapseShrinksAndFades(data) {
            createPanelScene(data.edge, { items: root.mixedItems });
            revealByKeyboard();
            const group = grid();
            const dials = shownDials();
            const button = handle();
            const fullThickness = scene.sizing.expandedThickness;
            compare(scene.panel.thickness, fullThickness);
            const nativeChangesBefore = scene.panel.thicknessChanges;
            const expandedLength = strip.vertical ? strip.height : strip.width;
            const before = renderedSize(group);
            // The dials slide from where they sit open to where the tab's
            // content will be.
            const open = renderedCentre(group);
            const tab = Qt.point(strip.compactCenterX, strip.compactCenterY);
            const tabDistance = centre => Math.hypot(tab.x - centre.x, tab.y - centre.y);
            verify(tabDistance(open) > 20, "The open dials must sit away from the tab, " + tabDistance(open) + "px");
            let previous = { progress: 1, distance: tabDistance(open) };
            let halfway = null;
            let late = null;
            strip.visibilityMode = 2;
            compare(strip.collapsed, true);
            compare(button.Accessible.name, "Unfold Ringside");
            let sawIntermediate = false;
            let sawShrink = false;
            let sawFade = false;
            let lateFrameOpacity = 0;
            for (let sample = 0; sample < 100 && strip.expansionProgress > 0; sample++) {
                wait(5);
                const progress = strip.expansionProgress;
                if (progress > 0 && progress < 1) {
                    sawIntermediate = true;
                    compare(group.visible, true);
                    for (const dial of dials) {
                        compare(toolTip(dial).active, false, "Tooltips must be off while the dials move");
                    }
                    const size = renderedSize(group);
                    sawShrink = sawShrink || (size.width < before.width - 0.01 && size.height < before.height - 0.01);
                    // Uniform scale: circles stay circles.
                    verify(Math.abs(size.width / size.height - before.width / before.height) <= 0.01,
                           "Dials must shrink uniformly, got " + JSON.stringify(size) + " from " + JSON.stringify(before));
                    verify(size.width >= before.width * 0.7, "Dials keep at least 70% of their size");
                    const centre = renderedCentre(group);
                    for (const axis of ["x", "y"]) {
                        verify(centre[axis] >= Math.min(open[axis], tab[axis]) - 0.01
                               && centre[axis] <= Math.max(open[axis], tab[axis]) + 0.01,
                               "Dials must stay between their open place " + open + " and the tab " + tab
                               + ", at " + centre + " with progress " + progress);
                    }
                    const sample = { progress: progress, distance: tabDistance(centre) };
                    // Each hundredth of the fold brings the dials at least
                    // 0.2 px closer, well clear of rounding.
                    if (progress <= previous.progress - 0.01) {
                        verify(sample.distance < previous.distance - 0.05,
                               "Dials must approach the tab as the fold goes on: " + JSON.stringify(sample)
                               + " after " + JSON.stringify(previous));
                        previous = sample;
                    }
                    if (!halfway || Math.abs(progress - 0.5) < Math.abs(halfway.progress - 0.5)) {
                        halfway = sample;
                    }
                    if (!late || Math.abs(progress - 0.1) < Math.abs(late.progress - 0.1)) {
                        late = sample;
                    }
                    sawFade = sawFade || (group.opacity > 0 && group.opacity < 1);
                    if (progress < 0.1) {
                        lateFrameOpacity = Math.max(lateFrameOpacity, group.opacity);
                    }
                    compare(scene.panel.thickness, fullThickness,
                            "Native width must stay fixed while the content animates");
                    compare(strip.vertical ? strip.height : strip.width, expandedLength,
                            "Native length must stay expanded until the content finishes closing");
                    verify(button.visible && button.enabled);
                    compare(handle(), button);
                }
            }
            verify(sawIntermediate, "Folding must show intermediate animation frames");
            verify(sawShrink, "Dials must shrink while approaching the tab");
            verify(halfway && Math.abs(halfway.progress - 0.5) <= 0.2,
                   "Folding must show a frame near halfway, closest " + JSON.stringify(halfway));
            verify(late && late.progress <= 0.2, "Folding must show a frame near its end, closest " + JSON.stringify(late));
            verify(halfway.distance < tabDistance(open) - 1 && late.distance < halfway.distance - 1,
                   "Dials must approach the tab: open " + tabDistance(open) + "px, then " + JSON.stringify(halfway)
                   + ", then " + JSON.stringify(late));
            verify(sawFade, "Dials must fade while folding");
            verify(lateFrameOpacity < 0.11, "Dials must be gone before the native snap, saw opacity " + lateFrameOpacity);
            settleExpansion(0);
            tryCompare(scene.panel, "thickness", 44);
            compare(group.visible, false);
            compare(strip.compactLayout, true);
            compare(scene.panel.thicknessChanges - nativeChangesBefore, 1);
            verify((strip.vertical ? strip.height : strip.width) < expandedLength);
            compare(scene.sizing.expandedThickness, fullThickness);
            tryCompare(button, "opacity", 1);

            button.Accessible.pressAction();
            compare(strip.collapsed, false);
            compare(strip.compactLayout, false);
            settleExpansion(1);
            tryCompare(scene.panel, "thickness", fullThickness);
            compare(group.visible, true);
            compare(group.opacity, 1);
            for (const dial of dials) {
                tryCompare(toolTip(dial), "active", true);
            }
            const restored = renderedSize(group);
            verify(Math.abs(restored.width - before.width) <= 0.01);
            verify(Math.abs(restored.height - before.height) <= 0.01);
            verify(Math.abs((strip.vertical ? strip.height : strip.width) - expandedLength) <= 0.01);
            compare(scene.sizing.expandedThickness, fullThickness);
            compare(scene.panel.thicknessChanges - nativeChangesBefore, 2,
                    "Folding and unfolding must each make one native thickness change");
        }

        function test_tabArrowWaitsForPanelToShrink() {
            createPanelScene(PlasmaCore.Types.RightEdge, { delayGeometry: true });
            const button = handle();
            // A slow compositor: the panel has been asked to shrink but has not
            // yet. No arrow may appear inside the still-wide window.
            scene.geometryDelay = 200;
            strip.visibilityMode = 2;
            tryCompare(strip, "compactLayout", true);
            tryCompare(scene.panel, "thickness", 44);
            verify(scene.renderedThickness > 44);
            wait(80);
            verify(scene.renderedThickness > 44);
            compare(button.opacity, 0);
            tryCompare(scene, "renderedThickness", 44);
            tryCompare(button, "opacity", 1);
        }

        function test_rapidCollapseReversePreservesFocusAndIntent() {
            createPanelScene(PlasmaCore.Types.RightEdge);
            revealByKeyboard();
            const button = handle();
            const fullThickness = scene.sizing.expandedThickness;
            keyClick(Qt.Key_Space);
            wait(Kirigami.Units.longDuration / 2);
            verify(strip.expansionProgress > 0 && strip.expansionProgress < 1);
            const closingProgress = strip.expansionProgress;
            keyClick(Qt.Key_Space);
            compare(strip.collapsed, false);
            wait(Kirigami.Units.longDuration / 3);
            verify(strip.expansionProgress > closingProgress, "Reversing must resume toward the latest intent");
            for (let toggle = 0; toggle < 3; toggle++) {
                keyClick(Qt.Key_Space);
                wait(Kirigami.Units.longDuration / 3);
                compare(handle(), button);
                compare(button.activeFocus, true);
            }
            compare(strip.collapsed, true);
            settleExpansion(0);
            tryCompare(scene.panel, "thickness", 44);
            compare(grid().visible, false);
            compare(modeRequests.count, 5);
            keyClick(Qt.Key_Space);
            settleExpansion(1);
            compare(strip.collapsed, false);
            compare(grid().visible, true);
            compare(button.activeFocus, true);
            compare(modeRequests.count, 6);
            compare(scene.sizing.expandedThickness, fullThickness);
        }

        function test_hoverKeepsDialsFixed_data() {
            const cases = [];
            for (const configuration of [
                { name: "base", baseScale: true, delayGeometry: false },
                { name: "fractional", baseScale: false, delayGeometry: false },
                { name: "fractional-delayed", baseScale: false, delayGeometry: true }
            ]) {
                for (const edge of [
                    { name: "right", edge: PlasmaCore.Types.RightEdge },
                    { name: "left", edge: PlasmaCore.Types.LeftEdge },
                    { name: "top", edge: PlasmaCore.Types.TopEdge },
                    { name: "bottom", edge: PlasmaCore.Types.BottomEdge }
                ]) {
                    cases.push({ tag: edge.name + "-" + configuration.name, edge: edge.edge,
                        baseScale: configuration.baseScale, delayGeometry: configuration.delayGeometry });
                }
            }
            return cases;
        }

        function test_hoverKeepsDialsFixed(data) {
            createPanelScene(data.edge, { delayGeometry: data.delayGeometry });
            if (data.baseScale) {
                scene.sizing.expandedThickness = strip.minimumThickness + scene.chrome;
                tryCompare(scene.panel, "thickness", scene.sizing.expandedThickness);
                tryCompare(scene, "renderedThickness", scene.panel.thickness);
                compare(strip.sizeFactor, 1);
            } else {
                verify(strip.sizeFactor > 1);
            }
            wait(20);
            const savedWidth = scene.sizing.expandedThickness;
            const nativeChangesBefore = scene.panel.thicknessChanges;
            const dials = shownDials();
            const before = dials.map(dial => ({ position: dial.mapToItem(root, 0, 0),
                diameter: gauge(dial).width, width: dial.width, height: dial.height }));
            let maximumXShift = 0;
            let maximumYShift = 0;
            const gridWidth = grid().width;
            const gridHeight = grid().height;
            let maximumGridSizeChange = 0;
            function checkPositions() {
                maximumGridSizeChange = Math.max(maximumGridSizeChange,
                    Math.abs(grid().width - gridWidth), Math.abs(grid().height - gridHeight));
                for (let i = 0; i < dials.length; i++) {
                    const dial = dials[i];
                    const position = dial.mapToItem(root, 0, 0);
                    maximumXShift = Math.max(maximumXShift, Math.abs(position.x - before[i].position.x));
                    maximumYShift = Math.max(maximumYShift, Math.abs(position.y - before[i].position.y));
                    compare(gauge(dial).width, before[i].diameter);
                    compare(dial.width, before[i].width);
                    compare(dial.height, before[i].height);
                }
                compare(scene.sizing.expandedThickness, savedWidth);
            }
            mouseMove(dials[0], dials[0].width / 2, dials[0].height / 2);
            for (let frame = 0; frame < 24; frame++) {
                wait(10);
                checkPositions();
            }
            tryCompare(strip, "handleProgress", 1);
            checkPositions();
            outsideWidget();
            for (let frame = 0; frame < 48; frame++) {
                wait(10);
                checkPositions();
            }
            tryCompare(strip, "handleProgress", 0);
            checkPositions();
            verify(maximumXShift <= 0.01 && maximumYShift <= 0.01,
                   "Dial displacement exceeded 0.01px: x=" + maximumXShift + ", y=" + maximumYShift);
            verify(maximumGridSizeChange <= 0.01,
                   "Dial layout changed size during hover by " + maximumGridSizeChange + "px");
            compare(scene.panel.thicknessChanges - nativeChangesBefore, 0);
        }

        function test_openingWaitsForPanelThenSettles() {
            createPanelScene(PlasmaCore.Types.RightEdge, { delayGeometry: true });
            const longDuration = Kirigami.Units.longDuration;
            strip.visibilityMode = 2;
            settleExpansion(0);
            tryCompare(scene, "renderedThickness", 44);
            strip.visibilityMode = 1;
            // The native panel is asked to grow first; the dials stay shut until
            // its new thickness has actually arrived.
            compare(strip.expansionProgress, 0);
            compare(strip.waitingForPanel, true);
            compare(grid().visible, false);
            tryCompare(scene.panel, "thickness", scene.sizing.expandedThickness);
            compare(strip.expansionProgress, 0);
            tryCompare(scene, "renderedThickness", scene.panel.thickness);
            const started = Date.now();
            tryCompare(strip, "waitingForPanel", false);
            wait(Math.ceil(longDuration / 2));
            verify(strip.expansionProgress > 0.5, "Opening must be well under way at half the long duration: " + strip.expansionProgress);
            const remainingBudget = Math.max(1, longDuration + 80 - (Date.now() - started));
            tryVerify(() => strip.expansionProgress === 1 && shownDials().length === 2
                      && shownDials().every(dial => toolTip(dial).active),
                      remainingBudget, "Opening must finish and restore interaction within the long duration plus frame allowance");
        }

        function test_openingProceedsIfPanelNeverResizes() {
            createPanelScene(PlasmaCore.Types.RightEdge);
            strip.visibilityMode = 2;
            settleExpansion(0);
            tryCompare(scene, "renderedThickness", 44);
            scene.stuckGeometry = true;
            strip.visibilityMode = 1;
            compare(strip.waitingForPanel, true);
            wait(Kirigami.Units.veryLongDuration / 2);
            compare(strip.expansionProgress, 0);
            tryCompare(strip, "waitingForPanel", false, Kirigami.Units.veryLongDuration);
            settleExpansion(1);
        }

        function test_activation_data() {
            return [
                { tag: "mouse", how: "mouse" },
                { tag: "space", how: Qt.Key_Space },
                { tag: "return", how: Qt.Key_Return },
                { tag: "keypad-enter", how: Qt.Key_Enter },
                { tag: "accessibility", how: "accessibility" }
            ];
        }

        // Each dial is a button that asks for its popup, once per press, and
        // hands over itself for the popup to sit beside.
        function test_activation(data) {
            makeStrip({ items: ["cpu", "network", "claude"], enabledItems: ["cpu", "network", "claude"] });
            for (let index = 0; index < 3; index++) {
                const dial = strip.cellAt(index);
                activations.clear();
                if (data.how === "mouse") {
                    mouseClick(dial, dial.width / 2, dial.height / 2);
                } else if (data.how === "accessibility") {
                    compare(dial.Accessible.role, Accessible.Button);
                    dial.Accessible.pressAction();
                } else {
                    dial.forceActiveFocus(Qt.TabFocusReason);
                    keyClick(data.how);
                }
                compare(activations.count, 1, dial.item);
                compare(activations.signalArguments[0][0], dial.item);
                compare(activations.signalArguments[0][1], dial);
            }
            // A dial asks for nothing once the strip is folding.
            strip.visibilityMode = 2;
            activations.clear();
            strip.cellAt(0).Accessible.pressAction();
            compare(activations.count, 0);
        }

        // The hover summary names the dial and says its readings in words;
        // it stays away while the strip folds and over the dial's own popup.
        function test_toolTips() {
            makeStrip({ items: ["cpu", "memory", "claude"], enabledItems: ["cpu", "memory", "claude"] });
            const cpu = dialFor("cpu");
            const area = toolTip(cpu);
            compare(area.mainText, cpu.title);
            compare(area.mainText, "Processor");
            compare(area.subText, "Usage 23%, temperature 61 °C");
            compare(cpu.Accessible.name, "Processor");
            compare(cpu.Accessible.description, area.subText);
            compare(toolTip(dialFor("memory")).subText, "13.4 GiB in use, 42%");
            verify(area.active);

            mouseMove(cpu, cpu.width / 2, cpu.height / 2);
            verify(cpu.containsMouse && area.containsMouse, "hover reaches the cell and the tooltip");

            strip.openItem = "cpu";
            verify(!area.active, "no tooltip over the dial's open popup");
            compare(cpu.open, true);
            verify(toolTip(dialFor("memory")).active, "other dials keep theirs");
            strip.openItem = "";
            verify(area.active);

            strip.visibilityMode = 2;
            for (const dial of shownDials()) {
                verify(!toolTip(dial).active, dial.item + " tooltip while folding");
            }
            settleExpansion(0);
            strip.visibilityMode = 1;
            settleExpansion(1);
            verify(area.active);
        }

        // A folded dial's clock stops; unfolding brings its countdown up to
        // date at once, not up to a minute later.
        function test_countdownRefreshesAfterUnfolding() {
            const claude = dialFor("claude");
            const codex = dialFor("codex");
            compare(shownReadout(claude), ["62%", "2d 21h"]);
            compare(shownReadout(codex), ["34%", "5d 4h"]);
            strip.visibilityMode = 2;
            settleExpansion(0);
            compare(claude.visible, false);
            const hourAgo = Date.now() - 3600 * 1000;
            claude.nowMs = hourAgo;
            codex.nowMs = hourAgo;
            compare(readoutParts(claude)[2].text, "2d 22h", "an hour stale while folded");
            compare(readoutParts(codex)[2].text, "5d 5h", "an hour stale while folded");
            strip.visibilityMode = 1;
            settleExpansion(1);
            for (const dial of [claude, codex]) {
                verify(Math.abs(dial.nowMs - Date.now()) < 5000,
                       dial.item + " clock " + (Date.now() - dial.nowMs) + "ms behind after unfolding");
            }
            compare(shownReadout(claude), ["62%", "2d 21h"]);
            compare(shownReadout(codex), ["34%", "5d 4h"]);
        }

        function test_usageDialNames() {
            const claude = dialFor("claude");
            compare(claude.title, "Claude");
            compare(toolTip(claude).mainText, "Claude");
            compare(dialFor("codex").title, "Codex");
        }

        function test_emptyRingWording_data() {
            return [
                { tag: "helper failed", error: "python3 was not found", enabled: ["claude"],
                  want: "python3 was not found" },
                { tag: "both signed out", error: "", enabled: ["claude", "codex"],
                  want: "Run claude or codex in a terminal to sign in." },
                { tag: "claude signed out", error: "", enabled: ["gpu", "claude"],
                  want: "Run claude in a terminal to sign in." },
                { tag: "codex signed out", error: "", enabled: ["codex"],
                  want: "Run codex in a terminal to sign in." },
                { tag: "first check failed", error: "", enabled: ["claude", "codex"],
                  statuses: { claude: { status: "signed_out", message: "" },
                              codex: { status: "error", message: "codex CLI not found" } },
                  want: "codex CLI not found" },
                { tag: "no GPU", error: "", enabled: ["gpu"],
                  want: "Choose items under Configure Ringside → Panel Items." },
                { tag: "nothing on", error: "", enabled: [],
                  want: "Choose items under Configure Ringside → Panel Items." }
            ];
        }

        function test_emptyRingWording(data) {
            monitor.usage.helperError = data.error;
            if (data.statuses) {
                monitor.usage.statuses = data.statuses;
            }
            makeStrip({ items: [], enabledItems: data.enabled });
            const empty = emptyRing();
            compare(empty.visible, true);
            compare(shownDials().length, 0);
            compare(empty.reason, data.want);
            compare(empty.Accessible.description, data.want);
            const area = Array.from(empty.children).find(child => child.subText !== undefined);
            compare(area.mainText, "Nothing to show");
            compare(area.subText, data.want);
            verify(area.active);
            strip.visibilityMode = 2;
            verify(!area.active, "no tooltip while folding");
            compare(handle().visible, true);
        }

        function test_emptyRingKeepsADialsFootprint_data() {
            const cases = [];
            for (const scale of [1, 1.5]) {
                for (const edge of [{ name: "right", location: PlasmaCore.Types.RightEdge, vertical: true },
                                    { name: "bottom", location: PlasmaCore.Types.BottomEdge, vertical: false }]) {
                    cases.push({ tag: edge.name + "-" + scale, location: edge.location,
                                 vertical: edge.vertical, scale: scale });
                }
            }
            return cases;
        }

        // The stand-in for an empty strip is as tall as a ring dial's face,
        // ring and both lines, so the panel keeps its size as the last reading
        // goes and the first one arrives, and it fits across the strip.
        function test_emptyRingKeepsADialsFootprint(data) {
            makeStrip({ items: ["claude"], enabledItems: root.usageItems, vertical: data.vertical,
                        location: data.location });
            if (data.vertical) {
                strip.width = strip.minimumThickness * data.scale;
                strip.height = Qt.binding(() => strip.implicitHeight);
            } else {
                strip.height = strip.minimumThickness * data.scale;
                strip.width = Qt.binding(() => strip.implicitWidth);
            }
            waitForRendering(strip);
            tryCompare(strip, "sizeFactor", data.scale);
            const dialHeight = dialFor("claude").faceHeight;
            const length = strip.implicitHeight;
            strip.items = [];
            waitForRendering(strip);
            const empty = emptyRing();
            compare(empty.visible, true);
            compare(shownDials().length, 0);
            verify(Math.abs(empty.implicitHeight - dialHeight) <= 0.5,
                   "empty ring " + empty.implicitHeight + "px tall, a dial's face " + dialHeight + "px");
            const at = empty.mapToItem(strip, 0, 0);
            verify(at.x >= -0.5 && at.x + empty.width <= strip.width + 0.5
                   && at.y >= -0.5 && at.y + empty.height <= strip.height + 0.5,
                   "the empty ring stays inside the strip: " + JSON.stringify({ x: at.x, y: at.y, width: empty.width,
                       height: empty.height, stripWidth: strip.width, stripHeight: strip.height }));
            if (data.vertical) {
                verify(Math.abs(strip.implicitHeight - length) <= 0.5,
                       "the strip's length " + strip.implicitHeight + "px, with a dial " + length + "px");
            } else {
                verify(empty.implicitHeight <= strip.minimumThickness * data.scale + 0.5,
                       "the empty ring " + empty.implicitHeight + "px across a " + strip.minimumThickness * data.scale
                       + "px strip");
            }
        }

        // A sleeping GPU drops out of its dial, whichever ring it is on; with
        // the only GPU asleep the dial says "off" around an empty ring. With
        // both awake the readout is the discrete GPU's alone.
        function test_gpuDialFollowsGpuView_data() {
            return [
                { tag: "both awake", outer: "live", inner: "live", present: true, dual: true,
                  readout: ["12%", "48°"], value: 12 },
                { tag: "outer asleep", outer: "asleep", inner: "live", present: true, dual: false,
                  readout: ["3%", "41°"], value: 3 },
                { tag: "inner asleep", outer: "live", inner: "asleep", present: true, dual: false,
                  readout: ["12%", "48°"], value: 12 },
                { tag: "only GPU asleep", outer: "asleep", inner: "live", present: false, dual: false,
                  readout: ["off"], value: NaN }
            ];
        }

        function test_gpuDialFollowsGpuView(data) {
            monitor.gpuInner.present = data.present;
            monitor.gpuOuter.phase = data.outer;
            monitor.gpuInner.phase = data.inner;
            makeStrip({ items: ["gpu"], enabledItems: ["gpu"] });
            const dial = dialFor("gpu");
            compare(gauge(dial).inner, data.dual);
            compare(shownReadout(dial), data.readout);
            if (Number.isNaN(data.value)) {
                verify(Number.isNaN(gauge(dial).value), "an empty ring");
                const [off, , blank] = readoutParts(dial);
                compareColour(off.color, Style.dim(Kirigami.Theme.textColor), "off reads dimmed");
                compare(blank.text, "");
                compare(blank.height, off.height, "the blank line keeps its place");
            } else {
                compare(gauge(dial).value, data.value);
            }
            verify(dial.description.indexOf("\n") < 0 || data.dual, "one GPU described");
        }

        function test_intelGpuLeavesTemperatureOut() {
            monitor.gpuOuter.reportsTemperature = false;
            monitor.gpuOuter.temperature = NaN;
            monitor.gpuInner.present = false;
            makeStrip({ items: ["gpu"], enabledItems: ["gpu"] });
            const dial = dialFor("gpu");
            compare(shownReadout(dial), ["12%"]);
            const [first, , second] = readoutParts(dial);
            compare(second.text, "");
            compare(second.height, first.height, "the blank line keeps its place");
        }

        // Claude and Codex breathe from 90 % until 100 %, and dim while their
        // last poll failed.
        function test_usagePulseAndDegraded_data() {
            return [
                { tag: "89", percent: 89, pulsing: false },
                { tag: "90", percent: 90, pulsing: true },
                { tag: "99", percent: 99, pulsing: true },
                { tag: "100", percent: 100, pulsing: false }
            ];
        }

        function test_usagePulseAndDegraded(data) {
            setEntry("claude", { status: "ok", weekly: { percent: data.percent }, scoped: [] });
            const claude = dialFor("claude");
            compare(gauge(claude).pulsing, data.pulsing);
            compare(face(claude).opacity, 1);
            setEntry("claude", { status: "ok", weekly: { percent: data.percent }, scoped: [],
                                 lastError: "rate limited", lastErrorAt: 1 });
            compare(face(claude).opacity, 0.55);
            compare(face(dialFor("codex")).opacity, 1);
        }

        function test_systemDialsNeverPulse() {
            monitor.cpuUsage = 95;
            makeStrip({ items: ["cpu"], enabledItems: ["cpu"] });
            compare(gauge(dialFor("cpu")).pulsing, false);
        }

        // A ring's own reading follows its level colours, as the ring does; a
        // temperature its heat. A countdown stays dim at every level.
        function test_levelColours_data() {
            return [{ tag: "74", percent: 74, tone: "text" }, { tag: "75", percent: 75, tone: "neutral" },
                    { tag: "89", percent: 89, tone: "neutral" }, { tag: "90", percent: 90, tone: "negative" }];
        }

        function test_levelColours(data) {
            const expected = data.tone === "negative" ? Kirigami.Theme.negativeTextColor
                           : data.tone === "neutral" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
            setEntry("claude", { status: "ok",
                                 weekly: { percent: data.percent, resetsAt: monitor.usage.createdAt + 2 * 86400 + 21 * 3600 + 30 * 60 },
                                 scoped: [{ id: "Opus", label: "Opus", percent: data.percent }] });
            const [percent, , countdown] = readoutParts(dialFor("claude"));
            compare(percent.text, data.percent + "%");
            compare(percent.color, expected);
            compare(countdown.text, "2d 21h");
            compareColour(countdown.color, Style.dim(Kirigami.Theme.textColor), "the countdown reads dim");
            compare(gauge(dialFor("claude")).outerTone, expected);
            compare(gauge(dialFor("claude")).innerTone, expected);

            monitor.cpuUsage = data.percent;
            monitor.cpuTemperature = 80;
            makeStrip({ items: ["cpu"], enabledItems: ["cpu"] });
            const [usage, , temperature] = readoutParts(dialFor("cpu"));
            compare(usage.color, expected);
            compare(temperature.text, "80°");
            compare(temperature.color, Kirigami.Theme.neutralTextColor, "80 °C reads warm");
            monitor.cpuTemperature = 50;
            compareColour(temperature.color, Style.dim(Kirigami.Theme.textColor), "50 °C reads dim");
        }

        function test_rateDials() {
            makeStrip({ items: ["network", "disk"], enabledItems: ["network", "disk"] });
            const texts = dial => {
                const found = [];
                const pending = [face(dial)];
                while (pending.length > 0) {
                    const item = pending.shift();
                    if (item.visible && item.text !== undefined && item.contentWidth !== undefined) {
                        found.push(item.text);
                    }
                    pending.push(...Array.from(item.children));
                }
                return found;
            };
            compare(texts(dialFor("network")), ["24.8M", "1.2M"]);
            compare(texts(dialFor("disk")), ["12.0M", "3.4M", "R", "W"]);
            compare(dialFor("network").description, "Down 24.8 Mb/s, up 1.2 Mb/s");
            compare(dialFor("disk").description, "Read 12.0 MiB/s, write 3.4 MiB/s");
            monitor.networkDown = NaN;
            compare(texts(dialFor("network"))[0], "–");
        }
    }
}
