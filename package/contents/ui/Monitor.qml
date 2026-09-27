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
        const t = value(cpuTemperatureReaders.count > 0 ? cpuTemperatureReaders.objectAt(0) : null);
        return Format.temperatureValid(t) ? t : NaN;
    }
    readonly property string cpuTemperatureLabel: {
        if (config.cpuTemperatureSensor) {
            const s = cpuTemperatureReaders.count > 0 ? cpuTemperatureReaders.objectAt(0) : null;
            return s ? s.shortName : "";
        }
        return hardware.cpu && hardware.cpu.tempLabel ? hardware.cpu.tempLabel : i18nc("CPU temperature source", "hottest core");
    }
    readonly property string cpuModel: hardware.cpu ? Format.cpuModel(hardware.cpu.model) : ""
    readonly property int cpuCores: hardware.cpu ? hardware.cpu.cores : 0
    readonly property int cpuThreads: hardware.cpu ? hardware.cpu.threads : Math.max(0, value(cpuCountSensor)) || 0
    property var cpuHistory: []

    // Memory
    readonly property real memoryTotal: value(memoryTotalSensor)
    readonly property real memoryUsed: value(memoryUsedSensor)
    readonly property real memoryCached: value(memoryCacheSensor) + (value(memoryBufferSensor) || 0)
    readonly property real memoryFree: value(memoryFreeSensor)
    readonly property real memoryPercent: memoryTotal > 0 ? memoryUsed / memoryTotal * 100 : NaN
    readonly property string memoryModules: Format.memoryModules(hardware.memory)
    readonly property real swapUsed: value(swapUsedSensor)
    readonly property real swapTotal: value(swapTotalSensor)
    readonly property string swapLabel: Hardware.swapLabel(hardware.swap)
    // Plasma 6.2 and later; NaN before.
    readonly property real memoryPressure: value(pressureSensor)
    property var memoryHistory: []

    // GPUs: the outer ring's and the inner ring's. See GpuSlot.qml.
    readonly property var gpuChoice: Hardware.assignGpus(hardware.gpus, config.outerGpu, config.innerGpu)
    readonly property GpuSlot gpuOuter: GpuSlot {
        info: monitor.gpuChoice.outer
        rateLimit: monitor.interval
        watched: monitor.openPopup === "gpu"
    }
    readonly property GpuSlot gpuInner: GpuSlot {
        info: monitor.gpuChoice.inner
        rateLimit: monitor.interval
        watched: monitor.openPopup === "gpu"
    }

    // Network
    readonly property bool networkBits: config.networkBits
    readonly property string networkSource: config.networkInterface || "all"
    // The interface the popup describes: the chosen one, or the default route's.
    readonly property string networkInterface: config.networkInterface || hardware.defaultInterface || ""
    readonly property real networkDown: groupValue(networkReaders, 0)
    readonly property real networkUp: groupValue(networkReaders, 1)
    readonly property real networkTotalDown: groupValue(networkReaders, 2)
    readonly property real networkTotalUp: groupValue(networkReaders, 3)
    readonly property string networkConnection: groupText(networkInfoReaders, 0)
    readonly property string networkAddress: groupText(networkInfoReaders, 1)
    property var networkDownHistory: []
    property var networkUpHistory: []

    // Disk: I/O of one device (or all), free space of one volume.
    readonly property string diskDevice: config.diskDevice === "all" ? "all"
                                       : config.diskDevice || (hardware.root && hardware.root.disk) || "all"
    readonly property string volumeId: config.diskVolume || (hardware.root && hardware.root.uuid) || "all"
    readonly property string volumeLabel: config.diskVolume ? groupText(volumeReaders, 2) : volumeId === "all" ? i18n("all volumes") : "/"
    readonly property real diskRead: groupValue(diskReaders, 0)
    readonly property real diskWrite: groupValue(diskReaders, 1)
    readonly property real diskSize: groupValue(diskReaders, 2)
    readonly property real volumeTotal: groupValue(volumeReaders, 0)
    readonly property real volumeFree: groupValue(volumeReaders, 1)
    readonly property string diskTemperatureSensorId: config.diskTemperatureSensor === "none" ? ""
        : config.diskTemperatureSensor || (!config.diskDevice && hardware.root ? hardware.root.tempSensor : "")
    readonly property real diskTemperature: {
        const t = value(diskTemperatureReaders.count > 0 ? diskTemperatureReaders.objectAt(0) : null);
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

    function groupValue(group, index) {
        group.count;
        return value(group.objectAt(index));
    }

    function groupText(group, index) {
        group.count;
        const sensor = group.objectAt(index);
        return sensor && typeof sensor.value === "string" ? sensor.value : "";
    }

    function sample() {
        const n = historyLength;
        cpuHistory = History.push(cpuHistory, cpuUsage, n);
        memoryHistory = History.push(memoryHistory, memoryPercent, n);
        gpuOuter.history = History.push(gpuOuter.history, gpuOuter.usage, n);
        gpuInner.history = History.push(gpuInner.history, gpuInner.usage, n);
        networkDownHistory = History.push(networkDownHistory, networkDown, n);
        networkUpHistory = History.push(networkUpHistory, networkUp, n);
        diskReadHistory = History.push(diskReadHistory, diskRead, n);
        diskWriteHistory = History.push(diskWriteHistory, diskWrite, n);
    }

    // A new interval or span would mix samples of different ages.
    onHistoryLengthChanged: {
        cpuHistory = [];
        memoryHistory = [];
        gpuOuter.history = [];
        gpuInner.history = [];
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

    // Steps the discrete GPU's sleep gate between runtime_status polls.
    Timer {
        interval: 1000
        running: monitor.gpuOuter.gated || monitor.gpuInner.gated
        repeat: true
        onTriggered: {
            const now = Date.now();
            monitor.gpuOuter.tick(now);
            monitor.gpuInner.tick(now);
        }
    }

    component Reader: Sensors.Sensor {
        updateRateLimit: monitor.interval
    }

    Reader { id: cpuUsageSensor; sensorId: "cpu/all/usage" }
    Reader { id: cpuCountSensor; sensorId: "cpu/all/cpuCount" }
    Reader { id: memoryTotalSensor; sensorId: "memory/physical/total" }
    Reader { id: memoryUsedSensor; sensorId: "memory/physical/used" }
    Reader { id: memoryCacheSensor; sensorId: "memory/physical/cache" }
    Reader { id: memoryBufferSensor; sensorId: "memory/physical/buffer" }
    Reader { id: memoryFreeSensor; sensorId: "memory/physical/free" }
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
        model: ["read", "write", "total"].map(key => "disk/" + monitor.diskDevice + "/" + key)
    }

    ReaderSet {
        id: volumeReaders
        model: ["total", "free", "name"].map(key => "disk/" + monitor.volumeId + "/" + key)
    }

    ReaderSet {
        id: diskTemperatureReaders
        model: monitor.diskTemperatureSensorId ? [monitor.diskTemperatureSensorId] : []
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
                return;
            }
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

    // runtime_status of the gated GPUs, polled from sysfs (which doesn't wake them).
    P5Support.DataSource {
        engine: "executable"
        interval: 2000
        connectedSources: {
            const bdfs = [monitor.gpuOuter, monitor.gpuInner].filter(s => s.gated).map(s => s.info.bdf);
            return bdfs.length > 0 ? [helper.command("pm " + bdfs.join(" "))] : [];
        }
        onNewData: (source, data) => {
            const status = {};
            for (const line of String(data.stdout || "").split("\n")) {
                const [bdf, state] = line.trim().split(" ");
                if (bdf) {
                    status[bdf] = state || "";
                }
            }
            for (const slot of [monitor.gpuOuter, monitor.gpuInner]) {
                if (slot.gated) {
                    slot.pmStatus = status[slot.info.bdf] || "";
                }
            }
        }
    }
}
