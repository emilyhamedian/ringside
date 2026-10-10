// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/style.js" as Style

// A progress ring filling clockwise from twelve o'clock, with an optional
// thinner, dimmer ring inside it for a second reading: the integrated GPU
// under the discrete one, or a model's limit inside a weekly one. NaN draws
// the track alone. Each arc moves to a new reading over `settle`, and turns
// amber as it passes 75 % and red as it passes 90 % of its own reading. An
// inner ring that comes fades its track in, then draws its arc in; one that
// goes unwinds its arc, then fades its track out. Children sit in the
// middle, over the rings. A ring can also show a reading that may be out of
// date, in grey and broken into segments, or none at all, struck through, or
// wait for its first.
// Assistive technology sees a progress bar from 0 to 100 with the outer
// reading as its value; the caller gives it a name.
Item {
    id: gauge

    property real value: NaN
    property real innerValue: NaN
    property bool inner: false
    // The strip's hidden animation, which a panel ring plays; null elsewhere.
    property Egg egg: null
    // The colour below the alert levels.
    property color color: Kirigami.Theme.textColor
    // Raises the ring's level, for a hot temperature the panel has no room
    // to show.
    property int minimumLevel: 0
    // About a thirteenth of the ring, in half pixels, for the panel's rings;
    // the popups set their own.
    property real strokeWidth: Math.max(2, Math.round(width / 6.5) / 2)
    property real innerStrokeWidth: Math.max(1.5, Math.round(strokeWidth * 2 / 3 * 2) / 2)
    property real innerRadius: outer.radius - strokeWidth / 2 - innerStrokeWidth / 2 - Math.max(1, strokeWidth / 2)
    // Shown in the middle of a single ring large enough to read it.
    property string text: ""
    property real textScale: 0.33
    // Breathes, as a Claude or Codex ring does close to its limit.
    property bool pulsing: false
    // No reading to show, as for a Claude or Codex ring whose checks have
    // failed for a while: the arcs unwind to the bare track, the inner
    // track goes, anything in the middle greys out, and as the arcs reach
    // the end of their way down a stroke draws across the ring from its
    // bottom left to its top right, as on a cancelled sign. Recovery runs
    // it backwards.
    property bool cancelled: false
    // The stroke, 0 to 1 as drawn from the bottom left.
    property real struck: 0
    // The readings go as the stroke comes and return as it goes, so a
    // readout beside the ring that follows `dashed` changes with it.
    readonly property bool dashed: struck > 0.25
    readonly property bool held: cancelled || dashed
    readonly property real outerValue: held ? NaN : value
    readonly property bool innerOn: inner && !held
    // The reading kept, drawn in grey with no alert colours and the middle
    // greyed, as one that may be out of date. A ring struck through is grey
    // too, so arcs unwinding from a reading that is gone carry no colour,
    // and a grey ring stays grey as it is struck.
    property bool stale: false
    property real greyed: stale || held ? 1 : 0
    Behavior on greyed {
        enabled: gauge.settle > 0
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutCubic }
    }
    // An out of date reading also breaks the rings into eight segments, so a
    // full grey ring doesn't read as a greyed-out mark; the gaps open and
    // close as the grey comes and goes. A struck ring is whole again.
    property real gap: stale ? 0.2 : 0
    Behavior on gap {
        enabled: gauge.settle > 0
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutCubic }
    }
    // Waiting for a first reading, as a Claude or Codex ring while its first
    // check runs: the track is a ring of still dots and the middle is dimmed.
    // After a second a lit dot travels round them, at a pace of its own
    // whatever the animation speed, as Plasma's busy indicator turns, so a
    // quick reply only fills the ring in. It stops after 30 s, so a helper
    // that hangs doesn't keep the panel redrawing, and while the window is
    // hidden, and at Instant it never moves. A reading fills the track in
    // over the dots from twelve as the arc draws in on top; a failure fades
    // the dots into the track where they are, and then the stroke draws.
    property bool loading: false
    // How much of the track is drawn, clockwise from twelve, with the dots
    // ahead of it, and how strong the dots are. With none of it drawn, the
    // track fades in whole as the dots fade out.
    property real sweep: 1
    property real dotsShown: 0
    // A second has passed while loading, or 30 s.
    property bool waited: false
    property bool capped: false
    readonly property bool moving: loading && waited && !capped && settle > 0 && visible
        && Window.visibility !== Window.Hidden
    // The lit dot's strength: in over longDuration, out over shortDuration,
    // so it is gone before the track has filled in.
    property real motion: 0
    onMovingChanged: {
        motionFade.to = moving ? 1 : 0;
        motionFade.duration = moving ? Kirigami.Units.longDuration : Kirigami.Units.shortDuration;
        motionFade.restart();
    }

    NumberAnimation {
        id: motionFade
        target: gauge
        property: "motion"
        easing.type: Easing.InOutQuad
    }
    // The middle dims while the dots show and brightens as the track fills
    // in; a failure keeps it dim for the stroke.
    readonly property real waitDim: cancelled ? (dotsShown > 0 ? 1 : 0) : dotsShown * (1 - sweep)

    function settleLoading() {
        fillIn.stop();
        fadeIn.stop();
        if (loading) {
            sweep = 0;
            dotsShown = 1;
            waited = false;
            capped = false;
        } else if (dotsShown > 0 && settle > 0) {
            (cancelled ? fadeIn : fillIn).start();
        } else {
            sweep = 1;
            dotsShown = 0;
        }
    }

    // After the readings have caught up, so a failure is known as one.
    onLoadingChanged: Qt.callLater(settleLoading)

    SequentialAnimation {
        id: fillIn
        NumberAnimation { target: gauge; property: "sweep"; to: 1; duration: Kirigami.Units.veryLongDuration; easing.type: Easing.InOutCubic }
        PropertyAction { target: gauge; property: "dotsShown"; value: 0 }
    }

    SequentialAnimation {
        id: fadeIn
        NumberAnimation { target: gauge; property: "dotsShown"; to: 0; duration: Kirigami.Units.longDuration; easing.type: Easing.InOutCubic }
        PropertyAction { target: gauge; property: "sweep"; value: 1 }
    }

    Timer {
        interval: 1000
        running: gauge.loading && !gauge.waited
        onTriggered: gauge.waited = true
    }

    Timer {
        interval: 30000
        running: gauge.loading && !gauge.capped
        onTriggered: gauge.capped = true
    }

    // How often the readings come, where that is often enough for the
    // rings to settle within half of it and be still before the next one;
    // 0 for readings minutes apart.
    property int interval: 0
    // How long the arcs take to reach a new reading. They follow it
    // critically damped, so they never pass it, and a reading that arrives
    // while they move bends the motion rather than starting it over. 0
    // moves them at once, as at Plasma's Instant speed, where Kirigami's
    // durations are a millisecond or two rather than none.
    property real settle: Kirigami.Units.longDuration > 1
        ? Math.min(Kirigami.Units.veryLongDuration, interval > 0 ? interval / 2 : Infinity) : 0
    // An inner ring that comes or goes, or an outer reading that comes from
    // none or goes to none, is a change of rings rather than of readings:
    // both arcs move at the pace of the inner track's fade until they and
    // the track are still, as when a GPU sleeps and the ring turns to the
    // other one.
    property bool shifting: false
    readonly property real arcSettle: shifting ? Math.min(Kirigami.Units.longDuration, settle) : settle
    readonly property bool hasValue: Number.isFinite(outerValue)
    readonly property bool still: !outerFollower.moving && !innerFollower.moving && innerShown === (innerHeld ? 1 : 0)

    // Checked once the bindings have caught up with the change: the track's
    // fade can end a frame before the inner arc starts to draw in.
    function endShift() {
        if (still) {
            shifting = false;
        }
    }

    function shift() {
        shifting = settle > 0;
        Qt.callLater(endShift);
    }

    onInnerOnChanged: shift()
    onHasValueChanged: shift()
    onStillChanged: {
        if (shifting) {
            Qt.callLater(endShift);
        }
    }
    default property alias centre: middle.data

    // The inner ring is held while it comes or until its arc has unwound out
    // of sight, and its track is shown, 0 to 1, fading in or out as it is
    // held or let go; its arc is drawn once the track is in. The arc is
    // watched only when the arcs move: at Plasma's Instant speed it follows
    // the reading at once, and these would then depend on each other in a
    // circle.
    readonly property bool innerHeld: innerOn || settle > 0 && innerArc.drawn
    property real innerShown: innerHeld ? 1 : 0
    readonly property bool innerDrawn: innerOn && innerShown === 1

    // The stroke draws on as the arcs reach the end of their way down
    // (half-way through their motion they have a sixth of it left), and
    // comes off a little faster on recovery, the readings returning as it
    // goes. Set here rather than bound, since the arcs wait on the stroke.
    function restrike() {
        const to = cancelled ? 1 : 0;
        if (!(settle > 0)) {
            strikeMotion.stop();
            struck = to;
            return;
        }
        if (strikeMotion.running ? strikeRun.to === to : struck === to) {
            return;
        }
        // It waits for the dots to fade, or for the arcs to near the end of
        // their way down.
        strikePause.duration = cancelled && dotsShown > 0 ? Kirigami.Units.longDuration
            : cancelled && (outerFollower.moving || innerFollower.moving) ? Kirigami.Units.longDuration / 2 : 0;
        strikeRun.to = to;
        strikeRun.duration = cancelled ? Kirigami.Units.longDuration : Kirigami.Units.longDuration * 3 / 4;
        strikeRun.easing.type = cancelled ? Easing.OutCubic : Easing.InCubic;
        strikeMotion.restart();
    }

    // After the followers have taken the change, so the arcs count as moving.
    onCancelledChanged: Qt.callLater(restrike)
    onSettleChanged: restrike()
    // A ring that starts cancelled, as a popup opening on a failed check,
    // starts struck, rather than drawing the stroke from a change of
    // `settle` while it was being made; one that starts loading starts with
    // its dots.
    Component.onCompleted: {
        strikeMotion.stop();
        struck = cancelled ? 1 : 0;
        settleLoading();
    }

    SequentialAnimation {
        id: strikeMotion
        PauseAnimation { id: strikePause; duration: 0 }
        NumberAnimation { id: strikeRun; target: gauge; property: "struck"; duration: Kirigami.Units.longDuration }
    }

    Behavior on innerShown {
        enabled: gauge.settle > 0
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutCubic }
    }

    // How far the outer ring reaches from the middle.
    readonly property real reach: outer.radius + strokeWidth / 2
    // The clear width in the middle, a pixel in from the innermost ring, for
    // a name or mark there: inside the inner ring while it is held, so a
    // name makes room as it comes and takes it back as the track goes. A
    // struck ring keeps the room, so its mark stays the size it was.
    readonly property real centreWidth: Math.max(0, 2 * ((inner || innerHeld ? innerRadius - innerStrokeWidth / 2
                                                                    : outer.radius - strokeWidth / 2) - 1))
    // The readings' colours, for the readings beside the ring.
    readonly property color outerTone: tone(Math.max(Format.level(outerValue), minimumLevel))
    readonly property color innerTone: tone(Format.level(innerValue))
    // The outer reading as drawn, for a number in the middle that counts
    // with the arc.
    readonly property real drawnValue: outerFollower.shown
    // The levels of the readings as drawn, so an arc changes colour as it
    // passes 75 or 90 % rather than when the reading arrives. The arcs head
    // for the whole percent a reading prints, so its fraction is added back:
    // at rest this is the reading's own level, and a ring at 74.6 % stays
    // below amber as the reading beside it does.
    readonly property int drawnLevel: Math.max(Format.level(drawn(outerFollower, outerValue)), minimumLevel)
    readonly property int drawnInnerLevel: Format.level(drawn(innerFollower, innerValue))

    function drawn(follower, reading) {
        const percent = clamped(reading);
        return Number.isFinite(reading) ? follower.shown + percent - Math.round(percent) : NaN;
    }

    function tone(level) {
        const live = level === 2 ? Kirigami.Theme.negativeTextColor
                   : level === 1 ? Kirigami.Theme.neutralTextColor
                   : color;
        return greyed > 0 ? outer.mix(live, Qt.alpha(color, 0.42 * color.a), greyed) : live;
    }

    function innerColor(level) {
        return Qt.alpha(tone(level), 0.55 * color.a);
    }

    // A circle as SVG path data.
    function circle(x, y, r) {
        return "M " + (x - r) + " " + y + " A " + r + " " + r + " 0 1 0 " + (x + r) + " " + y
             + " A " + r + " " + r + " 0 1 0 " + (x - r) + " " + y + " Z ";
    }

    function clamped(percent) {
        return Number.isFinite(percent) ? Math.max(0, Math.min(100, percent)) : 0;
    }

    // A length along an arc of this radius, in percent.
    function along(pixels, radius) {
        return 100 * pixels / (2 * Math.PI * Math.max(1, radius));
    }

    // Plays the windows that just started over, each { from, early } or null;
    // see code/reset.js.
    function playResets(outerReset, innerReset) {
        if (outerReset) {
            outer.playReset(clamped(outerReset.from), tone(Math.max(Format.level(outerReset.from), minimumLevel)),
                            outerReset.early);
        }
        if (innerReset && innerOn) {
            innerArc.playReset(clamped(innerReset.from), innerColor(Format.level(innerReset.from)),
                               innerReset.early);
        }
    }

    // Each arc follows the whole percent its reading prints, so a reading
    // that doesn't change the number doesn't move the arc. A reset animation
    // draws the arc itself, and the follower keeps to the reading meanwhile;
    // a hidden ring keeps to it too. An arc within a quarter of a pixel of
    // its reading comes to rest there.
    Follower {
        id: outerFollower
        target: Math.round(gauge.clamped(gauge.outerValue))
        settle: gauge.visible ? gauge.arcSettle : 0
        precision: gauge.along(0.25, outer.radius)
        enabled: !outer.animating
    }

    Follower {
        id: innerFollower
        target: gauge.innerDrawn ? Math.round(gauge.clamped(gauge.innerValue)) : 0
        settle: gauge.visible ? gauge.arcSettle : 0
        precision: gauge.along(0.25, gauge.innerRadius)
        enabled: gauge.innerShown > 0 && !innerArc.animating
    }

    // Qt reports these as the progress bar's range.
    readonly property real from: 0
    readonly property real to: 100

    // The height of the figures in the middle text, to set it by them.
    // capitalHeight needs Qt 6.9; the ink of "0" stands in before that.
    readonly property real figureHeight: percentMetrics.capitalHeight ?? figureSample.tightBoundingRect.height // qmllint disable missing-property

    FontMetrics {
        id: percentMetrics
        font: percent.font
    }

    TextMetrics {
        id: figureSample
        font: percent.font
        text: "0"
    }

    implicitWidth: 30
    implicitHeight: implicitWidth

    Accessible.role: Accessible.ProgressBar
    Accessible.description: hasValue ? i18nc("@info:status a percentage", "%1%", Math.round(value))
                          : loading ? i18nc("@info:status waiting for a first reading", "checking")
                                    : i18nc("@info:status no reading", "unavailable")

    Item {
        id: face
        anchors.fill: parent

        SequentialAnimation on opacity {
            running: gauge.pulsing && !gauge.cancelled && !gauge.stale
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.5; duration: 1000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 1000; easing.type: Easing.InOutSine }
        }

        // The waiting ring's dots, a stroke across, ahead of the track as it
        // fills in: filled circles in one path, rather than a dashed stroke
        // whose zero-length dashes each renderer draws its own way.
        Shape {
            id: dots
            anchors.fill: parent
            visible: gauge.dotsShown > 0
            preferredRendererType: Shape.CurveRenderer
            // About two and a half strokes apart, a multiple of four of them
            // so the ring keeps its quarters.
            readonly property int count: Math.max(8, Math.round(2 * Math.PI * outer.radius / (2.5 * gauge.strokeWidth) / 4) * 4)
            // The dots the filling track has reached, which go as it does.
            readonly property int covered: gauge.sweep > 0
                ? Math.min(count, Math.ceil(count * (gauge.sweep + gauge.strokeWidth / 2 / (2 * Math.PI * outer.radius)))) : 0

            ShapePath {
                fillColor: Qt.alpha(gauge.color, 0.36 * gauge.color.a * gauge.dotsShown)
                strokeColor: "transparent"

                PathSvg {
                    path: {
                        let d = "";
                        for (let i = dots.covered; i < dots.count; ++i) {
                            const angle = 2 * Math.PI * i / dots.count;
                            d += gauge.circle(dots.width / 2 + outer.radius * Math.sin(angle),
                                              dots.height / 2 - outer.radius * Math.cos(angle), gauge.strokeWidth / 2);
                        }
                        return d;
                    }
                }
            }
        }

        // The lit dot, a little larger than the others, turned round the
        // middle by the render thread as Plasma's busy indicator turns, and
        // started where the clock says, so every ring is in step.
        Shape {
            id: bead
            anchors.fill: parent
            visible: gauge.motion > 0
            opacity: gauge.motion
            preferredRendererType: Shape.CurveRenderer
            readonly property bool turning: gauge.moving
            onTurningChanged: {
                if (turning) {
                    const start = Date.now() % beadTurn.duration / beadTurn.duration * 360;
                    beadTurn.from = start;
                    beadTurn.to = start + 360;
                }
                beadTurn.running = turning;
            }

            RotationAnimator on rotation {
                id: beadTurn
                duration: 3200
                loops: Animation.Infinite
                running: false
            }

            ShapePath {
                fillColor: Qt.alpha(gauge.color, 0.62 * gauge.color.a)
                strokeColor: "transparent"

                PathSvg {
                    path: gauge.circle(bead.width / 2, bead.height / 2 - outer.radius, gauge.strokeWidth * 1.3 / 2)
                }
            }
        }

        // The arcs fill the gauge rather than centring in it: anchors.centerIn
        // rounds an odd-sized item's centre to a whole pixel, which set a
        // 33 px ring half a pixel up and left of a 34 px gauge's middle, and
        // the two rings off each other.
        RingArc {
            id: outer
            anchors.fill: parent
            radius: (Math.min(gauge.width, gauge.height) - gauge.strokeWidth) / 2 - 0.5
            strokeWidth: gauge.strokeWidth
            percent: outerFollower.shown
            shortest: gauge.hasValue ? 0 : gauge.along(gauge.strokeWidth, radius)
            color: gauge.tone(gauge.drawnLevel)
            // The track keeps the base colour whatever the level.
            trackColor: Qt.alpha(gauge.color, 0.16 * gauge.color.a * (gauge.sweep > 0 ? 1 : 1 - gauge.dotsShown))
            trackSweep: gauge.sweep > 0 ? gauge.sweep : 1
            gap: gauge.gap
        }

        RingArc {
            id: innerArc
            anchors.fill: parent
            visible: gauge.innerShown > 0
            opacity: gauge.innerShown
            radius: gauge.innerRadius
            strokeWidth: gauge.innerStrokeWidth
            percent: innerFollower.shown
            shortest: gauge.innerDrawn && Number.isFinite(gauge.innerValue) ? 0 : gauge.along(gauge.innerStrokeWidth, radius)
            color: gauge.innerColor(gauge.drawnInnerLevel)
            trackColor: Qt.alpha(gauge.color, 0.22 * 0.55 * gauge.color.a)
            gap: gauge.gap
        }

        // The name or mark, greyed out further while the ring is grey or
        // waits, and fainter still once it is struck, so the stroke in the
        // track's grey reads across it unbroken.
        Item {
            id: middle
            anchors.fill: parent
            opacity: 1 - Math.max(0.85 * gauge.struck, 0.6 * Math.max(gauge.greyed, gauge.waitDim))
        }

        // Draws the hidden animation over the arcs while it plays; see
        // Egg.qml for what it may change and how it gives it back.
        Egg.Ring {
            anchors.fill: parent
            clock: gauge.egg
            outerRing: outer
            innerRing: innerArc
            innerOn: gauge.innerOn
            innerShown: gauge.innerShown
        }

        // The cancelling stroke, from the bottom left of the track to its
        // top right, in the track's own colour. Its round caps end on the
        // track's inner edge, so it meets the ring and stays inside it
        // without the two translucent strokes overlapping.
        Shape {
            id: strike
            anchors.fill: parent
            visible: gauge.struck > 0
            // Its round caps would start it as a dot, so it starts as a
            // short stroke fading in.
            opacity: Math.min(1, gauge.struck * 4)
            preferredRendererType: Shape.CurveRenderer
            readonly property real lineWidth: gauge.strokeWidth * 0.8
            readonly property real half: (outer.radius - gauge.strokeWidth / 2 - lineWidth / 2) / Math.SQRT2
            readonly property real drawn: 0.15 + 0.85 * gauge.struck

            ShapePath {
                fillColor: "transparent"
                strokeColor: outer.trackColor
                strokeWidth: strike.lineWidth
                capStyle: ShapePath.RoundCap
                startX: strike.width / 2 - strike.half
                startY: strike.height / 2 + strike.half
                PathLine {
                    x: strike.width / 2 - strike.half + 2 * strike.half * strike.drawn
                    y: strike.height / 2 + strike.half - 2 * strike.half * strike.drawn
                }
            }
        }

        // Set by its figures' height and its advance, not anchors.centerIn:
        // that rounds an odd width to a whole pixel and centres the line
        // box, which is taller below the baseline than above the figures.
        // The theme's sans with figures of one width, like the panel's
        // readings, so a reading keeps its place as it changes.
        Text {
            id: percent
            x: (parent.width - width) / 2
            y: parent.height / 2 + gauge.figureHeight / 2 - baselineOffset
            visible: gauge.text !== "" && !gauge.inner && gauge.width >= 24
            text: gauge.text
            // A grey reading's number in the theme's dim text colour, which
            // keeps text legible, rather than the arc's fainter grey.
            color: outer.mix(outer.color, Style.dim(gauge.color), gauge.greyed)
            font.family: Kirigami.Theme.defaultFont.family
            font.features: ({ "tnum": 1 })
            font.pixelSize: Math.round(gauge.width * gauge.textScale)
            textFormat: Text.PlainText
            // The gauge's own description reads it out.
            Accessible.ignored: true
        }
    }
}
