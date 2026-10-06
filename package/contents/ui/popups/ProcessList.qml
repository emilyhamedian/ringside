// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.process as Process
import "../code/format.js" as Format
import "../code/processes.js" as Processes
import "../code/style.js" as Style
import ".."

// The three heaviest processes by CPU or by memory. The process model scans
// /proc every two seconds, so it only exists while its popup is open.
ColumnLayout {
    id: list

    // "usage" or "memory"
    required property string key
    // ProcessDataModel's usage is per core; divide by threads for the share of the CPU.
    required property int threads

    // Fixed rows ({ name, usage, memory, count }) stand in for the process
    // scan when set; the preview gallery uses them.
    property var sample: null
    property var rows: sample || []

    function refresh() {
        // The columns are the attributes the model took, in order.
        const columns = Array.from(model.enabledAttributes);
        const n = model.rowCount();
        const found = [];
        for (let r = 0; r < n; ++r) {
            const values = [];
            for (let c = 0; c < columns.length; ++c) {
                values.push(model.data(model.index(r, c), Process.ProcessDataModel.Value));
            }
            found.push(Processes.reading(columns, values));
        }
        rows = Processes.top(found, key, 3);
    }

    Layout.fillWidth: true
    Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
    Layout.rightMargin: Math.round(Kirigami.Units.largeSpacing * 2)
    Layout.topMargin: Kirigami.Units.largeSpacing
    // As much room below as the tile grids leave above the footer.
    Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.25)
    spacing: Kirigami.Units.smallSpacing

    Process.ProcessDataModel {
        id: model
        enabled: list.sample === null
        // Plasma 6.0 to 6.2 lack "memory", so the list asks for what they offer.
        enabledAttributes: Processes.attributes(model.availableAttributes)
    }

    Timer {
        interval: 2000
        running: list.sample === null
        repeat: true
        triggeredOnStart: true
        onTriggered: list.refresh()
    }

    Connections {
        target: model
        // The first scan lands a moment after the popup opens.
        function onModelReset() { list.refresh(); }
        function onRowsInserted() { if (list.rows.length === 0) list.refresh(); }
    }

    Caption {
        label: i18nc("@title:group", "Top processes")
        Layout.fillWidth: true
    }

    // Three rows always, so the popup keeps its height while the first scan runs.
    Repeater {
        model: 3

        // Each row is spoken whole, "firefox, 8.4%", as the value alone
        // would be read as its number and its unit apart.
        delegate: RowLayout {
            id: row

            required property int index
            readonly property var entry: list.rows[index] || null
            readonly property bool memory: list.key === "memory"
            // The value's number and unit, both from entry in one binding.
            // Reading entry beside a property made from it could see the new
            // row with that property still made from the last, null before
            // the first scan.
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

            Text {
                id: processName
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBaseline
                text: !row.entry ? " "
                    : row.entry.count > 1 ? i18nc("@info a process and how many of it run, e.g. chrome ×12", "%1 ×%2",
                                                  row.entry.name, Format.whole(row.entry.count))
                    : row.entry.name
                color: Kirigami.Theme.textColor
                font.family: Kirigami.Theme.fixedWidthFont?.family ?? "monospace" // qmllint disable redundant-optional-chaining
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.92
                elide: Text.ElideRight
                textFormat: Text.PlainText
                // Set, so the names move to the other edge in a mirrored layout.
                horizontalAlignment: Text.AlignLeft
                Accessible.ignored: true
            }

            // Set like the tiles' readings, with a smaller, dimmer unit; the
            // percent sign stays against its number.
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
