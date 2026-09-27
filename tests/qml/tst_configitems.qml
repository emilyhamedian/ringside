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
                cfg_ringSize: 32
            }
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

        function test_edges_and_tooltips() {
            const page = make().page;
            verify(!button(page, "Move CPU up").enabled);
            verify(button(page, "Move CPU down").enabled);
            verify(button(page, "Move Disk up").enabled);
            verify(!button(page, "Move Disk down").enabled);
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
            compare(page.cfg_itemOrder, ["gpu", "cpu", "memory", "network", "disk"]);
            tryVerify(() => !up.enabled);
            verify(down.activeFocus, "focus moved to Move GPU down");
            verify(down.visualFocus, "keyboard focus stays visible");
            keyClick(Qt.Key_Space);
            compare(page.cfg_itemOrder, ["cpu", "gpu", "memory", "network", "disk"]);
            verify(down.activeFocus, "focus stays on the pressed button");
            tryVerify(() => up.enabled);
            keyClick(Qt.Key_Space);
            compare(page.cfg_itemOrder, ["cpu", "memory", "gpu", "network", "disk"]);
            verify(down.activeFocus);
        }

        function test_keyboard_down_to_bottom() {
            const page = make().page;
            const down = button(page, "Move Network down");
            const up = button(page, "Move Network up");
            down.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(page.cfg_itemOrder, ["cpu", "gpu", "memory", "disk", "network"]);
            tryVerify(() => !down.enabled);
            verify(up.activeFocus, "focus moved to Move Network up");
        }

        function test_mouse() {
            const page = make().page;
            const up = button(page, "Move Memory up");
            const pt = up.mapToItem(null, up.width / 2, up.height / 2);
            mouseClick(up);
            compare(page.cfg_itemOrder, ["cpu", "memory", "gpu", "network", "disk"]);
            mouseClick(button(page, "Move Memory up"));
            compare(page.cfg_itemOrder, ["memory", "cpu", "gpu", "network", "disk"]);
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
    }
}
