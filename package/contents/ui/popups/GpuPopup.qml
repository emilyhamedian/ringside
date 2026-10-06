// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/style.js" as Style
import ".."

// One section per awake GPU, the outer ring's first, each under a header as
// in the other popups and the second after a rule. A powered-down GPU is a
// single line at the end; nothing here reads it, so opening the popup can't
// wake it.
PopupPage {
    id: popup

    readonly property var slots: [popup.monitor.gpuOuter, popup.monitor.gpuInner].filter(slot => slot.present)
    readonly property var awake: slots.filter(slot => slot.phase !== "asleep")
    readonly property var asleep: slots.filter(slot => slot.phase === "asleep")

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
            required property int index

            Layout.fillWidth: true
            spacing: 0

            Divider {
                visible: popup.awake.length > 0
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
                Layout.rightMargin: Layout.leftMargin
                // Where it opens the page, as far down as a header would start.
                Layout.topMargin: popup.awake.length > 0 || sleeper.index > 0
                    ? Kirigami.Units.largeSpacing : Math.round(Kirigami.Units.largeSpacing * 1.75)
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
        // The inner ring's GPU, set off from the first by a rule.
        property bool inner: false

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

        PopupHeader {
            ringValue: section.slot.usage
            title: section.slot.name
            subtitle: {
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
            value: section.temperatureShown ? Format.temperature(section.slot.temperature, section.monitor.fahrenheit) : ""
            degreeUnit: section.monitor.fahrenheit ? "F" : "C"
            valueColor: {
                const level = section.monitor.heat(section.slot.temperature);
                return level === 2 ? Kirigami.Theme.negativeTextColor
                     : level === 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
            }
            caption: section.temperatureName
            // NVIDIA names no sensor.
            keepsCaptionLine: true
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
            Layout.rightMargin: Layout.leftMargin
            Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 1.5)
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
                    values: section.slot.history
                    length: section.monitor.historyLength
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
