// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtTest
import "../../package/contents/ui/code/gpugate.js" as Gate

TestCase {
    name: "GpuGate"

    function test_asleepWakesToLiveOnAFreshStatus() {
        const asleep = Gate.initial();
        compare(asleep.phase, "asleep");
        compare(asleep.holdMs, 10000);
        const result = Gate.step(asleep, { now: 1000, status: "active", statusAt: 900, usage: undefined, watched: false,
                                           autosuspendMs: 5000, vendor: "1002" });
        compare(result.phase, "live");
        compare(result.since, 1000);
        compare(result.quietSince, -1);
        compare(result.holdMs, 10000); // carried over from the asleep state, not reset
    }

    // An "awake" status older than the GPU's shortest way back to sleep may
    // no longer be true, and subscribing a sleeping GPU wakes it.
    function test_aStaleAwakeStatusLeavesItAsleep() {
        const asleep = Gate.initial();
        // freshMs = max(5000, 3000) - 1000 = 4000
        const stale = Gate.step(asleep, { now: 10000, status: "active", statusAt: 6000, usage: undefined, watched: false,
                                          autosuspendMs: 5000, vendor: "1002" });
        verify(stale === asleep);
        const fresh = Gate.step(asleep, { now: 10000, status: "active", statusAt: 6001, usage: undefined, watched: false,
                                          autosuspendMs: 5000, vendor: "1002" });
        compare(fresh.phase, "live");
    }

    function test_usageUndefinedBeforeFirstSampleIsNotIdle() {
        const live = { phase: "live", since: 0, quietSince: -1, holdMs: 10000 };
        const result = Gate.step(live, { now: 2000, status: "active", usage: undefined, watched: false, autosuspendMs: 0 });
        compare(result.phase, "live");
        compare(result.quietSince, -1);
        verify(result === live);
    }

    function test_liveGoesRestingAfterTheHoldOfSubOnePercentUsage() {
        const live = { phase: "live", since: 0, quietSince: -1, holdMs: 10000 };

        const quiet = Gate.step(live, { now: 1000, status: "active", usage: 0.5, watched: false, autosuspendMs: 0 });
        compare(quiet.phase, "live");
        compare(quiet.quietSince, 1000);

        const stillQuiet = Gate.step(quiet, { now: 5000, status: "active", usage: 0.9, watched: false, autosuspendMs: 0 });
        compare(stillQuiet.phase, "live");
        compare(stillQuiet.quietSince, 1000); // still counting, hold not reached yet
        verify(stillQuiet === quiet);

        const rested = Gate.step(stillQuiet, { now: 11000, status: "active", usage: 0.2, watched: false, autosuspendMs: 0 });
        compare(rested.phase, "resting");
        compare(rested.since, 11000);
        compare(rested.quietSince, -1);
        compare(rested.holdMs, 10000);
    }

    function test_restingGoesAsleepOnSuspend() {
        const resting = { phase: "resting", since: 5000, quietSince: -1, holdMs: 20000 };
        const result = Gate.step(resting, { now: 6000, status: "suspended", usage: undefined, watched: false, autosuspendMs: 0 });
        compare(result.phase, "asleep");
        compare(result.holdMs, 10000); // hold resets on sleep
    }

    function test_holdResetsOnSleepEvenFromLive() {
        const live = { phase: "live", since: 0, quietSince: 500, holdMs: 40000 };
        const result = Gate.step(live, { now: 900, status: "suspending", usage: 0.1, watched: false, autosuspendMs: 0 });
        compare(result.phase, "asleep");
        compare(result.holdMs, 10000);
    }

    function test_restingGoesLiveWithDoubledHoldOnAReadingAfterTheProbeWindow() {
        const resting = { phase: "resting", since: 0, quietSince: -1, holdMs: 10000 };

        // probeMs = max(autosuspendMs, 2000) + 4000 = 6000 here.
        const stillWaiting = Gate.step(resting, { now: 7000, status: "active", statusAt: 5999, usage: undefined,
                                                  watched: false, autosuspendMs: 1000, vendor: "1002" });
        compare(stillWaiting.phase, "resting");
        verify(stillWaiting === resting);

        const probed = Gate.step(resting, { now: 7000, status: "active", statusAt: 6000, usage: undefined,
                                            watched: false, autosuspendMs: 1000, vendor: "1002" });
        compare(probed.phase, "live");
        compare(probed.since, 7000);
        compare(probed.holdMs, 20000); // doubled because it was still awake
    }

    // A slow poll can deliver a status read before the GPU had its chance to
    // suspend. Acting on it could subscribe a GPU that has since gone to sleep.
    function test_aStaleActiveStatusDoesNotEndResting() {
        const resting = { phase: "resting", since: 10000, quietSince: -1, holdMs: 10000 };
        const result = Gate.step(resting, { now: 60000, status: "active", statusAt: 12000, usage: undefined,
                                            watched: false, autosuspendMs: 5000, vendor: "1002" });
        verify(result === resting);
    }

    function test_restingRequiresAFreshPostProbeStatus_data() {
        return [
            { tag: "delayedPoll", statusAt: 20000, delay: 5000, vendor: "1002", watched: false, phase: "resting" },
            { tag: "delayedPollWithPopup", statusAt: 20000, delay: 5000, vendor: "1002", watched: true, phase: "resting" },
            { tag: "amdAgeLimit", statusAt: 56000, delay: 5000, vendor: "1002", watched: false, phase: "resting" },
            { tag: "amdFresh", statusAt: 56001, delay: 5000, vendor: "1002", watched: false, phase: "live" },
            { tag: "defaultAgeLimit", statusAt: 58000, delay: 0, vendor: "1002", watched: false, phase: "resting" },
            { tag: "defaultFresh", statusAt: 58001, delay: 0, vendor: "1002", watched: false, phase: "live" },
            { tag: "nvidiaAgeLimit", statusAt: 50000, delay: 0, vendor: "10de", watched: false, phase: "resting" },
            { tag: "nvidiaFresh", statusAt: 50001, delay: 0, vendor: "10de", watched: false, phase: "live" }
        ];
    }
    function test_restingRequiresAFreshPostProbeStatus(data) {
        const resting = { phase: "resting", since: 10000, quietSince: -1, holdMs: 10000 };
        const result = Gate.step(resting, { now: 60000, status: "active", statusAt: data.statusAt, usage: undefined,
                                            watched: data.watched, autosuspendMs: data.delay, vendor: data.vendor });
        compare(result.phase, data.phase);
        if (data.phase === "resting") {
            verify(result === resting);
            // A later fresh poll resumes monitoring and doubles the hold only once.
            const fresh = Gate.step(result, { now: 61000, status: "active", statusAt: 61000, usage: undefined,
                                              watched: data.watched, autosuspendMs: data.delay, vendor: data.vendor });
            compare(fresh, { phase: "live", since: 61000, quietSince: -1, holdMs: 20000 });
        } else {
            compare(result, { phase: "live", since: 60000, quietSince: -1, holdMs: 20000 });
        }
    }

    // NVIDIA publishes no autosuspend delay and powers down up to ~10 s after idle.
    function test_nvidiaWaitsLongerBeforeTheProbe() {
        const resting = { phase: "resting", since: 0, quietSince: -1, holdMs: 10000 };
        const early = Gate.step(resting, { now: 16000, status: "active", statusAt: 14900, usage: undefined,
                                           watched: false, autosuspendMs: 0, vendor: "10de" });
        compare(early.phase, "resting");
        const probed = Gate.step(resting, { now: 16000, status: "active", statusAt: 15000, usage: undefined,
                                            watched: false, autosuspendMs: 0, vendor: "10de" });
        compare(probed.phase, "live");
    }

    function test_holdDoublingIsCappedAtTheMaximum() {
        const resting = { phase: "resting", since: 0, quietSince: -1, holdMs: 200000 };
        const input = { now: 7000, status: "active", statusAt: 6000, usage: undefined, watched: false,
                        autosuspendMs: 0, vendor: "1002" };
        compare(Gate.step(resting, input).holdMs, 300000); // 400000 capped to MAX_HOLD_MS

        const alreadyAtCap = { phase: "resting", since: 0, quietSince: -1, holdMs: 300000 };
        compare(Gate.step(alreadyAtCap, input).holdMs, 300000);
    }

    // The README promises that opening the GPU popup never wakes the GPU.
    function test_anOpenPopupNeverCutsRestingShort() {
        const resting = { phase: "resting", since: 0, quietSince: -1, holdMs: 10000 };
        const result = Gate.step(resting, { now: 3000, status: "active", statusAt: 2500, usage: undefined,
                                            watched: true, autosuspendMs: 5000, vendor: "1002" });
        verify(result === resting);
    }

    // The pm poll reports "" for a GPU it hasn't heard back about yet; that
    // must not be mistaken for an awake state, popup open or not.
    function test_aSleepingGpuStaysAsleep_data() {
        return [
            { tag: "suspended", status: "suspended", watched: true },
            { tag: "suspending", status: "suspending", watched: true },
            { tag: "unknown", status: "", watched: true },
            { tag: "unknownUnwatched", status: "", watched: false }
        ];
    }
    function test_aSleepingGpuStaysAsleep(data) {
        const asleep = Gate.initial();
        const result = Gate.step(asleep, { now: 1000, status: data.status, statusAt: 900, usage: undefined,
                                           watched: data.watched, autosuspendMs: 5000, vendor: "10de" });
        compare(result.phase, "asleep");
        verify(result === asleep); // nothing changed, so no new object
    }

    function test_watchedResetsTheIdleTimerWhileLive() {
        const idling = { phase: "live", since: 0, quietSince: 1000, holdMs: 10000 };
        const result = Gate.step(idling, { now: 5000, status: "active", usage: 0.1, watched: true, autosuspendMs: 0 });
        compare(result.phase, "live");
        compare(result.quietSince, -1); // being watched cancels the idle countdown
    }
}
