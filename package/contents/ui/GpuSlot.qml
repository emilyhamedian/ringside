pragma ComponentBehavior: Bound
import QtQuick
import org.kde.ksysguard.sensors as Sensors
import "code/format.js" as Format
import "code/gpugate.js" as Gate

// One GPU's readings, for the outer or the inner ring. A discrete GPU the
// kernel can power down is only read while gpugate.js says so; see there.
QtObject {
    id: slot

    // The helper's entry for this GPU, or null for an empty slot.
    property var info: null
    property int rateLimit: 1000
    // runtime_status as last polled; only used when `gated`.
    property string pmStatus: ""
    // Its popup is open, so an awake GPU stays read while someone looks.
    property bool watched: false
    property var gate: Gate.initial()

    readonly property bool present: info !== null
    readonly property bool gated: present && info.runtimePm === true
    // live, resting or asleep; always live when there is nothing to gate.
    readonly property string phase: !present ? "asleep" : gated ? gate.phase : "live"
    readonly property bool live: phase === "live"
    readonly property string kind: present ? info.kind : ""
    readonly property string name: present ? Format.gpuModel(info.name, nameSensor.value, info.pciName, info.vendor) : ""
    // amdgpu's temp1 is the edge sensor; other drivers don't say.
    readonly property string temperatureLabel: present && info.vendor === "1002" ? "edge" : ""

    readonly property real usage: live ? read(0) : NaN
    readonly property real temperature: {
        const t = live ? read(1) : NaN;
        return Format.temperatureValid(t) ? t : NaN;
    }
    readonly property real vramUsed: live ? read(2) : NaN
    readonly property real vramTotal: live ? read(3) : NaN
    // The size doesn't change while the GPU sleeps, so keep the last one read.
    property real knownVramTotal: NaN
    readonly property real clock: live ? read(4) : NaN
    // An APU's power sensor measures the whole package, not the GPU, so
    // integrated GPUs report none.
    readonly property real power: live && kind !== "integrated" ? read(5) : NaN
    property var history: []

    readonly property string prefix: present ? "gpu/" + info.id + "/" : ""

    function read(index) {
        sensors.count;
        const sensor = sensors.objectAt(index);
        return sensor && typeof sensor.value === "number" ? sensor.value : NaN;
    }

    onVramTotalChanged: {
        if (Number.isFinite(vramTotal) && vramTotal > 0) {
            knownVramTotal = vramTotal;
        }
    }
    onInfoChanged: knownVramTotal = NaN

    function tick(now) {
        if (gated) {
            gate = Gate.step(gate, { now: now, status: pmStatus, usage: live ? read(0) : undefined,
                                     watched: watched, autosuspendMs: info.autosuspendMs });
        }
    }

    // The name is fixed at ksystemstats' start, so reading it wakes nothing.
    property Sensors.Sensor nameSensor: Sensors.Sensor {
        sensorId: slot.prefix ? slot.prefix + "name" : ""
        enabled: slot.present
    }

    // Recreated whenever the GPU changes: a Sensor never unsubscribes an id it
    // is moved away from. AMD reports board power as power1; NVIDIA as power.
    property Instantiator sensors: Instantiator {
        model: slot.prefix ? ["usage", "temperature", "usedVram", "totalVram", "coreFrequency"]
            .concat(slot.kind === "integrated" ? [] : [slot.info.vendor === "1002" ? "power1" : "power"])
            .map(key => slot.prefix + key) : []
        delegate: Sensors.Sensor {
            required property string modelData
            sensorId: modelData
            enabled: slot.live
            updateRateLimit: slot.rateLimit
        }
    }
}
