// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/code/gpugate.js" as Gate

TestCase {
    name: "GpuGate"

    function test_initialStateIsAsleep() {
        var state = Gate.initial();
        compare(state.phase, "asleep");
        compare(state.holdMs, 10000);
    }

    function test_asleepWakesToLiveOnAFreshStatus() {
        var asleep = Gate.initial();
        var result = Gate.step(asleep, { now: 1000, status: "active", statusAt: 900, usage: undefined, watched: false,
                                         autosuspendMs: 5000, vendor: "1002" });
        compare(result.phase, "live");
        compare(result.since, 1000);
        compare(result.quietSince, -1);
        compare(result.holdMs, 10000); // carried over from the asleep state, not reset
    }

    // An "awake" status older than the GPU's shortest way back to sleep may
    // no longer be true, and subscribing a sleeping GPU wakes it.
    function test_aStaleAwakeStatusLeavesItAsleep() {
        var asleep = Gate.initial();
        // freshMs = max(5000, 3000) - 1000 = 4000
        var stale = Gate.step(asleep, { now: 10000, status: "active", statusAt: 6000, usage: undefined, watched: false,
                                        autosuspendMs: 5000, vendor: "1002" });
        verify(stale === asleep);
        var fresh = Gate.step(asleep, { now: 10000, status: "active", statusAt: 6001, usage: undefined, watched: false,
                                        autosuspendMs: 5000, vendor: "1002" });
        compare(fresh.phase, "live");
    }

    // The pm poll reports "" for a GPU it hasn't heard back about yet; that
    // must not be mistaken for an awake state.
    function test_unknownStatusStaysAsleep() {
        var asleep = Gate.initial();
        var result = Gate.step(asleep, { now: 500, status: "", usage: undefined, watched: false, autosuspendMs: 0 });
        compare(result.phase, "asleep");
        verify(result === asleep); // nothing changed, so no new object
    }

    function test_usageUndefinedBeforeFirstSampleIsNotIdle() {
        var live = { phase: "live", since: 0, quietSince: -1, holdMs: 10000 };
        var result = Gate.step(live, { now: 2000, status: "active", usage: undefined, watched: false, autosuspendMs: 0 });
        compare(result.phase, "live");
        compare(result.quietSince, -1);
        verify(result === live);
    }

    function test_liveGoesRestingAfterTheHoldOfSubOnePercentUsage() {
        var live = { phase: "live", since: 0, quietSince: -1, holdMs: 10000 };

        var quiet = Gate.step(live, { now: 1000, status: "active", usage: 0.5, watched: false, autosuspendMs: 0 });
        compare(quiet.phase, "live");
        compare(quiet.quietSince, 1000);

        var stillQuiet = Gate.step(quiet, { now: 5000, status: "active", usage: 0.9, watched: false, autosuspendMs: 0 });
        compare(stillQuiet.phase, "live");
        compare(stillQuiet.quietSince, 1000); // still counting, hold not reached yet
        verify(stillQuiet === quiet);

        var rested = Gate.step(stillQuiet, { now: 11000, status: "active", usage: 0.2, watched: false, autosuspendMs: 0 });
        compare(rested.phase, "resting");
        compare(rested.since, 11000);
        compare(rested.quietSince, -1);
        compare(rested.holdMs, 10000);
    }

    function test_restingGoesAsleepOnSuspend() {
        var resting = { phase: "resting", since: 5000, quietSince: -1, holdMs: 20000 };
        var result = Gate.step(resting, { now: 6000, status: "suspended", usage: undefined, watched: false, autosuspendMs: 0 });
        compare(result.phase, "asleep");
        compare(result.holdMs, 10000); // hold resets on sleep
    }

    function test_holdResetsOnSleepEvenFromLive() {
        var live = { phase: "live", since: 0, quietSince: 500, holdMs: 40000 };
        var result = Gate.step(live, { now: 900, status: "suspending", usage: 0.1, watched: false, autosuspendMs: 0 });
        compare(result.phase, "asleep");
        compare(result.holdMs, 10000);
    }

    function test_restingGoesLiveWithDoubledHoldOnAReadingAfterTheProbeWindow() {
        var resting = { phase: "resting", since: 0, quietSince: -1, holdMs: 10000 };

        // probeMs = max(autosuspendMs, 2000) + 4000 = 6000 here.
        var stillWaiting = Gate.step(resting, { now: 7000, status: "active", statusAt: 5999, usage: undefined,
                                                watched: false, autosuspendMs: 1000, vendor: "1002" });
        compare(stillWaiting.phase, "resting");
        verify(stillWaiting === resting);

        var probed = Gate.step(resting, { now: 7000, status: "active", statusAt: 6000, usage: undefined,
                                          watched: false, autosuspendMs: 1000, vendor: "1002" });
        compare(probed.phase, "live");
        compare(probed.since, 7000);
        compare(probed.holdMs, 20000); // doubled because it was still awake
    }

    // A slow poll can deliver a status read before the GPU had its chance to
    // suspend. Acting on it could subscribe a GPU that has since gone to sleep.
    function test_aStaleActiveStatusDoesNotEndResting() {
        var resting = { phase: "resting", since: 10000, quietSince: -1, holdMs: 10000 };
        var result = Gate.step(resting, { now: 60000, status: "active", statusAt: 12000, usage: undefined,
                                          watched: false, autosuspendMs: 5000, vendor: "1002" });
        verify(result === resting);
    }

    // NVIDIA publishes no autosuspend delay and powers down up to ~10 s after idle.
    function test_nvidiaWaitsLongerBeforeTheProbe() {
        var resting = { phase: "resting", since: 0, quietSince: -1, holdMs: 10000 };
        var early = Gate.step(resting, { now: 16000, status: "active", statusAt: 14900, usage: undefined,
                                         watched: false, autosuspendMs: 0, vendor: "10de" });
        compare(early.phase, "resting");
        var probed = Gate.step(resting, { now: 16000, status: "active", statusAt: 15000, usage: undefined,
                                          watched: false, autosuspendMs: 0, vendor: "10de" });
        compare(probed.phase, "live");
    }

    function test_holdDoublingIsCappedAtTheMaximum() {
        var resting = { phase: "resting", since: 0, quietSince: -1, holdMs: 200000 };
        var input = { now: 7000, status: "active", statusAt: 6000, usage: undefined, watched: false,
                      autosuspendMs: 0, vendor: "1002" };
        compare(Gate.step(resting, input).holdMs, 300000); // 400000 capped to MAX_HOLD_MS

        var alreadyAtCap = { phase: "resting", since: 0, quietSince: -1, holdMs: 300000 };
        compare(Gate.step(alreadyAtCap, input).holdMs, 300000);
    }

    // The README promises that opening the GPU popup never wakes the GPU.
    function test_anOpenPopupNeverCutsRestingShort() {
        var resting = { phase: "resting", since: 0, quietSince: -1, holdMs: 10000 };
        var result = Gate.step(resting, { now: 3000, status: "active", statusAt: 2500, usage: undefined,
                                          watched: true, autosuspendMs: 5000, vendor: "1002" });
        verify(result === resting);
    }

    function test_anOpenPopupLeavesASleepingGpuAsleep() {
        var statuses = ["suspended", "suspending", ""];
        for (var i = 0; i < statuses.length; ++i) {
            var asleep = Gate.initial();
            var result = Gate.step(asleep, { now: 1000, status: statuses[i], statusAt: 900, usage: undefined,
                                             watched: true, autosuspendMs: 5000, vendor: "10de" });
            compare(result.phase, "asleep", statuses[i]);
            verify(result === asleep);
        }
    }

    function test_watchedResetsTheIdleTimerWhileLive() {
        var idling = { phase: "live", since: 0, quietSince: 1000, holdMs: 10000 };
        var result = Gate.step(idling, { now: 5000, status: "active", usage: 0.1, watched: true, autosuspendMs: 0 });
        compare(result.phase, "live");
        compare(result.quietSince, -1); // being watched cancels the idle countdown
    }
}
