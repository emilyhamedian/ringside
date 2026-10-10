// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui/config"

// Panel Items can be reordered without a mouse: move buttons with names a
// screen reader announces, disabled at the ends, and focus that follows the
// row. Loads the real page; outside Plasma its hardware hints are empty.

Item {
    id: root
    width: 660
    height: 560

    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }
    function i18n(text, ...args) { return substitute(text, args); }
    function i18nc(context, text, ...args) { return substitute(text, args); }
    function i18np(s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }
    function i18ncp(c, s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }


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

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }
        when: windowShown

        function find(item, pred) {
            if (pred(item)) return item;
            for (let i = 0; i < item.children.length; ++i) {
                const r = find(item.children[i], pred);
                if (r) return r;
            }
            return null;
        }
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
            // Claude and OpenAI trail the list by default, so OpenAI is now
            // the last row rather than Disk.
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
            verify(up.visualFocus);
            keyClick(Qt.Key_Space);
            compare(page.cfg_itemOrder, ["gpu", "cpu", "memory", "network", "disk", "claude", "codex"]);
            tryVerify(() => !up.enabled);
            verify(down.activeFocus, "focus moved to Move GPU down");
            verify(down.visualFocus, "keyboard focus stays visible");
            keyClick(Qt.Key_Space);
            compare(page.cfg_itemOrder, ["cpu", "gpu", "memory", "network", "disk", "claude", "codex"]);
            verify(down.activeFocus, "focus stays on the pressed button");
            tryVerify(() => up.enabled);
            keyClick(Qt.Key_Space);
            compare(page.cfg_itemOrder, ["cpu", "memory", "gpu", "network", "disk", "claude", "codex"]);
            verify(down.activeFocus);
        }

        // Claude and Codex trail every stored order, so they are the pair
        // that now sits at the bottom of the list.
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
            const pt = up.mapToItem(null, Qt.point(up.width / 2, up.height / 2));
            mouseClick(up);
            compare(page.cfg_itemOrder, ["cpu", "memory", "gpu", "network", "disk", "claude", "codex"]);
            mouseClick(button(page, "Move Memory up"));
            compare(page.cfg_itemOrder, ["memory", "cpu", "gpu", "network", "disk", "claude", "codex"]);
            verify(!up.enabled);
        }

        function test_tab_chain() {
            const page = make().page;
            const start = find(page, i => i.text === "CPU" && i.checkState !== undefined);
            start.forceActiveFocus(Qt.TabFocusReason);
            const seen = [];
            let item = start;
            for (let n = 0; n < 30; ++n) {
                const name = item.text || (item.Accessible ? item.Accessible.name : "") || String(item);
                seen.push(name + (item.enabled ? "" : " (disabled)"));
                keyClick(Qt.Key_Tab);
                item = root.Window.activeFocusItem;
                if (item === start) break;
            }
            verify(seen.includes("Move GPU up"));
            verify(!seen.includes("Move CPU up (disabled)"));
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

        // Rings follow the panel's thickness, so the page offers no ring size,
        // and with one layout there is none to pick.
        function test_noRingSizeSetting() {
            const page = openPage({ cfg_itemOrder: ["cpu", "gpu", "memory", "network", "disk"] });
            compare(page.cfg_ringSize, undefined);
            compare(accessible(page, "Ring size"), null);
            compare(find(page, i => i.value !== undefined && i.stepSize !== undefined), null, "no slider or spin box");
            compare(find(page, i => typeof i.text === "string" && i.text.indexOf("Ring size") >= 0), null);
            compare(page.cfg_layout, undefined);
            compare(accessible(page, "Layout"), null);
            compare(accessible(page, "Fold"), null);
            verify(accessible(page, "What CPU shows").enabled, "a horizontal panel offers Ring only");
        }
    }
}
