// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/hardware.js" as Hardware
import "code/items.js" as Items

// One item in the Standalone layout, at Usage Rings' size: a ring with the
// item's name inside it over its two readings ("23%" over "61°", the same as
// beside an inline ring), or for network and disk two lines of rates. Each
// line or column keeps the width the strip reserves for it (see
// StandaloneStrip.partWidths), so the dial keeps its size as the readings
// change. The strip sizes the cell, so the hover and pressed wash spans the
// strip's thickness, and gives it its tooltip; the face sits in its middle.
PanelCell {
    id: dial

    required property var monitor
    // Widths of the readout's lines, or the rates' columns, at the base size.
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
    readonly property real value: item === "cpu" ? monitor.cpuUsage
                                : item === "memory" ? monitor.memoryPercent
                                : item === "gpu" ? gpu.usage
                                : weekly?.percent ?? NaN
    readonly property bool innerShown: item === "gpu" ? gpuView.dual : limit !== null
    readonly property real innerValue: item === "gpu" ? monitor.gpuInner.usage : limit?.percent ?? NaN

    // The wash fills the cell, whichever way the strip runs.
    vertical: true
    description: words.describe(item, nowMs)

    Words {
        id: words
        monitor: dial.monitor
    }

    // Countdowns read in minutes, and catch up as soon as a folded dial
    // shows again.
    Timer {
        running: dial.usage && dial.visible
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: dial.nowMs = Date.now()
    }

    ReadoutFont {
        id: readingFont
        pointSize: Kirigami.Theme.smallFont.pointSize * dial.sizeFactor
    }

    Loader {
        id: face
        objectName: "face"
        anchors.centerIn: parent
        opacity: dial.degraded ? 0.55 : 1
        sourceComponent: Items.isRing(dial.item) ? ringFace : rateFace
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

                RingName {
                    item: dial.item
                    room: gauge.centreWidth
                    sizeFactor: dial.sizeFactor
                }
            }

            // Digits have no descenders, so the readout's box runs from the
            // first line's cap height to the second line's baseline: the face
            // ends at the ink, and the panel's margins read as equal.
            Item {
                objectName: "readout"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: readout.implicitWidth
                Layout.preferredHeight: Math.round(readingFont.lineHeight + readingFont.plain.ascent)
                Layout.topMargin: -Math.round(readingFont.strong.ascent - readingFont.capHeight)

                Readout {
                    id: readout
                    anchors.horizontalCenter: parent.horizontalCenter
                    pointSize: readingFont.pointSize
                    lines: words.readout(dial.item, dial.nowMs)
                    rooms: dial.parts.map(part => part * dial.sizeFactor)
                    alignment: Text.AlignHCenter
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
                    implicitHeight: readingFont.lineHeight

                    Arrow {
                        visible: rates.network
                        anchors.verticalCenter: parent.verticalCenter
                        height: Math.round(readingFont.plain.height * 0.62)
                        up: marker.index === 1
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.75)
                    }

                    Text {
                        visible: !rates.network
                        text: marker.index === 1 ? i18nc("@label short for disk writes", "W")
                                                 : i18nc("@label short for disk reads", "R")
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.75)
                        font: readingFont.plain.font
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
                    font: readingFont.plain.font
                    textFormat: Text.PlainText
                }
            }
        }
    }

}
