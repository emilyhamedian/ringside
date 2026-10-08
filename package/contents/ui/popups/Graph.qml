// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "../code/history.js" as History

// A history graph: a filled area under the main series and an optional
// dashed second series (upload under download), with no grid. Percentages
// run 0 to 100 under the 100 % rule the week graph shares (LimitRule).
// A rate's top is its peak, or the floor its tile sets when the peak is lower (1 Mb/s for the link,
// 1 MiB/s for a disk), so a near-idle line stays near the bottom. The
// tile's caption line names the top at its end: "100%" or the peak.
// A new sample redraws the line at once, each point a slot to the left;
// nothing on the graph moves on its own. An hour or a day draws each
// bucket's average, under a fainter band up to its highest reading, and
// leaves a gap where there was none (see History.add()).
Item {
    id: graph

    // Oldest first; see Monitor.sample().
    property var values: []
    // The highest reading behind each of `values`, at an hour or a day;
    // empty at a minute, where each value is a reading.
    property var highs: []
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
    // peak sits under the caption line as 100 % does.
    readonly property real topY: rule.limitY
    readonly property bool bucketed: highs.length > 0
    // Every shape from the same samples in one go: bindings reading them
    // apart could see a new span's samples with the last span's points. A
    // lone point draws nothing at a minute, and a short level line at an
    // hour or a day, where it stands for a whole bucket.
    readonly property var drawn: {
        const half = bucketed ? History.loneHalf(length, width) : 0;
        const main = History.points(values, length, width, height, maximum, topY);
        const tops = bucketed && highs.length === values.length
            ? History.points(highs, length, width, height, maximum, topY) : null;
        const later = second ? History.points(secondValues, length, width, height, maximum, topY) : [];
        return {
            main: main.map(qt),
            second: later.map(qt),
            runs: History.runs(values, main, half).filter(run => run.length > 1).map(run => run.map(qt)),
            secondRuns: History.runs(secondValues, later, half).filter(run => run.length > 1).map(run => run.map(qt)),
            bands: tops ? History.bands(values, highs, main, tops, half).map(run => run.map(qt)) : []
        };
    }
    readonly property var mainPoints: drawn.main
    readonly property var secondPoints: drawn.second

    function qt(p) {
        return Qt.point(p.x, p.y);
    }

    implicitHeight: Kirigami.Units.gridUnit * 2.7
    clip: true

    LimitRule {
        id: rule
        anchors.fill: parent
        visible: graph.ceiling
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.alpha(graph.color, 0.6 * graph.fillOpacity * graph.color.a)
            PathMultiline { paths: graph.drawn.bands }
        }

        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.alpha(graph.color, graph.fillOpacity * graph.color.a)
            PathMultiline {
                paths: graph.drawn.runs.map(run => [Qt.point(run[0].x, graph.height)].concat(run,
                                                     [Qt.point(run[run.length - 1].x, graph.height)]))
            }
        }

        ShapePath {
            strokeColor: graph.color
            strokeWidth: 1.5
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathMultiline { paths: graph.drawn.runs }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: graph.second

        ShapePath {
            strokeColor: Qt.alpha(graph.color, 0.55 * graph.color.a)
            strokeWidth: 1.5
            strokeStyle: ShapePath.DashLine
            dashPattern: [2, 1.33]
            fillColor: "transparent"
            PathMultiline { paths: graph.drawn.secondRuns }
        }
    }
}
