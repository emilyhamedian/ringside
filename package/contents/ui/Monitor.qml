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
import "code/log.js" as Log
import "code/publicaddress.js" as Lookup

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
//
// Every graph records three spans whether a popup is open or not: the last
// minute reading by reading, and the last hour and day in wall-clock
// buckets of their average and highest reading (see code/history.js). Its
// *History and *Highs properties hold the span shown; *Highs is empty at a
// minute, where each point is a reading.
//
// What keeps a reading or the saved history from working goes to the
// journal under ringside.setup.
Item {
    id: monitor

    LoggingCategory {
        id: journal
        name: "ringside.setup"
        defaultLogLevel: LoggingCategory.Info
    }

    // Plasmoid.configuration, or an object with the same keys.
    required property var config

    readonly property int interval: config.updateInterval
    readonly property int sampleInterval: Math.min(interval, 1000)
    // ksystemstats sends a frame every 500 ms. A rate limit half a frame
    // short of the sampling period lets one reading through per period even
    // when a frame comes a little early.
    readonly property int readInterval: sampleInterval - 250
    // The span the popups' graphs show, one for all of them; any graph's
    // caption changes it (see chooseSpan()).
    readonly property string graphSpan: History.SPANS.includes(config.graphSpan) ? config.graphSpan : "minute"
    // The minute's readings, a sampleInterval apart.
    readonly property int minuteLength: Math.max(2, Math.round(60000 / sampleInterval))
    // The points across a graph of the span shown.
    readonly property int historyLength: graphSpan === "minute" ? minuteLength : History.TIERS[graphSpan].length
    // Every graph's record by its key (see readings()): History.series().
    // Changed in place, and shown through the properties below.
    property var series: ({})

    // With "Keep graph history" on, the hour's and the day's buckets are
    // saved and restored when the widget starts (see HistoryStore.qml),
    // keyed by widgetId, Plasma's id for this widget. Each save is a
    // synchronous commit on Plasma's main thread, so closed hour buckets
    // wait in `unsaved` for the next day bucket, one save every 10 minutes,
    // and for the widget stopping.
    readonly property bool keepHistory: config.keepGraphHistory === true
    property string widgetId: ""
    // Loaded only while the setting is on, and only by URL, so a missing
    // LocalStorage module costs the setting rather than the widget. The
    // tests point it elsewhere.
    property url storeUrl: Qt.resolvedUrl("HistoryStore.qml")
    property QtObject store: null
    // The store couldn't load, so the history stays in memory.
    property bool storeMissing: false
    // Whether anything has been sampled yet: a store loaded before then
    // restores what it kept, and one loaded after saves what is held.
    property bool sampled: false
    property var unsaved: []

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
    // widget showing only Claude and Codex subscribes nothing. While any
    // system item is shown every system sensor is read, a hidden item's
    // too, except a GPU's (see gpuShown).
    readonly property var enabledItems: Items.enabled(config.itemOrder, config.hiddenItems)
    readonly property bool systemShown: enabledItems.some(k => Items.SYSTEM.includes(k))

    // Claude and Codex readings; see UsageData.qml.
    readonly property alias usage: usageData
    // The mark in the Codex ring: "codex", or "openai" for the OpenAI logo.
    readonly property string codexMark: config.codexMark === "openai" ? "openai" : "codex"
    // The Claude and Codex helper; the tests swap in a stub.
    property alias usageHelperPath: usageData.helperPath

    // Asked for by the popups' footers.
    signal systemMonitorRequested()
    signal configureRequested()

    // CPU
    readonly property real cpuUsage: value(cpuUsageSensor)
    readonly property string cpuTemperatureSensorId: config.cpuTemperatureSensor || "cpu/all/maximumTemperature"
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
    property var cpuHighs: []
    // °C, NaN while there is no reading.
    property var cpuTemperatureHistory: []
    property var cpuTemperatureHighs: []
    // [coolest, hottest] across the three spans, [] with no reading.
    property var cpuTemperatureExtent: []

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
    property var memoryHighs: []

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
    property var networkDownHighs: []
    property var networkUpHistory: []
    property var networkUpHighs: []
    // The address websites see; see PublicAddress.qml.
    readonly property alias publicAddress: publicChecker
    // The widget's version from its metadata, for that check's User-Agent.
    property string version: ""
    // The interface each address family leaves through, read while the
    // network popup shows the public address: null until the helper answers
    // after the popup opens, then { known, v4, v6 } (see code/publicaddress.js).
    property var egress: null
    readonly property bool egressShown: config.publicAddress === true && openPopup === "network"
    onEgressShownChanged: if (!egressShown) egress = null

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
    property var diskReadHighs: []
    property var diskWriteHistory: []
    property var diskWriteHighs: []
    // °C, NaN while there is no reading.
    property var diskTemperatureHistory: []
    property var diskTemperatureHighs: []
    property var diskTemperatureExtent: []

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

    // What each graph records: its series' key, where it is shown (this
    // monitor or a GPU reader, under `prefix` + History, Highs and, for a
    // temperature, Extent), the reading for the minute and for the hour and
    // the day, and whether a missing reading is a gap in the minute too.
    // A temperature's key names its sensor, so a saved history never goes
    // on under another sensor's name.
    function readings() {
        const list = [
            { key: "cpu", into: monitor, prefix: "cpu", minute: cpuUsage },
            { key: "cpuTemperature:" + cpuTemperatureSensorId, into: monitor, prefix: "cpuTemperature",
              minute: cpuTemperature, gaps: true },
            { key: "memory", into: monitor, prefix: "memory", minute: memoryPercent },
            { key: "networkDown", into: monitor, prefix: "networkDown", minute: networkDown },
            { key: "networkUp", into: monitor, prefix: "networkUp", minute: networkUp },
            { key: "diskRead", into: monitor, prefix: "diskRead", minute: diskRead },
            { key: "diskWrite", into: monitor, prefix: "diskWrite", minute: diskWrite },
            { key: "diskTemperature:" + diskTemperatureSensorId, into: monitor, prefix: "diskTemperature",
              minute: diskTemperature, gaps: true }
        ];
        // A GPU's readings are its reader's own, or its leader's: taking
        // them reads nothing more. The hour and the day take what is known
        // rather than what is shown (see GpuReader.recordedUsage).
        for (const r of [gpuOuter, gpuInner]) {
            if (r.present) {
                list.push({ key: "gpu:" + r.info.id, into: r, prefix: "", minute: r.usage, kept: r.recordedUsage },
                          { key: "gpuTemperature:" + r.info.id, into: r, prefix: "temperature", minute: r.temperature,
                            kept: r.recordedTemperature, gaps: true });
            }
        }
        return list;
    }

    function sample(nowMs) {
        const now = nowMs ?? Date.now();
        sampled = true;
        const closed = { hour: [], day: [] };
        for (const entry of readings()) {
            const s = seriesOf(entry.key);
            s.minute = entry.gaps ? History.record(s.minute, entry.minute, minuteLength)
                                  : History.push(s.minute, entry.minute, minuteLength);
            const ended = {};
            for (const name of ["hour", "day"]) {
                const bucket = History.add(s[name], entry.kept ?? entry.minute, now);
                if (bucket) {
                    ended[name] = true;
                    closed[name].push(Object.assign({ key: entry.key }, bucket));
                }
            }
            // An hour or a day changes only as its bucket closes. A
            // temperature's extent takes the new reading, and is worked
            // out afresh from every span only as a bucket closes, when
            // readings may have left the spans.
            if (graphSpan === "minute" || ended[graphSpan]) {
                show(entry, ended.hour || ended.day ? undefined : entry.minute);
            }
        }
        save(rowsOf(closed), closed.day.length > 0);
        latch(false);
    }

    function seriesOf(key) {
        if (!series[key]) {
            series[key] = History.series();
        }
        return series[key];
    }

    // Puts a series' span on show where its graph reads it. Given the
    // reading just taken, a temperature's extent only widens to take it in.
    function show(entry, latest) {
        const s = seriesOf(entry.key);
        const name = suffix => entry.prefix ? entry.prefix + suffix : suffix.toLowerCase();
        const minute = graphSpan === "minute";
        entry.into[name("History")] = minute ? s.minute : s[graphSpan].means;
        if (!minute || entry.into[name("Highs")].length > 0) {
            entry.into[name("Highs")] = minute ? [] : s[graphSpan].highs;
        }
        if (entry.gaps) {
            const was = entry.into[name("Extent")];
            const next = latest === undefined ? History.extent(s) : History.widen(was, latest);
            if (next.length !== was.length || next.some((v, i) => v !== was[i])) {
                entry.into[name("Extent")] = next;
            }
        }
    }

    function showAll() {
        for (const entry of readings()) {
            show(entry);
        }
    }

    // A temperature sensor's series goes with the sensor. By default the
    // disk's sensor comes from the helper's report, so until that arrives a
    // restored disk series stays for the sensor it may turn out to be.
    function dropOtherSensors() {
        const kept = ["cpuTemperature:" + cpuTemperatureSensorId, "diskTemperature:" + diskTemperatureSensorId];
        const known = Object.keys(hardware).length > 0 || config.diskTemperatureSensor || config.diskDevice
            ? /^(cpu|disk)Temperature:/ : /^cpuTemperature:/;
        for (const key of Object.keys(series)) {
            if (known.test(key) && !kept.includes(key)) {
                delete series[key];
            }
        }
    }

    function chooseSpan(span) {
        if (History.SPANS.includes(span) && config.graphSpan !== span) {
            config.graphSpan = span;
        }
    }

    // Closed buckets, { hour, day } of [{ key, at, mean, high }], as saved:
    // a row per bucket, [{ tier, at, data }], data each series' average and
    // highest to a tenth, leaving out a series with no reading in it and a
    // bucket with none. A series that went unsampled for a while, a GPU off
    // the rings say, closes its old bucket late, so each goes by its own
    // number.
    function rowsOf(closed) {
        const rows = [];
        const tenth = v => Math.round(v * 10) / 10;
        for (const tier of ["hour", "day"]) {
            const data = {};
            for (const b of closed[tier]) {
                if (Number.isFinite(b.mean)) {
                    data[b.at] = data[b.at] || {};
                    data[b.at][b.key] = [tenth(b.mean), tenth(b.high)];
                }
            }
            for (const at of Object.keys(data)) {
                rows.push({ tier: tier, at: Number(at), data: data[at] });
            }
        }
        return rows;
    }

    function save(rows, writeNow) {
        if (store && rows.length > 0) {
            unsaved = unsaved.concat(rows);
        }
        if (writeNow) {
            flush();
        }
    }

    function flush() {
        if (store && unsaved.length > 0) {
            store.save(unsaved); // qmllint disable missing-property
        }
        unsaved = [];
    }

    // Every bucket held, for a store just switched on.
    function saveAll() {
        const held = { hour: [], day: [] };
        for (const tier of ["hour", "day"]) {
            for (const key of Object.keys(series)) {
                const t = series[key][tier];
                t.means.forEach((mean, i) => held[tier].push({ key: key, at: t.at - t.means.length + i, mean: mean, high: t.highs[i] }));
            }
        }
        save(rowsOf(held), true);
    }

    function restore() {
        const now = Date.now();
        for (const tier of ["hour", "day"]) {
            const byKey = {};
            for (const row of store.load(tier)) { // qmllint disable missing-property
                for (const key of Object.keys(row.data)) {
                    const v = row.data[key];
                    byKey[key] = byKey[key] || [];
                    byKey[key].push({ at: row.at, mean: v[0], high: v[1] });
                }
            }
            for (const key of Object.keys(byKey)) {
                History.restore(seriesOf(key)[tier], byKey[key], now);
            }
        }
        dropOtherSensors();
        showAll();
    }

    // Loads the store and restores what it kept, as the widget starts, or
    // saves what is held, when the setting is switched on later.
    function startKeeping() {
        if (store || storeMissing || widgetId === "") {
            return;
        }
        const component = Qt.createComponent(storeUrl);
        if (component.status !== Component.Ready) {
            storeMissing = true;
            Log.write(journal, "warning", "the graphs' history stays in memory, as the store can't load: "
                      + component.errorString().trim());
            return;
        }
        store = component.createObject(monitor, { widget: widgetId });
        if (!sampled) {
            restore();
        } else {
            saveAll();
        }
    }

    // Switched off: what was saved goes.
    function stopKeeping() {
        if (store) {
            store.clear(); // qmllint disable missing-property
            store.destroy();
            store = null;
        }
    }

    // The settings and the widget's id may arrive in any order as it starts.
    onKeepHistoryChanged: keepHistory ? startKeeping() : stopKeeping()
    onWidgetIdChanged: if (keepHistory) startKeeping()
    Component.onCompleted: if (keepHistory) startKeeping()
    Component.onDestruction: flush()
    onGraphSpanChanged: showAll()
    // A ring's GPU, its history at once rather than at the next close.
    onGpuOuterChanged: Qt.callLater(monitor.showAll)
    onGpuInnerChanged: Qt.callLater(monitor.showAll)

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

    // A new interval would mix minute readings of different ages; the hour
    // and the day go by the clock.
    onMinuteLengthChanged: {
        for (const key of Object.keys(series)) {
            series[key].minute = [];
        }
        showAll();
    }

    // Another sensor's readings would go on under the new one's name.
    onCpuTemperatureSensorIdChanged: {
        dropOtherSensors();
        showAll();
    }
    onDiskTemperatureSensorIdChanged: {
        dropOtherSensors();
        showAll();
    }
    // Once the bindings on the report have settled.
    onHardwareChanged: Qt.callLater(monitor.dropOtherSensors)

    Timer {
        objectName: "sample"
        interval: monitor.sampleInterval
        running: monitor.systemShown
        repeat: true
        onTriggered: monitor.sample()
    }

    Timer {
        objectName: "latch"
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

    // A sensor ksystemstats doesn't publish stays loading for good. Each
    // minute while system items show, one enabled and loading at the check
    // before too goes to the journal, once: a CPU without a temperature
    // sensor, say, or Plasma before 6.2 without memory pressure. With none
    // loaded at all, ksystemstats isn't answering.
    property var sensorsLoading: ({})
    property var sensorsNamed: ({})

    function noteMissingSensors() {
        const sensors = [cpuUsageSensor, coreCountSensor, memoryTotalSensor, memoryUsedSensor, memoryApplicationSensor,
                         memoryCacheSensor, memoryBufferSensor, swapUsedSensor, swapTotalSensor, pressureSensor];
        for (const group of [cpuTemperatureReaders, networkReaders, networkInfoReaders, diskReaders, volumeReaders,
                             diskTemperatureReaders].concat(readers().map(r => r.sensors))) {
            for (let i = 0; i < group.count; ++i) {
                sensors.push(group.objectAt(i));
            }
        }
        const shown = sensors.filter(s => s && s.enabled && s.sensorId !== "");
        const loading = {};
        for (const s of shown.filter(s => s.status === Sensors.Sensor.Loading)) {
            loading[s.sensorId] = true;
        }
        const missing = Object.keys(loading).filter(id => sensorsLoading[id] && !sensorsNamed[id]);
        sensorsLoading = loading;
        if (missing.length > 0 && missing.length === shown.length) {
            Log.write(journal, "warning", "no sensor has answered for a minute: is ksystemstats running?");
        } else {
            for (const id of missing) {
                Log.write(journal, "info", "ksystemstats has no sensor " + id + ", so its reading stays empty");
            }
        }
        for (const id of missing) {
            sensorsNamed[id] = true;
        }
    }

    Timer {
        interval: 60000
        running: monitor.systemShown
        repeat: true
        onTriggered: monitor.noteMissingSensors()
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
        model: [monitor.cpuTemperatureSensorId]
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

    PublicAddress {
        id: publicChecker
        config: monitor.config
        open: monitor.openPopup === "network"
        egress: monitor.egress
        localAddress: monitor.networkAddress
        version: monitor.version
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
                const said = String(data.stderr ?? "").trim().split("\n").pop();
                retry.failed("ringside-info.sh exited with code " + data["exit code"] + (said ? ": " + said : ""));
                return;
            }
            try {
                monitor.hardware = JSON.parse(data.stdout);
            } catch (err) {
                retry.failed("ringside-info.sh gave a report that couldn't be read: " + err);
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
        function failed(why) {
            Log.write(journal, "warning", why + (left > 0 ? "; trying again in 5 s"
                                                          : "; the GPU item and the hardware details stay empty"));
            start();
        }
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
        connectedSources: monitor.openPopup === "network" ? [helper.command("route")] : []
        onNewData: (source, data) => {
            if (data["exit code"] === 0) {
                const name = String(data.stdout || "").trim();
                if (name !== monitor.routeInterface) {
                    monitor.routeInterface = name;
                }
            }
        }
    }

    // The routes the public address takes, re-read as often, and only while
    // the network popup shows it.
    P5Support.DataSource {
        engine: "executable"
        interval: 3000
        connectedSources: monitor.egressShown ? [helper.command("egress")] : []
        onNewData: (source, data) => {
            if (!monitor.egressShown) {
                return;
            }
            const next = Lookup.egress(data["exit code"], data.stdout);
            if (JSON.stringify(next) !== JSON.stringify(monitor.egress)) {
                monitor.egress = next;
            }
        }
    }
}
