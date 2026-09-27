pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import "../../package/contents/ui/config"

// The three settings pages load with their cfg_ properties set and without a
// script error. Outside Plasma there is no Plasmoid, so the pages see no
// hardware report. The Sensors page lists this machine's ksystemstats sensors
// (without subscribing to any), so for it this is a smoke test that needs a
// running ksystemstats, as tst_monitor does.

Item {
    id: root
    width: 660
    height: 560

    // A bare qml runtime has no KI18n; the pages find these on the root.
    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }
    function i18n(text, ...args) { return substitute(text, args); }
    function i18nc(context, text, ...args) { return substitute(text, args); }
    function i18np(s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }
    function i18ncp(c, s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }

    Component {
        id: general
        ConfigGeneral {
            width: root.width
            height: root.height
            cfg_updateInterval: 1000
            cfg_historySeconds: 60
            cfg_networkBits: true
            cfg_highlightTemperatures: true
            cfg_warmCelsius: 75
            cfg_hotCelsius: 90
        }
    }

    Component {
        id: items
        ConfigItems {
            width: root.width
            height: root.height
            cfg_itemOrder: ["cpu", "gpu", "memory", "network", "disk"]
            cfg_hiddenItems: ["disk"]
            cfg_ringSize: 30
        }
    }

    Component {
        id: sensors
        ConfigSensors {
            width: root.width
            height: root.height
        }
    }

    TestCase {
        name: "Config"
        when: windowShown

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }

        function make(component, properties) {
            const page = createTemporaryObject(component, root, properties);
            verify(page);
            waitForRendering(page);
            return page;
        }

        function test_general_data() {
            return [
                { tag: "celsius", fahrenheit: false },
                { tag: "fahrenheit", fahrenheit: true }
            ];
        }
        function test_general(data) {
            make(general, { cfg_fahrenheit: data.fahrenheit });
        }

        function test_items_data() {
            return [
                { tag: "defaults", ringsOnly: [] },
                { tag: "ringsOnly", ringsOnly: ["cpu", "memory"] }
            ];
        }
        function test_items(data) {
            make(items, { cfg_ringsOnly: data.ringsOnly });
        }

        // Stored ids that the sensor tree doesn't offer stay listed as they are.
        function test_sensors_data() {
            return [
                { tag: "automatic", stored: {} },
                { tag: "stored", stored: { cfg_cpuTemperatureSensor: "lmsensors/k10temp-pci-00c3/temp1",
                                           cfg_outerGpu: "gpu9", cfg_innerGpu: "none",
                                           cfg_networkInterface: "wlp9s0", cfg_diskDevice: "sdz",
                                           cfg_diskVolume: "all", cfg_diskTemperatureSensor: "none" } }
            ];
        }
        function test_sensors(data) {
            const page = make(sensors, data.stored);
            // collect() runs once ksystemstats answers.
            tryVerify(() => page.found.interfaces.length + page.found.devices.length + page.found.volumes.length > 0,
                      10000, "ksystemstats listed no network or disk sensors");
            waitForRendering(page);
        }
    }
}
