pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/style.js" as Style
import ".."

// One section per ring: the outer ring's GPU, then the inner ring's under a
// rule, drawn dimmer as its ring is. A powered-down GPU gets a note instead
// of readings; nothing here reads it, so opening the popup can't wake it.
PopupPage {
    id: popup

    PopupHeader {
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        ringShown: false
        title: i18nc("@title", "GPU")
        subtitle: [popup.monitor.gpuOuter, popup.monitor.gpuInner]
            .filter(slot => slot.present)
            .map(slot => slot.kind === "discrete" ? i18nc("@info kind of GPU", "Discrete")
                       : slot.kind === "integrated" ? i18nc("@info kind of GPU", "Integrated") : "")
            .filter(kind => kind !== "")
            .join(" · ")
    }

    Section {
        monitor: popup.monitor
        slot: popup.monitor.gpuOuter
    }

    Section {
        monitor: popup.monitor
        slot: popup.monitor.gpuInner
        inner: true
    }

    component Section: ColumnLayout {
        id: section

        required property var monitor
        // A GpuReader, or an object with the same properties.
        required property var slot
        property bool inner: false

        readonly property bool asleep: slot.phase === "asleep"
        readonly property color dim: Style.dim(Kirigami.Theme.textColor)
        readonly property color tone: inner ? dim : Kirigami.Theme.textColor
        // Intel GPUs publish no temperature, so theirs is left out rather than shown as a dash.
        readonly property bool temperatureShown: !asleep && slot.reportsTemperature
        readonly property bool hasPower: Number.isFinite(slot.power)
        readonly property real tilePointSize: Kirigami.Theme.defaultFont.pointSize * 1.23

        Layout.fillWidth: true
        visible: slot.present
        spacing: 0

        Rectangle {
            visible: section.inner
            Layout.fillWidth: true
            Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
            Layout.rightMargin: Layout.leftMargin
            Layout.preferredHeight: 1
            color: Qt.alpha(Kirigami.Theme.textColor, 0.1)
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
                text: section.asleep ? "" : Number.isFinite(value) ? Math.round(value) + "%" : "–"
                textScale: 0.275

                Accessible.role: Accessible.ProgressBar
                Accessible.name: section.slot.name
                Accessible.description: section.asleep ? i18nc("@info the GPU is powered down", "Asleep") : text
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
                    text: section.slot.temperatureLabel
                    color: section.dim
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.81
                    textFormat: Text.PlainText
                }

                Reading {
                    Layout.alignment: Qt.AlignBaseline
                    visible: section.temperatureShown
                    value: Format.temperature(section.slot.temperature, section.monitor.fahrenheit)
                    degree: true
                    color: {
                        const level = section.monitor.heat(section.slot.temperature);
                        return level === 2 ? Kirigami.Theme.negativeTextColor
                             : level === 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
                    }
                }

                Text {
                    visible: section.asleep
                    text: i18nc("@info the GPU is powered down", "off")
                    color: section.dim
                    textFormat: Text.PlainText
                }
            }
        }

        Text {
            visible: section.asleep
            Layout.fillWidth: true
            Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
            Layout.rightMargin: Layout.leftMargin
            Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
            text: i18nc("@info", "Powered down to save energy. Readings resume when something wakes it.")
            color: section.dim
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
        }

        GridLayout {
            visible: !section.asleep
            Layout.fillWidth: true
            Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
            Layout.rightMargin: Layout.leftMargin
            Layout.bottomMargin: Layout.leftMargin
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

                Reading {
                    // An integrated GPU's share of system memory has no meaningful total.
                    // The known size stands in while a resting GPU's readings are held.
                    readonly property bool ofTotal: section.slot.kind === "discrete"
                    readonly property var b: ofTotal ? Format.bytesOf(section.slot.vramUsed, section.slot.knownVramTotal)
                                                     : Format.bytes(section.slot.vramUsed, false)
                    value: b.value
                    unit: ofTotal && b.unit ? "/ " + b.total + " " + b.unit : b.unit
                    unitScale: 0.69
                    pointSize: section.tilePointSize
                }
            }

            Tile {
                caption: i18nc("@title:group GPU core clock", "Clock")

                Reading {
                    readonly property var f: Format.frequency(section.slot.clock)
                    value: f.value
                    unit: f.unit
                    unitScale: 0.69
                    pointSize: section.tilePointSize
                }
            }

            Tile {
                visible: section.hasPower
                caption: i18nc("@title:group GPU power draw", "Power")

                Reading {
                    readonly property var w: Format.watts(section.slot.power)
                    value: w.value
                    unit: w.unit
                    unitScale: 0.69
                    pointSize: section.tilePointSize
                }
            }
        }
    }
}
