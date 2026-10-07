// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import org.kde.ksysguard.sensors as Sensors
import org.kde.plasma.plasma5support as P5Support
import "code/format.js" as Format
import "code/hardware.js" as Hardware
import "code/history.js" as History
import "code/items.js" as Items

// Every reading the panel and the popups show, and the only place the widget
// subscribes to ksystemstats. Each sensor id has exactly one Sensor here:
// ksystemstats counts subscriptions per D-Bus client, all of plasmashell is
// one client, and a second Sensor on an id keeps it subscribed after the
// first lets go. Popups read these and never subscribe the same ids.
//
// Numbers are NaN until a reading arrives. Bytes are bytes, rates are bytes
// per second, temperatures are °C, clocks MHz, power W, percentages 0–100.
//
// Readings arrive, and the graphs take them, every sampleInterval: a second,
// or the update interval when that is shorter, so a graph catches a short
// burst whatever the panel's pace. The popups show these live readings, so a
// header agrees with the graph under it. The panel shows `panel` and the GPU
// readers' panel readings, which move to the latest readings once per update
// interval.
Item {
    id: monitor

    // Plasmoid.configuration, or an object with the same keys.
    required property var config

    readonly property int interval: config.updateInterval
    readonly property int sampleInterval: Math.min(interval, 1000)
    // ksystemstats sends a frame every 500 ms. A rate limit half a frame
    // short of the sampling period lets one reading through per period even
    // when a frame comes a little early.
    readonly property int readInterval: sampleInterval - 250
    readonly property int historySeconds: config.historySeconds
    readonly property int historyLength: Math.max(2, Math.round(historySeconds * 1000 / sampleInterval))

    // The readings the panel shows, as of the last update interval. A
    // reading that appears or goes away is taken at the next sample, so the
    // panel doesn't wait an interval to show one or keep one that has gone.
    property var panel: ({ cpuUsage: NaN, cpuTemperature: NaN, memoryPercent: NaN, memoryUsed: NaN,
                           networkDown: NaN, networkUp: NaN, diskRead: NaN, diskWrite: NaN })

    // The helper's report (see code/ringside-info.sh), {} until it answers.
    property var hardware: ({})
    // Which popup is open, so GPU reads can follow what's on screen.
    property string openPopup: ""
    // The hardware helper; the tests swap in a stub.
    property string helperPath: decodeURIComponent(Qt.resolvedUrl("../code/ringside-info.sh").toString()
                                                   .replace(/^file:\/\//, ""))

    // The items switched on, and whether any of them reads ksystemstats: a
    // widget showing only Claude and Codex subscribes nothing.
    readonly property var enabledItems: Items.enabled(config.itemOrder, config.hiddenItems)
    readonly property bool systemShown: enabledItems.some(k => Items.SYSTEM.includes(k))

    // Claude and Codex readings; see UsageData.qml.
    readonly property alias usage: usageData
    // The Claude and Codex helper; the tests swap in a stub.
    property alias usageHelperPath: usageData.helperPath

    // Asked for by the popups' footers.
    signal systemMonitorRequested()
    signal configureRequested()

    // CPU
    readonly property real cpuUsage: value(cpuUsageSensor)
    readonly property real cpuTemperature: {
        const t = value(member(cpuTemperatureReaders, 0));
        return Format.temperatureValid(t) ? t : NaN;
    }
    readonly property string cpuTemperatureLabel: {
        if (config.cpuTemperatureSensor) {
            const s = member(cpuTemperatureReaders, 0);
            return s ? s.shortName : "";
        }
        return hardware.cpu && hardware.cpu.tempLabel ? hardware.cpu.tempLabel : i18nc("CPU temperature source", "hottest core");
    }
    readonly property string cpuModel: hardware.cpu ? Format.cpuModel(hardware.cpu.model) : ""
    readonly property int cpuCores: hardware.cpu ? hardware.cpu.cores : 0
    // ksystemstats' coreCount is the number of logical processors.
    readonly property int cpuThreads: hardware.cpu ? hardware.cpu.threads : Math.max(0, value(coreCountSensor)) || 0
    // ksystemstats names CPUs by processor number, which skips offline threads.
    readonly property var cpuIds: hardware.cpu && Array.isArray(hardware.cpu.ids) ? hardware.cpu.ids
                                : Array.from({ length: cpuThreads }, (_, i) => i)
    property var cpuHistory: []

    // Memory. ksystemstats' "used" is the total minus MemAvailable, and its
    // "cache" (Cached plus Slab) also counts shared memory and unreclaimable
    // slab, which "used" already holds. So free is taken from "application"
    // (total - MemFree - Cached - Buffers - Slab), which makes it MemFree, and
    // cached is the rest of what's available. The three add up to the total.
    readonly property real memoryTotal: value(memoryTotalSensor)
    readonly property real memoryUsed: value(memoryUsedSensor)
    readonly property var memoryParts: Hardware.memoryParts(memoryTotal, memoryUsed, value(memoryApplicationSensor),
                                                            value(memoryCacheSensor), value(memoryBufferSensor))
    readonly property real memoryFree: memoryParts.free
    readonly property real memoryCached: memoryParts.cached
    readonly property real memoryPercent: memoryTotal > 0 ? memoryUsed / memoryTotal * 100 : NaN
    readonly property string memoryModules: Format.memoryModules(hardware.memory)
    readonly property real swapUsed: value(swapUsedSensor)
    readonly property real swapTotal: value(swapTotalSensor)
    readonly property string swapLabel: Hardware.swapLabel((hardware.swap || []).map(kind =>
        kind === "disk" ? i18nc("@info swap on a disk partition or file", "disk") : kind))
    // Plasma 6.2 and later; NaN before.
    readonly property real memoryPressure: value(pressureSensor)
    property var memoryHistory: []

    // GPUs: one reader per GPU (see GpuReader.qml); the rings point at two.
    // A hidden GPU item has no readers, so hiding it leaves the GPU alone.
    readonly property bool gpuShown: enabledItems.includes("gpu")
    // Milliseconds since this widget started, counted by its own timer: the
    // GPU gate must not follow wall-clock steps. A late timer only makes it
    // wait longer, which never wakes a GPU.
    property real clockMs: 0
    readonly property var gpuChoice: Hardware.assignGpus(hardware.gpus, config.outerGpu, config.innerGpu)
    readonly property var gpuOuter: readerFor(gpuChoice.outer)
    readonly property var gpuInner: readerFor(gpuChoice.inner)

    // Network
    readonly property bool networkBits: config.networkBits
    readonly property string networkSource: config.networkInterface || "all"
    // The default route's interface, re-read while the network popup is open.
    property string routeInterface: ""
    // The interface the popup describes: the chosen one, or the default route's.
    readonly property string networkInterface: config.networkInterface || routeInterface
    readonly property real networkDown: groupValue(networkReaders, 0)
    readonly property real networkUp: groupValue(networkReaders, 1)
    readonly property real networkTotalDown: groupValue(networkReaders, 2)
    readonly property real networkTotalUp: groupValue(networkReaders, 3)
    readonly property string networkConnection: groupText(networkInfoReaders, 0)
    readonly property string networkAddress: groupText(networkInfoReaders, 1)
    property var networkDownHistory: []
    property var networkUpHistory: []

    // Disk: I/O of one device or of every whole disk, free space of one volume.
    // ksystemstats' disk/all counts a volume and the disk under it both, so
    // "all" here adds up the whole disks the helper lists instead.
    readonly property string diskDevice: config.diskDevice === "all" ? "all"
                                       : config.diskDevice || (hardware.root && hardware.root.disk) || "all"
    readonly property var diskIds: diskDevice === "all" ? (hardware.disks || []) : [diskDevice]
    readonly property string volumeId: config.diskVolume || (hardware.root && hardware.root.uuid) || ""
    readonly property string volumeLabel: config.diskVolume ? groupText(volumeReaders, 2) : volumeId ? "/" : ""
    readonly property real diskRead: diskSum(0)
    readonly property real diskWrite: diskSum(1)
    readonly property real diskSize: diskSum(2)
    readonly property real volumeTotal: groupValue(volumeReaders, 0)
    readonly property real volumeFree: groupValue(volumeReaders, 1)
    readonly property string diskTemperatureSensorId: config.diskTemperatureSensor === "none" ? ""
        : config.diskTemperatureSensor || (!config.diskDevice && hardware.root ? hardware.root.tempSensor : "")
    readonly property real diskTemperature: {
        const t = value(member(diskTemperatureReaders, 0));
        return Format.temperatureValid(t) ? t : NaN;
    }
    property var diskReadHistory: []
    property var diskWriteHistory: []

    // Settings the views need.
    readonly property bool fahrenheit: config.fahrenheit
    readonly property bool highlightTemperatures: config.highlightTemperatures
    readonly property real warmCelsius: config.warmCelsius
    readonly property real hotCelsius: config.hotCelsius

    // 0 normal, 1 warm, 2 hot, for colouring a temperature.
    function heat(celsius) {
        return highlightTemperatures ? Format.heat(celsius, warmCelsius, hotCelsius) : 0;
    }

    function value(sensor) {
        return sensor && typeof sensor.value === "number" ? sensor.value : NaN;
    }

    // An Instantiator's object at index, as a binding dependency. Qt 6.10 and
    // older emit no countChanged when the objects are recreated at the same
    // count (new ids, same length); modelChanged comes after regeneration.
    function member(group, index) {
        group.model;
        group.count;
        return group.objectAt(index);
    }

    function groupValue(group, index) {
        return value(member(group, index));
    }

    function groupText(group, index) {
        const sensor = member(group, index);
        return sensor && typeof sensor.value === "string" ? sensor.value : "";
    }

    // The sum of one reading across the disks, NaN until any arrives.
    function diskSum(key) {
        let total = NaN;
        for (let i = 0; i < diskIds.length; ++i) {
            const v = groupValue(diskReaders, i * 3 + key);
            if (Number.isFinite(v)) {
                total = (Number.isFinite(total) ? total : 0) + v;
            }
        }
        return total;
    }

    function readers() {
        gpuReaders.model;
        gpuReaders.count;
        const list = [];
        for (let i = 0; i < gpuReaders.count; ++i) {
            const r = gpuReaders.objectAt(i);
            if (r) {
                list.push(r);
            }
        }
        return list;
    }

    function readerFor(info) {
        return (info && readers().find(r => r.info.id === info.id)) || noGpu;
    }

    // Only readers that lead their GPU, or have yet to learn who does, ask:
    // two widgets showing one GPU would otherwise poll it twice.
    function pollPower() {
        const bdfs = readers().filter(r => r.kind === "discrete" && (r.leading || r.leader === null))
            .map(r => r.info.bdf);
        if (bdfs.length > 0) {
            // Two turns flush previously queued source notifications even
            // when a callLater tick is already waiting.
            Qt.callLater(monitor.deferPowerPoll, helper.command("pm " + bdfs.join(" ")));
        }
    }

    function deferPowerPoll(command) {
        Qt.callLater(monitor.startPowerPoll, command);
    }

    function startPowerPoll(command) {
        // Wait for removal as well as completion: reconnecting sooner can
        // return the executable engine's cached answer without running it.
        if (powerStates.pendingSource !== "") {
            return;
        }
        powerStates.pendingSource = command;
        powerStates.requestedAt = clockMs;
        powerStates.freshRequest = false;
        powerStates.connectSource(command);
    }

    function sample() {
        const n = historyLength;
        cpuHistory = History.push(cpuHistory, cpuUsage, n);
        memoryHistory = History.push(memoryHistory, memoryPercent, n);
        for (const r of [gpuOuter, gpuInner]) {
            if (r.present) {
                r.history = History.push(r.history, r.usage, n);
            }
        }
        networkDownHistory = History.push(networkDownHistory, networkDown, n);
        networkUpHistory = History.push(networkUpHistory, networkUp, n);
        diskReadHistory = History.push(diskReadHistory, diskRead, n);
        diskWriteHistory = History.push(diskWriteHistory, diskWrite, n);
        latch(false);
    }

    // Moves the panel to the live readings: all of them, or only those that
    // have appeared or gone away.
    function latch(all) {
        const next = {};
        let changed = false;
        for (const key of Object.keys(panel)) {
            const live = monitor[key];
            next[key] = all || Number.isFinite(live) !== Number.isFinite(panel[key]) ? live : panel[key];
            changed = changed || !Object.is(next[key], panel[key]);
        }
        if (changed) {
            panel = next;
        }
        for (const r of readers()) {
            r.latch(all);
        }
    }

    // A new interval or span would mix samples of different ages.
    onHistoryLengthChanged: {
        cpuHistory = [];
        memoryHistory = [];
        for (const r of readers()) {
            r.history = [];
        }
        networkDownHistory = [];
        networkUpHistory = [];
        diskReadHistory = [];
        diskWriteHistory = [];
    }

    Timer {
        interval: monitor.sampleInterval
        running: monitor.systemShown
        repeat: true
        onTriggered: monitor.sample()
    }

    Timer {
        interval: monitor.interval
        running: monitor.systemShown
        repeat: true
        onTriggered: monitor.latch(true)
    }

    // The clock: steps every GPU reader (leadership, interest, sleep gates)
    // each second and polls the discrete GPUs' power states every other.
    Timer {
        interval: 1000
        running: monitor.readers().length > 0
        repeat: true
        onTriggered: {
            monitor.clockMs += 1000;
            if (monitor.clockMs % 2000 === 0) {
                monitor.pollPower();
            }
            for (const r of monitor.readers()) {
                r.tick(monitor.clockMs);
            }
        }
    }

    component Reader: Sensors.Sensor {
        updateRateLimit: monitor.readInterval
        enabled: monitor.systemShown
    }

    Reader { id: cpuUsageSensor; sensorId: "cpu/all/usage" }
    Reader { id: coreCountSensor; sensorId: "cpu/all/coreCount" }
    Reader { id: memoryTotalSensor; sensorId: "memory/physical/total" }
    Reader { id: memoryUsedSensor; sensorId: "memory/physical/used" }
    Reader { id: memoryApplicationSensor; sensorId: "memory/physical/application" }
    Reader { id: memoryCacheSensor; sensorId: "memory/physical/cache" }
    Reader { id: memoryBufferSensor; sensorId: "memory/physical/buffer" }
    Reader { id: swapUsedSensor; sensorId: "memory/swap/used" }
    Reader { id: swapTotalSensor; sensorId: "memory/swap/total" }
    Reader { id: pressureSensor; sensorId: "pressure/memory/some10Sec" }

    // Ids that follow the settings live in Instantiators, which destroy and
    // recreate their Sensors when the ids change: a Sensor never unsubscribes
    // an id it is moved away from.
    component ReaderSet: Instantiator {
        delegate: Reader {
            required property string modelData
            sensorId: modelData
        }
    }

    ReaderSet {
        id: cpuTemperatureReaders
        model: [monitor.config.cpuTemperatureSensor || "cpu/all/maximumTemperature"]
    }

    ReaderSet {
        id: networkReaders
        model: ["download", "upload", "totalDownload", "totalUpload"]
            .map(key => "network/" + monitor.networkSource + "/" + key)
    }

    ReaderSet {
        id: networkInfoReaders
        model: monitor.networkInterface ? ["network", "ipv4address"]
            .map(key => "network/" + monitor.networkInterface + "/" + key) : []
    }

    ReaderSet {
        id: diskReaders
        // Qt's JavaScript engine has no flatMap.
        model: monitor.diskIds.reduce((ids, id) => ids.concat(["read", "write", "total"].map(key => "disk/" + id + "/" + key)), [])
    }

    ReaderSet {
        id: volumeReaders
        model: monitor.volumeId ? ["total", "free", "name"].map(key => "disk/" + monitor.volumeId + "/" + key) : []
    }

    ReaderSet {
        id: diskTemperatureReaders
        model: monitor.diskTemperatureSensorId ? [monitor.diskTemperatureSensorId] : []
    }

    // One reader per GPU while the GPU item is on. The helper's report
    // arrives once, so readers and their sensor ids stay put until then.
    Instantiator {
        id: gpuReaders
        model: monitor.gpuShown ? monitor.hardware.gpus || [] : []
        delegate: GpuReader {
            required property var modelData
            info: modelData
            rateLimit: monitor.readInterval
            timeMs: monitor.clockMs
            onRing: monitor.gpuShown
                    && [monitor.gpuChoice.outer, monitor.gpuChoice.inner].some(g => g !== null && g.id === modelData.id)
            watched: onRing && monitor.openPopup === "gpu"
            // A state read after this moment is needed before subscribing.
            onOnRingChanged: if (onRing) Qt.callLater(monitor.pollPower)
        }
        onObjectAdded: Qt.callLater(monitor.pollPower)
    }

    // The empty ring.
    GpuReader {
        id: noGpu
    }

    UsageData {
        id: usageData
        config: monitor.config
        providers: monitor.enabledItems.filter(Items.isUsage)
    }

    // Static facts, read once. The report also goes into the configuration,
    // which is how the settings pages learn the GPU names.
    P5Support.DataSource {
        id: helper

        // Run by sh, so a quote in the install path is closed, escaped and reopened.
        function command(args) {
            return "sh '" + monitor.helperPath.replace(/'/g, "'\\''") + "' " + args;
        }

        engine: "executable"
        connectedSources: [command("static")]
        onNewData: (source, data) => {
            disconnectSource(source);
            if (data["exit code"] !== 0) {
                console.warn("ringside: hardware helper exited with", data["exit code"], data.stderr);
                retry.start();
                return;
            }
            try {
                monitor.hardware = JSON.parse(data.stdout);
            } catch (err) {
                console.warn("ringside: unreadable hardware report:", err);
                retry.start();
                return;
            }
            monitor.routeInterface = monitor.hardware.defaultInterface || "";
            const report = JSON.stringify(monitor.hardware);
            if (monitor.config.detectedHardware !== report) {
                monitor.config.detectedHardware = report;
            }
        }
    }

    // A slow or interrupted first run (a busy login, say) shouldn't cost the
    // GPU item for the whole session.
    Timer {
        id: retry
        property int left: 3
        interval: 5000
        onTriggered: {
            if (left-- > 0) {
                helper.connectSource(helper.command("static"));
            }
        }
    }

    // Answers to pollPower(): "BDF runtime_status control" per line. Reading
    // these from sysfs doesn't wake a GPU.
    P5Support.DataSource {
        id: powerStates
        engine: "executable"
        property string pendingSource: ""
        property real requestedAt: -1
        property bool freshRequest: false

        onSourceAdded: source => {
            if (source === powerStates.pendingSource) {
                powerStates.freshRequest = true;
            }
        }
        onSourceRemoved: source => {
            if (source === powerStates.pendingSource) {
                // The engine emits this signal before erasing the source.
                // The widget may be gone by the time this runs.
                Qt.callLater(() => {
                    if (powerStates?.pendingSource === source) {
                        powerStates.pendingSource = "";
                    }
                });
            }
        }
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source !== powerStates.pendingSource || !powerStates.freshRequest) {
                return;
            }
            const readAt = powerStates.requestedAt;
            const states = {};
            // Fields are separated by exactly one space and may be empty.
            for (const line of String(data.stdout || "").split("\n")) {
                const fields = line.split(" ");
                if (fields[0]) {
                    states[fields[0]] = { status: fields[1] || "", control: fields[2] || "" };
                }
            }
            for (const r of monitor.readers()) {
                const s = states[r.info.bdf];
                if (s) {
                    r.takeStatus(s.status, s.control, readAt);
                }
            }
        }
    }

    // The default route moves with docks, Wi-Fi and VPNs; re-read it while
    // the network popup shows it.
    P5Support.DataSource {
        engine: "executable"
        interval: 3000
        connectedSources: monitor.openPopup === "network" || monitor.openPopup === "disk"
                          ? [helper.command("route")] : []
        onNewData: (source, data) => {
            if (data["exit code"] === 0) {
                const name = String(data.stdout || "").trim();
                if (name !== monitor.routeInterface) {
                    monitor.routeInterface = name;
                }
            }
        }
    }
}
