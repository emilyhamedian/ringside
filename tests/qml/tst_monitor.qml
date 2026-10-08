// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
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
        compare(monitor.cpuTemperatureExtent, [1, 99]);
        config.graphSpan = "day";
        compare(monitor.cpuTemperatureExtent, [1, 99], "the same at every span");
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
