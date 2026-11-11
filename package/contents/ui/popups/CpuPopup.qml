// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import "../code/format.js" as Format
import "../code/hardware.js" as Hardware
import "../code/style.js" as Style
import ".."

// One section for the CPU, or on a machine with more than one CPU package
// (socket) one per package, as the GPU popup has one per GPU: each with its
// usage, its temperature where ksystemstats tells the packages apart, and
// its threads, its graphs marking a moment only among themselves. What
// ksystemstats reads only for the whole machine, the frequency, the load and
// there the temperature, follows the sections, then the processes.
PopupPage {
    id: popup

    readonly property int threads: monitor.cpuThreads
    readonly property var packages: monitor.cpuPackages ?? []
    readonly property bool split: packages.length > 1
    readonly property real frequencyValue: Hardware.sensorValue(frequency)
    readonly property var loadSensors: [load1, load5, load15]

    // Readings only this popup shows; the Monitor never subscribes these ids.
    // They're read as often as the graph, so the whole popup moves together.
    Sensors.Sensor { id: frequency; sensorId: "cpu/all/averageFrequency"; updateRateLimit: popup.monitor.readInterval }
    Sensors.Sensor { id: load1; sensorId: "cpu/loadaverages/loadaverage1" }
    Sensors.Sensor { id: load5; sensorId: "cpu/loadaverages/loadaverage5" }
    Sensors.Sensor { id: load15; sensorId: "cpu/loadaverages/loadaverage15" }

    Words {
        id: words
        monitor: popup.monitor
    }

    // The machine's one CPU.
    Repeater {
        model: popup.split ? 0 : 1

        delegate: Section {
            monitor: popup.monitor
            cursor: popup.graphCursor
            processesLoading: processList.loading
            title: i18nc("@title", "CPU")
            modelName: popup.monitor.cpuModel
            cores: popup.monitor.cpuCores
            threads: popup.monitor.cpuThreads
            ids: popup.monitor.cpuIds
            usage: popup.monitor.cpuUsage
            history: popup.monitor.cpuHistory
            highs: popup.monitor.cpuHighs
            temperature: popup.monitor.cpuTemperature
            temperatureHistory: popup.monitor.cpuTemperatureHistory
            temperatureHighs: popup.monitor.cpuTemperatureHighs
            temperatureExtent: popup.monitor.cpuTemperatureExtent
            machine: true
            frequency: popup.frequencyValue
            loadSensors: popup.loadSensors
        }
    }

    // Each package, numbered from 1 in ksystemstats' order.
    Repeater {
        model: popup.split ? popup.packages.length : 0

        delegate: Section {
            required property int index
            readonly property var cpu: popup.packages[index] ?? null

            monitor: popup.monitor
            first: index === 0
            processesLoading: index === 0 && processList.loading
            title: i18nc("@title one of several CPU packages, numbered from 1", "CPU %1", index + 1)
            modelName: cpu?.model ?? ""
            cores: cpu?.cores ?? 0
            threads: cpu?.threads ?? 0
            ids: cpu?.ids ?? []
            usage: cpu?.usage ?? NaN
            history: cpu?.history ?? []
            highs: cpu?.highs ?? []
            temperatureShown: popup.monitor.cpuPackageTemperatures
            temperature: cpu?.temperature ?? NaN
            temperatureHistory: cpu?.temperatureHistory ?? []
            temperatureHighs: cpu?.temperatureHighs ?? []
            temperatureExtent: cpu?.temperatureExtent ?? []
        }
    }

    // The machine's readings under its packages.
    Repeater {
        model: popup.split ? 1 : 0

        delegate: ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Divider {}

            GridLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: Kirigami.Units.largeSpacing
                Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
                columns: 2
                rowSpacing: Kirigami.Units.largeSpacing
                columnSpacing: Kirigami.Units.largeSpacing
                uniformCellWidths: true

                // Where the packages share one temperature, it is the machine's.
                TemperatureTile {
                    cursor: popup.graphCursor
                    graphed: !popup.monitor.cpuPackageTemperatures
                    Layout.columnSpan: 2
                    monitor: popup.monitor
                    history: popup.monitor.cpuTemperatureHistory
                    highs: popup.monitor.cpuTemperatureHighs
                    extent: popup.monitor.cpuTemperatureExtent
                }

                Tile {
                    id: machineTemperature
                    visible: !popup.monitor.cpuPackageTemperatures
                    caption: i18nc("@title:group", "Temperature")
                    detail: words.sensorName(popup.monitor.cpuTemperatureLabel)
                    foot: machineTemperatureReading

                    Reading {
                        id: machineTemperatureReading
                        value: Format.temperature(popup.monitor.cpuTemperature, popup.monitor.fahrenheit)
                        degreeUnit: popup.monitor.fahrenheit ? "F" : "C"
                        color: Style.levelColor(popup.monitor.heat(popup.monitor.cpuTemperature), Kirigami.Theme)
                        pointSize: Style.tilePointSize(Kirigami.Theme.defaultFont.pointSize)
                    }
                }

                FrequencyTile {
                    frequency: popup.frequencyValue
                }

                LoadTile {
                    Layout.columnSpan: machineTemperature.visible ? 2 : 1
                    sensors: popup.loadSensors
                }
            }
        }
    }

    Divider {
        visible: processList.visible
    }

    ProcessList {
        id: processList
        active: popup.visible && popup.monitor.processesReadable
        key: "usage"
        threads: popup.threads
        sample: popup.monitor.processSample || null
    }

    // A CPU's header and graphs, then its threads' usage. The machine's one
    // CPU has the frequency and load between them.
    component Section: ColumnLayout {
        id: section

        required property var monitor
        // Marks one moment across this CPU's graphs only.
        property GraphCursor cursor: GraphCursor {
            scope: section
            monitor: section.monitor
        }
        // Any section after the first is set off from it by a rule.
        property bool first: true
        property bool processesLoading: false
        property string title
        property string modelName
        property int cores
        property int threads
        // ksystemstats' numbers for its threads.
        property var ids: []
        property real usage: NaN
        property var history: []
        property var highs: []
        property bool temperatureShown: true
        property real temperature: NaN
        property var temperatureHistory: []
        property var temperatureHighs: []
        property var temperatureExtent: []
        // The whole machine's: it shows the frequency and load too.
        property bool machine: false
        property real frequency: NaN
        property var loadSensors: []

        Layout.fillWidth: true
        spacing: 0

        Words {
            id: sectionWords
            monitor: section.monitor
        }

        Divider {
            visible: !section.first
        }

        PopupHeader {
            processesLoading: section.processesLoading
            processesExpected: true
            ringValue: section.usage
            interval: section.monitor.sampleInterval
            title: section.title
            subtitle: {
                const count = section.cores > 0 && section.threads > 0
                    ? i18nc("@info cores and threads, e.g. 8C / 16T", "%1C / %2T", section.cores, section.threads) : "";
                return sectionWords.joined([section.modelName, count]);
            }
            value: section.temperatureShown ? Format.temperature(section.temperature, section.monitor.fahrenheit) : ""
            degreeUnit: section.monitor.fahrenheit ? "F" : "C"
            valueColor: Style.levelColor(section.monitor.heat(section.temperature), Kirigami.Theme)
            caption: section.temperatureShown ? sectionWords.sensorName(section.monitor.cpuTemperatureLabel) : ""
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
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
                spans: section.monitor
                graphTop: sectionWords.percent(100)
                graphReading: usageGraph.reading

                Graph {
                    id: usageGraph
                    cursor: section.cursor
                    Layout.fillWidth: true
                    describe: i => sectionWords.pointText(values, highs, i, v => sectionWords.percent(v))
                    values: section.history
                    highs: section.highs
                    length: section.monitor.historyLength
                }
            }

            // Under the usage it follows, on the same span and width, so a
            // burst of load lines up with the rise it causes.
            TemperatureTile {
                cursor: section.cursor
                graphed: section.temperatureShown
                Layout.columnSpan: 2
                monitor: section.monitor
                history: section.temperatureHistory
                highs: section.temperatureHighs
                extent: section.temperatureExtent
            }

            FrequencyTile {
                visible: section.machine
                frequency: section.frequency
            }

            LoadTile {
                visible: section.machine
                sensors: section.loadSensors
            }

            ThreadTile {
                Layout.columnSpan: 2
                monitor: section.monitor
                ids: section.ids
            }
        }
    }

    component FrequencyTile: Tile {
        id: frequencyTile

        property real frequency: NaN

        caption: i18nc("@title:group", "Frequency")
        foot: frequencyReading

        Reading {
            id: frequencyReading
            readonly property var f: Format.frequency(frequencyTile.frequency)
            value: f.value
            unit: f.unit
            pointSize: Style.tilePointSize(Kirigami.Theme.defaultFont.pointSize)
        }
    }

    component LoadTile: Tile {
        id: loadTile

        // The 1, 5 and 15 minute load averages' Sensors.
        property var sensors: []
        readonly property var averages: sensors.map(Hardware.sensorValue)

        // The load averages spoken as one, a missing one as a word rather
        // than the dash shown on screen.
        function loadAverageName(one, five, fifteen) {
            const spoken = v => Format.usable(v) ? Format.load(v) : i18nc("@info:tooltip no reading", "unavailable");
            return i18nc("@info accessible name of the load averages", "%1 over 1 minute, %2 over 5 minutes, %3 over 15 minutes",
                         spoken(one), spoken(five), spoken(fifteen));
        }

        caption: i18nc("@title:group", "Load average")
        foot: lastMinute

        // The last minute large, then the 5 and 15 minute averages dimmer,
        // evenly spaced and in reading order under mirroring too. The
        // spans don't fit beside the caption in a half-width tile, so
        // only the spoken name carries them. A Row rather than a
        // RowLayout: the tile's layout sits inside a Rectangle, out of
        // the popup's reach, and on Qt 6.6 a nested layout there only
        // reports its new width when the popup next lays out, so the
        // first readings arriving set off a layout polish loop.
        Row {
            id: load
            readonly property real pointSize: Style.tilePointSize(Kirigami.Theme.defaultFont.pointSize)
            spacing: Kirigami.Units.largeSpacing
            Accessible.role: Accessible.StaticText
            Accessible.name: loadTile.loadAverageName(loadTile.averages[0], loadTile.averages[1], loadTile.averages[2])

            Reading {
                id: lastMinute
                value: Format.load(loadTile.averages[0])
                pointSize: load.pointSize
                accessibleIgnored: true
            }

            Repeater {
                model: loadTile.sensors.slice(1)

                delegate: Text {
                    required property var modelData
                    anchors.baseline: lastMinute.baseline
                    text: Format.load(Hardware.sensorValue(modelData))
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

    component ThreadTile: Tile {
        id: perThread

        required property var monitor
        // ksystemstats names CPUs by their /proc/cpuinfo number, which
        // skips offline and SMT-disabled threads.
        property var ids: []

        caption: i18nc("@title:group usage of each CPU thread", "Per thread")

        // Balanced rows of bars at least 2 px wide, so a 256-thread
        // machine still shows every thread.
        GridLayout {
            id: bars

            readonly property int count: perThread.ids.length
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
                model: perThread.ids

                delegate: Rectangle {
                    id: bar

                    required property int modelData
                    // The Monitor reads each thread, so no id has a second Sensor.
                    readonly property real usage: Hardware.sensorValue(perThread.monitor.cpuThreadSensors?.[modelData])

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 2
                    color: Qt.alpha(Kirigami.Theme.textColor, Style.TRACK)
                    clip: true

                    Accessible.role: Accessible.ProgressBar
                    Accessible.name: i18nc("@info accessible name of a thread's usage bar", "Thread %1", modelData + 1)
                    Accessible.description: i18nc("@info a percentage", "%1%", Format.percent(usage))

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
