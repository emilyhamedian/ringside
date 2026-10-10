// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/pace.js" as Pace
import "../code/reset.js" as Reset
import "../code/style.js" as Style

// A weekly limit's use through its window: time from the window's start to
// its reset across, 0 to 100 % up, between a faint floor and the 100 % rule
// the system graphs share (LimitRule), with a tick on the floor at each
// midnight and an edge at the reset. The main series is filled; a second
// one, the model limit on the inner ring, is dashed, as in Graph. The line
// ends at the last poll, so the empty stretch to its right is the time
// left; only when the last poll is hours old does a marker say where now
// is. While checks fail, the marker shows once the gap is wide enough to
// see, and the gap is hatched. The limit the pace sentence under the bars names, when it is on
// course to run out before the reset, gets a dashed line from the rule to
// the floor at the moment it runs out, with the sentence's time under the
// floor, in the colour of that limit's level as its bar has it.
// A poll that adds a reading draws the new stretch of line on from the old
// end, and a run-out it brings fades in once the line has landed. A run-out
// that goes fades out where and as it was, the marker for now and a first
// reading's dot fade in and out, and a week that starts over while the
// popup is open fades out the last week's line, run-out and marker. Any
// other change is drawn at once.
Item {
    id: graph

    // Time runs left to right in every language.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    // A window as the helper reports it: resetsAt, windowSeconds, percent and
    // a history of [epoch seconds, percent], oldest first.
    property var window: null
    // Another window, drawn dashed on this window's time axis.
    property var secondWindow: null
    property real nowMs: Date.now()
    // When the readings were last fetched, in epoch seconds.
    property real pollAt: NaN
    // The last check failed: the stretch from the last reading to now is
    // hatched, as unknown, and the marker for now shows whatever its age.
    property bool failed: false
    // The readings may be out of date: the run-out carries no alert colour.
    property bool grey: false
    property color color: Kirigami.Theme.textColor
    property real fillOpacity: 0.15
    // The series whose run-out is drawn, "main" or "second", or "" for none:
    // the limit the popup's pace sentence names, so the two agree.
    property string projected: ""
    // When it runs out, as the pace sentence words it: "Fri 7:20 AM".
    property string runOutText: ""
    // A new stretch of line draws on over twice this, and the rest fades
    // over it or half of it: Kirigami's long duration, or 0 at Plasma's
    // Instant speed, where everything is drawn at once.
    property int duration: Kirigami.Units.longDuration > 1 ? Kirigami.Units.longDuration : 0

    // The time axis, in epoch seconds.
    readonly property real end: window && Number.isFinite(window.resetsAt) ? window.resetsAt : NaN
    readonly property real start: window ? end - window.windowSeconds : NaN
    readonly property bool placed: end > start

    // The plot, over the run-out's time, which takes room only while there
    // is a run-out, as the pace sentence does.
    readonly property real plotHeight: Math.round(Kirigami.Units.gridUnit * 3.2)
    readonly property real floorY: plotHeight - 1
    readonly property bool timeShown: runOutOpacity > 0 || ghostRunOutX >= 0 && ghostOpacity > 0

    readonly property var mainPoints: points(window)
    readonly property var secondPoints: points(secondWindow)
    // When that limit runs out, in epoch seconds, while the pace says it
    // will before the reset, as the popup's sentence reads it; NaN
    // otherwise.
    readonly property real runOutAt: projected === "main" ? runOut(mainPoints, window)
                                   : projected === "second" ? runOut(secondPoints, secondWindow)
                                   : NaN

    // The windows as last drawn, to tell a poll that adds a reading from
    // any other change.
    property var seenMain: null
    property var seenSecond: null
    // Where each series' new end draws on from, and how far it has come:
    // linearly, so the run-out can wait out the rest, and eased.
    property var mainFrom: null
    property var secondFrom: null
    property real drawClock: 1
    readonly property real drawIn: drawClock < 0.5 ? 4 * drawClock ** 3 : 1 - (-2 * drawClock + 2) ** 3 / 2
    readonly property var mainDrawn: drawnSeries(mainPoints, mainFrom)
    readonly property var secondDrawn: drawnSeries(secondPoints, secondFrom)
    // The run-out as drawn: kept, so that it fades out where it was once
    // the pace clears, and eases along the axis when a poll moves it.
    property bool runOutShown: false
    property real runOutOpacity: 0
    property real shownRunOutAt: NaN
    property string shownRunOutText: ""
    // Its limit's level, 0 to 2, as its bar and ring show it.
    property int shownRunOutLevel: 0
    readonly property real runOutX: Math.round(Math.max(0, Math.min(width - 1, xAt(shownRunOutAt))))
    // The marker for now as drawn, kept where it was as it fades out.
    property bool markerShown: stale
    property real markerShownX: markerX
    // Last week, fading out under the new one: its lines, and its run-out
    // and marker if it had them.
    property var ghostMain: []
    property var ghostSecond: []
    property real ghostRunOutX: -1
    property string ghostRunOutText: ""
    property int ghostRunOutLevel: 0
    property real ghostMarkerX: -1
    property real ghostOpacity: 0
    // Where a first reading's dot was, for it to fade out there.
    property point mainDotAt
    property point secondDotAt

    Behavior on shownRunOutAt {
        enabled: graph.duration > 0 && graph.runOutOpacity > 0
        NumberAnimation { duration: graph.duration; easing.type: Easing.OutCubic }
    }

    function drawnSeries(series, from) {
        if (drawClock >= 1 || !from || series.length < 2) {
            return series;
        }
        const end = series[series.length - 1];
        return series.slice(0, -1).concat([Qt.point(from.x + (end.x - from.x) * drawIn, from.y + (end.y - from.y) * drawIn)]);
    }

    function seen(source) {
        return source ? { resetsAt: source.resetsAt, windowSeconds: source.windowSeconds, history: Array.from(source.history ?? []) }
                      : null;
    }

    // "same", "grew" by one reading in the same window, or "other". A reset
    // time that jitters between reports is the same window, as in reset.js.
    function change(was, source) {
        if (!was || !source) {
            return !was && !source ? "same" : "other";
        }
        const history = Array.from(source.history ?? []);
        const kept = Math.abs(source.resetsAt - was.resetsAt) <= Reset.MOVED_BY
            && was.history.every((p, i) => i < history.length && p[0] === history[i][0] && p[1] === history[i][1]);
        return !kept ? "other" : history.length === was.history.length ? "same"
             : history.length === was.history.length + 1 ? "grew" : "other";
    }

    // A window has changed. Each series that took one more reading draws its
    // new stretch on from its last reading, the rest of a stretch still
    // drawing on put in at once so that the line never doubles back, and
    // one still drawing on carries on from where its end is; anything else
    // stops the drawing.
    function poll() {
        const main = change(seenMain, window);
        const second = change(seenSecond, secondWindow);
        if (duration > 0 && seenMain && window && window.resetsAt > seenMain.resetsAt + Reset.MOVED_BY && seenMain.history.length > 0) {
            const end = seenMain.resetsAt;
            const begin = end - seenMain.windowSeconds;
            ghostMain = pointsOn(seenMain.history, begin, end);
            ghostSecond = seenSecond ? pointsOn(seenSecond.history, begin, end) : [];
            ghostRunOutX = runOutOpacity > 0
                ? Math.round(Math.max(0, Math.min(width - 1, (shownRunOutAt - begin) / (end - begin) * width))) : -1;
            ghostRunOutText = shownRunOutText;
            ghostRunOutLevel = shownRunOutLevel;
            ghostMarkerX = markerShown ? markerShownX : -1;
            // The new week's own run-out and marker fade in once placed.
            fadeIn.stop();
            fadeOut.stop();
            runOutOpacity = 0;
            runOutShown = false;
            ghostFade.restart();
            markerShown = false;
        }
        if (duration > 0 && main !== "other" && second !== "other" && (main === "grew" || second === "grew")) {
            // The points afresh: the bindings on the windows may not have
            // caught up with them yet.
            const from = (series, was, grew) => series.length < 2 ? null : grew ? series[series.length - 2]
                                                : drawClock < 1 && was ? drawnSeries(series, was).slice(-1)[0] : null;
            mainFrom = from(points(window), mainFrom, main === "grew");
            secondFrom = from(points(secondWindow), secondFrom, second === "grew");
            drawing.restart();
        } else if (main !== "same" || second !== "same") {
            drawing.stop();
            drawClock = 1;
            mainFrom = null;
            secondFrom = null;
        }
        seenMain = seen(window);
        seenSecond = seen(secondWindow);
    }

    // The run-out and the marker follow the readings a moment later, with
    // motion, once they have all landed: the run-out and the marker change
    // with the windows, the poll time and the clock, one after the other.
    function place() {
        if (duration > 0) {
            placing.restart();
        } else {
            placeRunOut();
            placeMarker();
        }
    }

    function placeMarker() {
        if (stale) {
            markerShownX = markerX;
        }
        markerShown = stale;
    }

    // The run-out follows the pace, fading in once the line has landed, or
    // out from where it was and as it was.
    function placeRunOut() {
        const out = Number.isFinite(runOutAt);
        if (out) {
            keepRunOut();
        }
        if (out !== runOutShown) {
            runOutShown = out;
            fadeIn.stop();
            fadeOut.stop();
            if (duration > 0) {
                (out ? fadeIn : fadeOut).start();
            } else {
                runOutOpacity = out ? 1 : 0;
            }
        }
    }

    // A limit's level moves only with its percent, which moves the run-out,
    // so the level kept here is current for as long as the run-out shows.
    function keepRunOut() {
        shownRunOutAt = runOutAt;
        shownRunOutText = runOutText;
        shownRunOutLevel = Format.level((projected === "second" ? secondWindow : window)?.percent);
    }

    Component.onCompleted: {
        seenMain = seen(window);
        seenSecond = seen(secondWindow);
        runOutShown = Number.isFinite(runOutAt);
        if (runOutShown) {
            keepRunOut();
        }
        runOutOpacity = runOutShown ? 1 : 0;
        mainDotAt = mainPoints[0] ?? Qt.point(0, 0);
        secondDotAt = secondPoints[0] ?? Qt.point(0, 0);
    }
    onWindowChanged: poll()
    onSecondWindowChanged: poll()
    onRunOutAtChanged: place()
    onRunOutTextChanged: place()
    onStaleChanged: place()
    onMarkerXChanged: place()
    onMainPointsChanged: if (mainPoints.length > 0) mainDotAt = mainPoints[0]
    onSecondPointsChanged: if (secondPoints.length > 0) secondDotAt = secondPoints[0]
    // A resized graph draws its line whole at once.
    onWidthChanged: drawing.complete()

    // The graph's own, so nothing runs once the graph is gone.
    Timer {
        id: placing
        interval: 0
        onTriggered: {
            graph.placeRunOut();
            graph.placeMarker();
        }
    }

    NumberAnimation { id: drawing; target: graph; property: "drawClock"; from: 0; to: 1; duration: 2 * graph.duration }

    SequentialAnimation {
        id: fadeIn
        PauseAnimation { duration: (1 - graph.drawClock) * 2 * graph.duration }
        NumberAnimation { target: graph; property: "runOutOpacity"; to: 1; duration: graph.duration; easing.type: Easing.OutCubic }
    }

    NumberAnimation { id: fadeOut; target: graph; property: "runOutOpacity"; to: 0; duration: graph.duration; easing.type: Easing.OutCubic }
    NumberAnimation { id: ghostFade; target: graph; property: "ghostOpacity"; from: 1; to: 0; duration: 2 * graph.duration }

    // Two hours are about 4 px of a week: within that, the line's end
    // already shows now. Later than that, checks have been failing, which
    // the line under the header says. A failed check marks now as soon as
    // the gap to it is as wide.
    readonly property bool stale: placed && mainPoints.length > 0
        && (failed ? xAt(nowMs / 1000) - xAt(pollAt) >= 4 : pollAt < nowMs / 1000 - 7200)
    // The marker's place, inside the graph once the reset has passed.
    readonly property real markerX: Math.min(width - 1, Math.round(Math.max(0, xAt(nowMs / 1000))))

    function xAt(epoch) {
        return (epoch - start) / (end - start) * width;
    }

    // 100 % on the rule; 0 % half a stroke above the plot's bottom, on the
    // floor, so a line along it is drawn whole rather than half clipped.
    function yAt(percent) {
        return rule.limitY + (1 - Math.max(0, Math.min(100, percent)) / 100) * (plotHeight - 0.75 - rule.limitY);
    }

    // The window's samples inside this graph's window, as points.
    function points(source) {
        if (!placed || !source || !source.history) {
            return [];
        }
        return pointsOn(source.history, start, end);
    }

    function pointsOn(history, from, to) {
        return Array.from(history).filter(p => p[0] >= from && p[0] <= to)
            .map(p => Qt.point((p[0] - from) / (to - from) * width, yAt(p[1])));
    }

    // When a drawn series' limit runs out; see runOutAt.
    function runOut(series, source) {
        const pace = Pace.ofWindow(source, pollAt, nowMs / 1000);
        return series.length > 0 && pace.state === "out" ? pace.runOut : NaN;
    }

    // Midnights inside the window, in epoch seconds, on the clock its times
    // are told in (Words.zonedDate): the desktop clock's zone where the
    // helper gives one that system time doesn't keep, else system time.
    function midnights() {
        const found = [];
        const zone = window.clockZone;
        if (zone && zone.offset !== -new Date(end * 1000).getTimezoneOffset() * 60) {
            for (let t = (Math.floor((start + zone.offset) / 86400) + 1) * 86400 - zone.offset; t < end; t += 86400) {
                found.push(t);
            }
            return found;
        }
        const day = new Date(start * 1000);
        for (day.setHours(24, 0, 0, 0); day.getTime() < end * 1000; day.setDate(day.getDate() + 1)) {
            found.push(day.getTime() / 1000);
        }
        return found;
    }

    function levelColor(level) {
        // A run-out projected from a reading that couldn't be renewed
        // carries no alert colour, as the bars above it don't.
        return grey ? graph.color
             : level === 2 ? Kirigami.Theme.negativeTextColor : level === 1 ? Kirigami.Theme.neutralTextColor : graph.color;
    }

    // The run-out's time, the text the tile ends on while it shows.
    readonly property Item foot: timeShown ? runOutTime : null

    implicitHeight: plotHeight + (timeShown ? Math.round(Kirigami.Units.smallSpacing / 2) + runOutTime.implicitHeight : 0)
    clip: true

    LimitRule {
        id: rule
        width: parent.width
        height: graph.plotHeight
        visible: graph.placed
    }

    // The floor, so a low week reads against 0 %, with a tick at each
    // midnight, and an edge at the reset, so the time left reads as part of
    // the week: hairlines in the rule's colour, which meet and don't overlap.
    Rectangle {
        visible: graph.placed
        y: graph.floorY
        width: graph.width
        height: 1
        color: rule.lineColor
    }

    Repeater {
        model: graph.placed ? graph.midnights() : []

        Rectangle {
            required property real modelData
            x: Math.round(graph.xAt(modelData))
            y: graph.floorY - height
            width: 1
            height: Math.round(Kirigami.Units.smallSpacing / 2)
            color: rule.lineColor
        }
    }

    Rectangle {
        visible: graph.placed
        x: graph.width - 1
        y: rule.ruleY + 1
        width: 1
        height: graph.floorY - y
        color: rule.lineColor
    }

    // From the rule to the floor.
    component Marker: Rectangle {
        y: rule.ruleY + 1
        width: 1
        height: graph.floorY - y
        color: Qt.alpha(graph.color, 0.45 * graph.color.a)
    }

    // From the last reading to now while checks fail: diagonal hatching,
    // as the panel's ring is struck, in the rule's colour.
    Item {
        id: gap
        readonly property real from: Math.round(Math.max(0, graph.xAt(graph.pollAt)))
        x: from
        y: rule.ruleY + 1
        width: Math.max(0, graph.markerShownX - from)
        height: graph.floorY - y
        clip: true
        visible: graph.failed && width >= 2
        opacity: graph.markerShown ? 1 : 0

        Shape {
            width: gap.width
            height: gap.height
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.alpha(graph.color, 0.22 * graph.color.a)
                strokeWidth: 1
                fillColor: "transparent"
                PathMultiline {
                    // 45° lines, 4 px apart, bottom left to top right.
                    paths: Array.from({ length: Math.ceil((gap.width + gap.height) / 4) + 1 },
                                      (_, i) => [Qt.point(4 * i - gap.height, gap.height), Qt.point(4 * i, 0)])
                }
            }
        }
    }

    // At a new week the marker goes with the last week's lines.
    Marker {
        visible: opacity > 0
        opacity: graph.markerShown ? 1 : 0
        x: graph.markerShownX

        Behavior on opacity {
            enabled: graph.duration > 0 && !ghostFade.running
            NumberAnimation { duration: graph.duration }
        }
    }

    // A first reading has no line yet; it shows as a small round dot centred
    // on it, for either series, and the line draws on from it.
    component FirstDot: Rectangle {
        property point at
        property bool shown: false
        width: 3
        height: 3
        radius: 1.5
        x: at.x - 1.5
        y: at.y - 1.5
        visible: opacity > 0
        opacity: shown ? 1 : 0

        Behavior on opacity {
            enabled: graph.duration > 0
            NumberAnimation { duration: graph.duration / 2 }
        }
    }

    FirstDot {
        shown: graph.mainPoints.length === 1
        at: graph.mainDotAt
        color: graph.color
    }

    FirstDot {
        shown: graph.secondPoints.length === 1
        at: graph.secondDotAt
        color: Qt.alpha(graph.color, 0.55 * graph.color.a)
    }

    // A line and its fill, with the model's limit dashed.
    component Lines: Shape {
        id: lines

        property var main: []
        property var second: []

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.alpha(graph.color, graph.fillOpacity * graph.color.a)
            PathPolyline {
                path: lines.main.length > 1
                      ? [Qt.point(lines.main[0].x, graph.plotHeight)].concat(lines.main,
                            [Qt.point(lines.main[lines.main.length - 1].x, graph.plotHeight)])
                      : []
            }
        }

        ShapePath {
            strokeColor: lines.main.length > 1 ? graph.color : "transparent"
            strokeWidth: 1.5
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            // Ends where the fill does.
            capStyle: ShapePath.FlatCap
            PathPolyline { path: lines.main }
        }

        ShapePath {
            strokeColor: lines.second.length > 1 ? Qt.alpha(graph.color, 0.55 * graph.color.a) : "transparent"
            strokeWidth: 1.5
            strokeStyle: ShapePath.DashLine
            dashPattern: [2, 1.33]
            fillColor: "transparent"
            PathPolyline { path: lines.second }
        }
    }

    // The run-out: a dashed line from the rule to the floor at the moment
    // the limit runs out, so it reads as a forecast rather than as a reading,
    // with its time centred under the floor, inside the graph.
    component RunOut: Item {
        id: runOut

        property real at: 0
        property int level: 0
        property string text: ""
        readonly property color color: graph.levelColor(level)
        readonly property alias label: label

        anchors.fill: parent

        Repeater {
            // The series' weight, which keeps each dash two of the screen's
            // pixels wide at 125 %, and the second series' dashes, three on
            // and two off.
            model: Math.floor((graph.floorY - rule.ruleY) / 5) + 1

            Rectangle {
                required property int index
                x: runOut.at - 0.25
                y: rule.ruleY + 5 * index
                width: 1.5
                height: Math.min(3, graph.floorY - y)
                color: Qt.alpha(runOut.color, 0.6 * runOut.color.a)
            }
        }

        Text {
            id: label
            x: Math.max(0, Math.min(graph.width - implicitWidth, Math.round(runOut.at + 0.5 - implicitWidth / 2)))
            y: graph.plotHeight + Math.round(Kirigami.Units.smallSpacing / 2)
            text: runOut.text
            color: runOut.level === 0 ? Style.dim(Kirigami.Theme.textColor) : runOut.color
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            textFormat: Text.PlainText
            // The pace sentence says it.
            Accessible.ignored: true
        }
    }

    Item {
        anchors.fill: parent
        visible: opacity > 0
        opacity: graph.ghostOpacity

        Lines {
            main: graph.ghostMain
            second: graph.ghostSecond
        }

        RunOut {
            visible: graph.ghostRunOutX >= 0
            at: graph.ghostRunOutX
            level: graph.ghostRunOutLevel
            text: graph.ghostRunOutText
        }

        Marker {
            visible: graph.ghostMarkerX >= 0
            x: graph.ghostMarkerX
        }
    }

    Lines {
        visible: graph.mainDrawn.length > 1 || graph.secondDrawn.length > 1
        main: graph.mainDrawn
        second: graph.secondDrawn
    }

    RunOut {
        id: shownRunOut
        visible: graph.runOutOpacity > 0
        opacity: graph.runOutOpacity
        at: graph.runOutX
        level: graph.shownRunOutLevel
        text: graph.shownRunOutText
    }

    // For the foot, which has to name an item rather than a component's.
    readonly property Item runOutTime: shownRunOut.label
}
