pragma ComponentBehavior: Bound
import QtQuick
import org.kde.ksysguard.sensors as Sensors
import "code/format.js" as Format
import "code/gpugate.js" as Gate
import "code/gpushare.js" as GpuShare

// One GPU's readings. Monitor keeps one reader per GPU the helper found and
// points the outer and inner rings at two of them. A reader's sensor ids
// never change: putting a GPU on or off a ring only switches its Sensors on
// or off, because a Sensor moved to a new id never unsubscribes the old one.
//
// Across every Ringside widget in plasmashell, one reader per GPU leads (see
// gpushare.js): it alone subscribes, and the others show its readings. The
// leader reads a discrete GPU the kernel can power down only while
// gpugate.js says so, from runtime PM states Monitor polls from sysfs.
QtObject {
    id: reader

    // The helper's entry for this GPU, or null for an empty ring.
    property var info: null
    property bool onRing: false
    // Its popup is open, so an awake GPU stays read while someone looks.
    property bool watched: false
    property int rateLimit: 1000
    // Monitor's monotonic clock in milliseconds; polls are stamped with it.
    property real timeMs: 0

    // The latest poll of power/runtime_status and power/control, and the
    // clock when that poll started.
    property string pmStatus: ""
    property string pmControl: ""
    property real pmReadAt: -1
    property var gate: Gate.initial()

    // This GPU's leader, which is this reader when it leads.
    property QtObject leader: null
    readonly property bool leading: present && leader === reader
    // Set on the leader from every widget's interest in this GPU.
    property bool wanted: false
    property bool anyWatched: false
    property real wantedSince: 0

    readonly property bool present: info !== null
    readonly property string kind: present ? info.kind : ""
    readonly property string vendor: present ? info.vendor : ""
    // Gated while the kernel may power it down. The helper's report stands in
    // until the first poll; tools like TLP switch power/control on and off
    // with the power source.
    readonly property bool gated: kind === "discrete"
        && (pmControl || (info.runtimePm ? "auto" : "on")) === "auto"
    readonly property string ownPhase: !present ? "asleep" : gated ? gate.phase : "live"
    // qmllint disable missing-property
    // (the leader is another GpuReader; a file can't name its own type)
    // live, resting or asleep, as the leader sees it.
    readonly property string phase: !present ? "asleep" : leading ? ownPhase : leader ? leader.phase : "asleep"
    readonly property bool live: phase === "live"
    readonly property bool resting: phase === "resting"
    // A GPU that can sleep is only subscribed on a state read after it was
    // put on a ring: an older one may predate its going to sleep.
    readonly property bool subscribed: leading && wanted && ownPhase === "live" && (!gated || pmReadAt >= wantedSince)
    readonly property string name: present ? Format.gpuModel(info.name, nameSensor.value, info.pciName, info.vendor) : ""
    readonly property string temperatureLabel: vendor === "1002" ? i18nc("@label amdgpu's edge temperature sensor", "edge") : ""
    // ksystemstats' Intel backend publishes no temperature and no VRAM.
    readonly property bool reportsTemperature: present && vendor !== "8086"
    readonly property bool reportsVram: present && vendor !== "8086"

    // While resting the GPU is awake and idle but unread, so its last
    // readings stand in and usage is known to be near zero. A reader that
    // doesn't lead shows the leader's.
    property var held: ({})
    readonly property bool showsHeld: wanted && ownPhase === "resting"
    readonly property real usage: !leading ? (leader ? leader.usage : NaN)
        : subscribed ? read(0) : showsHeld ? 0 : NaN
    readonly property real temperature: !leading ? (leader ? leader.temperature : NaN)
        : subscribed ? liveTemperature : showsHeld ? held.temperature ?? NaN : NaN
    readonly property real vramUsed: !leading ? (leader ? leader.vramUsed : NaN)
        : subscribed ? read(2) : showsHeld ? held.vramUsed ?? NaN : NaN
    readonly property real vramTotal: !leading ? (leader ? leader.vramTotal : NaN) : subscribed ? read(3) : NaN
    // The size doesn't change while the GPU sleeps, so keep the last one read.
    property real ownVramTotal: NaN
    readonly property real knownVramTotal: !leading ? (leader ? leader.knownVramTotal : NaN) : ownVramTotal
    readonly property real clock: !leading ? (leader ? leader.clock : NaN)
        : subscribed ? read(4) : showsHeld ? held.clock ?? NaN : NaN
    readonly property real power: !leading ? (leader ? leader.power : NaN)
        : subscribed ? livePower : showsHeld ? held.power ?? NaN : NaN
    // qmllint enable missing-property
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

    function gateInput(now, status, statusAt) {
        return { now: now, status: status, statusAt: statusAt, usage: subscribed ? read(0) : undefined,
                 watched: anyWatched, autosuspendMs: info.autosuspendMs, vendor: vendor };
    }

    // One poll runs at a time, so answers arrive in order.
    function takeStatus(status, control, readAt) {
        const wasGated = gated;
        pmStatus = status;
        pmControl = control;
        pmReadAt = readAt;
        // Switched from "on" to "auto" (TLP on unplugging): start the gate from
        // this state rather than asleep, so an awake GPU stays shown.
        if (!wasGated && gated) {
            gate = Gate.step(Gate.initial(), gateInput(timeMs, status, readAt));
        }
    }

    function tick(now) {
        if (!present) {
            return;
        }
        GpuShare.note(info.id, reader, onRing, watched);
        // Taking over from a leader that went away happens here, a tick after
        // it left, so its unsubscribes reach ksystemstats before this one's
        // subscribes.
        if (!leader) {
            leader = GpuShare.lead(info.id, reader);
        }
        if (!leading) {
            return;
        }
        const want = GpuShare.wanted(info.id);
        if (want && !wanted) {
            wantedSince = now;
        }
        wanted = want;
        anyWatched = GpuShare.watched(info.id);
        if (gated) {
            gate = Gate.step(gate, gateInput(now, pmStatus, pmReadAt));
        }
    }

    onOnRingChanged: if (present) GpuShare.note(info.id, reader, onRing, watched)
    onWatchedChanged: if (present) GpuShare.note(info.id, reader, onRing, watched)
    onVramTotalChanged: {
        if (leading && Number.isFinite(vramTotal) && vramTotal > 0) {
            ownVramTotal = vramTotal;
        }
    }
    onLiveTemperatureChanged: hold("temperature", liveTemperature)
    onVramUsedChanged: hold("vramUsed", vramUsed)
    onClockChanged: hold("clock", clock)
    onLivePowerChanged: hold("power", livePower)

    Component.onCompleted: {
        if (present) {
            GpuShare.note(info.id, reader, onRing, watched);
            leader = GpuShare.lead(info.id, reader);
            if (leading) {
                wanted = GpuShare.wanted(info.id);
                wantedSince = timeMs;
            }
        }
    }
    Component.onDestruction: {
        if (present) {
            GpuShare.leave(info.id, reader);
        }
    }

    // The name is fixed at ksystemstats' start, so reading it wakes nothing,
    // and a second subscription to it costs nothing.
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
