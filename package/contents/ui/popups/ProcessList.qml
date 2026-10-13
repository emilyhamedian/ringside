// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/processes.js" as Processes
import "../code/style.js" as Style
import ".."

// The three heaviest processes by CPU or by memory, read while its popup is
// open and the list is shown. Until the list has readings, a busy indicator
// stands in for its rows.
ColumnLayout {
    id: list

    // "usage" or "memory"
    required property string key
    // ProcessDataModel's usage is per core; divide by threads for the share of the CPU.
    required property int threads

    // Fixed rows ({ name, usage, memory, count }) stand in for the process
    // scan when set; the preview gallery uses them.
    property var sample: null
    readonly property var rows: sample || Processes.top(scan.processes, key, 3)
    readonly property bool loading: rows.length === 0 && !scan.scanned

    Layout.fillWidth: true
    Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
    Layout.rightMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
    Layout.topMargin: Kirigami.Units.largeSpacing
    // Room above the footer: a tile's vertical padding, a little under the
    // tile grids' bottom margin.
    Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.25)
    spacing: Kirigami.Units.smallSpacing

    // Plasma 6.0 to 6.2 lack "memory", so the list asks for what they offer.
    ProcessScan {
        id: scan
        active: list.sample === null && list.visible
    }

    Caption {
        label: i18nc("@title:group", "Top processes")
        Layout.fillWidth: true
    }

    // Three rows always, so the popup keeps its height while the first scans
    // run, with a busy indicator over them until there are readings.
    Item {
        Layout.fillWidth: true
        implicitHeight: rowsColumn.implicitHeight

        ColumnLayout {
            id: rowsColumn
            width: parent.width
            spacing: list.spacing

            Repeater {
                model: 3

                // Each row is spoken whole, "firefox, 8.4%", as the value
                // alone would be read as its number and its unit apart.
                delegate: RowLayout {
                    id: row

                    required property int index
                    readonly property var entry: list.rows[index] || null
                    readonly property bool memory: list.key === "memory"
                    // The value's number and unit, both from entry in one
                    // binding. Reading entry beside a property made from it
                    // could see the new row with that property still made
                    // from the last, null before the first scan.
                    readonly property var reading: !entry ? { value: "", unit: "" }
                        : memory ? Format.bytes(entry.memory)
                        : { value: Format.fixed(entry.usage / Math.max(1, list.threads), 1), unit: "%" }

                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    Accessible.role: Accessible.StaticText
                    Accessible.name: !entry ? ""
                        : i18nc("@info accessible name of a process row: the process, then its CPU share or memory, e.g. firefox, 8.4%",
                                "%1, %2", processName.text,
                                memory ? i18nc("@info an amount of memory, e.g. 3.9 GiB", "%1 %2", reading.value, reading.unit)
                                       : i18nc("@info a percentage", "%1%", reading.value))

                    ProcessName {
                        id: processName
                        entry: row.entry
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBaseline
                    }

                    // Set like the tiles' readings, with a smaller, dimmer
                    // unit; the percent sign stays against its number.
                    Reading {
                        Layout.alignment: Qt.AlignBaseline
                        value: row.reading.value
                        unit: row.reading.unit
                        unitSpacing: row.memory ? Style.unitGap(pointSize) : 0
                        accessibleIgnored: true
                    }
                }
            }
        }

        ProcessesLoading {
            visible: list.loading
        }
    }
}
