// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import ".."

Tile {
    id: graph

    required property Words texts
    property alias window: plot.window
    property alias modelWindow: plot.secondWindow
    property alias nowMs: plot.nowMs
    property alias pollAt: plot.pollAt
    property alias rolling: plot.rolling
    property alias failed: plot.failed
    property alias grey: plot.grey
    property alias projected: plot.projected
    property bool monthly: texts.monthly(window)

    readonly property bool showModel: modelWindow !== null && (!rolling || plot.secondPoints.length > 0)

    caption: rolling ? i18nc("@title:group rolling CLIProxyAPI quota history", "Last %1 days", Format.whole(7))
                     : monthly ? i18nc("@title:group the current monthly window", "This month")
                               : i18nc("@title:group the current weekly window", "This week")
    graphTop: plot.placed ? texts.percent(100) : ""
    graphReading: plot.reading
    foot: showModel ? allModels : rolling ? nowLabel : null
    detail: {
        const date = rolling ? "" : texts.resetDate(window);
        return date ? i18nc("@title:group after THIS WEEK or THIS MONTH: when it starts over, e.g. · resets Sun 7:00 AM EDT",
                            "· resets %1", date) : "";
    }

    WeekGraph {
        id: plot
        Layout.fillWidth: true
        describe: i => {
            const [at, used] = plot.mainSamples[i];
            const percent = graph.texts.percent(used);
            const second = plot.secondAtMain[i];
            const reading = graph.showModel && Number.isFinite(second)
                ? i18nc("@info the week's use at a point on its graph, then a model limit's, e.g. 62%, Fable 30%",
                        "%1, %2 %3", percent, graph.modelWindow.label, graph.texts.percent(second))
                : percent;
            return i18nc("@info a graph point's reading and when, e.g. 62% · Mon 2:14 PM", "%1 · %2",
                         reading, graph.texts.weekdayTime(at, graph.window, graph.nowMs));
        }
    }

    RowLayout {
        visible: graph.rolling
        Layout.fillWidth: true
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        Caption {
            text: i18nc("@info the start of a rolling seven-day chart", "%1 days ago", Format.whole(7))
        }

        Caption {
            id: nowLabel
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: i18nc("@info the end of a rolling quota chart", "Now")
        }
    }

    RowLayout {
        visible: graph.showModel
        Layout.fillWidth: true
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)
        spacing: Math.round(Kirigami.Units.largeSpacing * 1.75)

        Caption {
            id: allModels
            Layout.minimumWidth: implicitWidth
            text: i18nc("@label graph legend, the solid line", "— All models")
        }

        Caption {
            Layout.fillWidth: true
            text: graph.showModel ? i18nc("@label graph legend, the dashed line; %1 is a model", "- - %1",
                                         graph.modelWindow.label) : ""
        }
    }
}
