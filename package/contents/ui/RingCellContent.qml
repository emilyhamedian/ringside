import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "code/format.js" as Format

// A panel ring with the item's name over its main reading: the CPU's
// temperature, the GPUs' temperatures, or memory in use.
RowLayout {
    id: content

    required property var monitor
    required property string item
    required property real ring
    required property bool textShown
    required property bool twoLines

    readonly property var gpuOuter: monitor.gpuOuter
    readonly property var gpuInner: monitor.gpuInner
    readonly property bool dual: item === "gpu" && gpuInner.present
    readonly property color dimColor: Qt.alpha(Kirigami.Theme.textColor, 0.6)
    readonly property real valuePointSize: Kirigami.Theme.defaultFont.pointSize * 0.96

    function heatColor(celsius, normal) {
        const level = monitor.heat(celsius);
        return level === 2 ? Kirigami.Theme.negativeTextColor : level === 1 ? Kirigami.Theme.neutralTextColor : normal;
    }

    spacing: Kirigami.Units.largeSpacing

    RingGauge {
        Layout.preferredWidth: content.ring
        Layout.preferredHeight: content.ring
        inner: content.dual
        value: content.item === "cpu" ? content.monitor.cpuUsage
             : content.item === "memory" ? content.monitor.memoryPercent : content.gpuOuter.usage
        innerValue: content.gpuInner.usage
        text: Format.percent(value)
    }

    ColumnLayout {
        visible: content.textShown
        spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)

        Text {
            visible: content.twoLines
            text: content.item === "cpu" ? i18nc("@label short for processor", "CPU")
                : content.item === "gpu" ? i18nc("@label short for graphics card", "GPU")
                : i18nc("@label short for memory", "MEM")
            color: content.dimColor
            font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.95
            font.letterSpacing: Kirigami.Theme.smallFont.pointSize * 0.08
            textFormat: Text.PlainText
        }

        RowLayout {
            spacing: Math.round(Kirigami.Units.smallSpacing * 1.5)

            Reading {
                readonly property var used: Format.bytes(content.monitor.memoryUsed)
                readonly property real celsius: content.item === "cpu" ? content.monitor.cpuTemperature
                                                                       : content.gpuOuter.temperature
                readonly property bool asleep: content.item === "gpu" && content.gpuOuter.phase === "asleep"

                degree: content.item !== "memory" && !asleep
                value: content.item === "memory" ? used.value
                     : asleep ? i18nc("@info:status the GPU is powered down", "off")
                     : Format.temperature(celsius, content.monitor.fahrenheit)
                unit: content.item === "memory" ? used.unit : ""
                color: asleep ? content.dimColor
                     : content.item === "memory" ? Kirigami.Theme.textColor
                     : content.heatColor(celsius, Kirigami.Theme.textColor)
                pointSize: content.valuePointSize
            }

            Reading {
                readonly property real celsius: content.gpuInner.temperature

                visible: content.dual
                degree: true
                value: Format.temperature(celsius, content.monitor.fahrenheit)
                color: content.heatColor(celsius, content.dimColor)
                pointSize: content.valuePointSize
            }
        }
    }
}
