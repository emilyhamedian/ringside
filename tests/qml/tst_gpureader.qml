// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui"
import "../../package/contents/ui/code/log.js" as Log

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

    // What is written to the journal, as "category level text".
    property var logged: []
    readonly property var listener: (category, level, text) => { logged = logged.concat([category + " " + level + " " + text]); }

    function init() {
        ++serial;
        reader = createTemporaryObject(readerComponent, testCase, { info: discrete(true), onRing: true });
        logged = [];
        Log.listen(listener);
    }

    function cleanup() {
        Log.unlisten(listener);
    }

    function above() {
        return logged.filter(line => !/^ringside\.gpu debug /.test(line));
    }

    // Sleeping and waking, and Ringside reading the GPU and letting go,
    // are written at info; the state found first and the gate's moves are
    // debug.
    function test_journalSleepAndWake() {
        reader.takeStatus("suspended", "auto", 1000);
        reader.tick(1500);
        compare(logged, ["ringside.gpu debug discrete GPU 0000:ff:00.0 is asleep"]);
        reader.takeStatus("active", "auto", 3000);
        reader.tick(3500);
        reader.takeStatus("suspended", "auto", 5000);
        reader.tick(5500);
        compare(above(), ["ringside.gpu info discrete GPU 0000:ff:00.0 woke up",
                          "ringside.gpu info subscribed to discrete GPU 0000:ff:00.0's readings",
                          "ringside.gpu info discrete GPU 0000:ff:00.0 went to sleep",
                          "ringside.gpu info released discrete GPU 0000:ff:00.0's readings"]);
        compare(logged.filter(line => / debug .*: /.test(line)),
                ["ringside.gpu debug discrete GPU 0000:ff:00.0: awake, so reading it",
                 "ringside.gpu debug discrete GPU 0000:ff:00.0: suspended, so not reading it"]);
    }

    // Kept awake by something else, the gate backs off to five minutes,
    // which is said once at info; the reads and releases from then on are
    // debug.
    function test_journalQuietOnceSomethingElseKeepsItAwake() {
        reader.takeStatus("active", "auto", 1000);
        reader.tick(1500);
        reader.gate = { phase: "resting", since: 2000, quietSince: -1, holdMs: 160000 };
        logged = [];
        reader.takeStatus("active", "auto", 20000);
        reader.tick(20500);
        compare(above(), ["ringside.gpu info discrete GPU 0000:ff:00.0: something else keeps it awake; "
                          + "Ringside lets go every 300 s to give it a chance to suspend"]);
        reader.gate = { phase: "resting", since: 21000, quietSince: -1, holdMs: 300000 };
        reader.takeStatus("active", "auto", 40000);
        reader.tick(40500);
        compare(above().length, 1, "nothing more at info: " + logged);
        verify(logged.includes("ringside.gpu debug released discrete GPU 0000:ff:00.0's readings"), logged);
    }

    // Only the leader writes, so two widgets showing one GPU say each thing once.
    function test_journalOnlyFromTheLeader() {
        const other = createTemporaryObject(readerComponent, testCase, { info: reader.info, onRing: true });
        other.tick(500);
        verify(!other.leading);
        other.takeStatus("suspended", "auto", 1000);
        other.takeStatus("active", "auto", 2000);
        compare(logged, []);
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

    // The hour and the day take a discrete GPU's usage as 0 only while it
    // is known to be suspended: before its state is polled, or with an
    // awake state the gate hasn't acted on yet, it is a gap.
    function test_recordsZeroOnlyWhenKnownSuspended() {
        compare(reader.phase, "asleep");
        verify(Number.isNaN(reader.recordedUsage), "not polled yet");
        reader.takeStatus("suspended", "auto", 1000);
        reader.tick(1500);
        compare(reader.recordedUsage, 0);
        reader.takeStatus("active", "auto", 3000);
        compare(reader.phase, "asleep", "until the next tick");
        verify(Number.isNaN(reader.recordedUsage));
        reader.tick(3500);
        compare(reader.phase, "live");
        reader.takeStatus("suspended", "auto", 5000);
        compare(reader.recordedUsage, 0, "suspended, whatever the gate still says");
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
