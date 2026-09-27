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

    function test_asleepWakesToLiveOnStatus() {
        var asleep = Gate.initial();
        var result = Gate.step(asleep, { now: 1000, status: "active", usage: undefined, watched: false, autosuspendMs: 5000 });
        compare(result.phase, "live");
        compare(result.since, 1000);
        compare(result.quietSince, -1);
        compare(result.holdMs, 10000); // carried over from the asleep state, not reset
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

    function test_restingGoesLiveWithDoubledHoldAfterTheProbeWindow() {
        var resting = { phase: "resting", since: 0, quietSince: -1, holdMs: 10000 };

        // probeMs = max(autosuspendMs, 2000) + 4000 = 6000 here.
        var stillWaiting = Gate.step(resting, { now: 5999, status: "active", usage: 0.5, watched: false, autosuspendMs: 1000 });
        compare(stillWaiting.phase, "resting");
        verify(stillWaiting === resting);

        var probed = Gate.step(resting, { now: 6000, status: "active", usage: 0.5, watched: false, autosuspendMs: 1000 });
        compare(probed.phase, "live");
        compare(probed.since, 6000);
        compare(probed.holdMs, 20000); // doubled because it was still awake
    }

    function test_holdDoublingIsCappedAtTheMaximum() {
        var resting = { phase: "resting", since: 0, quietSince: -1, holdMs: 200000 };
        var probed = Gate.step(resting, { now: 6000, status: "active", usage: 0, watched: false, autosuspendMs: 0 });
        compare(probed.holdMs, 300000); // 400000 capped to MAX_HOLD_MS

        var alreadyAtCap = { phase: "resting", since: 0, quietSince: -1, holdMs: 300000 };
        var probedAgain = Gate.step(alreadyAtCap, { now: 6000, status: "active", usage: 0, watched: false, autosuspendMs: 0 });
        compare(probedAgain.holdMs, 300000);
    }

    function test_watchedForcesRestingBackToLive() {
        var resting = { phase: "resting", since: 0, quietSince: -1, holdMs: 10000 };
        // Long before the probe window, but the popup is open, so it's read anyway.
        var result = Gate.step(resting, { now: 1, status: "active", usage: 0.1, watched: true, autosuspendMs: 0 });
        compare(result.phase, "live");
    }

    function test_watchedResetsTheIdleTimerWhileLive() {
        var idling = { phase: "live", since: 0, quietSince: 1000, holdMs: 10000 };
        var result = Gate.step(idling, { now: 5000, status: "active", usage: 0.1, watched: true, autosuspendMs: 0 });
        compare(result.phase, "live");
        compare(result.quietSince, -1); // being watched cancels the idle countdown
    }
}
