// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui"

// PanelSizeController against a fake panel window: it folds a panel that
// holds only Ringside to the tab and back, remembers the user's thickness,
// and leaves shared panels and ordinary windows alone.
TestCase {
    id: testCase
    name: "PanelSize"

    property var panel: null
    property var controller: null

    Component {
        id: panelComponent
        QtObject {
            property int thickness: 112
            property bool userConfiguring: false
        }
    }

    // Plasma 6.0's panel window has no edit-mode flag.
    Component {
        id: panelWithoutEditModeComponent
        QtObject {
            property int thickness: 112
        }
    }

    Component {
        id: ordinaryWindowComponent
        QtObject { property int width: 300 }
    }

    Component {
        id: controllerComponent
        PanelSizeController {
            onRememberThickness: thickness => expandedThickness = thickness
        }
    }

    SignalSpy {
        id: remembered
        target: testCase.controller
        signalName: "rememberThickness"
    }

    function init() {
        failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        panel = createTemporaryObject(panelComponent, testCase);
        controller = null;
        remembered.clear();
    }

    function createController(properties) {
        controller = createTemporaryObject(controllerComponent, testCase,
            Object.assign({ panelWindow: panel, dedicated: true }, properties || {}));
        verify(controller !== null);
        wait(0);
    }

    function test_collapseAndRestore() {
        createController();
        tryCompare(controller, "expandedThickness", 112);
        compare(panel.thickness, 112);
        controller.collapsed = true;
        tryCompare(panel, "thickness", 44);
        compare(controller.tabThickness, 44);
        compare(controller.expandedThickness, 112);
        controller.collapsed = false;
        tryCompare(panel, "thickness", 112);
        compare(controller.expandedThickness, 112);
        compare(remembered.count, 1);
    }

    function test_restartWhileCollapsedPreservesExpandedWidth() {
        panel.thickness = 44;
        createController({ collapsed: true, expandedThickness: 160 });
        compare(panel.thickness, 44);
        compare(controller.expandedThickness, 160);
        compare(remembered.count, 0);
        controller.collapsed = false;
        tryCompare(panel, "thickness", 160);
        compare(controller.expandedThickness, 160);
    }

    function test_userExpandedResizePersists() {
        createController();
        tryCompare(controller, "expandedThickness", 112);
        panel.userConfiguring = true;
        panel.thickness = 148;
        tryCompare(controller, "expandedThickness", 148);
        panel.userConfiguring = false;
        wait(0);
        compare(panel.thickness, 148);
        controller.collapsed = true;
        tryCompare(panel, "thickness", 44);
        controller.collapsed = false;
        tryCompare(panel, "thickness", 148);
    }

    function test_configuringDefersAutomaticResize() {
        createController();
        tryCompare(controller, "expandedThickness", 112);
        panel.userConfiguring = true;
        controller.collapsed = true;
        wait(0);
        compare(panel.thickness, 112);
        panel.userConfiguring = false;
        tryCompare(panel, "thickness", 44);
        compare(controller.expandedThickness, 112);
    }

    // Without edit mode to wait for, folding and remembering still work.
    function test_panelWithoutEditMode() {
        panel = createTemporaryObject(panelWithoutEditModeComponent, testCase);
        createController();
        tryCompare(controller, "expandedThickness", 112);
        compare(controller.configuring, false);
        panel.thickness = 130;
        tryCompare(controller, "expandedThickness", 130);
        controller.collapsed = true;
        tryCompare(panel, "thickness", 44);
        compare(controller.expandedThickness, 130);
        controller.collapsed = false;
        tryCompare(panel, "thickness", 130);
    }

    function test_sharedPanelNeverChanged() {
        createController({ dedicated: false, expandedThickness: 160 });
        controller.collapsed = true;
        controller.minimumContentThickness = 200;
        wait(0);
        compare(panel.thickness, 112);
        controller.collapsed = false;
        panel.userConfiguring = true;
        panel.userConfiguring = false;
        wait(0);
        compare(panel.thickness, 112);
        compare(remembered.count, 0);
    }

    function test_addingSecondWidgetRestoresWidth() {
        createController();
        tryCompare(controller, "expandedThickness", 112);
        controller.collapsed = true;
        tryCompare(panel, "thickness", 44);
        controller.dedicated = false;
        tryCompare(panel, "thickness", 112);
        panel.thickness = 136;
        controller.collapsed = false;
        controller.collapsed = true;
        wait(0);
        compare(panel.thickness, 136);
        compare(controller.expandedThickness, 112);
    }

    function test_ordinaryWindowUnaffected() {
        const ordinary = createTemporaryObject(ordinaryWindowComponent, testCase);
        createController({ panelWindow: ordinary });
        controller.collapsed = true;
        controller.minimumContentThickness = 200;
        wait(0);
        compare(ordinary.width, 300);
        compare(controller.expandedThickness, 0);
        compare(remembered.count, 0);
    }

    function test_moveToSharedPanel_data() {
        return [
            { tag: "window-first", windowFirst: true },
            { tag: "dedicated-first", windowFirst: false }
        ];
    }

    function test_moveToSharedPanel(data) {
        createController();
        tryCompare(controller, "expandedThickness", 112);
        controller.collapsed = true;
        tryCompare(panel, "thickness", 44);
        const shared = createTemporaryObject(panelComponent, testCase, { thickness: 60 });
        if (data.windowFirst) {
            controller.panelWindow = shared;
            controller.dedicated = false;
        } else {
            controller.dedicated = false;
            controller.panelWindow = shared;
        }
        wait(0);
        compare(panel.thickness, 112);
        compare(shared.thickness, 60);
        compare(controller.expandedThickness, 112);
        compare(controller.controlledWindow, null);
    }

    function test_growsForMinimumContent() {
        createController({ minimumContentThickness: 120.25 });
        tryCompare(panel, "thickness", 129);
        compare(controller.expandedThickness, 129);
        controller.collapsed = true;
        tryCompare(panel, "thickness", 44);
        controller.minimumContentThickness = 150;
        tryCompare(controller, "expandedThickness", 158);
        compare(panel.thickness, 44);
        controller.collapsed = false;
        tryCompare(panel, "thickness", 158);
    }

    // The widget passes in the theme's measured margins as chrome. The panel
    // is kept at least content plus chrome thick, so a wider chrome needs a
    // thicker panel.
    function test_chromeSetsReservedThickness() {
        createController({ minimumContentThickness: 100, chrome: 16 });
        tryCompare(panel, "thickness", 116);
        compare(controller.expandedThickness, 116);
        controller.chrome = 8;
        wait(0);
        compare(panel.thickness, 116);
        controller.minimumContentThickness = 110;
        wait(0);
        compare(panel.thickness, 118);
        compare(controller.expandedThickness, 118);
        controller.collapsed = true;
        tryCompare(panel, "thickness", 44);
        controller.chrome = 24;
        tryCompare(controller, "expandedThickness", 134);
        compare(panel.thickness, 44);
        controller.collapsed = false;
        tryCompare(panel, "thickness", 134);
    }

    function test_userResizeRemembered() {
        createController({ expandedThickness: 160 });
        tryCompare(panel, "thickness", 160);
        panel.thickness = 172;
        tryCompare(controller, "expandedThickness", 172);
        wait(0);
        compare(panel.thickness, 172);
        controller.collapsed = true;
        tryCompare(panel, "thickness", 44);
        controller.collapsed = false;
        tryCompare(panel, "thickness", 172);
    }

    function test_editCollapsedPanelRemembersFullWidth() {
        createController({ collapsed: true });
        tryCompare(panel, "thickness", 44);
        compare(controller.expandedThickness, 112);
        panel.userConfiguring = true;
        tryCompare(panel, "thickness", 112);
        panel.thickness = 150;
        tryCompare(controller, "expandedThickness", 150);
        panel.userConfiguring = false;
        tryCompare(panel, "thickness", 44);
        compare(controller.expandedThickness, 150);
        controller.collapsed = false;
        tryCompare(panel, "thickness", 150);
    }

    function test_savedWidthChangeResizesPanel() {
        createController({ expandedThickness: 160 });
        tryCompare(panel, "thickness", 160);
        controller.expandedThickness = 180;
        tryCompare(panel, "thickness", 180);
        compare(controller.expandedThickness, 180);
        compare(remembered.count, 0);
    }

    function test_destroyRestoresOwnedPanel_data() {
        return [
            { tag: "expanded", collapsed: false },
            { tag: "collapsed", collapsed: true }
        ];
    }

    function test_destroyRestoresOwnedPanel(data) {
        createController({ collapsed: data.collapsed });
        tryCompare(panel, "thickness", data.collapsed ? 44 : 112);
        compare(controller.expandedThickness, 112);
        const before = remembered.count;
        controller.destroy();
        wait(0);
        compare(panel.thickness, 112);
        compare(remembered.count, before);
    }
}
