pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.process as Process
import "../code/format.js" as Format
import "../code/processes.js" as Processes

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
        const n = model.rowCount();
        const found = [];
        for (let r = 0; r < n; ++r) {
            found.push({
                name: model.data(model.index(r, 0), Process.ProcessDataModel.Value),
                usage: Number(model.data(model.index(r, 1), Process.ProcessDataModel.Value)),
                memory: Number(model.data(model.index(r, 2), Process.ProcessDataModel.Value)) * 1024
            });
        }
        rows = Processes.top(found, key, 3);
    }

    Layout.fillWidth: true
    Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
    Layout.rightMargin: Math.round(Kirigami.Units.largeSpacing * 2)
    Layout.topMargin: Kirigami.Units.largeSpacing
    Layout.bottomMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    Process.ProcessDataModel {
        id: model
        enabled: list.sample === null
        // Resident memory (PSS where readable) arrives in KiB.
        enabledAttributes: ["name", "usage", "memory"]
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

        delegate: RowLayout {
            id: row

            required property int index
            readonly property var entry: list.rows[index] || null

            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Text {
                Layout.fillWidth: true
                text: !row.entry ? " " : row.entry.count > 1 ? row.entry.name + " ×" + row.entry.count : row.entry.name
                color: Kirigami.Theme.textColor
                font.family: Kirigami.Theme.fixedWidthFont.family
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.92
                elide: Text.ElideRight
                textFormat: Text.PlainText
                // Set, so the names move to the other edge in a mirrored layout.
                horizontalAlignment: Text.AlignLeft
            }

            Text {
                text: {
                    if (!row.entry) {
                        return "";
                    }
                    if (list.key === "memory") {
                        const b = Format.bytes(row.entry.memory);
                        return b.value + " " + b.unit;
                    }
                    return Format.fixed(row.entry.usage / Math.max(1, list.threads), 1) + "%";
                }
                color: Kirigami.Theme.textColor
                font.family: Kirigami.Theme.fixedWidthFont.family
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.92
                textFormat: Text.PlainText
            }
        }
    }
}
