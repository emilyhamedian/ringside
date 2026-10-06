// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/style.js" as Style
import ".."

// One section per awake GPU, the outer ring's first, the second under a rule
// and drawn dimmer as its ring is. A powered-down GPU is a single line at the
// end; nothing here reads it, so opening the popup can't wake it.
PopupPage {
    id: popup

    readonly property var slots: [popup.monitor.gpuOuter, popup.monitor.gpuInner].filter(slot => slot.present)
    readonly property var awake: slots.filter(slot => slot.phase !== "asleep")
    readonly property var asleep: slots.filter(slot => slot.phase === "asleep")

    PopupHeader {
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        ringShown: false
        title: i18nc("@title", "GPU")
        // With two GPUs, each section's own line says which is which.
        subtitle: {
            const kind = popup.slots.length === 1 ? popup.slots[0].kind : "";
            return kind === "discrete" ? i18nc("@info kind of GPU", "Discrete")
                 : kind === "integrated" ? i18nc("@info kind of GPU", "Integrated") : "";
        }
    }

    Repeater {
        model: popup.awake

        delegate: Section {
            required property var modelData
            required property int index

            monitor: popup.monitor
            slot: modelData
            temperatureName: words.sensorName(modelData.temperatureLabel)
            inner: index > 0
        }
    }

    Words {
        id: words
        monitor: popup.monitor
    }

    Repeater {
        model: popup.asleep

        delegate: ColumnLayout {
            id: sleeper

            required property var modelData

            Layout.fillWidth: true
            spacing: 0

            Divider {
                visible: popup.awake.length > 0
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: Kirigami.Units.largeSpacing
                Layout.bottomMargin: Kirigami.Units.largeSpacing
                text: i18nc("@info a powered-down GPU: its name, then off", "%1 · off", sleeper.modelData.name)
                color: Style.dim(Kirigami.Theme.textColor)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
            }
        }
    }

    component Section: ColumnLayout {
        id: section

        required property var monitor
        // A GpuReader, or an object with the same properties.
        required property var slot
        // The slot's temperature label in plain words.
        required property string temperatureName
        property bool inner: false

        readonly property color dim: Style.dim(Kirigami.Theme.textColor)
        readonly property color tone: inner ? dim : Kirigami.Theme.textColor
        // Intel GPUs publish no temperature, so theirs is left out rather than shown as a dash.
        readonly property bool temperatureShown: slot.reportsTemperature
        readonly property bool hasPower: Number.isFinite(slot.power)
        readonly property real tilePointSize: Kirigami.Theme.defaultFont.pointSize * 1.23

        Layout.fillWidth: true
        visible: slot.present
        spacing: 0

        Divider {
            visible: section.inner
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
            Layout.rightMargin: Layout.leftMargin
            Layout.topMargin: section.inner ? Math.round(Kirigami.Units.largeSpacing * 1.5) : Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.largeSpacing
            spacing: Math.round(Kirigami.Units.largeSpacing * 1.25)

            RingGauge {
                Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 2.2)
                Layout.preferredHeight: Layout.preferredWidth
                strokeWidth: 3.5
                color: section.tone
                value: section.slot.usage
                text: Number.isFinite(value) ? i18nc("@info a percentage", "%1%", Format.percent(value)) : "–"
                textScale: 0.275

                Accessible.role: Accessible.ProgressBar
                Accessible.name: section.slot.name
                Accessible.description: text
            }

            // Stacked rather than on one line as in the mock: real names
            // ("AMD Radeon 780M Graphics") don't fit beside the descriptor.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: section.slot.name
                    color: Kirigami.Theme.textColor
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.96
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignLeft
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: {
                        const slot = section.slot;
                        if (slot.kind === "integrated") {
                            return i18nc("@info integrated GPU using system memory", "iGPU · shared");
                        }
                        if (slot.kind !== "discrete") {
                            return "";
                        }
                        const total = Format.bytes(slot.knownVramTotal, true);
                        return total.unit ? i18nc("@info discrete GPU and its memory, e.g. dGPU · 8 GiB",
                                                  "dGPU · %1 %2", total.value, total.unit)
                                          : i18nc("@info discrete GPU", "dGPU");
                    }
                    color: section.dim
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignLeft
                }
            }

            RowLayout {
                spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)

                Text {
                    Layout.alignment: Qt.AlignBaseline
                    visible: text !== "" && section.temperatureShown
                    text: section.temperatureName
                    color: section.dim
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.81
                    textFormat: Text.PlainText
                }

                Reading {
                    Layout.alignment: Qt.AlignBaseline
                    visible: section.temperatureShown
                    value: Format.temperature(section.slot.temperature, section.monitor.fahrenheit)
                    degreeUnit: section.monitor.fahrenheit ? "F" : "C"
                    color: {
                        const level = section.monitor.heat(section.slot.temperature);
                        return level === 2 ? Kirigami.Theme.negativeTextColor
                             : level === 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
            Layout.rightMargin: Layout.leftMargin
            Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
            columns: (section.slot.reportsVram ? 1 : 0) + 1 + (section.hasPower ? 1 : 0)
            rowSpacing: Kirigami.Units.largeSpacing
            columnSpacing: Kirigami.Units.largeSpacing
            // Equal columns while the VRAM reading fits one; a long one
            // ("11.6 / 16 GiB") takes a wider column rather than overflow.
            uniformCellWidths: vram.implicitWidth * columns + columnSpacing * (columns - 1) <= width

            Tile {
                Layout.columnSpan: parent.columns
                caption: i18nc("@title:group", "Usage")
                graphSeconds: section.monitor.historySeconds

                Graph {
                    Layout.fillWidth: true
                    Layout.preferredHeight: section.inner ? Math.round(Kirigami.Units.gridUnit * 2) : implicitHeight
                    values: section.slot.history
                    length: section.monitor.historyLength
                    color: section.tone
                    // Graph scales the fill by the colour's alpha; undo that for the dimmer tone.
                    fillOpacity: (section.inner ? 0.1 : 0.15) / section.tone.a
                }
            }

            Tile {
                id: vram
                visible: section.slot.reportsVram
                caption: i18nc("@title:group video memory", "VRAM")
                foot: vramReading

                Reading {
                    id: vramReading
                    // An integrated GPU's share of system memory has no meaningful total.
                    // The known size stands in while a resting GPU's readings are held.
                    readonly property bool ofTotal: section.slot.kind === "discrete"
                    readonly property var b: ofTotal ? Format.bytesOf(section.slot.vramUsed, section.slot.knownVramTotal)
                                                     : Format.bytes(section.slot.vramUsed, false)
                    value: b.value
                    unit: ofTotal && b.unit ? "/ " + b.total + " " + b.unit : b.unit
                    pointSize: section.tilePointSize
                }
            }

            Tile {
                caption: i18nc("@title:group GPU core clock", "Clock")
                foot: clockReading

                Reading {
                    id: clockReading
                    readonly property var f: Format.frequency(section.slot.clock)
                    value: f.value
                    unit: f.unit
                    pointSize: section.tilePointSize
                }
            }

            Tile {
                visible: section.hasPower
                caption: i18nc("@title:group GPU power draw", "Power")
                foot: powerReading

                Reading {
                    id: powerReading
                    readonly property var w: Format.watts(section.slot.power)
                    value: w.value
                    unit: w.unit
                    pointSize: section.tilePointSize
                }
            }
        }
    }
}
