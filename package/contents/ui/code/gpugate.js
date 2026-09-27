.pragma library

// When to read a discrete GPU that the kernel can power down.
//
// Subscribing to a GPU's sensors keeps it awake: ksystemstats reads it every
// 500 ms, and on amdgpu those reads hold off runtime suspend for as long as
// they continue; the NVIDIA backend polls nvidia-smi, which wakes the GPU
// too. So the widget only subscribes while the GPU is awake anyway, and when
// it has sat idle for a while it lets go, giving the GPU its chance to
// suspend. If the GPU is still awake once the autosuspend delay has passed,
// something else is holding it (a game, a display on its outputs), so the
// widget reads it again and waits twice as long before the next try.
//
//   asleep   suspended; not subscribed
//   live     awake; subscribed
//   resting  awake; unsubscribed while waiting to see whether it suspends
//
// Nothing here wakes a GPU: asleep only turns live on a status that says the
// GPU is awake, and resting only on a status read after the GPU had its
// chance to suspend. An open popup keeps a live GPU live but never cuts
// resting short, since that could subscribe a GPU that suspended moments ago.

const BASE_HOLD_MS = 10000;
const MAX_HOLD_MS = 300000;
const IDLE_PERCENT = 1;
// The NVIDIA driver publishes no autosuspend delay, and takes up to about
// ten seconds to power the GPU down once it is idle.
const NVIDIA_DELAY_MS = 11000;

function initial() {
    return { phase: "asleep", since: 0, quietSince: -1, holdMs: BASE_HOLD_MS };
}

function sleeping(status) {
    return status === "suspended" || status === "suspending";
}

// How long after letting go a status must have been read to prove the GPU
// stayed awake: its autosuspend delay (plus the kernel's timer slack) and
// one poll.
function probeMs(input) {
    const delay = input.autosuspendMs > 0 ? input.autosuspendMs : input.vendor === "10de" ? NVIDIA_DELAY_MS : 0;
    return Math.max(delay, 2000) + 4000;
}

// input: { now, status (runtime_status text), statusAt (when that status was
// read), usage (percent, or undefined while unread), watched (its popup is
// open), autosuspendMs, vendor }
function step(state, input) {
    const now = input.now;
    if (sleeping(input.status) || !input.status) {
        return state.phase === "asleep" && state.holdMs === BASE_HOLD_MS ? state
             : { phase: "asleep", since: now, quietSince: -1, holdMs: BASE_HOLD_MS };
    }

    if (state.phase === "asleep") {
        return { phase: "live", since: now, quietSince: -1, holdMs: state.holdMs };
    }

    if (state.phase === "resting") {
        if (input.statusAt >= state.since + probeMs(input)) {
            return { phase: "live", since: now, quietSince: -1,
                     holdMs: Math.min(state.holdMs * 2, MAX_HOLD_MS) };
        }
        return state;
    }

    // live
    const quiet = typeof input.usage === "number" && input.usage < IDLE_PERCENT;
    if (input.watched || !quiet) {
        return state.quietSince === -1 ? state : Object.assign({}, state, { quietSince: -1 });
    }
    if (state.quietSince === -1) {
        return Object.assign({}, state, { quietSince: now });
    }
    if (now - state.quietSince >= state.holdMs) {
        return { phase: "resting", since: now, quietSince: -1, holdMs: state.holdMs };
    }
    return state;
}
