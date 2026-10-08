// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.LocalStorage as Sql
import QtTest
import org.kde.plasma.plasma5support as P5Support
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
            property string graphSpan: "minute"
            property bool keepGraphHistory: false
            property bool fahrenheit: false
            property bool networkBits: true
            property bool highlightTemperatures: true
            property real warmCelsius: 75
            property real hotCelsius: 90
            property var itemOrder: ["cpu", "gpu", "memory", "network", "disk"]
            property var hiddenItems: ["disk"]
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
    }

    Component {
        id: monitorComponent
        Monitor {}
    }

    Component {
        id: sourceHolderComponent
        P5Support.DataSource {
            engine: "executable"
            property int deliveries: 0
            onNewData: deliveries++
        }
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

    // The graphs take a reading every second, or at the update interval
    // when that is shorter, so a minute's graph has 60 points at any slower
    // interval. The Sensors let one reading through per sample.
    function test_graphsSampleEverySecond_data() {
        return [500, 1000, 2500, 5000, 10000].map(ms => ({ tag: ms + " ms", interval: ms,
                                                          sample: Math.min(ms, 1000), length: ms < 1000 ? 120 : 60 }));
    }
    function test_graphsSampleEverySecond(data) {
        config.updateInterval = data.interval;
        compare(monitor.sampleInterval, data.sample);
        compare(monitor.historyLength, data.length);
        const timer = name => Array.from(monitor.data).find(c => c.objectName === name);
        compare(timer("sample").interval, data.sample, "the graphs' timer");
        verify(timer("sample").running);
        compare(timer("latch").interval, data.interval, "the panel's timer");
        verify(timer("latch").running);
        const sensors = sensorsOf(monitor);
        verify(sensors.length > 5);
        verify(sensors.every(s => s.updateRateLimit === data.sample - 250),
               sensors.map(s => s.updateRateLimit).join());
        verify(monitor.readers().length > 0);
        verify(monitor.readers().every(r => r.rateLimit === data.sample - 250));
    }

    // At a 4 s update interval the panel keeps its first CPU reading for
    // the 4 s while the graph gains one every second; then it takes the
    // latest. Timed by the panel's timer rather than by the reading
    // changing, which a quiet machine's CPU needn't do in 4 s.
    function test_panelKeepsToTheIntervalWhileGraphsSample() {
        const started = Date.now();
        const slow = makeMonitor({ config: createTemporaryObject(configComponent, testCase, { updateInterval: 4000 }) });
        const latch = Array.from(slow.data).find(c => c.objectName === "latch");
        // What the panel and the live reading are as the panel's timer
        // fires, after Monitor's own handler has run.
        const taken = [];
        const record = () => taken.push([slow.panel.cpuUsage, slow.cpuUsage, Date.now() - started]);
        latch.triggered.connect(record);
        try {
            tryVerify(() => Number.isFinite(slow.panel.cpuUsage), 3000, "the first reading reaches the panel at a sample");
            const shown = slow.panel.cpuUsage;
            const samples = slow.cpuHistory.length;
            while (Date.now() - started < 3600) {
                wait(100);
                compare(slow.panel.cpuUsage, shown, "held at " + (Date.now() - started) + " ms");
            }
            compare(taken.length, 0, "no panel update before the interval");
            verify(slow.cpuHistory.length >= samples + 2, "the graph gained " + (slow.cpuHistory.length - samples));
            // A held value no reading could be, so the update shows even on
            // a machine whose CPU reading hasn't moved.
            slow.panel = Object.assign({}, slow.panel, { cpuUsage: -1 });
            tryVerify(() => taken.length > 0, 2000, "the panel's update at the interval");
            verify(taken[0][1] >= 0, "a live reading: " + taken[0][1]);
            compare(taken[0][0], taken[0][1], "the panel takes the latest reading at " + taken[0][2] + " ms");
        } finally {
            latch.triggered.disconnect(record);
        }
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

    // A widget of only Claude and Codex, beside another with the system
    // items, reads no sensors and runs no GPU clock.
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

    function powerStatesOf(m) {
        return Array.from(m.data).find(child => child.pendingSource !== undefined);
    }

    // The default route is re-read only while the network popup shows it;
    // the disk popup, which once shared that popup, has no use for it.
    function test_theRouteIsReadForTheNetworkPopupOnly() {
        const route = Array.from(monitor.data).find(child => child.engine === "executable" && child.interval === 3000);
        verify(route, "the monitor owns the route's DataSource");
        for (const open of ["", "cpu", "memory", "disk"]) {
            monitor.openPopup = open;
            compare(route.connectedSources.length, 0, "with " + (open || "nothing") + " open");
        }
        monitor.openPopup = "network";
        compare(route.connectedSources.length, 1);
        verify(route.connectedSources[0].endsWith(" route"), route.connectedSources[0]);
        tryCompare(monitor, "routeInterface", "eth9", 10000, "the stub's route arrives");
        monitor.openPopup = "";
        compare(route.connectedSources.length, 0);
    }

    function stopTimers(m) {
        for (const child of m.data) {
            if (child.running !== undefined && child.repeat !== undefined) {
                child.running = false;
            }
        }
    }

    function settledPowerStates(m) {
        stopTimers(m);
        const power = powerStatesOf(m);
        verify(power !== undefined, "the monitor owns a power DataSource");
        tryVerify(() => m.gpuOuter.pmReadAt >= 0, 10000, "the initial PM reading arrives");
        tryCompare(power, "pendingSource", "", 10000);
        return power;
    }

    // QQmlPropertyMap retains cleared keys: checking the actual maps catches
    // source names accumulating even after connectedSources becomes empty.
    function test_repeatedPowerPollsKeepTheDataSourceMapsBounded() {
        const power = settledPowerStates(monitor);
        const dataKeys = Object.keys(power.data).sort();
        const modelKeys = Object.keys(power.models).sort();
        verify(dataKeys.some(key => key.indexOf(" pm ") >= 0), "a PM source reached the data map");
        verify(modelKeys.some(key => key.indexOf(" pm ") >= 0), "a PM source reached the models map");
        for (let i = 1; i <= 64; ++i) {
            const started = i * 2000;
            monitor.clockMs = started;
            monitor.pollPower();
            tryCompare(monitor.gpuOuter, "pmReadAt", started, 10000);
            tryCompare(power, "pendingSource", "", 10000);
            compare(power.connectedSources.length, 0);
            compare(Object.keys(power.data).sort(), dataKeys, "data keys after poll " + i);
            compare(Object.keys(power.models).sort(), modelKeys, "model keys after poll " + i);
        }
    }

    function test_aSlowPowerPollKeepsItsStartTimeAndSkipsOverlaps() {
        monitor.destroy();
        wait(0);
        const slow = makeMonitor({ helperPath: dataPath("fake-info-slow-pm.sh") });
        tryVerify(() => slow.hardware.cpu !== undefined, 10000);
        const power = settledPowerStates(slow);
        const before = slow.gpuOuter.pmReadAt;
        slow.clockMs = 5000;
        slow.pollPower();
        tryVerify(() => power.pendingSource !== "", 1000);
        const source = power.pendingSource;
        verify(source.length > 0);
        compare(power.requestedAt, 5000);
        wait(50);
        compare(slow.gpuOuter.pmReadAt, before, "the delayed helper has not answered");
        slow.clockMs = 9000;
        slow.pollPower();
        compare(power.pendingSource, source);
        compare(power.requestedAt, 5000);
        tryCompare(slow.gpuOuter, "pmReadAt", 5000, 10000);
        tryCompare(power, "pendingSource", "", 10000);
        compare(slow.clockMs, 9000);
        slow.clockMs = 10000;
        slow.pollPower();
        tryCompare(slow.gpuOuter, "pmReadAt", 10000, 10000);
        tryCompare(power, "pendingSource", "", 10000);
    }

    // Holding the first leader's source keeps its cached result in the real
    // executable engine while a new leader connects to the same command.
    function test_aCachedPreviousLeaderCannotStampAFreshPowerReading() {
        monitor.destroy();
        wait(0);
        const path = dataPath("fake-info-slow-pm.sh");
        const first = makeMonitor({ helperPath: path });
        tryVerify(() => first.hardware.cpu !== undefined, 10000);
        const firstPower = settledPowerStates(first);
        const holder = createTemporaryObject(sourceHolderComponent, testCase);
        first.clockMs = 6000;
        first.pollPower();
        tryVerify(() => firstPower.pendingSource !== "", 1000);
        const source = firstPower.pendingSource;
        verify(source.length > 0);
        holder.connectSource(source);
        tryCompare(first.gpuOuter, "pmReadAt", 6000, 10000);
        tryVerify(() => holder.deliveries > 0, 10000);
        compare(firstPower.connectedSources.length, 0);
        compare(firstPower.pendingSource, source, "the holder has kept the source alive");
        first.destroy();
        wait(0);

        const next = makeMonitor({ helperPath: path });
        tryVerify(() => next.hardware.cpu !== undefined, 10000);
        stopTimers(next);
        const power = powerStatesOf(next);
        verify(power !== undefined);
        tryCompare(power, "pendingSource", source, 10000);
        compare(next.gpuOuter.pmReadAt, -1, "the old leader's cached data is not a fresh poll");
        compare(power.connectedSources.length, 0);
        compare(power.freshRequest, false);
        const cachedRequestAt = power.requestedAt;
        next.clockMs = 10000;
        next.pollPower();
        compare(power.requestedAt, cachedRequestAt);
        compare(power.pendingSource, source);
        compare(next.gpuOuter.pmReadAt, -1);

        holder.disconnectSource(source);
        tryCompare(power, "pendingSource", "", 10000);
        next.clockMs = 12000;
        next.pollPower();
        tryCompare(next.gpuOuter, "pmReadAt", 12000, 10000);
        tryCompare(power, "pendingSource", "", 10000);
        compare(next.gpuOuter.pmStatus, "suspended");
    }

    // sourceAdded is queued. An older process started in this event-loop
    // turn must not make a later connection claim its result as fresh.
    function test_anUnfinishedExternalPowerRequestCannotBeStampedFresh() {
        monitor.destroy();
        wait(0);
        const slow = makeMonitor({ helperPath: dataPath("fake-info-slow-pm.sh") });
        tryVerify(() => slow.hardware.cpu !== undefined, 10000);
        const power = settledPowerStates(slow);
        const source = Object.keys(power.data).find(key => key.indexOf(" pm ") >= 0);
        verify(source !== undefined);
        const before = slow.gpuOuter.pmReadAt;
        const holder = createTemporaryObject(sourceHolderComponent, testCase);
        // Qt's shared callLater tick is already posted before sourceAdded.
        Qt.callLater(() => {});
        holder.connectSource(source);
        slow.clockMs = 9000;
        slow.pollPower();
        tryCompare(power, "pendingSource", source, 1000);
        compare(power.requestedAt, 9000);
        compare(power.freshRequest, false);
        compare(holder.deliveries, 0, "the older helper is still running");
        tryVerify(() => holder.deliveries > 0, 10000);
        compare(slow.gpuOuter.pmReadAt, before);
        compare(power.connectedSources.length, 0);
        slow.clockMs = 14000;
        slow.pollPower();
        wait(0);
        compare(power.requestedAt, 9000);
        compare(power.pendingSource, source);
        compare(slow.gpuOuter.pmReadAt, before);
        holder.disconnectSource(source);
        tryCompare(power, "pendingSource", "", 10000);
        slow.clockMs = 16000;
        slow.pollPower();
        tryCompare(slow.gpuOuter, "pmReadAt", 16000, 10000);
        tryCompare(power, "pendingSource", "", 10000);
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

    function temperatureHistories(m) {
        return { cpu: m.cpuTemperatureHistory, disk: m.diskTemperatureHistory,
                 outer: m.gpuOuter.temperatureHistory, inner: m.gpuInner.temperatureHistory };
    }

    // The temperatures are sampled with the other histories, every
    // sampleInterval and as many as a minute holds, so a graph is full when
    // its popup opens. With no reading, here from made-up sensor ids and
    // GPUs, each sample is NaN, a gap, never 0; a new interval starts the
    // minute afresh.
    function test_temperatureHistoriesSample() {
        stopTimers(monitor);
        config.cpuTemperatureSensor = "cpu/cpu97/temperature";
        config.diskTemperatureSensor = "disk/vdz/temperature";
        config.updateInterval = 500;
        compare(monitor.minuteLength, 120);
        compare(monitor.historyLength, 120);
        for (let i = 0; i < 122; ++i) {
            monitor.sample();
        }
        compare(monitor.cpuHistory.length, 120);
        for (const [name, history] of Object.entries(temperatureHistories(monitor))) {
            compare(history.length, 120, name);
            verify(history.every(t => Number.isNaN(t)), name + ": " + history.join());
        }
        config.updateInterval = 1000;
        for (const [name, history] of Object.entries(temperatureHistories(monitor))) {
            compare(history.length, 0, name + " starts afresh");
        }
        monitor.sample();
        compare(monitor.historyLength, 60);
        for (const [name, history] of Object.entries(temperatureHistories(monitor))) {
            compare(history.length, 1, name);
        }
    }

    // A reading goes in as it is, the CPU's and the disk's each into its
    // own history. The CPU count stands in for a temperature sensor:
    // ksystemstats always has it, and it is a number from 1 as a
    // temperature is.
    function test_temperatureReadingsAreRecorded_data() {
        return [{ tag: "cpu", read: "cpuTemperatureSensor", missing: "diskTemperatureSensor",
                  reading: "cpuTemperature", history: "cpuTemperatureHistory", gap: "diskTemperatureHistory" },
                { tag: "disk", read: "diskTemperatureSensor", missing: "cpuTemperatureSensor",
                  reading: "diskTemperature", history: "diskTemperatureHistory", gap: "cpuTemperatureHistory" }];
    }
    function test_temperatureReadingsAreRecorded(data) {
        stopTimers(monitor);
        config[data.missing] = data.tag === "cpu" ? "disk/vdz/temperature" : "cpu/cpu97/temperature";
        config[data.read] = "cpu/all/coreCount";
        tryVerify(() => Number.isFinite(monitor[data.reading]), 10000, "the stand-in reading arrives");
        monitor.sample();
        monitor.sample();
        compare(monitor[data.history].slice(-2), [monitor[data.reading], monitor[data.reading]]);
        verify(monitor[data.gap].every(t => Number.isNaN(t)), monitor[data.gap].join());
    }

    // Another sensor starts its graph afresh rather than going on from the
    // samples of the one before, and leaves the other graph alone.
    function test_anotherTemperatureSensorStartsAfresh_data() {
        return [{ tag: "cpu", key: "cpuTemperatureSensor", ids: ["cpu/cpu97/temperature", "cpu/cpu98/temperature"],
                  history: "cpuTemperatureHistory", other: "diskTemperatureHistory" },
                { tag: "disk", key: "diskTemperatureSensor", ids: ["disk/vdy/temperature", "disk/vdz/temperature"],
                  history: "diskTemperatureHistory", other: "cpuTemperatureHistory" }];
    }
    function test_anotherTemperatureSensorStartsAfresh(data) {
        stopTimers(monitor);
        config[data.key] = data.ids[0];
        monitor.sample();
        monitor.sample();
        const kept = monitor[data.other].length;
        verify(monitor[data.history].length >= 2);
        config[data.key] = data.ids[1];
        compare(monitor[data.history].length, 0);
        compare(monitor[data.other].length, kept);
        monitor.sample();
        compare(monitor[data.history].length, 1);
    }

    // A GPU's temperature comes from its reader, so sampling it reads
    // nothing: a resting GPU's held reading goes in, and a sleeping GPU's
    // history has a gap whatever it held, with its sensors left off.
    function test_aSleepingGpuRecordsGaps() {
        const gpu = monitor.gpuOuter;
        tryVerify(() => gpu.leading && gpu.wanted, 5000, "this widget's reader leads and wants the GPU");
        settledPowerStates(monitor);
        compare(gpu.phase, "asleep");
        monitor.sample();
        verify(Number.isNaN(gpu.temperatureHistory[gpu.temperatureHistory.length - 1]));

        gpu.held = { temperature: 55 };
        gpu.gate = { phase: "resting", since: 0, quietSince: -1, holdMs: 5000 };
        compare(gpu.phase, "resting");
        monitor.sample();
        compare(gpu.temperatureHistory[gpu.temperatureHistory.length - 1], 55);
        verify(enabledSensors(gpu).every(e => !e), "a resting GPU is unread");

        gpu.gate = { phase: "asleep", since: 0, quietSince: -1, holdMs: 5000 };
        monitor.sample();
        monitor.sample();
        compare(gpu.held.temperature, 55, "still held");
        verify(gpu.temperatureHistory.slice(-2).every(t => Number.isNaN(t)), gpu.temperatureHistory.join());
        verify(enabledSensors(gpu).every(e => !e), "nor is a sleeping one");
    }

    // The start of the wall clock's 10-minute bucket `back` buckets ago, so
    // a test's readings land in buckets a widget would keep now.
    function tenMinutes(back) {
        return (Math.floor(Date.now() / 600000) - back) * 600000;
    }

    // A widget whose readings have come, its timers stopped so only the
    // test samples.
    function sampling(m) {
        tryVerify(() => m.hardware.cpu !== undefined, 10000);
        tryVerify(() => Number.isFinite(m.cpuUsage) && Number.isFinite(m.memoryPercent), 10000, "readings arrive");
        stopTimers(m);
        return m;
    }

    // Every graph records the minute, the hour and the day together,
    // whichever is shown: the hour and the day in wall-clock buckets of the
    // average and the highest reading, shown as each closes.
    function test_everyGraphRecordsTheThreeSpans() {
        sampling(monitor);
        const t = tenMinutes(2);
        const cpu = monitor.cpuUsage;
        monitor.sample(t);
        monitor.sample(t + 1000);
        monitor.sample(t + 30000);
        monitor.sample(t + 600000);
        const keys = Object.keys(monitor.series).sort();
        compare(keys, ["cpu", "cpuTemperature:cpu/all/maximumTemperature", "diskRead", "diskTemperature:", "diskWrite",
                       "gpu:gpu97", "gpu:gpu98", "gpuTemperature:gpu97", "gpuTemperature:gpu98", "memory", "networkDown",
                       "networkUp"]);
        const s = monitor.series.cpu;
        compare(s.minute.length, 4);
        compare(s.hour.means.length, 20, "two buckets then gaps to the tenth minute");
        compare(s.hour.means[0], cpu);
        compare(s.hour.highs[0], cpu);
        compare(s.day.means, [cpu]);

        compare(monitor.graphSpan, "minute");
        compare(monitor.cpuHistory, s.minute);
        compare(monitor.cpuHighs, [], "each point at a minute is a reading");
        config.graphSpan = "hour";
        compare(monitor.historyLength, 120);
        compare(monitor.cpuHistory, s.hour.means);
        compare(monitor.cpuHighs, s.hour.highs);
        compare(monitor.memoryHistory, monitor.series.memory.hour.means);
        compare(monitor.gpuOuter.history, monitor.series["gpu:gpu97"].hour.means);
        config.graphSpan = "day";
        compare(monitor.historyLength, 144);
        compare(monitor.cpuHistory, [cpu]);
        compare(monitor.networkDownHighs, monitor.series.networkDown.day.highs);
        config.graphSpan = "minute";
        compare(monitor.historyLength, 60);
        compare(monitor.cpuHistory.length, 4);
    }

    // At an hour or a day a graph changes only when its bucket closes, so
    // an open popup redraws it every 30 seconds or 10 minutes, not every
    // second.
    function test_aLongSpanChangesAsItsBucketsClose() {
        sampling(monitor);
        config.graphSpan = "hour";
        const t = tenMinutes(1);
        let changes = 0;
        const count = () => ++changes;
        monitor.cpuHistoryChanged.connect(count);
        try {
            monitor.sample(t);
            monitor.sample(t + 1000);
            monitor.sample(t + 29000);
            compare(changes, 0, "the bucket is open");
            monitor.sample(t + 30000);
            compare(changes, 1, "it closed");
            config.graphSpan = "minute";
            const was = changes;
            monitor.sample(t + 31000);
            monitor.sample(t + 32000);
            compare(changes, was + 2, "a minute moves at every sample");
        } finally {
            monitor.cpuHistoryChanged.disconnect(count);
        }
    }

    // A temperature's scale comes from all three spans, kept with it.
    function test_temperatureExtentCoversEverySpan() {
        sampling(monitor);
        config.cpuTemperatureSensor = "cpu/all/coreCount";
        tryVerify(() => Number.isFinite(monitor.cpuTemperature), 10000, "the stand-in reading arrives");
        const t = tenMinutes(1);
        monitor.sample(t);
        monitor.sample(t + 30000);
        compare(monitor.cpuTemperatureExtent, [monitor.cpuTemperature, monitor.cpuTemperature]);
        const s = monitor.series["cpuTemperature:cpu/all/coreCount"];
        s.day.highs = [99];
        s.day.means = [1];
        monitor.sample(t + 31000);
        compare(monitor.cpuTemperatureExtent, [monitor.cpuTemperature, monitor.cpuTemperature],
                "a reading only widens it");
        monitor.sample(t + 60000);
        compare(monitor.cpuTemperatureExtent, [1, 99], "worked out afresh as a bucket closes");
        config.graphSpan = "day";
        compare(monitor.cpuTemperatureExtent, [1, 99], "the same at every span");
        config.graphSpan = "minute";
        s.minute = s.minute.concat([200]);
        monitor.sample(t + 61000);
        compare(monitor.cpuTemperatureExtent, [1, 99]);
        monitor.cpuTemperatureExtent = [0, 1000];
        monitor.sample(t + 62000);
        compare(monitor.cpuTemperatureExtent, [0, 1000], "a reading inside it leaves it");
        monitor.cpuTemperatureExtent = [];
        monitor.sample(t + 63000);
        compare(monitor.cpuTemperatureExtent, [monitor.cpuTemperature, monitor.cpuTemperature], "and one outside widens it");
        monitor.sample(t + 90000);
        compare(monitor.cpuTemperatureExtent, [1, 200]);
    }

    // Any graph's caption picks the span for all of them, through the
    // setting; anything else is ignored, and a stored value Ringside
    // doesn't know reads as the minute.
    function test_chooseSpan() {
        monitor.chooseSpan("day");
        compare(config.graphSpan, "day");
        compare(monitor.graphSpan, "day");
        monitor.chooseSpan("week");
        compare(config.graphSpan, "day");
        config.graphSpan = "fortnight";
        compare(monitor.graphSpan, "minute");
        compare(monitor.historyLength, monitor.minuteLength);
    }

    // A GPU item shown again has new readers, which show the span's
    // history at once rather than as the next bucket closes: with two GPUs,
    // and with the discrete one alone, where the inner ring stays empty and
    // only the outer ring's reader changes.
    function test_aReshownGpuShowsItsHistoryAtOnce_data() {
        return [{ tag: "twoGpus", inner: "" }, { tag: "discreteOnly", inner: "none" }];
    }

    function test_aReshownGpuShowsItsHistoryAtOnce(data) {
        config.innerGpu = data.inner;
        sampling(monitor);
        config.graphSpan = "hour";
        const t = tenMinutes(1);
        monitor.sample(t);
        monitor.sample(t + 30000);
        compare(monitor.gpuOuter.history.length, 1);
        compare(monitor.gpuInner.present, data.inner === "");
        // Lets a show still queued by the inner ring's change run first, so
        // that only the readers' return can show the history.
        wait(0);
        config.hiddenItems = ["disk", "gpu"];
        verify(!monitor.gpuOuter.present);
        config.hiddenItems = ["disk"];
        tryVerify(() => monitor.gpuOuter.present, 5000);
        tryVerify(() => monitor.gpuOuter.history.length === 1, 1000, "shown at once");
        compare(monitor.gpuOuter.history, monitor.series["gpu:gpu97"].hour.means);
    }

    // A GPU put back on the inner ring shows the span chosen while it was
    // off at once, though the outer ring's reader stays as it was.
    function test_aGpuBackOnTheInnerRingShowsTheSpanAtOnce() {
        sampling(monitor);
        config.graphSpan = "hour";
        const t = tenMinutes(1);
        monitor.sample(t);
        monitor.sample(t + 30000);
        const [outer, inner] = [monitor.gpuOuter, monitor.gpuInner];
        compare(inner.history.length, 1);
        config.innerGpu = "none";
        config.graphSpan = "day";
        compare(inner.history.length, 1, "off the ring, it keeps the hour");
        config.innerGpu = "";
        verify(monitor.gpuOuter === outer && monitor.gpuInner === inner);
        tryVerify(() => inner.history.length === 0, 1000, "shown at once");
        compare(inner.history, monitor.series["gpu:gpu98"].day.means);
    }

    // A discrete GPU asleep is truly idle, so its hour and day take 0; one
    // awake but unread, resting say, is unknown, so a gap, though the
    // minute shows the 0 and the held reading the panel does. Sampling it
    // reads nothing.
    function test_anUnreadGpuIsAGapInTheHourAndDay() {
        const gpu = monitor.gpuOuter;
        tryVerify(() => gpu.leading && gpu.wanted, 5000, "this widget's reader leads and wants the GPU");
        settledPowerStates(monitor);
        compare(gpu.phase, "asleep");
        const t = tenMinutes(1);
        monitor.sample(t);
        gpu.held = { temperature: 55 };
        gpu.pmStatus = "active";
        gpu.gate = { phase: "resting", since: 0, quietSince: -1, holdMs: 5000 };
        compare(gpu.phase, "resting");
        monitor.sample(t + 30000);
        monitor.sample(t + 60000);
        verify(enabledSensors(gpu).every(e => !e), "nothing is read");
        const usage = monitor.series["gpu:gpu97"];
        const temperature = monitor.series["gpuTemperature:gpu97"];
        compare(usage.hour.means[0], 0, "asleep, idle");
        verify(Number.isNaN(usage.hour.means[1]), "resting, unknown: " + usage.hour.means[1]);
        verify(Number.isNaN(temperature.hour.means[0]) && Number.isNaN(temperature.hour.means[1]),
               "no temperature asleep, and the held one isn't recorded");
        compare(usage.minute.slice(-2), [0, 0]);
        compare(temperature.minute[temperature.minute.length - 1], 55, "the minute shows what the header does");
    }

    // The store, in the tests' own database.
    readonly property url testStore: Qt.resolvedUrl("data/TestStore.qml")

    function database() {
        const db = Sql.LocalStorage.openDatabaseSync("ringside-tests", "", "", 1000000);
        db.transaction(tx => tx.executeSql("CREATE TABLE IF NOT EXISTS buckets (widget TEXT NOT NULL, tier TEXT NOT NULL, "
                                           + "at INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY (widget, tier, at))"));
        return db;
    }

    // What a widget saved: [{ tier, at, data }], by tier and time.
    function saved(widget) {
        const out = [];
        database().readTransaction(tx => {
            const r = tx.executeSql("SELECT tier, at, data FROM buckets WHERE widget = ? ORDER BY tier, at", [widget]);
            for (let i = 0; i < r.rows.length; ++i) {
                out.push({ tier: r.rows.item(i).tier, at: r.rows.item(i).at, data: JSON.parse(r.rows.item(i).data) });
            }
        });
        return out;
    }

    function forget() {
        database().transaction(tx => tx.executeSql("DELETE FROM buckets"));
    }

    function keeping(widget, keep, properties) {
        return makeMonitor(Object.assign({ widgetId: widget, storeUrl: testStore,
                                           config: createTemporaryObject(configComponent, testCase, { keepGraphHistory: keep }) },
                                         properties ?? {}));
    }

    // Stands in for a widget's store, counting its saves.
    Component {
        id: countingStore
        QtObject {
            property QtObject store
            property int saves: 0
            function save(rows) {
                ++saves;
                store.save(rows);
            }
            function load(tier) {
                return store.load(tier);
            }
            function clear() {
                store.clear();
            }
        }
    }

    // A widget whose discrete GPU is known to be suspended, by this widget
    // or by the one leading it, and whose readings have come.
    function suspended(m) {
        tryVerify(() => m.gpuOuter.knownAsleep, 10000, "the GPU's state arrives");
        return sampling(m);
    }

    function counted(m) {
        m.store = countingStore.createObject(m, { store: m.store });
        return m.store;
    }

    // Kept, closed buckets are saved with the day's, every 10 minutes,
    // since each save is a commit on Plasma's main thread, and what waits
    // is saved as the widget stops. Each series goes to a tenth.
    function test_bucketsAreSavedEveryTenMinutes() {
        forget();
        const m = suspended(keeping("w1", true));
        const store = counted(m);
        const t = tenMinutes(1);
        const cpu = m.cpuUsage;
        m.sample(t);
        m.sample(t + 1000);
        m.sample(t + 30000);
        m.sample(t + 60000);
        compare(store.saves, 0, "hour buckets wait");
        compare(saved("w1").length, 0);
        m.sample(t + 600000);
        compare(store.saves, 1, "saved with the day's");
        const rows = saved("w1");
        compare(rows.map(r => [r.tier, r.at]),
                [["day", t / 600000], ["hour", t / 30000], ["hour", t / 30000 + 1], ["hour", t / 30000 + 2]]);
        const hour = rows[1].data;
        compare(hour.cpu, [Math.round(cpu * 10) / 10, Math.round(cpu * 10) / 10]);
        verify(hour.memory !== undefined);
        compare(hour["gpu:gpu97"], [0, 0], "a suspended GPU is idle");
        verify(hour["diskTemperature:"] === undefined, "a series with no reading is left out");
        m.sample(t + 601000);
        m.sample(t + 630000);
        compare(store.saves, 1);
        m.destroy();
        wait(0);
        compare(saved("w1").map(r => [r.tier, r.at]).slice(-2), [["hour", t / 30000 + 2], ["hour", t / 30000 + 20]],
                "what waited, as the widget stops");
        forget();
    }

    // A series left unsampled for a while, a GPU off the rings say, closes
    // its old bucket when it comes back: saved under that bucket's own
    // time, as it is held, not with the buckets closing beside it.
    function test_aLateBucketIsSavedUnderItsOwnTime() {
        forget();
        const m = suspended(keeping("w1", true));
        const t = tenMinutes(1);
        m.sample(t);
        m.config.outerGpu = "none";
        m.config.innerGpu = "none";
        verify(!m.gpuOuter.present);
        m.sample(t + 1000);
        m.sample(t + 30000);
        m.sample(t + 60000);
        m.config.outerGpu = "";
        m.config.innerGpu = "";
        verify(m.gpuOuter.present);
        m.sample(t + 90000);
        const held = m.series["gpu:gpu97"].hour;
        compare(held.means[0], 0);
        verify(held.means.length === 3 && held.means.slice(1).every(v => Number.isNaN(v)), JSON.stringify(held.means));
        m.flush();
        const rows = saved("w1").filter(r => r.tier === "hour");
        compare(rows.map(r => r.at - t / 30000), [0, 1, 2], "the CPU's");
        compare(rows.filter(r => r.data["gpu:gpu97"] !== undefined).map(r => r.at - t / 30000), [0], "the GPU's");
        forget();
    }

    // By default the disk's temperature sensor comes from the helper's
    // report, which arrives after the widget has restored its history:
    // what was saved under that sensor stays for it, and another sensor's
    // goes once the report is in.
    function test_aRestoredDiskTemperatureWaitsForItsSensor_data() {
        return [{ tag: "reported", helper: "fake-info-disk-temperature.sh", kept: true },
                { tag: "none", helper: "fake-info.sh", kept: false }];
    }

    function test_aRestoredDiskTemperatureWaitsForItsSensor(data) {
        forget();
        const hour = Math.floor(Date.now() / 30000);
        const key = "diskTemperature:disk/vdz/temperature";
        database().transaction(tx => tx.executeSql("INSERT INTO buckets VALUES ('w9', 'hour', ?, ?)", [hour - 2, JSON.stringify(
            { cpu: [5, 6], [key]: [40, 41], "diskTemperature:disk/old/temperature": [30, 31] })]));
        const m = keeping("w9", true, { helperPath: dataPath(data.helper) });
        stopTimers(m);
        compare(m.diskTemperatureSensorId, "", "the report hasn't come");
        verify(m.series[key] !== undefined, "restored");
        tryVerify(() => m.hardware.cpu !== undefined, 10000);
        wait(0);
        compare(m.diskTemperatureSensorId, data.kept ? "disk/vdz/temperature" : "");
        verify(m.series["diskTemperature:disk/old/temperature"] === undefined, "another sensor's goes");
        compare(m.series[key] !== undefined, data.kept);
        if (data.kept) {
            compare(m.series[key].hour.means.filter(v => Number.isFinite(v)), [40]);
            m.chooseSpan("hour");
            compare(m.diskTemperatureHistory, m.series[key].hour.means);
        }
        forget();
    }

    // A saved row or series not in the store's shape, from a damaged file
    // say, is a gap, and the rest is restored.
    function test_malformedRowsAreGaps() {
        failOnWarning(/graph history|RangeError/);
        forget();
        const hour = Math.floor(Date.now() / 30000);
        database().transaction(tx => {
            for (const [at, data] of [[hour - 7, "null"], [hour - 6, '{"cpu":null}'], [hour - 5, "[1, 2]"],
                                      [hour - 4.5, '{"cpu":[9,9]}'], [hour - 4, "not JSON"], [hour - 3, '{"cpu":[5,6]}'],
                                      [hour - 2, '{"cpu":[7,8],"memory":"x","networkUp":[1]}']]) {
                tx.executeSql("INSERT INTO buckets VALUES ('w1', 'hour', ?, ?)", [at, data]);
            }
        });
        const m = keeping("w1", true);
        stopTimers(m);
        compare(m.series.cpu.hour.means.filter(v => Number.isFinite(v)), [5, 7]);
        verify(["memory", "networkUp"].every(key => !m.series[key].hour.means.some(v => Number.isFinite(v))));
        forget();
    }

    // A database that can't be used says so once, however often it is
    // tried, and the history stays in memory.
    function test_aBrokenStoreSaysSoOnce() {
        Sql.LocalStorage.openDatabaseSync("ringside-tests-broken", "", "", 1000000)
            .transaction(tx => tx.executeSql("CREATE TABLE IF NOT EXISTS buckets (x TEXT)"));
        ignoreWarning(/^ringside: graph history store:/);
        failOnWarning(/graph history/);
        const m = sampling(keeping("w1", true, { storeUrl: Qt.resolvedUrl("data/BrokenStore.qml") }));
        verify(m.store.failed);
        const t = tenMinutes(1);
        m.sample(t);
        m.sample(t + 30000);
        m.sample(t + 600000);
        m.flush();
        compare(m.series.cpu.hour.means.length, 20);
        m.config.keepGraphHistory = false;
        compare(m.store, null);
    }

    // A widget that starts with the setting on picks up where it left
    // off: the last hour's and day's buckets in place, older ones dropped.
    function test_historyIsRestoredAfterARestart() {
        forget();
        const first = sampling(keeping("w1", true));
        const t = tenMinutes(2);
        const cpu = first.cpuUsage;
        first.sample(t);
        first.sample(t + 30000);
        first.sample(t + 600000);
        first.sample(t + 1200000);
        // Buckets from before the span: three hours and two days ago.
        first.store.save([{ tier: "hour", at: t / 30000 - 360, data: { cpu: [77, 77] } },
                          { tier: "day", at: t / 600000 - 288, data: { cpu: [66, 66] } }]);
        first.destroy();
        wait(0);
        const again = keeping("w1", true);
        const s = again.series.cpu;
        verify(s !== undefined, "restored");
        const nowHour = Math.floor(Date.now() / 30000);
        compare(s.hour.at, nowHour);
        compare(s.hour.means[s.hour.means.length - (nowHour - t / 30000)], Math.round(cpu * 10) / 10);
        verify(s.hour.means.length <= 120 && !s.hour.means.includes(77), "nothing older than the hour");
        compare(s.day.means.filter(v => Number.isFinite(v)).length, 2);
        verify(!s.day.means.includes(66), "nothing older than the day");
        compare(again.cpuHistory, s.minute, "the minute isn't kept");
        again.chooseSpan("day");
        compare(again.cpuHistory, s.day.means);
        forget();
    }

    // Each widget keeps its own.
    function test_historyIsKeyedPerWidget() {
        forget();
        const first = sampling(keeping("w1", true));
        const t = tenMinutes(1);
        first.sample(t);
        first.sample(t + 30000);
        first.flush();
        verify(saved("w1").length > 0);
        const other = keeping("w2", true);
        verify(other.series.cpu === undefined || other.series.cpu.hour.means.length === 0, "w2 restores nothing of w1's");
        compare(saved("w2").length, 0);
        forget();
    }

    // Switching the setting off deletes what this widget saved, and
    // nothing of another's; the history it holds stays in memory.
    function test_switchingOffDeletesIt() {
        forget();
        const m = sampling(keeping("w1", true));
        const t = tenMinutes(1);
        m.sample(t);
        m.sample(t + 30000);
        m.flush();
        database().transaction(tx => tx.executeSql("INSERT INTO buckets VALUES ('w2', 'hour', ?, '{}')", [t / 30000]));
        verify(saved("w1").length > 0);
        m.config.keepGraphHistory = false;
        compare(m.store, null);
        compare(saved("w1").length, 0, "deleted");
        compare(saved("w2").length, 1, "another widget's kept");
        compare(m.series.cpu.hour.means.length, 1, "still shown");
        m.sample(t + 60000);
        m.sample(t + 600000);
        m.destroy();
        wait(0);
        compare(saved("w1").length, 0, "and no more saved");
        forget();
    }

    // Switched on, what the widget holds is saved at once, so a restart
    // soon after keeps it.
    function test_switchingOnSavesWhatIsHeld() {
        forget();
        const m = sampling(keeping("w1", false));
        const t = tenMinutes(1);
        m.sample(t);
        m.sample(t + 30000);
        m.sample(t + 600000);
        compare(m.store, null, "not loaded while off");
        compare(saved("w1").length, 0);
        m.config.keepGraphHistory = true;
        compare(saved("w1").map(r => [r.tier, r.at]), [["day", t / 600000], ["hour", t / 30000], ["hour", t / 30000 + 1]]);
        forget();
    }

    // Every save drops what has fallen out of its span, whoever saved it,
    // and anything ahead of the clock: about a day's buckets at most.
    function test_theStoreIsBounded() {
        forget();
        const m = keeping("w1", true);
        const hour = Math.floor(Date.now() / 30000);
        const day = Math.floor(Date.now() / 600000);
        const rows = [];
        for (let i = -400; i <= 5; ++i) {
            rows.push({ tier: "hour", at: hour + i, data: { cpu: [i, i] } });
            rows.push({ tier: "day", at: day + i, data: { cpu: [i, i] } });
        }
        database().transaction(tx => tx.executeSql("INSERT INTO buckets VALUES ('gone', 'hour', ?, '{}')", [hour - 1000]));
        m.store.save(rows);
        const kept = saved("w1");
        compare(kept.filter(r => r.tier === "hour").length, 121);
        compare(kept.filter(r => r.tier === "day").length, 145);
        verify(kept.every(r => r.at <= (r.tier === "hour" ? hour : day)), "nothing ahead of the clock");
        compare(saved("gone").length, 0, "a removed widget's old buckets go too");
        m.store.save([{ tier: "hour", at: hour, data: { cpu: [7, 8] } }]);
        compare(saved("w1").find(r => r.tier === "hour" && r.at === hour).data, { cpu: [7, 8] },
                "a bucket closed again, after the clock was set back, replaces what was saved");
        forget();
    }

    // Where the store can't load, Qt's LocalStorage module missing, the
    // widget still runs, keeps its history in memory and says so once.
    function test_aMissingStoreKeepsHistoryInMemory() {
        ignoreWarning(/graph history stays in memory, as the store can't load/);
        failOnWarning(/graph history/);
        const m = sampling(keeping("w1", true, { storeUrl: Qt.resolvedUrl("data/MissingStore.qml") }));
        verify(m.storeMissing);
        compare(m.store, null);
        const t = tenMinutes(1);
        m.sample(t);
        m.sample(t + 30000);
        compare(m.series.cpu.hour.means.length, 1);
        m.config.keepGraphHistory = false;
        m.config.keepGraphHistory = true;
        m.sample(t + 60000);
        compare(m.store, null, "not tried again");
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
