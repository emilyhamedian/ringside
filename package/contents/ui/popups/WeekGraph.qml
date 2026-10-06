// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "../code/pace.js" as Pace

// A weekly limit's use through its window: time from the window's start to
// its reset across, 0 to 100 % up, between a faint floor and the labelled
// 100 % rule the system graphs share (LimitRule), with a tick at the reset.
// The main series is filled; a second one, the model limit on the inner
// ring, is dashed, as in Graph. The line ends at the last poll, so the empty
// stretch to its right is the time left; only when the last poll is hours
// old does a marker say where now is. The limit the pace sentence under the
// bars names, when it is on course to run out before the reset, gets a line
// of red dots on to where it reaches 100 %, at the time the sentence gives.
// A poll that adds a reading draws the new stretch of line on from the old
// end, and a run-out it brings fades in once the line has landed. A run-out
// that goes fades out where it was, the marker for now and a first
// reading's dot fade in and out, and a week that starts over while the
// popup is open fades out the last week's line. Any other change is drawn
// at once.
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
    property color color: Kirigami.Theme.textColor
    property real fillOpacity: 0.15
    // The series whose run-out is drawn, "main" or "second", or "" for none:
    // the limit the popup's pace sentence names, so the two agree.
    property string projected: ""
    // A new stretch of line draws on over twice this, and the rest fades
    // over it or half of it: Kirigami's long duration, or 0 at Plasma's
    // Instant speed, where everything is drawn at once.
    property int duration: Kirigami.Units.longDuration > 1 ? Kirigami.Units.longDuration : 0

    // The time axis, in epoch seconds.
    readonly property real end: window && Number.isFinite(window.resetsAt) ? window.resetsAt : NaN
    readonly property real start: window ? end - window.windowSeconds : NaN
    readonly property bool placed: end > start

    readonly property var mainPoints: points(window)
    readonly property var secondPoints: points(secondWindow)
    // When that limit runs out, in epoch seconds, while the pace says it
    // will before the reset, as the popup's sentence reads it; NaN
    // otherwise. The projection runs from the series' last point to there.
    readonly property real runOutAt: projected === "main" ? runOut(mainPoints, window)
                                   : projected === "second" ? runOut(secondPoints, secondWindow)
                                   : NaN
    readonly property var projection: Number.isFinite(runOutAt)
        ? [(projected === "main" ? mainPoints : secondPoints).slice(-1)[0], Qt.point(xAt(runOutAt), yAt(100))] : []

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
    // the pace clears, and its end eases when a poll moves it.
    property bool runOutShown: false
    property real runOutOpacity: 0
    property string runOutSeries: "main"
    property real shownRunOutAt: NaN
    readonly property point runOutEnd: Qt.point(xAt(shownRunOutAt), yAt(100))
    readonly property var runOutDrawn: {
        const series = runOutSeries === "second" ? secondDrawn : mainDrawn;
        return series.length > 0 ? [series[series.length - 1], runOutEnd] : [];
    }
    // Last week's line, fading out under the new week's.
    property var ghostMain: []
    property var ghostSecond: []
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

    // Where a series' end is drawn, `added` readings (0 or 1) back from its
    // last point.
    function drawnEnd(series, from, added) {
        const end = series[series.length - 1 - added];
        return drawClock < 1 && from ? Qt.point(from.x + (end.x - from.x) * drawIn, from.y + (end.y - from.y) * drawIn) : end;
    }

    function seen(source) {
        return source ? { resetsAt: source.resetsAt, windowSeconds: source.windowSeconds, history: Array.from(source.history ?? []) }
                      : null;
    }

    // "same", "grew" by one reading in the same window, or "other".
    function change(was, source) {
        if (!was || !source) {
            return !was && !source ? "same" : "other";
        }
        const history = Array.from(source.history ?? []);
        const kept = was.resetsAt === source.resetsAt
            && was.history.every((p, i) => i < history.length && p[0] === history[i][0] && p[1] === history[i][1]);
        return !kept ? "other" : history.length === was.history.length ? "same"
             : history.length === was.history.length + 1 ? "grew" : "other";
    }

    // A window has changed. Each series that took one more reading draws its
    // new stretch on from where its end was drawn, and one still drawing on
    // carries on from where it is; anything else stops the drawing.
    function poll() {
        const main = change(seenMain, window);
        const second = change(seenSecond, secondWindow);
        if (duration > 0 && seenMain && window && seenMain.resetsAt !== window.resetsAt && seenMain.history.length > 0) {
            const end = seenMain.resetsAt;
            ghostMain = pointsOn(seenMain.history, end - seenMain.windowSeconds, end);
            ghostSecond = seenSecond ? pointsOn(seenSecond.history, end - seenMain.windowSeconds, end) : [];
            ghostFade.restart();
        }
        if (duration > 0 && main !== "other" && second !== "other" && (main === "grew" || second === "grew")) {
            // The points afresh: the bindings on the windows may not have
            // caught up with them yet.
            const from = (series, was, grew) => series.length < 2 ? null : grew ? drawnEnd(series, was, 1)
                                                : drawClock < 1 && was ? drawnEnd(series, was, 0) : null;
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

    // The run-out follows its projection, fading in once the line has
    // landed, or out from where it was.
    function placeRunOut() {
        const out = projection.length > 0;
        if (out) {
            runOutSeries = projected;
            shownRunOutAt = runOutAt;
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

    Component.onCompleted: {
        seenMain = seen(window);
        seenSecond = seen(secondWindow);
        runOutShown = projection.length > 0;
        if (runOutShown) {
            runOutSeries = projected;
            shownRunOutAt = runOutAt;
        }
        runOutOpacity = runOutShown ? 1 : 0;
        mainDotAt = mainPoints[0] ?? Qt.point(0, 0);
        secondDotAt = secondPoints[0] ?? Qt.point(0, 0);
    }
    onWindowChanged: poll()
    onSecondWindowChanged: poll()
    // The projection changes with the windows and the poll time, one after
    // the other, so with motion it is placed a moment later, once the
    // drawing it waits for has started.
    onProjectionChanged: {
        if (duration > 0) {
            placing.restart();
        } else {
            placeRunOut();
        }
    }
    onMainPointsChanged: if (mainPoints.length > 0) mainDotAt = mainPoints[0]
    onSecondPointsChanged: if (secondPoints.length > 0) secondDotAt = secondPoints[0]
    // A resized graph draws its line whole at once.
    onWidthChanged: drawing.complete()

    // The graph's own, so nothing runs once the graph is gone.
    Timer {
        id: placing
        interval: 0
        onTriggered: graph.placeRunOut()
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
    // the line under the header says.
    readonly property bool stale: placed && mainPoints.length > 0 && pollAt < nowMs / 1000 - 7200
    // The marker's place, inside the graph once the reset has passed.
    readonly property real markerX: Math.min(width - 1, Math.round(Math.max(0, xAt(nowMs / 1000))))

    function xAt(epoch) {
        return (epoch - start) / (end - start) * width;
    }

    // 100 % on the rule; 0 % half a stroke above the bottom, so a line
    // along it is drawn whole rather than half clipped.
    function yAt(percent) {
        return rule.limitY + (1 - Math.max(0, Math.min(100, percent)) / 100) * (height - 0.75 - rule.limitY);
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

    implicitHeight: Kirigami.Units.gridUnit * 3.2
    clip: true

    LimitRule {
        id: rule
        anchors.fill: parent
        visible: graph.placed
        // The week so far lies to the left; the right end is still to come,
        // though late in the week the marker for now can stand there.
        preferEnd: true
        series: [graph.mainPoints, graph.secondPoints, graph.projection,
                 graph.stale ? [Qt.point(graph.markerX, rule.ruleY), Qt.point(graph.markerX, graph.height)] : []]
    }

    // The floor, so a low week reads against 0 %, and the reset's tick at
    // the right end, so the time left reads as part of the week.
    Rectangle {
        visible: graph.placed
        y: graph.height - 1
        width: graph.width
        height: 1
        color: rule.lineColor
    }

    Rectangle {
        visible: graph.placed
        x: graph.width - 1
        y: graph.height - height
        width: 1
        height: Kirigami.Units.smallSpacing + 1
        color: rule.lineColor
    }

    Rectangle {
        visible: opacity > 0
        opacity: graph.stale ? 1 : 0
        x: graph.markerX
        y: rule.ruleY
        width: 1
        height: graph.height - rule.ruleY
        color: Qt.alpha(graph.color, 0.45 * graph.color.a)

        Behavior on opacity {
            enabled: graph.duration > 0
            NumberAnimation { duration: graph.duration }
        }
    }

    // A small round mark centred on a point.
    component Dot: Rectangle {
        property point at
        width: 3
        height: 3
        radius: 1.5
        x: at.x - 1.5
        y: at.y - 1.5
    }

    // A first reading has no line yet; it shows as a dot, for either series,
    // and the line draws on from it.
    component FirstDot: Dot {
        property bool shown: false
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
                      ? [Qt.point(lines.main[0].x, graph.height)].concat(lines.main,
                            [Qt.point(lines.main[lines.main.length - 1].x, graph.height)])
                      : []
            }
        }

        ShapePath {
            strokeColor: lines.main.length > 1 ? graph.color : "transparent"
            strokeWidth: 1.5
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
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

    Lines {
        visible: graph.ghostOpacity > 0
        opacity: graph.ghostOpacity
        main: graph.ghostMain
        second: graph.ghostSecond
    }

    Lines {
        visible: graph.mainDrawn.length > 1 || graph.secondDrawn.length > 1
        main: graph.mainDrawn
        second: graph.secondDrawn
    }

    // The run-out: round dots in the colour of a limit running out, from
    // the series' last point to a dot on the 100 % rule where it runs out,
    // so it reads as a projection rather than as more readings.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: graph.runOutOpacity > 0 && graph.runOutDrawn.length > 0
        opacity: graph.runOutOpacity

        ShapePath {
            strokeColor: Kirigami.Theme.negativeTextColor
            strokeWidth: 1.5
            strokeStyle: ShapePath.DashLine
            capStyle: ShapePath.RoundCap
            // In stroke widths: the round caps of a dash this short make a
            // dot, with about two dots' room between it and the next.
            dashPattern: [0.01, 3]
            fillColor: "transparent"
            PathPolyline { path: graph.runOutDrawn }
        }
    }

    Dot {
        visible: graph.runOutOpacity > 0
        opacity: graph.runOutOpacity
        at: graph.runOutEnd
        color: Kirigami.Theme.negativeTextColor
    }
}
