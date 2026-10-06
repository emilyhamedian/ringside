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
// wake it. A GPU that wakes opens its section at once and fades it in; one
// that goes to sleep fades its section out with its last readings, and only
// then gives way to its line, so the popup changes height once each way.
PopupPage {
    id: popup

    readonly property var slots: [popup.monitor.gpuOuter, popup.monitor.gpuInner].filter(slot => slot.present)
    readonly property var awake: slots.filter(slot => slot.phase !== "asleep")
    // The GPUs with a section open: the awake ones, and one that has just
    // gone to sleep while its section fades out. Set rather than bound, so
    // that a GPU going to sleep is still among them when it is noticed.
    property var open: []
    // Off opens and closes sections at once, as at Plasma's Instant speed.
    property bool animated: Kirigami.Units.longDuration > 1

    Component.onCompleted: open = awake
    onAwakeChanged: {
        if (animated && open.some(slot => !awake.includes(slot))) {
            open = slots.filter(slot => open.includes(slot) || awake.includes(slot));
            closing.restart();
        } else {
            closing.stop();
            open = awake;
        }
    }

    Timer {
        id: closing
        interval: Kirigami.Units.longDuration
        onTriggered: popup.open = popup.awake
    }

    // A section per GPU, kept as it sleeps and wakes.
    Repeater {
        model: popup.slots.length

        delegate: Section {
            required property int index
            readonly property var live: popup.slots[index] ?? popup.monitor.gpuOuter
            readonly property bool opened: popup.open.includes(live)
            // Its readings while it was last awake, a reading that went
            // missing keeping the one before.
            property var last: null
            readonly property var readings: [live.phase, live.usage, live.temperature, live.vramUsed, live.knownVramTotal,
                                             live.clock, live.power, live.history]

            function keep() {
                if (live.phase === "asleep") {
                    return;
                }
                const was = last ?? {};
                const held = key => Number.isFinite(live[key]) ? live[key] : was[key] ?? NaN;
                last = {
                    present: true, name: live.name, kind: live.kind, reportsVram: live.reportsVram,
                    reportsTemperature: live.reportsTemperature, temperatureLabel: live.temperatureLabel,
                    knownVramTotal: held("knownVramTotal"), usage: held("usage"), temperature: held("temperature"),
                    vramUsed: held("vramUsed"), clock: held("clock"), power: held("power"),
                    history: live.history.length > 0 ? live.history : was.history ?? []
                };
            }

            Component.onCompleted: keep()
            onReadingsChanged: keep()

            monitor: popup.monitor
            awake: live.phase !== "asleep"
            visible: opened
            slot: !awake && opened && last ? last : live
            temperatureName: words.sensorName(live.temperatureLabel)
            first: popup.open.indexOf(live) === 0
            animated: popup.animated
        }
    }

    Words {
        id: words
        monitor: popup.monitor
    }

    Repeater {
        model: popup.slots.filter(slot => !popup.open.includes(slot))

        delegate: ColumnLayout {
            id: sleeper

            required property var modelData
            required property int index

            Layout.fillWidth: true
            spacing: 0

            Divider {
                visible: popup.open.length > 0
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
                Layout.rightMargin: Layout.leftMargin
                // Where it opens the page, as far down as a header would start.
                Layout.topMargin: popup.open.length > 0 || sleeper.index > 0
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
        // Any section after the first is set off from it by a rule.
        property bool first: true
        // Faded in while the GPU is awake and out while it sleeps.
        property bool awake: true
        property bool animated: true

        // Intel GPUs publish no temperature, so theirs is left out rather than shown as a dash.
        readonly property bool temperatureShown: slot.reportsTemperature
        readonly property bool hasPower: Number.isFinite(slot.power)
        readonly property real tilePointSize: Kirigami.Theme.defaultFont.pointSize * 1.23

        Layout.fillWidth: true
        opacity: awake ? 1 : 0
        spacing: 0

        Behavior on opacity {
            enabled: section.animated
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
        }

        Divider {
            visible: !section.first
        }

        PopupHeader {
            ringValue: section.slot.usage
            interval: section.monitor.interval
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
                    interval: section.monitor.interval
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
