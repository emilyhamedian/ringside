// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import org.kde.kirigami as Kirigami
import "code/format.js" as Format

// A progress ring filling clockwise from twelve o'clock, with an optional
// thinner, dimmer ring inside it for a second reading: the integrated GPU
// under the discrete one, or a model's limit inside a weekly one. NaN draws
// the track alone. Each arc moves to a new reading over `settle`, and turns
// amber as it passes 75 % and red as it passes 90 % of its own reading. An
// inner ring that comes fades its track in, then draws its arc in; one that
// goes unwinds its arc, then fades its track out. Children sit in the
// middle, over the rings.
// Assistive technology sees a progress bar from 0 to 100 with the outer
// reading as its value; the caller gives it a name.
Item {
    id: gauge

    property real value: NaN
    property real innerValue: NaN
    property bool inner: false
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
    readonly property bool hasValue: Number.isFinite(value)
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

    onInnerChanged: shift()
    onHasValueChanged: shift()
    onStillChanged: {
        if (shifting) {
            Qt.callLater(endShift);
        }
    }
    default property alias centre: face.data

    // The inner ring is held while it comes or until its arc has unwound out
    // of sight, and its track is shown, 0 to 1, fading in or out as it is
    // held or let go; its arc is drawn once the track is in. The arc is
    // watched only when the arcs move: at Plasma's Instant speed it follows
    // the reading at once, and these would then depend on each other in a
    // circle.
    readonly property bool innerHeld: inner || settle > 0 && innerArc.drawn
    property real innerShown: innerHeld ? 1 : 0
    readonly property bool innerDrawn: inner && innerShown === 1

    Behavior on innerShown {
        enabled: gauge.settle > 0
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutCubic }
    }

    // How far the outer ring reaches from the middle.
    readonly property real reach: outer.radius + strokeWidth / 2
    // The clear width in the middle, a pixel in from the innermost ring, for
    // a name or mark there: inside the inner ring while it is held, so a
    // name makes room as it comes and takes it back as the track goes.
    readonly property real centreWidth: Math.max(0, 2 * ((innerHeld ? innerRadius - innerStrokeWidth / 2
                                                                    : outer.radius - strokeWidth / 2) - 1))
    // The readings' colours, for the readings beside the ring.
    readonly property color outerTone: tone(Math.max(Format.level(value), minimumLevel))
    readonly property color innerTone: tone(Format.level(innerValue))
    // The outer reading as drawn, for a number in the middle that counts
    // with the arc.
    readonly property real drawnValue: outerFollower.shown
    // The levels of the readings as drawn, so an arc changes colour as it
    // passes 75 or 90 % rather than when the reading arrives. The arcs head
    // for the whole percent a reading prints, so its fraction is added back:
    // at rest this is the reading's own level, and a ring at 74.6 % stays
    // below amber as the reading beside it does.
    readonly property int drawnLevel: Math.max(Format.level(drawn(outerFollower, value)), minimumLevel)
    readonly property int drawnInnerLevel: Format.level(drawn(innerFollower, innerValue))

    function drawn(follower, reading) {
        const percent = clamped(reading);
        return Number.isFinite(reading) ? follower.shown + percent - Math.round(percent) : NaN;
    }

    function tone(level) {
        return level === 2 ? Kirigami.Theme.negativeTextColor
             : level === 1 ? Kirigami.Theme.neutralTextColor
             : color;
    }

    function innerColor(level) {
        return Qt.alpha(tone(level), 0.55 * color.a);
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
        if (innerReset && inner) {
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
        target: Math.round(gauge.clamped(gauge.value))
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
    Accessible.description: Number.isFinite(value) ? i18nc("@info:status a percentage", "%1%", Math.round(value))
                                                   : i18nc("@info:status no reading", "unavailable")

    Item {
        id: face
        anchors.fill: parent

        SequentialAnimation on opacity {
            running: gauge.pulsing
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.5; duration: 1000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 1000; easing.type: Easing.InOutSine }
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
            trackColor: Qt.alpha(gauge.color, 0.16 * gauge.color.a)
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
            color: outer.color
            font.family: Kirigami.Theme.defaultFont.family
            font.features: ({ "tnum": 1 })
            font.pixelSize: Math.round(gauge.width * gauge.textScale)
            textFormat: Text.PlainText
            // The gauge's own description reads it out.
            Accessible.ignored: true
        }
    }
}
