pragma ComponentBehavior: Bound
import QtQuick
import org.kde.ksysguard.sensors as Sensors
import org.kde.plasma.plasma5support as P5Support
import "code/format.js" as Format
import "code/hardware.js" as Hardware
import "code/history.js" as History

// Every reading the panel and the popups show, and the only place the widget
// subscribes to ksystemstats. Each sensor id has exactly one Sensor here:
// ksystemstats counts subscriptions per D-Bus client, all of plasmashell is
// one client, and a second Sensor on an id keeps it subscribed after the
// first lets go. Popups read these and never subscribe the same ids.
//
// Numbers are NaN until a reading arrives. Bytes are bytes, rates are bytes
// per second, temperatures are °C, clocks MHz, power W, percentages 0–100.
Item {
    id: monitor

    // Plasmoid.configuration, or an object with the same keys.
    required property var config

    readonly property int interval: config.updateInterval
    readonly property int historySeconds: config.historySeconds
    readonly property int historyLength: Math.max(2, Math.round(historySeconds * 1000 / interval))

    // The helper's report (see code/ringside-info.sh), {} until it answers.
    property var hardware: ({})
    // Which popup is open, so GPU reads can follow what's on screen.
    property string openPopup: ""

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
    readonly property real memoryFree: Math.max(0, Math.min(
        memoryTotal - value(memoryApplicationSensor) - value(memoryCacheSensor) - (value(memoryBufferSensor) || 0),
        memoryTotal - memoryUsed))
    readonly property real memoryCached: memoryTotal - memoryUsed - memoryFree
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

    function pollPower() {
        const bdfs = readers().filter(r => r.kind === "discrete").map(r => r.info.bdf);
        // On a machine too busy to answer within the interval, don't pile up runs.
        if (bdfs.length > 0 && powerStates.connectedSources.length === 0) {
            // The start time rides along in a shell comment: it makes each run a
            // new source, and tells the gate how old the answer is.
            powerStates.connectSource(helper.command("pm " + bdfs.join(" ")) + " #" + Date.now());
        }
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
        interval: monitor.interval
        running: true
        repeat: true
        onTriggered: monitor.sample()
    }

    // Steps each discrete GPU's sleep gate between power-state polls.
    Timer {
        interval: 1000
        running: monitor.readers().some(r => r.gated)
        repeat: true
        onTriggered: {
            const now = Date.now();
            for (const r of monitor.readers()) {
                r.tick(now);
            }
        }
    }

    // Every discrete GPU's power state, whether or not a ring shows it, so
    // its gate is current the moment it is put on one.
    Timer {
        interval: 2000
        running: monitor.readers().some(r => r.kind === "discrete")
        repeat: true
        triggeredOnStart: true
        onTriggered: monitor.pollPower()
    }

    component Reader: Sensors.Sensor {
        updateRateLimit: monitor.interval
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
        model: monitor.diskIds.flatMap(id => ["read", "write", "total"].map(key => "disk/" + id + "/" + key))
    }

    ReaderSet {
        id: volumeReaders
        model: monitor.volumeId ? ["total", "free", "name"].map(key => "disk/" + monitor.volumeId + "/" + key) : []
    }

    ReaderSet {
        id: diskTemperatureReaders
        model: monitor.diskTemperatureSensorId ? [monitor.diskTemperatureSensorId] : []
    }

    // One reader per GPU. The helper's report arrives once, so readers and
    // their sensor ids stay put for the session.
    Instantiator {
        id: gpuReaders
        model: monitor.hardware.gpus || []
        delegate: GpuReader {
            required property var modelData
            info: modelData
            rateLimit: monitor.interval
            onRing: [monitor.gpuChoice.outer, monitor.gpuChoice.inner].some(g => g !== null && g.id === modelData.id)
            watched: onRing && monitor.openPopup === "gpu"
        }
        onObjectAdded: Qt.callLater(monitor.pollPower)
    }

    // The empty ring.
    GpuReader {
        id: noGpu
    }

    // Static facts, read once. The report also goes into the configuration,
    // which is how the settings pages learn the GPU names.
    P5Support.DataSource {
        id: helper

        readonly property string path: decodeURIComponent(Qt.resolvedUrl("../code/ringside-info.sh").toString()
                                                           .replace(/^file:\/\//, ""))
        // Run by sh, so a quote in the install path is closed, escaped and reopened.
        function command(args) {
            return "sh '" + path.replace(/'/g, "'\\''") + "' " + args;
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
        onNewData: (source, data) => {
            disconnectSource(source);
            const readAt = Number(source.slice(source.lastIndexOf("#") + 1));
            const states = {};
            for (const line of String(data.stdout || "").split("\n")) {
                const [bdf, status, control] = line.trim().split(/\s+/);
                if (bdf) {
                    states[bdf] = { status: status || "", control: control || "" };
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
