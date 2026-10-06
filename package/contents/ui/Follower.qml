// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

// Eases `shown` to `target` as a critically damped spring, which never
// passes the target it is heading for. A new target while it moves keeps
// the position and as much of the speed as can't carry it past the new
// target, so the motion bends rather than starting over. Frames run only
// while it moves, each taking the exact step for the time since the last,
// so a late frame doesn't change the curve. Within 1 % of a change after
// `settle` milliseconds, half-way at a quarter of that.
QtObject {
    id: follower

    property real target: 0
    // Bound to `target` while it can't move; see kick().
    property real shown: target
    // Milliseconds; 0 follows at once.
    property real settle: 0
    // How near counts as there, in units of target: it comes to rest once
    // this near and too slow to carry itself further than this. What draws
    // it sets what a quarter of a pixel is worth.
    property real precision: 0.05
    // Off follows at once, as while a reset animation draws the ring.
    property bool enabled: true
    // In units of target per second.
    property real velocity: 0
    readonly property bool moving: frames.running

    // While it can't move, `shown` stays bound to `target`, and a new target
    // writes nothing: onTargetChanged can run while a binding that reads
    // both is evaluating (RingGauge.drawnLevel), and a write then would be
    // a binding loop. Only a change of `settle` or `enabled`, or completion,
    // binds it again or frees it to move.
    property bool bound: true

    function kick(release) {
        if (!enabled || !(settle > 0)) {
            frames.stop();
            velocity = 0;
            if (!bound) {
                bound = true;
                shown = Qt.binding(() => target);
            }
            return;
        }
        if (bound) {
            if (!release) {
                return;
            }
            bound = false;
            shown = target;
        }
        if (shown !== target || velocity !== 0) {
            frames.start();
        }
    }

    function omega() {
        // (1 + ωt)e^(-ωt) is 1 % at ωt = 6.64.
        return 6.64 / (settle / 1000);
    }

    // x'' + 2ωx' + ω²x = 0, solved exactly over dt seconds.
    function advance(dt) {
        const w = omega();
        const x = shown - target;
        const e = Math.exp(-w * dt);
        const c = (velocity + w * x) * dt;
        const nx = (x + c) * e;
        const nv = (velocity - w * c) * e;
        // A critically damped follower at speed v carries on by less than
        // v / ω.
        if (Math.abs(nx) < precision && Math.abs(nv) < w * precision) {
            frames.stop();
            shown = target;
            velocity = 0;
        } else {
            shown = target + nx;
            velocity = nv;
        }
    }

    // Heading for the new target faster than ω times the distance would
    // carry it past: 62 to 30, then 45 50 ms later, would dip to 42. The
    // excess speed goes; the position stays where it is.
    onTargetChanged: {
        const x = shown - target;
        if (!bound && x * velocity < 0 && Math.abs(velocity) > omega() * Math.abs(x)) {
            velocity = -omega() * x;
        }
        kick(false);
    }
    onSettleChanged: kick(true)
    onEnabledChanged: kick(true)
    Component.onCompleted: kick(true)

    property FrameAnimation frames: FrameAnimation {
        onTriggered: follower.advance(frameTime)
    }
}
