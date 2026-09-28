// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/hardware.js" as Hardware
import "code/items.js" as Items
import "code/style.js" as Style

// One item in the Standalone layout, at Usage Rings' size: a ring over a
// one-line readout ("23% · 61°"), or for network and disk two lines of rates.
// Each readout part keeps the width the strip reserves for it (see
// StandaloneStrip.partWidths), so the dial keeps its size as the readings
// change. The strip sizes the cell, so the hover and pressed wash spans the
// strip's thickness, and gives it its tooltip; the face sits in its middle.
PanelCell {
    id: dial

    required property var monitor
    // Widths of the readout's parts at the base size, in order.
    required property var parts
    property real sizeFactor: 1
    readonly property real faceWidth: face.implicitWidth
    readonly property real faceHeight: face.implicitHeight
    property real nowMs: Date.now()

    readonly property bool usage: Items.isUsage(item)
    readonly property var entry: usage ? monitor.usage.entry(item) : null
    readonly property var weekly: entry?.weekly ?? null
    // The per-model limit drawn inside the weekly ring, or null.
    readonly property var limit: usage ? monitor.usage.inner(item) : null
    readonly property bool degraded: usage && monitor.usage.degraded(item)
    readonly property var gpuView: item === "gpu" ? Hardware.gpuView(monitor.gpuOuter, monitor.gpuInner) : null
    // The GPU the ring shows: a sleeping one drops out, as in the inline strip.
    readonly property var gpu: gpuView?.primary ?? null
    readonly property bool asleep: gpu?.phase === "asleep"
    readonly property real value: item === "cpu" ? monitor.cpuUsage
                                : item === "memory" ? monitor.memoryPercent
                                : item === "gpu" ? gpu.usage
                                : weekly?.percent ?? NaN
    readonly property bool innerShown: item === "gpu" ? gpuView.dual : limit !== null
    readonly property real innerValue: item === "gpu" ? monitor.gpuInner.usage : limit?.percent ?? NaN
    readonly property real celsius: item === "cpu" ? monitor.cpuTemperature : item === "gpu" ? gpu.temperature : NaN
    // The part after the separator: a temperature, memory in use, or the
    // inner limit. Intel GPUs publish no temperature.
    readonly property bool secondShown: item === "cpu" || item === "memory"
                                        || item === "gpu" && !asleep && gpu.reportsTemperature
                                        || usage && limit !== null
    readonly property string secondText: {
        if (item === "memory") {
            const used = Format.bytes(monitor.memoryUsed);
            return used.value + used.unit.charAt(0);
        }
        if (usage) {
            return percentText(innerValue);
        }
        return Format.temperatureValid(celsius) ? Format.temperature(celsius, monitor.fahrenheit) + "°" : "–";
    }

    function percentText(percent) {
        return Number.isFinite(percent) ? i18nc("@info:status a percentage", "%1%", Format.percent(percent)) : "–";
    }

    function tone(percent) {
        const level = Format.level(percent);
        return level === 2 ? Kirigami.Theme.negativeTextColor
             : level === 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
    }

    function heatColor(celsius) {
        const level = monitor.heat(celsius);
        return level === 2 ? Kirigami.Theme.negativeTextColor
             : level === 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
    }

    // The wash fills the cell, whichever way the strip runs.
    vertical: true
    description: words.describe(item, nowMs)

    Words {
        id: words
        monitor: dial.monitor
    }

    // Countdowns read in minutes.
    Timer {
        running: dial.usage && dial.visible
        interval: 60000
        repeat: true
        onTriggered: dial.nowMs = Date.now()
    }

    FontMetrics {
        id: metrics
        font.pointSize: Kirigami.Theme.smallFont.pointSize * dial.sizeFactor
        font.weight: Font.DemiBold
    }
    TextMetrics {
        id: capMetrics
        font: metrics.font
        text: "H"
    }
    // capitalHeight needs Qt 6.9; the ink of "H" stands in before that and can
    // round a pixel taller.
    readonly property real capHeight: metrics.capitalHeight ?? capMetrics.tightBoundingRect.height // qmllint disable missing-property

    Loader {
        id: face
        objectName: "face"
        anchors.centerIn: parent
        opacity: dial.degraded ? 0.55 : 1
        sourceComponent: Items.isRing(dial.item) ? ringFace : rateFace
    }

    component Part: Text {
        required property real reserve
        Layout.preferredWidth: reserve * dial.sizeFactor
        Layout.fillHeight: true
        verticalAlignment: Text.AlignTop
        color: Kirigami.Theme.textColor
        font: metrics.font
        textFormat: Text.PlainText
    }

    Component {
        id: ringFace

        ColumnLayout {
            spacing: Math.round(8 * dial.sizeFactor)

            RingGauge {
                id: gauge
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 52 * dial.sizeFactor
                Layout.preferredHeight: 52 * dial.sizeFactor
                strokeWidth: 3.5 * dial.sizeFactor
                innerStrokeWidth: 2 * dial.sizeFactor
                innerRadius: 17 * dial.sizeFactor
                value: dial.value
                inner: dial.innerShown
                innerValue: dial.innerValue
                // Close to a weekly limit; at 100 % there is nothing left to warn about.
                pulsing: dial.usage && dial.value >= 90 && dial.value < 100
                // The cell's description covers it.
                Accessible.ignored: true

                Kirigami.Icon {
                    anchors.centerIn: parent
                    visible: dial.usage
                    width: Math.round(15 * dial.sizeFactor)
                    height: width
                    source: dial.item === "claude" ? Qt.resolvedUrl("../icons/claude.svg")
                                                   : Qt.resolvedUrl("../icons/openai.svg")
                    isMask: true
                    color: Kirigami.Theme.textColor
                }

                // Shrinks to fit inside the inner ring when it is drawn.
                Text {
                    anchors.centerIn: parent
                    visible: !dial.usage
                    width: 2 * (dial.innerShown ? 13 : 18) * dial.sizeFactor
                    horizontalAlignment: Text.AlignHCenter
                    text: dial.item === "cpu" ? i18nc("@label short for processor", "CPU")
                        : dial.item === "gpu" ? i18nc("@label short for graphics card", "GPU")
                        : i18nc("@label short for memory", "MEM")
                    color: Style.dim(Kirigami.Theme.textColor)
                    font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.95 * dial.sizeFactor
                    font.letterSpacing: Kirigami.Theme.smallFont.pointSize * 0.08 * dial.sizeFactor
                    fontSizeMode: Text.HorizontalFit
                    minimumPointSize: Kirigami.Theme.smallFont.pointSize * 0.5 * dial.sizeFactor
                    textFormat: Text.PlainText
                }
            }

            // Digits have no descenders, so the readout's box ends at the
            // baseline and starts at the cap height: the face ends at the ink,
            // and the panel's margins read as equal.
            Item {
                objectName: "readout"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: dial.parts.reduce((sum, part) => sum + part, 0) * dial.sizeFactor
                Layout.preferredHeight: Math.round(metrics.ascent)
                Layout.topMargin: -Math.round(metrics.ascent - dial.capHeight)

                RowLayout {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: parent.height
                    spacing: 0

                    Part {
                        reserve: dial.parts[0]
                        horizontalAlignment: dial.secondShown ? Text.AlignRight : Text.AlignHCenter
                        text: dial.asleep ? i18nc("@info:status the GPU is powered down", "off") : dial.percentText(dial.value)
                        color: dial.asleep ? Style.dim(Kirigami.Theme.textColor) : dial.tone(dial.value)
                    }
                    Part {
                        reserve: dial.parts[1]
                        visible: dial.secondShown
                        horizontalAlignment: Text.AlignHCenter
                        text: "·"
                        opacity: 0.55
                    }
                    Part {
                        reserve: dial.parts[2]
                        visible: dial.secondShown
                        horizontalAlignment: Text.AlignLeft
                        text: dial.secondText
                        color: dial.usage ? dial.tone(dial.innerValue)
                             : dial.item === "memory" ? Kirigami.Theme.textColor : dial.heatColor(dial.celsius)
                        // The inner limit reads dimmer, unless it is near its end.
                        opacity: dial.usage && Format.level(dial.innerValue) < 2 ? 0.55 : 1
                    }
                }
            }

            // A reset is announced before the new readings arrive, so the
            // ring plays it on the arcs it shows now.
            Connections {
                target: dial.usage ? dial.monitor.usage : null

                function onResetsDetected(events) {
                    gauge.playResets(events[dial.item + ".weekly"] ?? null,
                                     dial.limit ? events[dial.item + ".scoped." + dial.limit.id] ?? null : null);
                }
            }
        }
    }

    // Down and up for the network, read and write for the disk, as the
    // vertical inline strip writes them: "24.8M".
    Component {
        id: rateFace

        GridLayout {
            id: rates

            readonly property bool network: dial.item === "network"
            readonly property var lines: network
                ? [Format.rate(dial.monitor.networkDown, dial.monitor.networkBits),
                   Format.rate(dial.monitor.networkUp, dial.monitor.networkBits)]
                : [Format.rate(dial.monitor.diskRead, false), Format.rate(dial.monitor.diskWrite, false)]

            columns: 2
            columnSpacing: 0
            rowSpacing: Math.round(3 * dial.sizeFactor)

            Repeater {
                model: 2

                delegate: Item {
                    id: marker

                    required property int index

                    Layout.row: index
                    Layout.column: 0
                    Layout.preferredWidth: dial.parts[0] * dial.sizeFactor
                    implicitHeight: metrics.height

                    Arrow {
                        visible: rates.network
                        anchors.verticalCenter: parent.verticalCenter
                        height: Math.round(metrics.height * 0.62)
                        up: marker.index === 1
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.75)
                    }

                    Text {
                        visible: !rates.network
                        text: marker.index === 1 ? i18nc("@label short for disk writes", "W")
                                                 : i18nc("@label short for disk reads", "R")
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.75)
                        font: metrics.font
                        textFormat: Text.PlainText
                    }
                }
            }

            Repeater {
                model: 2

                delegate: Text {
                    required property int index

                    Layout.row: index
                    Layout.column: 1
                    Layout.preferredWidth: dial.parts[1] * dial.sizeFactor
                    horizontalAlignment: Text.AlignRight
                    text: rates.lines[index].value === "–" ? "–"
                        : rates.lines[index].value + rates.lines[index].unit.charAt(0).replace(/[bB]/, "")
                    color: Kirigami.Theme.textColor
                    font: metrics.font
                    textFormat: Text.PlainText
                }
            }
        }
    }

}
