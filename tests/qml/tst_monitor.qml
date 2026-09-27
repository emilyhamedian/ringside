import QtQuick
import QtTest
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

    readonly property string stub: decodeURIComponent(Qt.resolvedUrl("data/fake-info.sh").toString()
                                                      .replace(/^file:\/\//, ""))

    Component {
        id: configComponent
        QtObject {
            property int updateInterval: 1000
            property int historySeconds: 60
            property bool fahrenheit: false
            property bool networkBits: true
            property bool highlightTemperatures: true
            property real warmCelsius: 75
            property real hotCelsius: 90
            property var itemOrder: ["cpu", "gpu", "memory", "network", "disk"]
            property var hiddenItems: ["disk"]
            property var ringsOnly: []
            property int ringSize: 30
            property string cpuTemperatureSensor: ""
            property string outerGpu: ""
            property string innerGpu: ""
            property string networkInterface: ""
            property string diskDevice: ""
            property string diskVolume: ""
            property string diskTemperatureSensor: ""
            property string detectedHardware: ""
        }
    }

    Component {
        id: monitorComponent
        Monitor {}
    }

    property var config: null
    property var monitor: null

    function init() {
        failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign/);
        config = createTemporaryObject(configComponent, testCase);
        monitor = createTemporaryObject(monitorComponent, testCase, { config: config, helperPath: stub });
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

    function test_memoryPartsAddUp() {
        tryVerify(() => monitor.memoryTotal > 0, 10000);
        tryVerify(() => Number.isFinite(monitor.memoryFree) && Number.isFinite(monitor.memoryCached), 10000);
        fuzzyCompare(monitor.memoryUsed + monitor.memoryCached + monitor.memoryFree, monitor.memoryTotal, 1);
        verify(monitor.memoryCached >= 0);
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
