// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
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
        id: plain
        ConfigItems {
            width: root.width
            height: root.height
            cfg_itemOrder: ["cpu", "gpu", "memory", "network", "disk"]
        }
    }

    TestCase {
        id: testCase
        name: "ConfigItems"

        // ConfigItems.qml with fakeplasmoid/ for org.kde.plasma.plasmoid,
        // and the page made from it, if any.
        property string panelSource: ""
        property var panelPage: null

        function initTestCase() {
            const text = root.read("../../package/contents/ui/config/ConfigItems.qml");
            const from = /^import org\.kde\.plasma\.plasmoid$/m;
            verify(from.test(text), "ConfigItems.qml no longer matches " + from);
            panelSource = text.replace(from, 'import "' + Qt.resolvedUrl("fakeplasmoid") + '"');
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
            return root.find(page, i => i.text === label && i.display !== undefined && i.icon !== undefined);
        }
        function openPage(properties) {
            const p = createTemporaryObject(plain, root, properties);
            verify(p);
            waitForRendering(p);
            return p;
        }
        function checkbox(page, name) {
            return root.find(page, i => i.text === name && i.checkState !== undefined);
        }
        function accessible(page, name) {
            return root.find(page, i => i.Accessible && i.Accessible.name === name);
        }

        // The move buttons show icons alone, so their text, which a screen
        // reader announces and the tooltip shows, says what each does. The
        // first row can't go up and the last can't go down.
        function test_keyboard_up_to_top() {
            const page = openPage();
            verify(!button(page, "Move CPU up").enabled);
            verify(button(page, "Move CPU down").enabled);
            // Claude and OpenAI trail the list by default, so OpenAI is the
            // last row.
            verify(button(page, "Move OpenAI up").enabled);
            verify(!button(page, "Move OpenAI down").enabled);
            const up = button(page, "Move GPU up");
            const down = button(page, "Move GPU down");
            compare(up.display, QQC2.AbstractButton.IconOnly);
            compare(up.QQC2.ToolTip.text, "Move GPU up");
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
            const page = openPage();
            const down = button(page, "Move Claude down");
            const up = button(page, "Move Claude up");
            down.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(page.cfg_itemOrder, ["cpu", "gpu", "memory", "network", "disk", "codex", "claude"]);
            tryVerify(() => !down.enabled);
            verify(up.activeFocus, "focus moved to Move Claude up");
        }

        function test_mouse() {
            const page = openPage();
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
            root.pick(testCase, mode, 1);
            compare(page.cfg_ringsOnly, ["memory", "cpu"]);
            root.pick(testCase, mode, 0);
            compare(page.cfg_ringsOnly, ["memory"]);
        }

        // Panel space names the panel's ends as the panel runs, shows the
        // stored choice, and stores each one picked.
        function test_panelSpace_data() {
            return [{ tag: "horizontal", vertical: false, mirrored: false, ends: ["on the left", "on the right"] },
                    { tag: "right-to-left", vertical: false, mirrored: true, ends: ["on the right", "on the left"] },
                    { tag: "vertical", vertical: true, mirrored: false, ends: ["at the top", "at the bottom"] }];
        }
        function test_panelSpace(data) {
            Plasmoid.formFactor = data.vertical ? PlasmaCore.Types.Vertical : PlasmaCore.Types.Horizontal;
            panelPage = Qt.createQmlObject(panelSource, root, Qt.resolvedUrl("../../package/contents/ui/config/ConfigItems.qml"));
            const page = panelPage;
            page.width = root.width;
            page.height = root.height;
            page.LayoutMirroring.enabled = data.mirrored;
            page.cfg_fillPanel = "center";
            waitForRendering(page);
            const box = accessible(page, "Panel space");
            verify(box && box.visible);
            compare(box.currentIndex, 2);
            compare(box.model[1], "Fill free space, items " + data.ends[0]);
            compare(box.model[3], "Fill free space, items " + data.ends[1]);
            for (const [row, place] of [[3, "end"], [1, "start"], [0, ""]]) {
                root.pick(testCase, box, row);
                compare(page.cfg_fillPanel, place);
            }
        }
    }
}
