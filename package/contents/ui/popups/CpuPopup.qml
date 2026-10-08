// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import "../code/format.js" as Format
import "../code/style.js" as Style
import ".."

PopupPage {
    id: popup

    readonly property int threads: monitor.cpuThreads

    function sensorValue(sensor) {
        return sensor && typeof sensor.value === "number" ? sensor.value : NaN;
    }

    // The load averages spoken as one, a missing one as a word rather than
    // the dash shown on screen.
    function loadAverageName(one, five, fifteen) {
        const spoken = v => Format.usable(v) ? Format.load(v) : i18nc("@info:tooltip no reading", "unavailable");
        return i18nc("@info accessible name of the load averages", "%1 over 1 minute, %2 over 5 minutes, %3 over 15 minutes",
                     spoken(one), spoken(five), spoken(fifteen));
    }

    // Readings only this popup shows; the Monitor never subscribes these ids.
    // They're read as often as the graph, so the whole popup moves together.
    Sensors.Sensor { id: frequency; sensorId: "cpu/all/averageFrequency"; updateRateLimit: popup.monitor.readInterval }
    Sensors.Sensor { id: load1; sensorId: "cpu/loadaverages/loadaverage1" }
    Sensors.Sensor { id: load5; sensorId: "cpu/loadaverages/loadaverage5" }
    Sensors.Sensor { id: load15; sensorId: "cpu/loadaverages/loadaverage15" }

    PopupHeader {
        ringValue: popup.monitor.cpuUsage
        interval: popup.monitor.sampleInterval
        title: i18nc("@title", "CPU")
        subtitle: {
            const m = popup.monitor;
            const count = m.cpuCores > 0 && m.cpuThreads > 0
                ? i18nc("@info cores and threads, e.g. 8C / 16T", "%1C / %2T", m.cpuCores, m.cpuThreads) : "";
            return [m.cpuModel, count].filter(s => s !== "").join(" · ");
        }
        value: Format.temperature(popup.monitor.cpuTemperature, popup.monitor.fahrenheit)
        degreeUnit: popup.monitor.fahrenheit ? "F" : "C"
        valueColor: {
            const level = popup.monitor.heat(popup.monitor.cpuTemperature);
            return level === 2 ? Kirigami.Theme.negativeTextColor
                 : level === 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
        }
        caption: words.sensorName(popup.monitor.cpuTemperatureLabel)
    }

    Words {
        id: words
        monitor: popup.monitor
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 1.5)
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        columns: 2
        rowSpacing: Kirigami.Units.largeSpacing
        columnSpacing: Kirigami.Units.largeSpacing
        uniformCellWidths: true

        Tile {
            Layout.columnSpan: 2
            caption: i18nc("@title:group", "Usage")
            spans: popup.monitor
            graphTop: i18nc("@info a percentage", "%1%", Format.percent(100))

            Graph {
                Layout.fillWidth: true
                values: popup.monitor.cpuHistory
                highs: popup.monitor.cpuHighs
                length: popup.monitor.historyLength
            }
        }

        // Under the usage it follows, on the same span and width, so a
        // burst of load lines up with the rise it causes.
        TemperatureTile {
            Layout.columnSpan: 2
            monitor: popup.monitor
            history: popup.monitor.cpuTemperatureHistory
            highs: popup.monitor.cpuTemperatureHighs
            extent: popup.monitor.cpuTemperatureExtent
        }

        Tile {
            caption: i18nc("@title:group", "Frequency")
            foot: frequencyReading

            Reading {
                id: frequencyReading
                readonly property var f: Format.frequency(popup.sensorValue(frequency))
                value: f.value
                unit: f.unit
                pointSize: Kirigami.Theme.defaultFont.pointSize * 1.38
            }
        }

        Tile {
            caption: i18nc("@title:group", "Load average")
            foot: lastMinute

            // The last minute large, then the 5 and 15 minute averages dimmer,
            // evenly spaced and in reading order under mirroring too. The
            // spans don't fit beside the caption in a half-width tile, so
            // only the spoken name carries them.
            RowLayout {
                id: load
                readonly property real pointSize: Kirigami.Theme.defaultFont.pointSize * 1.38
                spacing: Kirigami.Units.largeSpacing
                Accessible.role: Accessible.StaticText
                Accessible.name: popup.loadAverageName(popup.sensorValue(load1), popup.sensorValue(load5),
                                                       popup.sensorValue(load15))

                Reading {
                    id: lastMinute
                    Layout.alignment: Qt.AlignBaseline
                    value: Format.load(popup.sensorValue(load1))
                    pointSize: load.pointSize
                    accessibleIgnored: true
                }

                Repeater {
                    model: [load5, load15]

                    delegate: Text {
                        required property var modelData
                        Layout.alignment: Qt.AlignBaseline
                        text: Format.load(popup.sensorValue(modelData))
                        color: Style.dim(Kirigami.Theme.textColor)
                        font.family: Kirigami.Theme.defaultFont.family
                        font.features: ({ "tnum": 1 })
                        font.pointSize: Style.unitPointSize(load.pointSize, Kirigami.Theme.smallFont.pointSize)
                        textFormat: Text.PlainText
                        Accessible.ignored: true
                    }
                }
            }
        }

        Tile {
            id: perThread

            Layout.columnSpan: 2
            caption: i18nc("@title:group usage of each CPU thread", "Per thread")

            // Balanced rows of bars at least 2 px wide, so a 256-thread
            // machine still shows every thread.
            GridLayout {
                id: bars

                readonly property int count: popup.monitor.cpuIds.length
                readonly property int gap: count > 32 ? 1 : 3
                // From the tile rather than this layout's own width, which it
                // only learns mid-layout: changing columns then makes the
                // layout rearrange itself recursively. The rows' height still
                // follows the width, so on Qt 6.6 a host that sized the popup
                // straight from the Loader's preferred size, rather than a
                // resize later as AppletPopup does, reports a binding loop on
                // preferredHeight with more than 32 threads.
                readonly property real available: perThread.width - 2 * perThread.horizontalPadding
                readonly property int maxColumns: Math.max(1, Math.floor((available + gap) / (2 + gap)))
                // One row until the tile has a width to fit, and while no thread is known.
                readonly property int rowCount: available > 0 ? Math.max(1, Math.ceil(count / maxColumns)) : 1

                // Asks for no width of its own: a width hint that grew with the
                // columns would feed back into the tile's width, which follows
                // its content until the popup lays it out.
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                Layout.preferredHeight: Math.round(Kirigami.Units.gridUnit * (1.9 + 0.9 * (rowCount - 1)))
                columns: Math.max(1, Math.ceil(count / rowCount))
                columnSpacing: gap
                rowSpacing: Kirigami.Units.smallSpacing
                uniformCellWidths: true
                uniformCellHeights: true

                Repeater {
                    // ksystemstats names CPUs by their /proc/cpuinfo number,
                    // which skips offline and SMT-disabled threads.
                    model: popup.monitor.cpuIds

                    delegate: Rectangle {
                        id: bar

                        required property int modelData
                        readonly property real usage: popup.sensorValue(sensor)

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 2
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                        clip: true

                        Accessible.role: Accessible.ProgressBar
                        Accessible.name: i18nc("@info accessible name of a thread's usage bar", "Thread %1", modelData + 1)
                        Accessible.description: i18nc("@info a percentage", "%1%", Format.percent(usage))

                        Sensors.Sensor {
                            id: sensor
                            sensorId: "cpu/cpu" + bar.modelData + "/usage"
                            updateRateLimit: popup.monitor.readInterval
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: parent.height * (Number.isFinite(bar.usage) ? Math.max(0, Math.min(100, bar.usage)) / 100 : 0)
                            color: Kirigami.Theme.textColor

                            Behavior on height {
                                NumberAnimation { duration: Kirigami.Units.shortDuration }
                            }
                        }
                    }
                }
            }
        }
    }

    Divider {}

    ProcessList {
        key: "usage"
        threads: popup.threads
        sample: popup.monitor.processSample || null
    }
}
