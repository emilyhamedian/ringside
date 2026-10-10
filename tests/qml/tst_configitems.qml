// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import "../../package/contents/ui/config"
import "fakeplasmoid"

// Panel Items can be reordered without a mouse: move buttons with names a
// screen reader announces, disabled at the ends, and focus that follows the
// row. Loads the real page; outside Plasma its hardware hints are empty.
// Plasma gives org.kde.plasma.plasmoid only to an applet it runs, so the
// Ring only test loads the page from its source with that import pointed at
// fakeplasmoid/, whose form factor the test sets. Reading the source needs
// QML_XHR_ALLOW_FILE_READ=1, which scripts/test.sh sets.

TestRoot {
    id: root
    width: 660
    height: 560


    Component {
        id: frame
        Rectangle {
            property alias page: page
            width: root.width
            height: root.height
            color: Kirigami.Theme.backgroundColor
            Kirigami.Theme.colorSet: Kirigami.Theme.Window
            ConfigItems {
                id: page
                anchors.fill: parent
                cfg_itemOrder: ["cpu", "gpu", "memory", "network", "disk"]
                cfg_ringsOnly: ["memory"]
            }
        }
    }

    // A bare page, for tests that only read cfg_ values, page.hints or
    // control state and don't need the Rectangle's theming.
    Component {
        id: plain
        ConfigItems {
            width: root.width
            height: root.height
        }
    }

    TestCase {
        name: "ConfigItems"

        // ConfigItems.qml with fakeplasmoid/ for org.kde.plasma.plasmoid,
        // and the page made from it, if any.
        property string panelSource: ""
        property var panelPage: null

        function initTestCase() {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../package/contents/ui/config/ConfigItems.qml"), false);
            request.send();
            verify(request.responseText !== "", "ConfigItems.qml read; set QML_XHR_ALLOW_FILE_READ=1");
            const from = /^import org\.kde\.plasma\.plasmoid$/m;
            verify(from.test(request.responseText), "ConfigItems.qml no longer matches " + from);
            panelSource = request.responseText.replace(from, 'import "' + Qt.resolvedUrl("fakeplasmoid") + '"');
        }

        function cleanup() {
            if (panelPage) {
                panelPage.destroy();
                panelPage = null;
            }
        }

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }
        when: windowShown

        function button(page, label) {
            return find(page, i => i.text === label && i.display !== undefined && i.icon !== undefined);
        }
        function make() {
            const f = createTemporaryObject(frame, root);
            verify(f);
            waitForRendering(f);
            return f;
        }
        function openPage(properties) {
            const p = createTemporaryObject(plain, root, properties);
            verify(p);
            waitForRendering(p);
            return p;
        }
        function checkbox(page, name) {
            return find(page, i => i.text === name && i.checkState !== undefined);
        }
        function accessible(page, name) {
            return find(page, i => i.Accessible && i.Accessible.name === name);
        }

        function test_edges_and_tooltips() {
            const page = make().page;
            verify(!button(page, "Move CPU up").enabled);
            verify(button(page, "Move CPU down").enabled);
            // Claude and OpenAI trail the list by default, so OpenAI is the
            // last row.
            verify(button(page, "Move OpenAI up").enabled);
            verify(!button(page, "Move OpenAI down").enabled);
            const up = button(page, "Move GPU up");
            compare(up.QQC2.ToolTip.text, "Move GPU up");
            compare(up.icon.name, "go-up");
            compare(up.display, QQC2.AbstractButton.IconOnly);
        }

        function test_keyboard_up_to_top() {
            const page = make().page;
            const up = button(page, "Move GPU up");
            const down = button(page, "Move GPU down");
            up.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => up.visualFocus);
            keyClick(Qt.Key_Space);
            compare(page.cfg_itemOrder, ["gpu", "cpu", "memory", "network", "disk", "claude", "codex"]);
            tryVerify(() => !up.enabled);
            tryVerify(() => down.activeFocus, 5000, "focus moved to Move GPU down");
            tryVerify(() => down.visualFocus, 5000, "keyboard focus stays visible");
            keyClick(Qt.Key_Space);
            compare(page.cfg_itemOrder, ["cpu", "gpu", "memory", "network", "disk", "claude", "codex"]);
            verify(down.activeFocus, "focus stays on the pressed button");
            tryVerify(() => up.enabled);
            keyClick(Qt.Key_Space);
            compare(page.cfg_itemOrder, ["cpu", "memory", "gpu", "network", "disk", "claude", "codex"]);
            verify(down.activeFocus);
        }

        // Claude and Codex trail every stored order, so they are the pair
        // at the bottom of the list.
        function test_keyboard_down_to_bottom() {
            const page = make().page;
            const down = button(page, "Move Claude down");
            const up = button(page, "Move Claude up");
            down.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(page.cfg_itemOrder, ["cpu", "gpu", "memory", "network", "disk", "codex", "claude"]);
            tryVerify(() => !down.enabled);
            verify(up.activeFocus, "focus moved to Move Claude up");
        }

        function test_mouse() {
            const page = make().page;
            const up = button(page, "Move Memory up");
            mouseClick(up);
            compare(page.cfg_itemOrder, ["cpu", "memory", "gpu", "network", "disk", "claude", "codex"]);
            mouseClick(button(page, "Move Memory up"));
            compare(page.cfg_itemOrder, ["memory", "cpu", "gpu", "network", "disk", "claude", "codex"]);
            verify(!up.enabled);
        }

        // Claude and Codex are opt-in: a 0.1-era config, with or without a
        // hidden list, never had a chance to list them in the stored order,
        // so both start unchecked. Loading the page must not write anything
        // back on its own.
        function test_aiRowsUnchecked_data() {
            return [
                { tag: "noStoredLists", order: ["cpu", "gpu", "memory", "network", "disk"], hidden: [] },
                { tag: "withStoredHidden", order: ["cpu", "gpu", "memory", "network", "disk"], hidden: ["disk"] }
            ];
        }
        function test_aiRowsUnchecked(data) {
            const page = openPage({ cfg_itemOrder: data.order, cfg_hiddenItems: data.hidden });
            verify(!checkbox(page, "Claude").checked, "Claude starts unchecked");
            verify(!checkbox(page, "OpenAI").checked, "OpenAI starts unchecked");
            compare(page.cfg_itemOrder, data.order, "loading writes nothing back");
            compare(page.cfg_hiddenItems, data.hidden, "loading writes nothing back");
        }

        function test_aiRowOnWhenOrderListsIt() {
            const page = openPage({ cfg_itemOrder: ["cpu", "claude", "gpu", "memory", "network", "disk"], cfg_hiddenItems: [] });
            verify(checkbox(page, "Claude").checked, "the stored order lists Claude");
            verify(!checkbox(page, "OpenAI").checked, "the stored order doesn't list OpenAI");
        }

        // Whichever list the page writes, it writes both together: the order
        // always lists every known item, so writing it alone would switch a
        // still-unchecked AI item on the moment it appeared there.
        function test_checkingClaudeWritesOrderAndHiddenNormalised() {
            const page = openPage({ cfg_itemOrder: ["cpu", "gpu", "memory", "network", "disk"], cfg_hiddenItems: [] });
            mouseClick(checkbox(page, "Claude"));
            compare(page.cfg_itemOrder, ["cpu", "gpu", "memory", "network", "disk", "claude", "codex"]);
            compare(page.cfg_hiddenItems, ["codex"]);
        }

        function test_movingCpuDoesNotSwitchAiOn() {
            const page = openPage({ cfg_itemOrder: ["cpu", "gpu", "memory", "network", "disk"], cfg_hiddenItems: [] });
            mouseClick(button(page, "Move CPU down"));
            compare(page.cfg_itemOrder, ["gpu", "cpu", "memory", "network", "disk", "claude", "codex"]);
            compare(page.cfg_hiddenItems, ["claude", "codex"], "moving never switches an opted-out AI item on");
        }

        // The hint column reads usageStatus from the page; these rows set that
        // property directly, and tst_config's test_pagesFollowTheReports
        // covers the live path.
        function test_hints_data() {
            return [
                { tag: "helperError", status: { helperError: "python3 not found" },
                  claude: "python3 not found", codex: "python3 not found" },
                { tag: "ok", status: { claude: { status: "ok" }, codex: { status: "ok" } },
                  claude: "Signed in", codex: "Signed in" },
                { tag: "signedOut", status: { claude: { status: "signed_out" }, codex: { status: "signed_out" } },
                  claude: "Not signed in: run claude in a terminal", codex: "Not signed in: run codex in a terminal" },
                { tag: "error", status: { claude: { status: "error", message: "timed out" } },
                  claude: "timed out", codex: "Shows while Codex is signed in" },
                { tag: "rateLimited", status: { codex: { status: "rate_limited", message: "try again in a minute" } },
                  claude: "Shows while Claude Code is signed in", codex: "try again in a minute" },
                { tag: "noStatusYet", status: {},
                  claude: "Shows while Claude Code is signed in", codex: "Shows while Codex is signed in" }
            ];
        }
        function test_hints(data) {
            const page = openPage({ usageStatus: data.status });
            compare(page.hints.claude, data.claude);
            compare(page.hints.codex, data.codex);
        }

        // A horizontal panel offers Ring only for each ring item, which adds
        // it to ringsOnly beside the items already there, and Ring and text
        // takes it out again. A vertical panel shows the rings alone whatever
        // the setting, so there the list is off.
        function test_ringOnly_data() {
            return [{ tag: "horizontal", vertical: false }, { tag: "vertical", vertical: true }];
        }
        function test_ringOnly(data) {
            Plasmoid.formFactor = data.vertical ? PlasmaCore.Types.Vertical : PlasmaCore.Types.Horizontal;
            panelPage = Qt.createQmlObject(panelSource, root, Qt.resolvedUrl("../../package/contents/ui/config/ConfigItems.qml"));
            const page = panelPage;
            page.width = root.width;
            page.height = root.height;
            page.cfg_ringsOnly = ["memory"];
            waitForRendering(page);
            const mode = accessible(page, "What CPU shows");
            compare(mode.enabled, !data.vertical);
            if (data.vertical) {
                return;
            }
            for (const [key, expected] of [[Qt.Key_Down, ["memory", "cpu"]], [Qt.Key_Up, ["memory"]]]) {
                mode.forceActiveFocus();
                keyClick(Qt.Key_Space);
                tryCompare(mode.popup, "opened", true);
                keyClick(key);
                keyClick(Qt.Key_Return);
                tryCompare(mode.popup, "visible", false);
                compare(page.cfg_ringsOnly, expected);
            }
        }
    }
}
