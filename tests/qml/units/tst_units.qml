// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../../package/contents/ui"
import "../../../package/contents/ui/code/format.js" as Format
import ".."

// Monitor learns KDE's data units from KDE's own formatter, and the panel
// and the popups show them. Each test function is one of the three choices
// under Region & Language → Data and storage units, so scripts/test.sh runs
// each alone, in English, under a kdeglobals that makes that choice. It
// sits outside tests/qml's suites, which run under the machine's own
// settings.
TestCase {
    id: testCase
    name: "Units"

    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (match, n) => n <= args.length ? String(args[n - 1]) : match);
    }
    function i18nc(context, text, ...args) {
        return substitute(text, args);
    }
    function i18n(text, ...args) {
        return substitute(text, args);
    }

    // Outlives each test's monitor, which reads it until it is gone.
    QtObject {
        id: settings
        property int updateInterval: 1000
        property string graphSpan: "minute"
        property bool keepGraphHistory: false
        property bool fahrenheit: false
        property bool networkBits: false
        property bool highlightTemperatures: true
        property real warmCelsius: 75
        property real hotCelsius: 90
        property var itemOrder: ["cpu", "gpu", "memory", "network", "disk"]
        property var hiddenItems: []
        property var ringsOnly: []
        property string cpuTemperatureSensor: ""
        property string outerGpu: ""
        property string innerGpu: ""
        property string networkInterface: ""
        property string diskDevice: ""
        property string diskVolume: ""
        property string diskTemperatureSensor: ""
        property string detectedHardware: ""
        property int usageRefreshMinutes: 5
        property string claudeInnerLimit: ""
        property string codexInnerLimit: ""
        property string knownLimits: ""
        property string usageStatus: ""
    }

    Component {
        id: wordsComponent
        Words {}
    }

    // The widget as main.qml lays it out: a Monitor, then the panel's
    // strip, here showing a fake's fixed readings.
    Component {
        id: widgetComponent
        Item {
            id: widget
            readonly property alias monitor: real
            readonly property alias strip: strip
            required property QtObject config
            required property string helperPath
            Monitor {
                id: real
                config: widget.config
                helperPath: widget.helperPath
            }
            FakeMonitor {
                id: shown
            }
            Strip {
                id: strip
                monitor: shown
                items: ["memory", "disk"]
                vertical: false
                thickness: 38
                ringsOnly: []
            }
        }
    }

    function findAll(item, test) {
        const found = test(item) ? [item] : [];
        for (const child of item.children) {
            found.push(...findAll(child, test));
        }
        return found;
    }

    // What a monitor started under the running kdeglobals learns, and what
    // the panel and the popups then show.
    function check(base, labels, shows) {
        failOnWarning(/TypeError|ReferenceError|Binding loop|sizes stay in/);
        const stub = decodeURIComponent(Qt.resolvedUrl("../data/fake-info.sh").toString().replace(/^file:\/\//, ""));
        const widget = createTemporaryObject(widgetComponent, testCase, { config: settings, helperPath: stub });
        const monitor = widget.monitor;
        tryVerify(() => monitor.hardware.cpu !== undefined, 10000, "the stub's report arrives");
        compare(monitor.byteUnits, { base: base, labels: labels });
        // The panel's cells keep their room from the start, so they are
        // made with these units, not given them later. The fake has
        // 31.9 GiB installed.
        const readout = findAll(widget.strip, i => i.widest !== undefined && i.rooms !== undefined)[0];
        compare(readout.widest.second, [shows.installed], "the memory cell's room");
        compare(Format.panelByteUnits(), labels, "the panel keeps room for these");

        const gib = 1024 ** 3;
        monitor.panel = Object.assign({}, monitor.panel, { memoryUsed: 9.6 * gib, memoryPercent: 30 });
        const words = createTemporaryObject(wordsComponent, testCase, { monitor: monitor });
        compare(words.readout("memory").second, shows.memory, "the panel's memory");
        compare(words.describe("memory"), shows.memory + " in use, 30%", "the memory in words");
        const used = Format.bytesOf(3.2 * gib, 16 * gib);
        compare(used.value + " / " + used.total + " " + used.unit, shows.usedOfTotal, "used of a total, as for swap and VRAM");
        const rate = Format.rate(5.8 * 1024 ** 2, false);
        compare(rate.value + " " + rate.unit, shows.rate, "a disk's rate in its popup");
        const panelRate = Format.panelRate(5.8 * 1024 ** 2, false);
        compare(panelRate.value + " " + panelRate.unit, shows.panelRate, "a disk's rate in the panel");
    }

    function test_iec() {
        check(1024, ["B", "KiB", "MiB", "GiB", "TiB", "PiB"],
              { memory: "9.6 GiB", installed: "31.9 GiB", usedOfTotal: "3.2 / 16 GiB", rate: "5.8 MiB/s", panelRate: "5.80 MiB/s" });
    }

    function test_jedec() {
        check(1024, ["B", "KB", "MB", "GB", "TB", "PB"],
              { memory: "9.6 GB", installed: "31.9 GB", usedOfTotal: "3.2 / 16 GB", rate: "5.8 MB/s", panelRate: "5.80 MB/s" });
    }

    function test_metric() {
        check(1000, ["B", "kB", "MB", "GB", "TB", "PB"],
              { memory: "10.3 GB", installed: "34.3 GB", usedOfTotal: "3.4 / 17.2 GB", rate: "6.1 MB/s", panelRate: "6.08 MB/s" });
    }
}
