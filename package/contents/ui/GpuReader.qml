pragma ComponentBehavior: Bound
import QtQuick
import org.kde.ksysguard.sensors as Sensors
import "code/format.js" as Format
import "code/gpugate.js" as Gate

// One GPU's readings. Monitor keeps one reader per GPU the helper found and
// points the outer and inner rings at two of them. A reader's sensor ids
// never change: putting a GPU on or off a ring only switches its Sensors on
// or off, because a Sensor moved to a new id never unsubscribes the old one.
//
// A discrete GPU the kernel can power down is only read while gpugate.js
// says so, from runtime PM states that Monitor polls for every discrete GPU.
QtObject {
    id: reader

    // The helper's entry for this GPU, or null for an empty ring.
    property var info: null
    property bool onRing: false
    // Its popup is open, so an awake GPU stays read while someone looks.
    property bool watched: false
    property int rateLimit: 1000

    // The latest poll of power/runtime_status and power/control, and when
    // that poll started.
    property string pmStatus: ""
    property string pmControl: ""
    property real pmReadAt: 0
    property var gate: Gate.initial()

    readonly property bool present: info !== null
    readonly property string kind: present ? info.kind : ""
    readonly property string vendor: present ? info.vendor : ""
    // Gated while the kernel may power it down. The helper's report stands in
    // until the first poll; tools like TLP switch power/control on and off
    // with the power source.
    readonly property bool gated: kind === "discrete"
        && (pmControl || (info.runtimePm ? "auto" : "on")) === "auto"
    // live, resting or asleep; always live when there is nothing to gate.
    readonly property string phase: !present ? "asleep" : gated ? gate.phase : "live"
    readonly property bool live: phase === "live"
    readonly property bool resting: phase === "resting"
    readonly property bool subscribed: onRing && live
    readonly property string name: present ? Format.gpuModel(info.name, nameSensor.value, info.pciName, info.vendor) : ""
    readonly property string temperatureLabel: vendor === "1002" ? i18nc("@label amdgpu's edge temperature sensor", "edge") : ""
    // ksystemstats' Intel backend publishes no temperature and no VRAM.
    readonly property bool reportsTemperature: present && vendor !== "8086"
    readonly property bool reportsVram: present && vendor !== "8086"

    // While resting the GPU is awake and idle but unread, so its last
    // readings stand in and usage is known to be near zero.
    property var held: ({})
    readonly property real usage: subscribed ? read(0) : onRing && resting ? 0 : NaN
    readonly property real temperature: subscribed ? liveTemperature : onRing && resting ? held.temperature ?? NaN : NaN
    readonly property real vramUsed: subscribed ? read(2) : onRing && resting ? held.vramUsed ?? NaN : NaN
    readonly property real vramTotal: subscribed ? read(3) : NaN
    // The size doesn't change while the GPU sleeps, so keep the last one read.
    property real knownVramTotal: NaN
    readonly property real clock: subscribed ? read(4) : onRing && resting ? held.clock ?? NaN : NaN
    readonly property real power: subscribed ? livePower : onRing && resting ? held.power ?? NaN : NaN
    property var history: []

    readonly property real liveTemperature: {
        const t = subscribed ? read(1) : NaN;
        return Format.temperatureValid(t) ? t : NaN;
    }
    // An APU's power sensor measures the whole package, not the GPU, so
    // integrated GPUs report none.
    readonly property real livePower: {
        const p = subscribed && kind !== "integrated" ? read(5) : NaN;
        return Format.powerValid(p) ? p : NaN;
    }

    function read(index) {
        // Qt 6.10 and older emit no countChanged when an Instantiator's
        // objects are recreated at the same count; modelChanged comes after.
        sensors.model;
        sensors.count;
        const sensor = sensors.objectAt(index) as Sensors.Sensor;
        return sensor && typeof sensor.value === "number" ? sensor.value : NaN;
    }

    function hold(key, value) {
        if (subscribed && Number.isFinite(value)) {
            held = Object.assign({}, held, { [key]: value });
        }
    }

    // Polls can finish out of order on a busy machine; keep the newest.
    function takeStatus(status, control, readAt) {
        if (readAt > pmReadAt) {
            pmStatus = status;
            pmControl = control;
            pmReadAt = readAt;
        }
    }

    function tick(now) {
        if (gated) {
            gate = Gate.step(gate, { now: now, status: pmStatus, statusAt: pmReadAt,
                                     usage: subscribed ? read(0) : undefined, watched: watched,
                                     autosuspendMs: info.autosuspendMs, vendor: vendor });
        }
    }

    onGatedChanged: gate = Gate.initial()
    onVramTotalChanged: {
        if (Number.isFinite(vramTotal) && vramTotal > 0) {
            knownVramTotal = vramTotal;
        }
    }
    onLiveTemperatureChanged: hold("temperature", liveTemperature)
    onVramUsedChanged: hold("vramUsed", vramUsed)
    onClockChanged: hold("clock", clock)
    onLivePowerChanged: hold("power", livePower)

    // The name is fixed at ksystemstats' start, so reading it wakes nothing.
    property Sensors.Sensor nameSensor: Sensors.Sensor {
        sensorId: reader.present ? "gpu/" + reader.info.id + "/name" : ""
        enabled: reader.present && reader.onRing
    }

    // AMD reports board power as power1, NVIDIA as power; an APU's is left out.
    property Instantiator sensors: Instantiator {
        model: reader.present
            ? ["usage", "temperature", "usedVram", "totalVram", "coreFrequency"]
                .concat(reader.info.kind === "integrated" ? [] : [reader.info.vendor === "1002" ? "power1" : "power"])
                .map(key => "gpu/" + reader.info.id + "/" + key)
            : []
        delegate: Sensors.Sensor {
            required property string modelData
            sensorId: modelData
            enabled: reader.subscribed
            updateRateLimit: reader.rateLimit
        }
    }
}
