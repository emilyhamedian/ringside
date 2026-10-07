// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.plasma.core as PlasmaCore
import "fakeplasmoid"

// main.qml in a panel: the applet's size along and across it in either
// orientation, the icon that stands in with every item hidden, the popup
// following its item's cell, and the global shortcut. Plasma gives
// org.kde.plasma.plasmoid only to an applet it runs, so main.qml is loaded
// from its source with that import pointed at fakeplasmoid/, its contextual
// actions left out (they are an attached property, which a fake can't
// take) and FakeMonitor for Monitor. Reading the source needs
// QML_XHR_ALLOW_FILE_READ=1, which scripts/test.sh sets.
Item {
    id: root
    width: 1800
    height: 1000

    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }
    function i18n(text, ...args) { return substitute(text, args); }
    function i18nc(context, text, ...args) { return substitute(text, args); }
    function i18np(s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }
    function i18ncp(c, s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }

    // A panel as Plasma lays one out: a GridLayout whose flow follows the
    // form factor, with something before the applet and room after it.
    Component {
        id: panelComponent
        GridLayout {
            readonly property bool horizontal: Plasmoid.formFactor !== PlasmaCore.Types.Vertical
            rowSpacing: 0
            columnSpacing: 0
            rows: horizontal ? 1 : -1
            columns: horizontal ? -1 : 1
            flow: horizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom

            Item {
                Layout.preferredWidth: parent.horizontal ? 100 : -1
                Layout.preferredHeight: parent.horizontal ? -1 : 100
                Layout.fillWidth: !parent.horizontal
                Layout.fillHeight: parent.horizontal
            }
        }
    }

    TestCase {
        id: testCase
        name: "Main"
        when: windowShown

        property string source: ""
        // The applet the test made, if any.
        property Item applet: null

        // main.qml's source with `from` replaced, which has to be there.
        function swap(text, from, to) {
            verify(from.test(text), "main.qml no longer matches " + from);
            return text.replace(from, to);
        }

        function initTestCase() {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../package/contents/ui/main.qml"), false);
            request.send();
            verify(request.responseText !== "", "main.qml read; set QML_XHR_ALLOW_FILE_READ=1");
            let text = swap(request.responseText, /^import org\.kde\.plasma\.plasmoid$/m,
                            'import "' + Qt.resolvedUrl("fakeplasmoid") + '"\nimport "' + Qt.resolvedUrl(".") + '"');
            text = swap(text, /^    Plasmoid\.contextualActions: \[\n[\s\S]*?^    \]\n/m, "");
            source = swap(text, /^    Monitor \{$/m, "    FakeMonitor {");
        }

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop|recursive rearrange/);
            Plasmoid.configuration = { ringsOnly: [] };
            Plasmoid.status = PlasmaCore.Types.PassiveStatus;
        }

        // The applet goes with its panel after the test, deleting its
        // monitor before the strip, whose cells would then read from null,
        // and on Qt 6.6 deleting the CPU popup's page in an order that has
        // its load averages read from null. So every item is hidden first,
        // and the popup's page left to unload as it does a moment after the
        // popup closes.
        function cleanup() {
            if (applet) {
                const p = popup(applet);
                p.visible = false;
                strip(applet).monitor.enabledItems = [];
                tryVerify(() => p.mainItem.item === null, 2000, "the popup's page unloaded");
                settle();
                applet = null;
            }
        }

        // A panel `thickness` across, `vertical` or not, holding the applet
        // after its first item.
        function panel(vertical, thickness) {
            Plasmoid.formFactor = vertical ? PlasmaCore.Types.Vertical : PlasmaCore.Types.Horizontal;
            Plasmoid.location = vertical ? PlasmaCore.Types.RightEdge : PlasmaCore.Types.BottomEdge;
            const p = createTemporaryObject(panelComponent, root,
                                            vertical ? { width: thickness, height: 900 } : { width: 1700, height: thickness });
            applet = Qt.createQmlObject(source, p, Qt.resolvedUrl("../../package/contents/ui/main.qml"));
            verify(applet, "main.qml loads");
            settle();
            return applet;
        }

        // Layouts settle on their next polish; nothing need be drawn.
        function settle() {
            wait(50);
            for (const item of root.children) {
                verify(waitForPolish(item), "laid out");
            }
        }

        function find(item, test) {
            if (test(item)) {
                return item;
            }
            for (const child of item.children) {
                const found = find(child, test);
                if (found) {
                    return found;
                }
            }
            return null;
        }

        function strip(applet) {
            return find(applet, i => i.cellAt !== undefined && i.ringsOnly !== undefined);
        }

        function popup(applet) {
            return Array.from(applet.data).find(o => o && o.popupDirection !== undefined);
        }

        // Each cell spans the panel's thickness inside the applet, after
        // the one before it.
        function checkCells(applet, vertical, thickness) {
            const s = strip(applet);
            let end = 0;
            for (let i = 0; i < applet.items.length; ++i) {
                const c = s.cellAt(i);
                verify(c, applet.items[i]);
                const box = c.mapToItem(applet, Qt.rect(0, 0, c.width, c.height));
                const [start, length, across] = vertical ? [box.y, box.height, box.width] : [box.x, box.width, box.height];
                verify(start >= end - 0.5, applet.items[i] + " follows");
                verify(start + length <= (vertical ? applet.height : applet.width) + 0.5, applet.items[i] + " inside the applet");
                compare(across, thickness, applet.items[i] + " spans the panel");
                end = start + length;
            }
        }

        function test_horizontal_data() {
            // A thick panel's rings stop growing, so there the strip still
            // has to stretch across it.
            return [{ tag: "26", thickness: 26 }, { tag: "44", thickness: 44 }, { tag: "72", thickness: 72 }];
        }

        // Along a horizontal panel the applet is as wide as the strip and as
        // tall as the panel, the strip at its start.
        function test_horizontal(data) {
            const applet = panel(false, data.thickness);
            const s = strip(applet);
            verify(s.visible);
            compare(applet.vertical, false);
            compare(applet.thickness, data.thickness);
            compare(applet.height, data.thickness, "as tall as the panel");
            fuzzyCompare(applet.width, s.implicitWidth, 0.001, "as wide as the strip");
            compare(applet.Layout.maximumWidth, applet.Layout.minimumWidth, "no wider");
            compare(s.height, data.thickness);
            fuzzyCompare(s.x, 0, 0.5);
            checkCells(applet, false, data.thickness);
        }

        // Down a vertical panel the applet is as tall as the strip and as
        // wide as the panel; switching the panel between the two follows.
        function test_verticalAndBack() {
            const applet = panel(true, 44);
            const s = strip(applet);
            compare(applet.vertical, true);
            compare(applet.width, 44, "as wide as the panel");
            fuzzyCompare(applet.height, s.implicitHeight, 0.001, "as tall as the strip");
            compare(applet.Layout.maximumHeight, applet.Layout.minimumHeight, "no taller");
            compare(s.width, 44);
            checkCells(applet, true, 44);

            const p = applet.parent;
            Plasmoid.formFactor = PlasmaCore.Types.Horizontal;
            Plasmoid.location = PlasmaCore.Types.BottomEdge;
            p.width = 1700;
            p.height = 44;
            settle();
            compare(applet.height, 44);
            fuzzyCompare(applet.width, s.implicitWidth, 0.001);
            checkCells(applet, false, 44);

            Plasmoid.formFactor = PlasmaCore.Types.Vertical;
            Plasmoid.location = PlasmaCore.Types.LeftEdge;
            p.width = 44;
            p.height = 900;
            settle();
            compare(applet.width, 44);
            fuzzyCompare(applet.height, s.implicitHeight, 0.001);
            checkCells(applet, true, 44);
        }

        function test_emptyKeepsASquare_data() {
            return [{ tag: "horizontal", vertical: false }, { tag: "vertical", vertical: true }];
        }

        // With every item hidden the applet is a square the panel's
        // thickness, with the icon that opens the settings.
        function test_emptyKeepsASquare(data) {
            const applet = panel(data.vertical, 44);
            strip(applet).monitor.enabledItems = [];
            settle();
            compare(applet.items.length, 0);
            verify(!strip(applet).visible);
            compare([applet.width, applet.height], [44, 44]);
            const icon = find(applet, i => i.source !== undefined && i.active !== undefined && i.isMask !== undefined);
            verify(icon && icon.visible, "the icon stands in");
            const configured = Plasmoid.configured;
            mouseClick(icon);
            compare(Plasmoid.configured, configured + 1, "a click opens the settings");
        }

        // An open popup moves to its item's new cell when the strip rebuilds,
        // and closes when its item goes.
        function test_popupFollowsItsCell() {
            const applet = panel(false, 44);
            const s = strip(applet);
            const memory = s.cellAt(2);
            compare(memory.item, "memory");
            applet.toggle("memory", memory);
            settle();
            verify(popup(applet).visible);
            compare(applet.openCell, memory);
            s.monitor.enabledItems = ["cpu", "memory", "network"];
            settle();
            tryVerify(() => applet.openCell !== null && applet.openCell.item === "memory", 2000, "on the new memory cell");
            compare(applet.openCell, s.cellAt(1));
            verify(popup(applet).visible, "still open");
            s.monitor.enabledItems = ["cpu", "network"];
            tryCompare(popup(applet), "visible", false, 2000, "closed with its item");
        }

        // Each system item opens its own popup: network and disk one each.
        function test_itemsOpenTheirOwnPopup() {
            const applet = panel(false, 44);
            const s = strip(applet);
            const loader = popup(applet).mainItem;
            const expected = { cpu: "CpuPopup", gpu: "GpuPopup", memory: "MemoryPopup", network: "NetworkPopup", disk: "DiskPopup" };
            compare(applet.items, Object.keys(expected));
            applet.items.forEach((item, n) => {
                applet.toggle(item, s.cellAt(n));
                settle();
                verify(popup(applet).visible, item);
                verify(String(loader.source).endsWith("/popups/" + expected[item] + ".qml"), item + " loads " + loader.source);
                compare(loader.status, Loader.Ready, item);
            });
            const title = () => find(loader.item, i => i.partsShown !== undefined).title;
            applet.toggle("network", s.cellAt(3));
            settle();
            compare(title(), "Network");
            applet.toggle("disk", s.cellAt(4));
            settle();
            compare(title(), "Disk");
        }

        // The global shortcut opens the first item's popup, and closes it.
        function test_shortcutOpensTheFirstItem() {
            const applet = panel(false, 44);
            Plasmoid.activated();
            settle();
            compare(applet.openItem, "cpu");
            compare(applet.openCell, strip(applet).cellAt(0));
            verify(popup(applet).visible);
            Plasmoid.activated();
            tryCompare(popup(applet), "visible", false, 2000);
        }
    }
}
