// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import "../../package/contents/ui/code/format.js" as Format
import "../../package/contents/ui/code/hardware.js" as Hardware

// Fixed readings in the shape of Monitor.qml, for the preview gallery: every
// property and function the panel and the popups read. All of them are
// writable, so a gallery entry overrides one to show a state.
// The GPU slots are shaped like GpuReader.qml: live readings, the last ones
// held while resting (usage 0), NaN while asleep. At an hour or a day each
// graph has its buckets' highest readings too, and a stretch where the
// machine slept.
QtObject {
    id: monitor

    property int interval: 1000
    property int sampleInterval: Math.min(interval, 1000)
    property int readInterval: sampleInterval - 250
    property string graphSpan: "minute"
    property int minuteLength: Math.max(2, Math.round(60000 / sampleInterval))
    property int historyLength: graphSpan === "hour" ? 120 : graphSpan === "day" ? 144 : minuteLength
    readonly property bool bucketed: graphSpan !== "minute"
    property string widgetId: ""
    property var hardware: ({
        memory: { type: "DDR5", speed: 5600, modules: [17179869184, 17179869184] },
        swap: ["zram"]
    })

    // Stands in for ProcessList's scan, so renders don't show this machine's processes.
    property var processSample: [
        { name: "firefox", usage: 8.4 * 16, memory: 3.9 * 1024 ** 3, count: 1 },
        { name: "plasmashell", usage: 3.1 * 16, memory: 620 * 1024 ** 2, count: 1 },
        { name: "kwin_wayland", usage: 2.6 * 16, memory: 410 * 1024 ** 2, count: 1 }
    ]

    signal systemMonitorRequested()
    signal configureRequested()

    function chooseSpan(span) {
        graphSpan = span;
    }

    // What main.qml gives and takes from Monitor.
    property var config: null
    property string version: ""
    property string openPopup: ""
    property var enabledItems: ["cpu", "gpu", "memory", "network", "disk"]
    readonly property bool systemShown: true

    // The Claude and Codex readings, as Monitor.usage.
    property FakeUsage usage: FakeUsage {}
    property string codexMark: "codex"

    property real cpuUsage: 23
    property real cpuTemperature: 61
    property string cpuTemperatureLabel: "Tctl"
    property string cpuModel: "AMD Ryzen 7 7840HS"
    property int cpuCores: 8
    property int cpuThreads: 16
    property var cpuIds: Array.from({ length: cpuThreads }, (_, i) => i)
    property var cpuHistory: slept(wave(cpuUsage, 14, 1))
    property var cpuHighs: highsOf(cpuHistory, 40, 1, 100)
    property var cpuTemperatureHistory: slept(wave(cpuTemperature, 2.5, 9))
    property var cpuTemperatureHighs: highsOf(cpuTemperatureHistory, 8, 9, Infinity)
    property var cpuTemperatureExtent: []

    property real memoryTotal: 31.9 * gib
    property real memoryUsed: 13.4 * gib
    property real memoryCached: 6.1 * gib
    property real memoryFree: Math.max(0, memoryTotal - memoryUsed - memoryCached)
    property real memoryPercent: memoryTotal > 0 ? memoryUsed / memoryTotal * 100 : NaN
    property string memoryModules: Format.memoryModules(hardware.memory)
    property real swapUsed: 0.2 * gib
    property real swapTotal: 16 * gib
    property string swapLabel: Hardware.swapLabel(hardware.swap)
    property real memoryPressure: 0
    property var memoryHistory: slept(wave(memoryPercent, 2, 2))
    property var memoryHighs: highsOf(memoryHistory, 3, 2, 100)

    property FakeGpu gpuOuter: FakeGpu {
        kind: "discrete"
        name: "AMD Radeon RX 7700S"
        usage: live ? 12 : resting ? 0 : NaN
        temperature: awake ? 48 : NaN
        vramUsed: awake ? 1.6 * monitor.gib : NaN
        vramTotal: live ? 8 * monitor.gib : NaN
        knownVramTotal: 8 * monitor.gib
        clock: awake ? 800 : NaN
        power: awake ? 14 : NaN
        history: monitor.slept(monitor.wave(12, 10, 3))
        highs: monitor.highsOf(history, 30, 3, 100)
        temperatureHistory: monitor.slept(monitor.wave(temperature, 2, 10))
        temperatureHighs: monitor.highsOf(temperatureHistory, 6, 10, Infinity)
    }
    property FakeGpu gpuInner: FakeGpu {
        kind: "integrated"
        name: "AMD Radeon 780M Graphics"
        usage: live ? 3 : resting ? 0 : NaN
        temperature: awake ? 41 : NaN
        vramUsed: awake ? 0.4 * monitor.gib : NaN
        vramTotal: live ? 0.5 * monitor.gib : NaN
        knownVramTotal: 0.5 * monitor.gib
        clock: awake ? 400 : NaN
        history: monitor.slept(monitor.wave(3, 3, 4))
        highs: monitor.highsOf(history, 10, 4, 100)
        temperatureHistory: monitor.slept(monitor.wave(temperature, 1.5, 11))
        temperatureHighs: monitor.highsOf(temperatureHistory, 4, 11, Infinity)
    }

    property bool networkBits: true
    property string networkInterface: "wlp1s0"
    property string networkConnection: "Home"
    property string networkAddress: "192.168.1.42"
    property real networkDown: 3.1e6
    property real networkUp: 1.5e5
    property real networkTotalDown: 3.2 * gib
    property real networkTotalUp: 410 * 1048576
    property var networkDownHistory: slept(bursts(networkDown, 6e6, 5))
    property var networkDownHighs: highsOf(networkDownHistory, 12e6, 5, Infinity)
    property var networkUpHistory: slept(wave(networkUp, 1e5, 6))
    property var networkUpHighs: highsOf(networkUpHistory, 4e5, 6, Infinity)
    // Monitor.publicAddress (PublicAddress.qml), or null, which the popup
    // reads as switched off; the tests and the gallery give it a real one.
    property var publicAddress: null

    property string diskDevice: "nvme0n1"
    property string volumeLabel: "/"
    property real diskSize: 4e12
    property real volumeFree: 2.1e12
    property real diskTemperature: 39
    property real diskRead: 12 * 1048576
    property real diskWrite: 3.4 * 1048576
    property var diskReadHistory: slept(bursts(diskRead, 30 * 1048576, 7))
    property var diskReadHighs: highsOf(diskReadHistory, 120 * 1048576, 7, Infinity)
    property var diskWriteHistory: slept(bursts(diskWrite, 8 * 1048576, 8))
    property var diskWriteHighs: highsOf(diskWriteHistory, 60 * 1048576, 8, Infinity)
    property var diskTemperatureHistory: slept(wave(diskTemperature, 1, 12))
    property var diskTemperatureHighs: highsOf(diskTemperatureHistory, 2, 12, Infinity)
    property var diskTemperatureExtent: []

    // The panel's readings follow the live ones here; Monitor holds them
    // for an update interval.
    property var panel: ({ cpuUsage: cpuUsage, cpuTemperature: cpuTemperature, memoryPercent: memoryPercent,
                           memoryUsed: memoryUsed, networkDown: networkDown, networkUp: networkUp,
                           diskRead: diskRead, diskWrite: diskWrite })

    property bool fahrenheit: false
    property bool highlightTemperatures: true
    property real warmCelsius: 75
    property real hotCelsius: 90

    readonly property real gib: 1073741824

    function heat(celsius) {
        return highlightTemperatures ? Format.heat(celsius, warmCelsius, hotCelsius) : 0;
    }

    // Park–Miller, so every run draws the same graphs.
    function random(state) {
        return state * 16807 % 2147483647;
    }

    // A full history that drifts around `level` and ends on it; NaN
    // throughout for a missing reading.
    function wave(level, swing, seed) {
        const out = [];
        let state = seed * 7919;
        for (let i = 0; i < historyLength; ++i) {
            state = random(state);
            const noise = state / 2147483647 * 2 - 1;
            out.push(Math.max(0, level + swing * (0.6 * Math.sin(i / 6 + seed) + 0.4 * noise)));
        }
        out[out.length - 1] = level;
        return out;
    }

    // At an hour or a day, the highest reading behind each of `values`: up
    // to `lift` over it, no higher than `cap`. Empty at a minute, where each
    // value is a reading.
    function highsOf(values, lift, seed, cap) {
        if (!bucketed) {
            return [];
        }
        let state = seed * 104729;
        return values.map(v => {
            state = random(state);
            return Number.isFinite(v) ? Math.min(cap, v + lift * (state / 2147483647) ** 2) : NaN;
        });
    }

    // At an hour or a day, a stretch with no readings where the machine
    // slept: eight minutes of the hour, the night of the day.
    function slept(values) {
        const [from, to] = graphSpan === "hour" ? [70, 86] : graphSpan === "day" ? [28, 76] : [0, 0];
        return values.map((v, i) => i >= from && i < to ? NaN : v);
    }

    // Mostly quiet with occasional peaks up to `peak`, ending on `level`.
    function bursts(level, peak, seed) {
        const out = [];
        let state = seed * 7919;
        for (let i = 0; i < historyLength; ++i) {
            state = random(state);
            out.push(peak * (state / 2147483647) ** 4);
        }
        out[out.length - 1] = level;
        return out;
    }

    component FakeGpu: QtObject {
        property bool present: true
        // live, resting or asleep
        property string phase: "live"
        readonly property bool live: phase === "live"
        readonly property bool resting: phase === "resting"
        readonly property bool awake: phase !== "asleep"
        // False for Intel GPUs, which publish no temperature.
        property bool reportsTemperature: true
        property bool reportsVram: true
        property string kind: ""
        property string name: ""
        property string temperatureLabel: "edge"
        property real usage: NaN
        property real temperature: NaN
        property real vramUsed: NaN
        property real vramTotal: NaN
        property real knownVramTotal: NaN
        property real clock: NaN
        property real power: NaN
        property var history: []
        property var highs: []
        property var temperatureHistory: []
        property var temperatureHighs: []
        property var temperatureExtent: []
        property real panelUsage: usage
        property real panelTemperature: temperature
    }
}
