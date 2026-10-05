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

    // The top sits where the rule would, with or without it, so a rate's
    // peak keeps the same room under the caption as 100 % does.
    readonly property real topY: rule.limitY
    readonly property var mainPoints: History.points(values, length, width, height, maximum, topY)
        .map(p => Qt.point(p.x, p.y))
    readonly property var secondPoints: second ? History.points(secondValues, length, width, height, maximum, topY)
        .map(p => Qt.point(p.x, p.y)) : []

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
        visible: graph.second && graph.secondPoints.length > 1

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
