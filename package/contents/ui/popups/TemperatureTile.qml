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
// top named at the end of the caption line. The top is the hot threshold,
// under a faint rule as a percentage graph's 100% is, "hot 90 °C", or the
// peak when the line runs hotter or the highlighting is off, "peak 93 °C",
// as a rate graph's is. The floor goes unnamed (see
// History.temperatureFloor()). Both come from every reading the three spans
// keep, so the scale and its name hold still when the span changes. The
// line turns amber and red where it passes the warm and hot thresholds, as
// the header's reading does, and breaks off where there was no reading. An
// hour or a day draws each bucket's average under a fainter band up to its
// highest reading, so a short hot spell still shows.
Tile {
    id: tile

    // Monitor.qml, or anything shaped like it.
    required property var monitor
    // °C, oldest first, NaN for a missing reading.
    property var history: []
    // The highest reading behind each point at an hour or a day; empty at
    // a minute, where each point is a reading.
    property var highs: []
    // [coolest, hottest] across the three spans (Monitor's *Extent), or
    // empty, when the scale comes from the history alone.
    property var extent: []

    readonly property bool fahrenheit: monitor.fahrenheit
    // Samples and thresholds in the unit shown, so the floor is a round
    // number in it.
    readonly property var shown: history.map(c => Format.degrees(c, fahrenheit))
    readonly property var scaleSamples: (extent.length > 0 ? extent : history).map(c => Format.degrees(c, fahrenheit))
    readonly property real hot: Format.degrees(monitor.hotCelsius, fahrenheit)
    readonly property bool bucketed: highs.length > 0
    // With the highlighting off the settings grey the thresholds out and
    // the line keeps one colour, so the hot threshold means nothing here.
    readonly property real scaleTop: History.temperatureTop(scaleSamples, monitor.highlightTemperatures ? hot : -Infinity)
    readonly property bool topIsHot: monitor.highlightTemperatures && scaleTop === hot
    // 5 °C in the unit shown.
    readonly property real margin: fahrenheit ? 9 : 5
    // Set as the samples come rather than bound, since where it stays
    // depends on where it was.
    property real floor: NaN
    // A lone reading draws no line at a minute, so a sensor needs two in a
    // row there for a graph, as the header needs one for a reading; at an
    // hour or a day one bucket is a mark of its own.
    readonly property bool hasReading: bucketed ? history.some(c => Number.isFinite(c))
        : history.some((c, i) => i > 0 && Number.isFinite(c) && Number.isFinite(history[i - 1]))

    Component.onCompleted: floor = History.temperatureFloor(scaleSamples, margin, NaN)
    onScaleSamplesChanged: floor = History.temperatureFloor(scaleSamples, margin, floor)

    visible: hasReading
    caption: i18nc("@title:group", "Temperature")
    spans: monitor
    graphTop: {
        const t = Format.whole(scaleTop);
        if (topIsHot) {
            return fahrenheit
                ? i18nc("@title:group at the end of a temperature graph's caption line: the hot threshold set for red, which the graph's top and its rule stand for, as in hot 194 °F", "hot %1 °F", t)
                : i18nc("@title:group at the end of a temperature graph's caption line: the hot threshold set for red, which the graph's top and its rule stand for, as in hot 90 °C", "hot %1 °C", t);
        }
        return fahrenheit
            ? i18nc("@title:group at the end of a temperature graph's caption line: its highest reading, as in peak 199 °F", "peak %1 °F", t)
            : i18nc("@title:group at the end of a temperature graph's caption line: its highest reading, as in peak 93 °C", "peak %1 °C", t);
    }

    Item {
        id: graph

        // The top sits where the other graphs put theirs.
        readonly property real topY: rule.limitY
        // The samples, in the unit shown, and their points, kept together:
        // as a history grows, a binding reading them apart could see the
        // new samples with the old points, one short.
        readonly property var plot: {
            const values = tile.shown;
            const length = tile.monitor.historyLength;
            const tops = tile.bucketed && tile.highs.length === values.length
                ? History.points(tile.highs.map(c => Format.degrees(c, tile.fahrenheit)), length, width, height,
                                 tile.scaleTop, topY, tile.floor) : null;
            return { values: values, points: History.points(values, length, width, height, tile.scaleTop, topY, tile.floor),
                     tops: tops, half: tile.bucketed ? History.loneHalf(length, width) : 0 };
        }
        readonly property var areas: History.runs(plot.values, plot.points, plot.half).filter(run => run.length > 1).map(run =>
            [Qt.point(run[0].x, height)].concat(run.map(p => Qt.point(p.x, p.y)), [Qt.point(run[run.length - 1].x, height)]))
        readonly property var bands: plot.tops
            ? History.bands(plot.values, tile.highs, plot.points, plot.tops, plot.half).map(run => run.map(p => Qt.point(p.x, p.y)))
            : []
        readonly property var pieces: tile.monitor.highlightTemperatures
            ? History.pieces(plot.values, plot.points, Format.degrees(tile.monitor.warmCelsius, tile.fahrenheit), tile.hot, plot.half)
            : History.pieces(plot.values, plot.points, Infinity, Infinity, plot.half)

        function lines(level) {
            return pieces.filter(p => p.level === level).map(p => p.points.map(q => Qt.point(q.x, q.y)));
        }

        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 2.7
        clip: true

        LimitRule {
            id: rule
            anchors.fill: parent
            visible: tile.topIsHot
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                fillColor: Qt.alpha(Kirigami.Theme.textColor, 0.6 * 0.15)
                PathMultiline { paths: graph.bands }
            }

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
