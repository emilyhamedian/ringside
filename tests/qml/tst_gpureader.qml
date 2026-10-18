// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui"
import "journal.js" as Journal

// The subscription side of the sleep gate: a GpuReader must never switch its
// Sensors on for a GPU that may be asleep, and only one reader per GPU across
// widgets may subscribe at all. The ids are made up, so nothing on the
// machine running the test is read.
TestRoot {
    TestCase {
        id: testCase
        name: "GpuReader"

        property var reader: null
        property int serial: 0

        Component {
            id: readerComponent
            GpuReader {}
        }

        Component {
            id: idleReaderComponent
            GpuReader {
                function read(index) { return 0; }
            }
        }

        Component {
            id: sampledReaderComponent
            GpuReader {
                property var samples: [0, NaN, NaN, NaN, NaN, NaN]
                function read(index) { return samples[index]; }
            }
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
            Journal.listen(listener);
        }

        function cleanup() {
            Journal.unlisten();
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

        // AMD reports board power as power1 and NVIDIA as power; an APU's
        // power sensor measures the whole package, so it is left out. Only a
        // discrete GPU is gated: an integrated one is read from the start.
        function test_sensorIds_data() {
            const common = ["usage", "temperature", "usedVram", "totalVram", "coreFrequency"];
            return [
                { tag: "amd", vendor: "1002", kind: "discrete", keys: common.concat(["power1"]), gated: true },
                { tag: "nvidia", vendor: "10de", kind: "discrete", keys: common.concat(["power"]), gated: true },
                { tag: "integrated", vendor: "1002", kind: "integrated", keys: common, gated: false },
                { tag: "xeDiscrete", vendor: "8086", kind: "discrete", keys: common.concat(["power"]), gated: true },
                { tag: "xeIntegrated", vendor: "8086", kind: "integrated", keys: common, gated: false }
            ];
        }
        function test_sensorIds(data) {
            // An id apart from init()'s reader, so this one leads.
            const id = "gpu" + (1900 + serial);
            reader = createTemporaryObject(readerComponent, testCase,
                                           { info: Object.assign(discrete(data.gated), { id: id, vendor: data.vendor, kind: data.kind }),
                                             onRing: true });
            const ids = [];
            for (let i = 0; i < reader.sensors.count; ++i) {
                ids.push(reader.sensors.objectAt(i).sensorId);
            }
            compare(ids, data.keys.map(key => "gpu/" + id + "/" + key));
            verify(reader.leading);
            compare(reader.gated, data.gated);
            compare(reader.phase, data.gated ? "asleep" : "live");
            compare(sensorStates(reader), data.keys.map(() => !data.gated));
        }

        function intelReader(kind, samples) {
            return createTemporaryObject(sampledReaderComponent, testCase, {
                info: Object.assign(discrete(kind === "discrete"), {
                    id: "gpu" + (3900 + serial), vendor: "8086", kind: kind
                }), onRing: true, samples: samples
            });
        }

        function test_otherVendorsKeepCapabilities_data() {
            return [{ tag: "amd", vendor: "1002" }, { tag: "nvidia", vendor: "10de" }];
        }
        function test_otherVendorsKeepCapabilities(data) {
            const r = createTemporaryObject(sampledReaderComponent, testCase, {
                info: Object.assign(discrete(true), { id: "gpu" + (4900 + serial), vendor: data.vendor }), onRing: true
            });
            compare(r.phase, "asleep");
            verify(r.reportsTemperature);
            verify(r.reportsVram);
        }

        function test_intelCapabilitiesNeedValidReadings_data() {
            return [
                { tag: "missing", temperature: NaN, total: NaN, heat: false, vram: false },
                { tag: "uninitialised", temperature: 0, total: 0, heat: false, vram: false },
                { tag: "absurd", temperature: 1e30, total: -1, heat: false, vram: false },
                { tag: "negative", temperature: -1, total: Infinity, heat: false, vram: false },
                { tag: "xeIntegrated", temperature: 51, total: 0, heat: true, vram: false },
                { tag: "xeDedicated", temperature: 62, total: 8 * 1024 ** 3, heat: true, vram: true }
            ];
        }
        function test_intelCapabilitiesNeedValidReadings(data) {
            const r = intelReader("integrated", [20, data.temperature, 0, data.total, 800]);
            verify(r.subscribed);
            compare(r.reportsTemperature, data.heat);
            compare(r.reportsVram, data.vram);
            compare(r.temperature, data.heat ? data.temperature : NaN);
        }

        function test_intelCapabilitiesSurviveMissingSamplesAndSleep() {
            const r = intelReader("discrete", [20, 0, 0, 0, 800, 10]);
            compare(sensorStates(r), off);
            verify(!r.reportsTemperature);
            verify(!r.reportsVram);
            r.takeStatus("active", "auto", 1000);
            r.tick(1500);
            compare(sensorStates(r), on);
            verify(!r.reportsTemperature);
            verify(!r.reportsVram);

            r.samples = [20, 62, 2 * 1024 ** 3, 8 * 1024 ** 3, 800, 10];
            verify(r.reportsTemperature);
            verify(r.reportsVram);
            compare(r.held.temperature, 62);
            compare(r.knownVramTotal, 8 * 1024 ** 3);
            for (const invalid of [NaN, 0, 1e30]) {
                r.samples = [20, invalid, NaN, 0, 800, 10];
                verify(r.reportsTemperature);
                verify(r.reportsVram);
                compare(r.temperature, NaN);
                compare(r.held.temperature, 62);
                compare(r.knownVramTotal, 8 * 1024 ** 3);
            }
            r.gate = { phase: "resting", since: 1500, quietSince: -1, holdMs: 10000 };
            compare(sensorStates(r), off);
            compare(r.temperature, 62);
            verify(r.reportsTemperature);
            verify(r.reportsVram);
            r.takeStatus("suspended", "auto", 2000);
            r.tick(2500);
            compare(r.phase, "asleep");
            compare(sensorStates(r), off);
            compare(r.temperature, NaN);
            verify(r.reportsTemperature);
            verify(r.reportsVram);
        }

        function test_intelFollowersShareCapabilitiesWithoutSubscriptions() {
            const r = intelReader("discrete", [20, 62, 2 * 1024 ** 3, 8 * 1024 ** 3, 800, 10]);
            const other = createTemporaryObject(sampledReaderComponent, testCase, { info: r.info, onRing: true });
            compare(sensorStates(r), off);
            compare(sensorStates(other), off);
            verify(!other.reportsTemperature);
            verify(!other.reportsVram);
            r.takeStatus("active", "auto", 1000);
            r.tick(1500);
            other.tick(1500);
            verify(!other.leading);
            compare(sensorStates(r), on);
            compare(sensorStates(other), off);
            compare(other.held.temperature, undefined, "a follower has no held temperature of its own");
            verify(other.reportsTemperature);
            verify(other.reportsVram);
            compare(other.temperature, 62);
            compare(other.knownVramTotal, 8 * 1024 ** 3);
            r.takeStatus("suspended", "auto", 2000);
            r.tick(2500);
            compare(sensorStates(r), off);
            compare(sensorStates(other), off);
            verify(other.reportsTemperature);
            verify(other.reportsVram);

            r.destroy();
            wait(0);
            other.tick(3000);
            verify(other.leading);
            compare(sensorStates(other), off);
            verify(!other.reportsTemperature, "taking over asleep needs a fresh valid sample");
            verify(!other.reportsVram);
            other.samples = [20, 0, 0, 0, 800, 10];
            other.takeStatus("active", "auto", 3000);
            other.tick(3500);
            compare(sensorStates(other), on);
            verify(!other.reportsTemperature);
            verify(!other.reportsVram);
            other.samples = [20, 59, 1024 ** 3, 8 * 1024 ** 3, 800, 10];
            verify(other.reportsTemperature);
            verify(other.reportsVram);
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
            verify(reader.leading);
            compare(reader.phase, "asleep");
            compare(sensorStates(reader), off);
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
        function test_joiningARingWaitsForANewerState_data() {
            return ["active", "suspended", "suspending", "resuming", "", "error", "unsupported"].map(status =>
                ({ tag: status || "missing", status: status, subscribed: status === "active" }));
        }
        function test_joiningARingWaitsForANewerState(data) {
            reader.onRing = false;
            reader.takeStatus("active", "auto", 1000);
            reader.tick(1500);
            compare(reader.phase, "live");
            compare(sensorStates(reader), off);

            reader.onRing = true;
            reader.tick(2000);
            compare(sensorStates(reader), off);
            reader.timeMs = 2000;
            const changes = [];
            reader.subscribedChanged.connect(() => changes.push(reader.subscribed));
            reader.takeStatus(data.status, "auto", 2000);
            compare(sensorStates(reader), data.subscribed ? on : off, "before the gate's next tick");
            compare(changes, data.subscribed ? [true] : [], "no brief subscription to a non-active GPU");
        }

        function test_nonActiveReportReleasesImmediately_data() {
            return ["suspended", "suspending", "resuming", "", "error", "unsupported"].map(status =>
                ({ tag: status || "missing", status: status }));
        }
        function test_nonActiveReportReleasesImmediately(data) {
            reader.takeStatus("active", "auto", 1000);
            reader.tick(1500);
            compare(sensorStates(reader), on);

            reader.timeMs = 2000;
            reader.takeStatus(data.status, "auto", 2000);
            compare(reader.phase, "live", "the cached gate has not ticked yet");
            compare(sensorStates(reader), off);
        }

        function test_subscriptionsRequireFreshReports_data() {
            return [
                { tag: "amd", vendor: "1002", delay: 5000, maxAge: 4000 },
                { tag: "nvidia", vendor: "10de", delay: -1, maxAge: 10000 },
                { tag: "no-delay", vendor: "1002", delay: -1, maxAge: 2000 }
            ];
        }
        function test_subscriptionsRequireFreshReports(data) {
            reader.info = Object.assign({}, reader.info, { vendor: data.vendor, autosuspendMs: data.delay });
            reader.takeStatus("active", "auto", 1000);
            reader.tick(1500);
            compare(sensorStates(reader), on);

            reader.timeMs = 1000 + data.maxAge;
            compare(sensorStates(reader), on);
            reader.timeMs += 1;
            compare(reader.phase, "live");
            compare(sensorStates(reader), off, "the active report expired without a gate transition");

            reader.onRing = false;
            reader.tick(reader.timeMs);
            reader.onRing = true;
            reader.timeMs += 1000;
            reader.tick(reader.timeMs);
            const rejoinedAt = reader.timeMs;
            reader.timeMs += data.maxAge + 1;
            reader.takeStatus("active", "auto", rejoinedAt);
            compare(sensorStates(reader), off, "a delayed rejoin report is already too old");
            reader.takeStatus("active", "auto", reader.timeMs);
            compare(sensorStates(reader), on, "a fresh active report restores monitoring");
        }

        function test_regularPollingStillLetsAnIdleGpuRest_data() {
            return test_subscriptionsRequireFreshReports_data();
        }
        function test_regularPollingStillLetsAnIdleGpuRest(data) {
            reader = createTemporaryObject(idleReaderComponent, testCase, {
                info: Object.assign(discrete(true), { id: "gpu" + (2900 + serial), vendor: data.vendor, autosuspendMs: data.delay }),
                onRing: true
            });
            const changes = [];
            reader.subscribedChanged.connect(() => changes.push(reader.subscribed));
            reader.takeStatus("active", "auto", 0);
            reader.tick(0);
            // Monitor advances the clock and ticks before each asynchronous
            // poll reply arrives, including at the shortest freshness bound.
            for (let now = 1000; now <= 11000; now += 1000) {
                reader.timeMs = now;
                reader.tick(now);
                if (now % 2000 === 0) {
                    reader.takeStatus("active", "auto", now);
                }
            }
            compare(reader.phase, "resting");
            compare(sensorStates(reader), off);
            compare(changes, [true, false], "one subscription followed by the idle release");
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
    }
}
