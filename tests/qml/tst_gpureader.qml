import QtQuick
import QtTest
import "../../package/contents/ui"

// The subscription side of the sleep gate: a GpuReader must never switch its
// Sensors on for a GPU that is asleep, whatever else is going on. The ids are
// made up, so nothing on the machine running the test is read.
TestCase {
    id: testCase
    name: "GpuReader"

    function i18nc(context, text) {
        return text;
    }

    property var reader: null

    Component {
        id: readerComponent
        GpuReader {}
    }

    function discrete(runtimePm) {
        return { id: "gpu97", bdf: "0000:ff:00.0", vendor: "1002", kind: "discrete", name: "", pciName: "",
                 runtimePm: runtimePm, autosuspendMs: 5000 };
    }

    function sensorsEnabled() {
        const flags = [];
        for (let i = 0; i < reader.sensors.count; ++i) {
            flags.push(reader.sensors.objectAt(i).enabled);
        }
        return flags;
    }

    function init() {
        reader = createTemporaryObject(readerComponent, testCase, { info: discrete(true), onRing: true });
    }

    function test_idsAreFixedAndIncludeBoardPower() {
        compare(reader.sensors.count, 6);
        compare(reader.sensors.objectAt(5).sensorId, "gpu/gpu97/power1");
    }

    function test_startsAsleepUntilAPollSaysOtherwise() {
        compare(reader.phase, "asleep");
        compare(sensorsEnabled(), [false, false, false, false, false, false]);
    }

    function test_anOpenPopupDoesNotWakeASleepingGpu() {
        reader.watched = true;
        reader.takeStatus("suspended", "auto", 1000);
        reader.tick(1500);
        compare(reader.phase, "asleep");
        compare(sensorsEnabled(), [false, false, false, false, false, false]);
    }

    function test_subscribesOnceAwakeAndOnARing() {
        reader.takeStatus("active", "auto", 1000);
        reader.tick(1500);
        compare(reader.phase, "live");
        compare(sensorsEnabled(), [true, true, true, true, true, true]);

        reader.onRing = false;
        compare(sensorsEnabled(), [false, false, false, false, false, false]);
    }

    function test_anOlderPollDoesNotOverrideANewerOne() {
        reader.takeStatus("suspended", "auto", 2000);
        reader.takeStatus("active", "auto", 1000);
        compare(reader.pmStatus, "suspended");
    }

    // TLP and the like switch power/control with the power source: "on" keeps
    // the GPU powered, so there is nothing to gate and it is read directly.
    function test_followsPowerControlFlips() {
        reader.takeStatus("active", "on", 1000);
        verify(!reader.gated);
        compare(reader.phase, "live");

        reader.takeStatus("suspended", "auto", 2000);
        verify(reader.gated);
        reader.tick(2500);
        compare(reader.phase, "asleep");
        compare(sensorsEnabled(), [false, false, false, false, false, false]);
    }

    function test_integratedGpusLeaveOutPackagePower() {
        reader = createTemporaryObject(readerComponent, testCase,
                                       { info: Object.assign(discrete(false), { kind: "integrated" }), onRing: true });
        compare(reader.sensors.count, 5);
        verify(!reader.gated);
        compare(reader.phase, "live");
    }
}
