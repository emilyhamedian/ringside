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
// old does a marker say where now is. A limit on course to run out before
// the reset gets a dotted line on to where it reaches 100 %, the time the
// pace sentence under the bars names.
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

    // The time axis, in epoch seconds.
    readonly property real end: window && Number.isFinite(window.resetsAt) ? window.resetsAt : NaN
    readonly property real start: window ? end - window.windowSeconds : NaN
    readonly property bool placed: end > start

    readonly property var mainPoints: points(window)
    readonly property var secondPoints: points(secondWindow)
    // Each window's projection, as the popup's sentence reads it.
    readonly property var mainPace: Pace.ofWindow(window, pollAt, nowMs / 1000)
    readonly property var secondPace: Pace.ofWindow(secondWindow, pollAt, nowMs / 1000)
    readonly property var mainRunOut: runOut(mainPoints, mainPace)
    readonly property var secondRunOut: runOut(secondPoints, secondPace)

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
        return Array.from(source.history).filter(p => p[0] >= start && p[0] <= end)
            .map(p => Qt.point(xAt(p[0]), yAt(p[1])));
    }

    // From a series' last point to where its limit runs out, while the pace
    // says it will before the reset; otherwise no segment.
    function runOut(series, pace) {
        if (series.length === 0 || pace.state !== "out") {
            return [];
        }
        return [series[series.length - 1], Qt.point(xAt(pace.runOut), yAt(100))];
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
        series: [graph.mainPoints, graph.secondPoints, graph.mainRunOut, graph.secondRunOut,
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
        visible: graph.stale
        x: graph.markerX
        y: rule.ruleY
        width: 1
        height: graph.height - rule.ruleY
        color: Qt.alpha(graph.color, 0.45 * graph.color.a)
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

    // A first reading has no line yet; it shows as a dot, for either series.
    Dot {
        visible: graph.mainPoints.length === 1
        at: graph.mainPoints.length === 1 ? graph.mainPoints[0] : Qt.point(0, 0)
        color: graph.color
    }

    Dot {
        visible: graph.secondPoints.length === 1
        at: graph.secondPoints.length === 1 ? graph.secondPoints[0] : Qt.point(0, 0)
        color: Qt.alpha(graph.color, 0.55 * graph.color.a)
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: graph.mainPoints.length > 1

        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.alpha(graph.color, graph.fillOpacity * graph.color.a)
            PathPolyline {
                path: graph.mainPoints.length > 1
                      ? [Qt.point(graph.mainPoints[0].x, graph.height)].concat(graph.mainPoints,
                            [Qt.point(graph.mainPoints[graph.mainPoints.length - 1].x, graph.height)])
                      : []
            }
        }

        ShapePath {
            strokeColor: graph.color
            strokeWidth: 1.5
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: graph.mainPoints }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: graph.secondPoints.length > 1

        ShapePath {
            strokeColor: Qt.alpha(graph.color, 0.55 * graph.color.a)
            strokeWidth: 1.5
            strokeStyle: ShapePath.DashLine
            dashPattern: [2, 1.33]
            fillColor: "transparent"
            PathPolyline { path: graph.secondPoints }
        }
    }

    // The run-outs, dotted in their series' colours.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: graph.mainRunOut.length > 0 || graph.secondRunOut.length > 0

        ShapePath {
            strokeColor: graph.mainRunOut.length > 0 ? graph.color : "transparent"
            strokeWidth: 1.5
            strokeStyle: ShapePath.DashLine
            dashPattern: [1, 2]
            fillColor: "transparent"
            PathPolyline { path: graph.mainRunOut }
        }

        ShapePath {
            strokeColor: graph.secondRunOut.length > 0 ? Qt.alpha(graph.color, 0.55 * graph.color.a) : "transparent"
            strokeWidth: 1.5
            strokeStyle: ShapePath.DashLine
            dashPattern: [1, 2]
            fillColor: "transparent"
            PathPolyline { path: graph.secondRunOut }
        }
    }
}
