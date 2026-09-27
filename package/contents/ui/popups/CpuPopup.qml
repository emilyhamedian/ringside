pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import "../code/format.js" as Format
import ".."

PopupPage {
    id: popup

    readonly property int threads: monitor.cpuThreads

    function sensorValue(sensor) {
        return sensor && typeof sensor.value === "number" ? sensor.value : NaN;
    }

    // Readings only this popup shows; the Monitor never subscribes these ids.
    Sensors.Sensor { id: frequency; sensorId: "cpu/all/averageFrequency"; updateRateLimit: popup.monitor.interval }
    Sensors.Sensor { id: load1; sensorId: "cpu/loadaverages/loadaverage1" }
    Sensors.Sensor { id: load5; sensorId: "cpu/loadaverages/loadaverage5" }
    Sensors.Sensor { id: load15; sensorId: "cpu/loadaverages/loadaverage15" }

    Instantiator {
        id: perThread
        model: popup.threads
        delegate: Sensors.Sensor {
            required property int index
            sensorId: "cpu/cpu" + index + "/usage"
            updateRateLimit: popup.monitor.interval
        }
    }

    PopupHeader {
        ringValue: popup.monitor.cpuUsage
        title: i18nc("@title", "CPU")
        subtitle: {
            const m = popup.monitor;
            const count = m.cpuCores > 0 && m.cpuThreads > 0
                ? i18nc("@info cores and threads, e.g. 8C / 16T", "%1C / %2T", m.cpuCores, m.cpuThreads) : "";
            return [m.cpuModel, count].filter(s => s !== "").join(" · ");
        }
        value: Format.temperature(popup.monitor.cpuTemperature, popup.monitor.fahrenheit)
        degree: true
        valueColor: {
            const level = popup.monitor.heat(popup.monitor.cpuTemperature);
            return level === 2 ? Kirigami.Theme.negativeTextColor
                 : level === 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
        }
        caption: popup.monitor.cpuTemperatureLabel
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 1.5)
        Layout.bottomMargin: Layout.leftMargin
        columns: 2
        rowSpacing: Kirigami.Units.largeSpacing
        columnSpacing: Kirigami.Units.largeSpacing
        uniformCellWidths: true

        Tile {
            Layout.columnSpan: 2
            caption: i18nc("@title:group graph span, e.g. Usage · 60 s", "Usage · %1",
                           Format.duration(popup.monitor.historySeconds))

            Graph {
                Layout.fillWidth: true
                values: popup.monitor.cpuHistory
                length: popup.monitor.historyLength
            }
        }

        Tile {
            caption: i18nc("@title:group", "Frequency")

            Reading {
                readonly property var f: Format.frequency(popup.sensorValue(frequency))
                value: f.value
                unit: f.unit
                unitScale: 0.67
                pointSize: Kirigami.Theme.defaultFont.pointSize * 1.38
            }
        }

        Tile {
            caption: i18nc("@title:group", "Load average")

            Reading {
                value: Format.fixed(popup.sensorValue(load1), 2)
                unit: Format.fixed(popup.sensorValue(load5), 2) + " · " + Format.fixed(popup.sensorValue(load15), 2)
                unitScale: 0.67
                pointSize: Kirigami.Theme.defaultFont.pointSize * 1.38
            }
        }

        Tile {
            Layout.columnSpan: 2
            caption: i18nc("@title:group usage of each CPU thread", "Per thread")

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(Kirigami.Units.gridUnit * 1.9)
                spacing: popup.threads > 32 ? 1 : 3

                Repeater {
                    model: popup.threads

                    delegate: Rectangle {
                        id: bar

                        required property int index
                        readonly property real usage: {
                            perThread.count;
                            return popup.sensorValue(perThread.objectAt(index));
                        }

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 2
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                        clip: true

                        Accessible.role: Accessible.ProgressBar
                        Accessible.name: i18nc("@info accessible name of a thread's usage bar", "Thread %1", index + 1)
                        Accessible.description: Format.percent(usage) + "%"

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

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
    }

    ProcessList {
        key: "usage"
        threads: popup.threads
    }
}
