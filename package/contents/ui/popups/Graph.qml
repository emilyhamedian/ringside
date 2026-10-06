// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "../code/history.js" as History

// A history graph: a filled area under the main series and an optional
// dashed second series (upload under download), with no grid. Percentages
// run 0 to 100 under the labelled 100 % rule the week graph shares
// (LimitRule). A rate's top is its peak, which the tile's caption names,
// or the floor its tile sets when the peak is lower (1 Mb/s for the link,
// 1 MiB/s for a disk), so a near-idle line stays near the bottom.
// A new sample doesn't move the slots: each point eases from the height it
// was drawn at to its new one, the newest rising or falling from the last
// reading, and a rate's new top eases in with them, so the line meets its
// peak caption as it comes to rest.
Item {
    id: graph

    // Oldest first; see Monitor.sample().
    property var values: []
    property var secondValues: []
    property bool second: false
    property int length: 60
    // The top of the scale, in the series' own units.
    property real maximum: 100
    // Whether the top is a fixed 100 % worth a labelled rule.
    property bool ceiling: true
    property color color: Kirigami.Theme.textColor
    property real fillOpacity: 0.15
    // How long the points take to ease to a new sample; 0 draws it at once,
    // as at Plasma's Instant speed.
    property int duration: Kirigami.Units.longDuration > 1 ? Kirigami.Units.longDuration : 0

    // The samples and top the line shows: set rather than bound, a moment
    // after they change, so that a sample and the top that comes with it
    // are taken together and nothing is drawn ahead of the easing.
    property var shownValues: []
    property var shownSecondValues: []
    property real shownMaximum: 100
    // The points each sample eases from, and how far it has gone.
    property var mainFrom: []
    property var secondFrom: []
    property real progress: 1

    // The top sits where the rule would, with or without it, so a rate's
    // peak keeps the same room under the caption as 100 % does.
    readonly property real topY: rule.limitY
    // Where the line comes to rest.
    readonly property var mainPoints: History.points(shownValues, length, width, height, shownMaximum, topY)
    readonly property var secondPoints: second ? History.points(shownSecondValues, length, width, height, shownMaximum, topY) : []
    // Where it is drawn.
    readonly property var mainDrawn: blend(mainFrom, mainPoints, progress)
    readonly property var secondDrawn: blend(secondFrom, secondPoints, progress)

    function blend(from, to, t) {
        return (from.length === to.length && t < 1 ? to.map((p, i) => ({ x: from[i].x + (p.x - from[i].x) * t,
                                                                          y: from[i].y + (p.y - from[i].y) * t }))
                                                   : to).map(p => Qt.point(p.x, p.y));
    }

    // Where each point of a series that took one more sample eases from:
    // with the history full, the height drawn in its own slot; while it
    // grows in, each sample moves a slot left and the new one grows out of
    // the old end. Nothing for any other change, which is drawn at once.
    function easedFrom(drawn, before, after, rest) {
        const arrival = History.arrival(before, after, length);
        const from = arrival === null || drawn.length === 0 ? []
            : rest.map((p, i) => arrival.dropped === undefined ? drawn[Math.min(i, drawn.length - 1)] : { x: p.x, y: drawn[i].y });
        return from.some((p, i) => p.x !== rest[i].x || p.y !== rest[i].y) ? from : [];
    }

    function take() {
        const restOf = samples => History.points(samples, length, width, height, maximum, topY);
        // A hidden graph takes a sample at once.
        const eases = duration > 0 && visible && values !== shownValues;
        mainFrom = eases ? easedFrom(mainDrawn, shownValues, values, restOf(values)) : [];
        secondFrom = eases && second ? easedFrom(secondDrawn, shownSecondValues, secondValues, restOf(secondValues)) : [];
        shownValues = values;
        shownSecondValues = secondValues;
        shownMaximum = maximum;
        if (mainFrom.length > 0 || secondFrom.length > 0) {
            progress = 0;
            easing.restart();
        } else {
            easing.stop();
            progress = 1;
        }
    }

    Component.onCompleted: {
        shownValues = values;
        shownSecondValues = secondValues;
        shownMaximum = maximum;
    }
    onValuesChanged: arrive()
    onSecondValuesChanged: arrive()
    onMaximumChanged: arrive()
    // A resized graph shows its points at once.
    onWidthChanged: easing.complete()

    // A sample and a rate's new top arrive one after the other, so they are
    // taken a moment later, together. Without easing they are taken at
    // once, as each arrives.
    function arrive() {
        if (duration > 0) {
            taking.restart();
        } else {
            take();
        }
    }

    // The graph's own, so nothing runs once the graph is gone.
    Timer {
        id: taking
        interval: 0
        onTriggered: graph.take()
    }

    NumberAnimation {
        id: easing
        target: graph
        property: "progress"
        to: 1
        duration: graph.duration
        easing.type: Easing.OutCubic
    }

    implicitHeight: Kirigami.Units.gridUnit * 2.7
    clip: true

    LimitRule {
        id: rule
        anchors.fill: parent
        visible: graph.ceiling
        series: [graph.mainPoints, graph.secondPoints]
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: graph.mainDrawn.length > 1

        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.alpha(graph.color, graph.fillOpacity * graph.color.a)
            PathPolyline {
                path: graph.mainDrawn.length > 1
                      ? [Qt.point(graph.mainDrawn[0].x, graph.height)].concat(graph.mainDrawn,
                            [Qt.point(graph.mainDrawn[graph.mainDrawn.length - 1].x, graph.height)])
                      : []
            }
        }

        ShapePath {
            strokeColor: graph.color
            strokeWidth: 1.5
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: graph.mainDrawn }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: graph.second && graph.secondDrawn.length > 1

        ShapePath {
            strokeColor: Qt.alpha(graph.color, 0.55 * graph.color.a)
            strokeWidth: 1.5
            strokeStyle: ShapePath.DashLine
            dashPattern: [2, 1.33]
            fillColor: "transparent"
            PathPolyline { path: graph.secondDrawn }
        }
    }
}
