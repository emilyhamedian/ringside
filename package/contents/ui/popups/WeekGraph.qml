// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// A weekly limit's use through its window: time from the window's start to
// its reset across, 0 to 100 % up, with a faint line per day and a marker at
// the current time. The faint diagonal is an even pace, the use that would
// reach the limit just as the week resets, so a line above it is ahead of
// pace. The main series is filled; a second one, the model limit on the
// inner ring, is dashed, as in Graph. The line ends at the last poll, since
// nothing is known about the use after it.
Item {
    id: graph

    // A window as the helper reports it: resetsAt, windowSeconds and a
    // history of [epoch seconds, percent], oldest first.
    property var window: null
    // Another window's history, drawn dashed on this window's time axis.
    property var secondWindow: null
    property real nowMs: Date.now()
    property color color: Kirigami.Theme.textColor
    property real fillOpacity: 0.15

    // The time axis, in epoch seconds.
    readonly property real end: window && Number.isFinite(window.resetsAt) ? window.resetsAt : NaN
    readonly property real start: window ? end - window.windowSeconds : NaN
    readonly property bool placed: end > start

    readonly property var mainPoints: points(window)
    readonly property var secondPoints: points(secondWindow)
    readonly property real nowX: placed ? Math.max(0, Math.min(width, xAt(nowMs / 1000))) : NaN
    // A line where each day of the window starts, counted back from the reset.
    readonly property var dayXs: {
        const list = [];
        for (let t = end - 86400; placed && t > start; t -= 86400) {
            list.unshift(xAt(t));
        }
        return list;
    }

    function xAt(epoch) {
        return (epoch - start) / (end - start) * width;
    }

    function yAt(percent) {
        return height - Math.max(0, Math.min(100, percent)) / 100 * height;
    }

    // The window's samples inside this graph's window, as points.
    function points(source) {
        if (!placed || !source || !source.history) {
            return [];
        }
        return Array.from(source.history).filter(p => p[0] >= start && p[0] <= end)
            .map(p => Qt.point(xAt(p[0]), yAt(p[1])));
    }

    implicitHeight: Kirigami.Units.gridUnit * 3.2
    clip: true

    Repeater {
        model: graph.dayXs
        delegate: Rectangle {
            required property real modelData
            x: Math.round(modelData)
            width: 1
            height: graph.height
            color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
        }
    }

    // A rule at half the limit.
    Rectangle {
        y: Math.round(graph.height / 2)
        width: graph.width
        height: 1
        color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: graph.placed

        ShapePath {
            strokeColor: Qt.alpha(graph.color, 0.25 * graph.color.a)
            strokeWidth: 1
            fillColor: "transparent"
            startX: 0
            startY: graph.height
            PathLine { x: graph.width; y: 0 }
        }
    }

    Rectangle {
        visible: graph.placed
        x: Math.min(graph.width - width, Math.round(graph.nowX))
        width: 1
        height: graph.height
        color: Qt.alpha(graph.color, 0.45 * graph.color.a)
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
}
