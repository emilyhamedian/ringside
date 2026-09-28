// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui"

// Monitor with a stub helper (data/fake-info.sh): its bindings evaluate
// without script errors, the helper's report drives the GPU rings and the
// disk ids, and a sleeping discrete GPU is never subscribed. The GPU and disk
// ids are made up, so the machine's own devices are not read.
TestCase {
    id: testCase
    name: "Monitor"

    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (match, n) => n <= args.length ? String(args[n - 1]) : match);
    }
    function i18nc(context, text, ...args) {
        return substitute(text, args);
    }
    function i18n(text, ...args) {
        return substitute(text, args);
    }

    function dataPath(name) {
        return decodeURIComponent(Qt.resolvedUrl("data/" + name).toString().replace(/^file:\/\//, ""));
    }
    readonly property string stub: dataPath("fake-info.sh")

    function enabledSensors(reader) {
        const flags = [];
        for (let i = 0; i < reader.sensors.count; ++i) {
            flags.push(reader.sensors.objectAt(i).enabled);
        }
        return flags;
    }

    Component {
        id: configComponent
        QtObject {
            property int updateInterval: 1000
            property int historySeconds: 60
            property bool fahrenheit: false
            property bool networkBits: true
            property bool highlightTemperatures: true
            property real warmCelsius: 75
            property real hotCelsius: 90
            property var itemOrder: ["cpu", "gpu", "memory", "network", "disk"]
            property var hiddenItems: ["disk"]
            property var ringsOnly: []
            property int ringSize: 30
            property string cpuTemperatureSensor: ""
            property string outerGpu: ""
            property string innerGpu: ""
            property string networkInterface: ""
            property string diskDevice: ""
            property string diskVolume: ""
            property string diskTemperatureSensor: ""
            property string detectedHardware: ""
            property int layout: 0
            property int usageRefreshMinutes: 5
            property string claudeInnerLimit: ""
            property string codexInnerLimit: ""
            property string knownLimits: ""
            property string usageStatus: ""
        }
    }

    Component {
        id: monitorComponent
        Monitor {}
    }

    property var config: null
    property var monitor: null
    property var monitors: []

    // A monitor with its own config. Monitors go before their configs, which
    // UsageData reads until it is gone.
    function makeMonitor(properties) {
        const m = createTemporaryObject(monitorComponent, testCase,
                                        Object.assign({ config: createTemporaryObject(configComponent, testCase),
                                                        helperPath: stub }, properties));
        monitors.push(m);
        return m;
    }

    function cleanup() {
        for (const m of monitors) {
            m?.destroy();
        }
        monitors = [];
        wait(0);
    }

    function init() {
        failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        config = createTemporaryObject(configComponent, testCase);
        monitor = makeMonitor({ config: config });
        tryVerify(() => monitor.hardware.cpu !== undefined, 10000, "the stub's report arrives");
    }

    function test_reportDrivesTheRings() {
        compare(monitor.gpuOuter.info.id, "gpu97");
        compare(monitor.gpuInner.info.id, "gpu98");
        compare(monitor.cpuIds, [0, 1, 2, 3]);
        compare(monitor.cpuModel, "AMD Ryzen 7 7840HS");
        compare(monitor.networkInterface, "eth9");
        verify(config.detectedHardware.indexOf("gpu97") >= 0);
    }

    function test_aSleepingDiscreteGpuIsNeverSubscribed() {
        const gpu = monitor.gpuOuter;
        tryVerify(() => gpu.pmStatus === "suspended", 10000);
        compare(gpu.phase, "asleep");
        for (let i = 0; i < gpu.sensors.count; ++i) {
            verify(!gpu.sensors.objectAt(i).enabled, gpu.sensors.objectAt(i).sensorId);
        }
        // The integrated GPU has nothing to gate.
        compare(monitor.gpuInner.phase, "live");
    }

    function test_diskIdsFollowTheSettings() {
        compare(monitor.diskIds, ["vdz"]);
        config.diskDevice = "all";
        compare(monitor.diskIds, ["vdz", "vdy"]);
        compare(monitor.member(diskReadersOf(monitor), 5).sensorId, "disk/vdy/total");
        config.diskDevice = "vdy";
        compare(monitor.diskIds, ["vdy"]);
    }

    function test_turningTheOuterRingOffKeepsTheIntegratedGpu() {
        config.outerGpu = "none";
        compare(monitor.gpuOuter.info.id, "gpu98");
        verify(!monitor.gpuInner.present);
        verify(!monitor.readers()[0].onRing);
    }

    // Hiding the GPU item leaves the GPUs alone: there are no readers.
    function test_aHiddenGpuItemReadsNothing() {
        config.hiddenItems = ["disk", "gpu"];
        compare(monitor.readers().length, 0);
        verify(!monitor.gpuOuter.present);
        config.hiddenItems = ["disk"];
        verify(monitor.readers().some(r => r.onRing));
    }

    // A widget of only Claude and Codex, as on a Standalone panel beside an
    // Inline one, reads no sensors and runs no GPU clock.
    function test_aUsageOnlyWidgetSubscribesNothing() {
        const usageOnly = createTemporaryObject(configComponent, testCase, {
            itemOrder: ["claude", "codex", "cpu", "gpu", "memory", "network", "disk"],
            hiddenItems: ["cpu", "gpu", "memory", "network", "disk"]
        });
        const other = makeMonitor({ config: usageOnly, usageHelperPath: dataPath("fake-usage-signed-out.py") });
        tryVerify(() => other.hardware.cpu !== undefined, 10000);
        verify(!other.systemShown);
        compare(other.usage.providers, ["claude", "codex"]);
        compare(other.readers().length, 0);
        const sensors = sensorsOf(other);
        verify(sensors.length > 5);
        verify(sensors.every(s => !s.enabled), sensors.filter(s => s.enabled).map(s => s.sensorId).join());
        tryVerify(() => other.usage.entry("claude") !== null, 10000, "the stub's report arrives");
        verify(!other.usage.claudePresent);
    }

    // Two widgets showing one GPU poll its power state once between them.
    function test_onlyTheLeaderPollsPowerStates() {
        const second = makeMonitor({});
        tryVerify(() => second.hardware.cpu !== undefined, 10000);
        tryVerify(() => monitor.gpuOuter.leading !== second.gpuOuter.leading, 5000, "exactly one leads");
        const follower = monitor.gpuOuter.leading ? second : monitor;
        verify(follower.readers().filter(r => r.kind === "discrete").every(r => !r.leading && r.leader !== null));
        const before = follower.gpuOuter.pmReadAt;
        wait(2500);
        compare(follower.gpuOuter.pmReadAt, before);
    }

    // Two widgets in one plasmashell: one reader per GPU subscribes, and the
    // other widget shows its readings.
    function test_twoWidgetsShareOneSubscriptionPerGpu() {
        const second = makeMonitor({});
        tryVerify(() => second.hardware.cpu !== undefined, 10000);
        const mine = monitor.gpuInner;
        const theirs = second.gpuInner;
        // A reader from the previous test may still lead until its widget is
        // gone; the next tick hands over.
        tryVerify(() => mine.leading !== theirs.leading, 5000, "exactly one leads");
        const leader = mine.leading ? mine : theirs;
        const follower = mine.leading ? theirs : mine;
        tryVerify(() => enabledSensors(leader).every(e => e), 5000);
        verify(enabledSensors(follower).every(e => !e));
        compare(follower.phase, leader.phase);
    }

    // The helper prints "BDF  auto" when runtime_status can't be read: the
    // state is unknown, so the GPU is left asleep.
    function test_anUnreadableStateKeepsTheGpuAsleep() {
        const other = makeMonitor({ helperPath: dataPath("fake-info-unreadable.sh") });
        tryVerify(() => other.hardware.cpu !== undefined, 10000);
        monitor.destroy();
        wait(0);
        const gpu = other.gpuOuter;
        tryVerify(() => gpu.pmControl === "auto", 10000);
        compare(gpu.pmStatus, "");
        other.clockMs += 1000;
        gpu.tick(other.clockMs);
        compare(gpu.phase, "asleep");
        verify(enabledSensors(gpu).every(e => !e));
    }

    function test_memoryPartsArriveFromTheSensors() {
        tryVerify(() => monitor.memoryTotal > 0, 10000);
        tryVerify(() => Number.isFinite(monitor.memoryFree) && Number.isFinite(monitor.memoryCached), 10000);
        // The arithmetic is tested in tst_hardware.qml; this checks the sensors reach it.
    }

    // Every Sensor the monitor holds directly or through its reader sets.
    function sensorsOf(m) {
        const found = [];
        for (const child of m.data) {
            if (child.sensorId !== undefined) {
                found.push(child);
            } else if (child.objectAt !== undefined && child.count !== undefined) {
                for (let i = 0; i < child.count; ++i) {
                    const o = child.objectAt(i);
                    if (o && o.sensorId !== undefined) {
                        found.push(o);
                    }
                }
            }
        }
        return found;
    }

    function diskReadersOf(m) {
        for (const child of m.data) {
            if (child.model !== undefined && String(child.model).indexOf("disk/") >= 0) {
                return child;
            }
        }
        return null;
    }
}
