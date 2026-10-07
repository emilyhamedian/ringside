// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui"

// The subscription side of the sleep gate: a GpuReader must never switch its
// Sensors on for a GPU that may be asleep, and only one reader per GPU across
// widgets may subscribe at all. The ids are made up, so nothing on the
// machine running the test is read.
TestCase {
    id: testCase
    name: "GpuReader"

    function i18nc(context, text) {
        return text;
    }

    property var reader: null
    property int serial: 0

    Component {
        id: readerComponent
        GpuReader {}
    }

    // A fresh id per test: leadership lives in a library shared by the
    // whole engine, like every Ringside widget in plasmashell.
    function discrete(runtimePm) {
        return { id: "gpu" + (900 + serial), bdf: "0000:ff:00.0", vendor: "1002", kind: "discrete", name: "",
                 pciName: "", runtimePm: runtimePm, autosuspendMs: 5000 };
    }

    function sensorStates(r) {
        const flags = [];
        for (let i = 0; i < r.sensors.count; ++i) {
            flags.push(r.sensors.objectAt(i).enabled);
        }
        return flags;
    }

    readonly property var off: [false, false, false, false, false, false]
    readonly property var on: [true, true, true, true, true, true]

    function init() {
        ++serial;
        reader = createTemporaryObject(readerComponent, testCase, { info: discrete(true), onRing: true });
    }

    function test_idsAreFixedAndIncludeBoardPower() {
        compare(reader.sensors.count, 6);
        compare(reader.sensors.objectAt(5).sensorId, "gpu/" + reader.info.id + "/power1");
    }

    function test_startsAsleepUntilAPollSaysOtherwise() {
        verify(reader.leading);
        compare(reader.phase, "asleep");
        compare(sensorStates(reader), off);
    }

    function test_anOpenPopupDoesNotWakeASleepingGpu() {
        reader.watched = true;
        reader.takeStatus("suspended", "auto", 1000);
        reader.tick(1500);
        compare(reader.phase, "asleep");
        compare(sensorStates(reader), off);
    }

    function test_subscribesOnceAwakeAndLetsGoOffTheRing() {
        reader.takeStatus("active", "auto", 1000);
        reader.tick(1500);
        compare(reader.phase, "live");
        compare(sensorStates(reader), on);

        reader.onRing = false;
        reader.tick(2500);
        compare(sensorStates(reader), off);
    }

    function test_aRestingGpuIsUnsubscribedEvenWhileWatched() {
        reader.takeStatus("active", "auto", 1000);
        reader.tick(1500);
        reader.gate = { phase: "resting", since: 1500, quietSince: -1, holdMs: 10000 };
        reader.watched = true;
        reader.tick(2500);
        compare(reader.phase, "resting");
        compare(sensorStates(reader), off);
        compare(reader.usage, 0);
    }

    // A state read before the GPU went onto a ring may predate its going to
    // sleep, so the reader waits for a newer one.
    function test_joiningARingWaitsForANewerState() {
        reader.onRing = false;
        reader.takeStatus("active", "auto", 1000);
        reader.tick(1500);
        compare(reader.phase, "live");
        compare(sensorStates(reader), off);

        reader.onRing = true;
        reader.tick(2000);
        compare(sensorStates(reader), off);
        reader.takeStatus("active", "auto", 2000);
        compare(sensorStates(reader), on);
    }

    // TLP and the like switch power/control with the power source: "on"
    // keeps the GPU powered, so there is nothing to gate.
    function test_followsPowerControlFlips() {
        reader.takeStatus("active", "on", 1000);
        verify(!reader.gated);
        compare(reader.phase, "live");
        compare(sensorStates(reader), on);

        reader.timeMs = 2000;
        reader.takeStatus("active", "auto", 2000);
        verify(reader.gated);
        compare(reader.phase, "live"); // no "off" in between for an awake GPU

        reader.takeStatus("suspended", "auto", 3000);
        reader.tick(3500);
        compare(reader.phase, "asleep");
        compare(sensorStates(reader), off);
    }

    // Two widgets showing one GPU: only the leader subscribes, the other
    // shows its readings, and a follower takes over a tick after the leader
    // goes away, never in the same turn.
    function test_oneReaderPerGpuSubscribes() {
        reader.takeStatus("active", "auto", 1000);
        reader.tick(1500);
        const other = createTemporaryObject(readerComponent, testCase, { info: reader.info, onRing: true });
        other.takeStatus("active", "auto", 1000);
        other.tick(1500);
        verify(reader.leading);
        verify(!other.leading);
        compare(sensorStates(reader), on);
        compare(sensorStates(other), off);
        compare(other.phase, reader.phase);

        reader.destroy();
        wait(0);
        compare(sensorStates(other), off);
        other.takeStatus("active", "auto", 2000);
        other.tick(2500);
        verify(other.leading);
        compare(sensorStates(other), off); // only on a state read after taking over
        other.takeStatus("active", "auto", 2500);
        compare(sensorStates(other), on);
    }

    function test_aGpuNoWidgetShowsIsNotSubscribed() {
        const other = createTemporaryObject(readerComponent, testCase, { info: reader.info, onRing: false });
        reader.onRing = false;
        reader.takeStatus("active", "auto", 1000);
        reader.tick(1500);
        other.tick(1500);
        compare(sensorStates(reader), off);
        compare(sensorStates(other), off);

        other.onRing = true;
        reader.tick(2000);
        reader.takeStatus("active", "auto", 2000);
        compare(sensorStates(reader), on); // the leader subscribes for the other widget
        compare(sensorStates(other), off);
    }

    function rateLimits(r) {
        const limits = [];
        for (let i = 0; i < r.sensors.count; ++i) {
            limits.push(r.sensors.objectAt(i).updateRateLimit);
        }
        return limits;
    }

    // A widget that graphs every half second, beside one that graphs every
    // second, gets a new reading for each of its samples from the leader.
    function test_theLeaderReadsAsOftenAsTheFastestWidget() {
        reader.rateLimit = 750;
        reader.takeStatus("active", "auto", 1000);
        reader.tick(1500);
        compare(rateLimits(reader), Array(6).fill(750));
        const other = createTemporaryObject(readerComponent, testCase, { info: reader.info, onRing: true, rateLimit: 250 });
        other.tick(1500);
        verify(!other.leading);
        reader.tick(2000);
        compare(rateLimits(reader), Array(6).fill(250));
        other.onRing = false;
        reader.tick(2500);
        compare(rateLimits(reader), Array(6).fill(750));
    }

    // The panel takes a reading once per update interval, and one that
    // appears or goes away at the next sample (see Monitor.latch()).
    function test_panelReadingsWaitForTheInterval() {
        const leader = createTemporaryObject(fakeLeader, testCase);
        const follower = createTemporaryObject(readerComponent, testCase, { info: reader.info, onRing: true });
        follower.leader = leader;
        compare(follower.usage, 10);
        compare(follower.panelUsage, NaN);
        follower.latch(false);
        compare([follower.panelUsage, follower.panelTemperature], [10, 50], "a reading that appears is taken at once");
        leader.usage = 20;
        leader.temperature = 55;
        follower.latch(false);
        compare([follower.panelUsage, follower.panelTemperature], [10, 50], "a changed reading waits");
        follower.latch(true);
        compare([follower.panelUsage, follower.panelTemperature], [20, 55], "and is taken at the interval");
        leader.usage = NaN;
        follower.latch(false);
        compare([follower.panelUsage, follower.panelTemperature], [NaN, 55], "a reading that goes away is dropped at once");
    }

    // A GPU that falls asleep leaves the panel at once, ring and readout
    // together, even before its last reading goes away.
    function test_sleepLeavesThePanelAtOnce() {
        const leader = createTemporaryObject(fakeLeader, testCase);
        const follower = createTemporaryObject(readerComponent, testCase, { info: reader.info, onRing: true });
        follower.leader = leader;
        follower.latch(true);
        compare([follower.panelUsage, follower.panelTemperature], [10, 50]);
        leader.phase = "asleep";
        compare(follower.phase, "asleep");
        compare([follower.panelUsage, follower.panelTemperature], [NaN, NaN], "dropped with the phase");
    }

    Component {
        id: fakeLeader
        QtObject {
            property string phase: "live"
            property real usage: 10
            property real temperature: 50
            property real vramUsed: NaN
            property real vramTotal: NaN
            property real knownVramTotal: NaN
            property real clock: NaN
            property real power: NaN
        }
    }

    function test_integratedGpusLeaveOutPackagePower() {
        reader = createTemporaryObject(readerComponent, testCase,
                                       { info: Object.assign(discrete(false), { id: "gpu999", kind: "integrated" }),
                                         onRing: true });
        compare(reader.sensors.count, 5);
        verify(!reader.gated);
        compare(reader.phase, "live");
        compare(sensorStates(reader), [true, true, true, true, true]);
    }
}
