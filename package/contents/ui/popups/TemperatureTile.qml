// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/history.js" as History

// A temperature's history, as quiet as the other graphs: no grid. The
// scale comes from every reading the three spans keep, so it holds still
// when the span changes: its top is the hot threshold, or the hottest
// reading rounded up to a five when that runs hotter, and its floor goes
// unnamed (see History.temperatureFloor()). The end of the caption line
// speaks for the span on screen. While its line stays at or under the hot
// threshold, a faint rule marks the threshold wherever it falls in the
// scale, as a percentage graph's marks 100%, and the caption names it,
// "hot 90 °C". Once the line passes it, or with the highlighting off, the
// caption names the span's peak instead, "peak 93 °C", as a rate graph's
// does, and there is no rule. The line turns amber and red where it passes
// the warm and hot thresholds, as the header's reading does, and breaks off
// where there was no reading. An hour or a day draws each bucket's average
// under a fainter band up to its highest reading, so a short hot spell
// still shows.
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
    // The hottest reading the span on screen shows, up to its band at an
    // hour or a day; NaN with none.
    readonly property real shownPeak: Format.degrees(History.peak(History.tops(history, highs))?.value ?? NaN, fahrenheit)
    // The line shown stays at or under the hot threshold, which the rule
    // and the caption then stand for.
    readonly property bool underHot: monitor.highlightTemperatures && !(shownPeak > hot)
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

    // At an hour or a day the tile stays while the sensor has read
    // anything, its first bucket still open say, so switching spans
    // doesn't take away the tile, and the span control in it.
    visible: hasReading || monitor.graphSpan !== "minute" && extent.length > 0
    caption: i18nc("@title:group", "Temperature")
    spans: monitor
    graphTop: {
        if (underHot) {
            const h = Format.whole(hot);
            return fahrenheit
                ? i18nc("@title:group at the end of a temperature graph's caption line: the hot threshold set for red, which a faint rule across the graph marks, as in hot 194 °F", "hot %1 °F", h)
                : i18nc("@title:group at the end of a temperature graph's caption line: the hot threshold set for red, which a faint rule across the graph marks, as in hot 90 °C", "hot %1 °C", h);
        }
        if (!Number.isFinite(shownPeak)) {
            return "";
        }
        const t = Format.whole(shownPeak);
        return fahrenheit
            ? i18nc("@title:group at the end of a temperature graph's caption line: its highest reading, as in peak 199 °F", "peak %1 °F", t)
            : i18nc("@title:group at the end of a temperature graph's caption line: its highest reading, as in peak 93 °C", "peak %1 °C", t);
    }

    Item {
        id: graph

        // The top sits where the other graphs put theirs.
        readonly property real topY: rule.limitY
        // Where the hot threshold falls in the scale: the top, unless a
        // reading in any span ran hotter.
        readonly property real hotY: History.points([tile.hot], 2, width, height, tile.scaleTop, topY, tile.floor)[0].y
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

        // Moved down from the top so that its line runs through hotY.
        LimitRule {
            id: rule
            y: graph.hotY - rule.limitY
            width: parent.width
            height: parent.height
            visible: tile.underHot
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
