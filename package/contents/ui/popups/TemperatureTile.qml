// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/history.js" as History

// A temperature's history, as quiet as the other graphs: no grid, and the
// scale named at the end of the caption line, "40–90 °C" (see
// History.temperatureScale()). The line turns amber and red where it passes
// the warm and hot thresholds, as the header's reading does, and breaks off
// where there was no reading.
Tile {
    id: tile

    // Monitor.qml, or anything shaped like it.
    required property var monitor
    // °C, oldest first, NaN for a missing reading.
    property var history: []

    readonly property bool fahrenheit: monitor.fahrenheit
    // Samples and thresholds in the unit shown, so the scale's ends are
    // round numbers in it.
    readonly property var shown: history.map(c => Format.degrees(c, fahrenheit))
    readonly property var range: History.temperatureScale(shown, Format.degrees(monitor.hotCelsius, fahrenheit),
                                                          Format.degrees(5, fahrenheit) - Format.degrees(0, fahrenheit))
    // A sensor that has never answered in the graph's span has no graph,
    // as its header has no reading.
    readonly property bool hasReading: history.some(c => Number.isFinite(c))

    visible: hasReading
    caption: i18nc("@title:group", "Temperature")
    graphSeconds: monitor.historySeconds
    graphTop: fahrenheit
        ? i18nc("@title:group at the end of a temperature graph's caption line: the range it spans, as in 100–194 °F",
                "%1–%2 °F", Format.whole(range.low), Format.whole(range.high))
        : i18nc("@title:group at the end of a temperature graph's caption line: the range it spans, as in 40–90 °C",
                "%1–%2 °C", Format.whole(range.low), Format.whole(range.high))

    Item {
        id: graph

        // In the unit shown, as the scale is.
        readonly property var values: tile.shown
        // The top sits where the other graphs put theirs.
        readonly property real topY: rule.limitY
        readonly property var points: History.points(values, tile.monitor.historyLength, width, height,
                                                     tile.range.high, topY, tile.range.low)
        readonly property var areas: History.runs(values, points).map(run =>
            [Qt.point(run[0].x, height)].concat(run.map(p => Qt.point(p.x, p.y)), [Qt.point(run[run.length - 1].x, height)]))
        readonly property var pieces: tile.monitor.highlightTemperatures
            ? History.pieces(values, points, Format.degrees(tile.monitor.warmCelsius, tile.fahrenheit),
                             Format.degrees(tile.monitor.hotCelsius, tile.fahrenheit))
            : History.pieces(values, points, Infinity, Infinity)

        function lines(level) {
            return pieces.filter(p => p.level === level).map(p => p.points.map(q => Qt.point(q.x, q.y)));
        }

        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 2.7
        clip: true

        LimitRule {
            id: rule
            visible: false
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                fillColor: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                PathMultiline { paths: graph.areas }
            }

            // Hotter pieces over cooler ones, so where two meet the hotter
            // one's round end shows.
            Stroke { lines: graph.lines(0); strokeColor: Kirigami.Theme.textColor }
            Stroke { lines: graph.lines(1); strokeColor: Kirigami.Theme.neutralTextColor }
            Stroke { lines: graph.lines(2); strokeColor: Kirigami.Theme.negativeTextColor }
        }
    }

    component Stroke: ShapePath {
        id: stroke

        property var lines: []

        strokeWidth: 1.5
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        capStyle: ShapePath.RoundCap
        PathMultiline { paths: stroke.lines }
    }
}
