// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/style.js" as Style
import ".."

// A GPU's busiest processes, each with its share of the GPU and its video
// memory. Only the user's own processes can be read, so the caption says
// whose they are: a system service using the GPU isn't among them.
ColumnLayout {
    id: list

    // { name, usage, memory, count } for each process, busiest first.
    property var rows: []
    // The rows laid out, filled or not, so the popup keeps its height as
    // processes come and go.
    property int count: 3
    // Off for a GPU that reports no video memory of its own, as Intel's
    // integrated ones don't.
    property bool memoryShown: true

    // Each reading's column is as wide as its widest value, so the columns
    // line up down the rows and hold still as the values change.
    readonly property real usageWidth: Math.max(usageHead.implicitWidth, usageSample.implicitWidth)
    readonly property real vramWidth: Math.max(vramHead.implicitWidth, vramSample.implicitWidth)
    // A row's height: the name and the readings on one baseline. Measured
    // from texts rather than the rows, which a hidden list doesn't lay out.
    readonly property real rowHeight: Math.max(nameSample.baselineOffset, usageSample.baselineOffset)
        + Math.max(nameSample.implicitHeight - nameSample.baselineOffset, usageSample.implicitHeight - usageSample.baselineOffset)

    // The list's height with `count` rows, its bottom margin included; with
    // none it is left out.
    function heightFor(count) {
        return count > 0 ? usageHead.implicitHeight + count * (spacing + rowHeight) + Layout.bottomMargin : 0;
    }

    Layout.fillWidth: true
    Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
    Layout.rightMargin: Layout.leftMargin
    Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
    // Reckoned rather than laid out: a hidden list doesn't lay itself out,
    // so one whose count changed while its section was closed would
    // otherwise open at its old height for a frame.
    Layout.preferredHeight: heightFor(count) - Layout.bottomMargin
    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        Caption {
            label: i18nc("@title:group the user's own processes using a GPU", "Your top processes")
            Layout.fillWidth: true
        }

        Caption {
            id: usageHead
            label: i18nc("@title:column a process's share of the GPU", "Usage")
            Layout.preferredWidth: list.usageWidth
            horizontalAlignment: Text.AlignRight
        }

        Caption {
            id: vramHead
            visible: list.memoryShown
            label: i18nc("@title:column a process's video memory", "VRAM")
            Layout.preferredWidth: list.vramWidth
            horizontalAlignment: Text.AlignRight
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: rowsColumn.implicitHeight

        // The widest values, and a row's name, measured for the columns and
        // the rows: transparent rather than hidden, as a hidden reading
        // leaves its unit out of its width.
        ProcessName {
            id: nameSample
            opacity: 0
        }

        Reading {
            id: usageSample
            opacity: 0
            accessibleIgnored: true
            value: Format.fixed(100, 1)
            unit: "%"
            unitSpacing: 0
        }

        Reading {
            id: vramSample
            opacity: 0
            accessibleIgnored: true
            readonly property var b: Format.bytes(1023 * 1024 ** 2)
            value: b.value
            unit: b.unit
        }

        ColumnLayout {
            id: rowsColumn
            width: parent.width
            spacing: list.spacing

            Repeater {
                model: list.count

                // Each row is spoken whole, "blender, 9.8%, 1.1 GiB".
                delegate: RowLayout {
                    id: row

                    required property int index
                    readonly property var entry: list.rows[index] || null
                    readonly property string usage: entry ? Format.fixed(entry.usage, 1) : ""
                    readonly property bool counted: entry !== null && Number.isFinite(entry.usage)
                    readonly property var vram: entry ? Format.bytes(entry.memory) : { value: "", unit: "" }

                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    Accessible.role: Accessible.StaticText
                    readonly property string usageSpoken: counted ? i18nc("@info a percentage", "%1%", usage)
                        : i18nc("@info a process's GPU usage, which the system doesn't count for compute work", "usage not counted")
                    Accessible.name: !entry ? ""
                        : list.memoryShown
                        ? i18nc("@info accessible name of a GPU process row: the process, its share of the GPU, then its video memory, e.g. blender, 9.8%, 1.1 GiB",
                                "%1, %2, %3", processName.text, usageSpoken,
                                i18nc("@info an amount of memory, e.g. 3.9 GiB", "%1 %2", vram.value, vram.unit))
                        : i18nc("@info accessible name of a GPU process row: the process, then its share of the GPU, e.g. firefox, 9.8%",
                                "%1, %2", processName.text, usageSpoken)

                    ProcessName {
                        id: processName
                        entry: row.entry
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBaseline
                    }

                    // Each reading at its column's end edge, the percent
                    // sign against its number as in the CPU's list.
                    Item {
                        Layout.preferredWidth: list.usageWidth
                        Layout.alignment: Qt.AlignBaseline
                        implicitHeight: usageReading.implicitHeight
                        baselineOffset: usageReading.baselineOffset

                        Reading {
                            id: usageReading
                            anchors.right: parent.right
                            value: row.usage
                            unit: row.counted ? "%" : ""
                            unitSpacing: 0
                            accessibleIgnored: true
                        }
                    }

                    Item {
                        visible: list.memoryShown
                        Layout.preferredWidth: list.vramWidth
                        Layout.alignment: Qt.AlignBaseline
                        implicitHeight: vramReading.implicitHeight
                        baselineOffset: vramReading.baselineOffset

                        Reading {
                            id: vramReading
                            anchors.right: parent.right
                            value: row.vram.value
                            unit: row.vram.unit
                            accessibleIgnored: true
                        }
                    }
                }
            }
        }
    }
}
