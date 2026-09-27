pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The row of items in the panel. Rings come first in the user's order; a
// hairline separates them from the text-only transfer rates. On a vertical
// panel the items stack and show their rings alone.
GridLayout {
    id: strip

    required property var monitor
    required property var items
    required property bool vertical
    required property real thickness
    required property int ringSize
    required property var ringsOnly
    // The item whose popup is open, for its pressed look.
    property string openItem: ""

    signal activated(string item, Item cell)

    readonly property real ring: Math.max(16, Math.min(ringSize, thickness - 2 * Kirigami.Units.smallSpacing))
    // Label over value needs room for both lines; otherwise the value sits alone.
    readonly property bool twoLines: thickness >= Kirigami.Units.gridUnit * 2

    function isRing(item) {
        return item === "cpu" || item === "gpu" || item === "memory";
    }

    function cellAt(index) {
        const entry = cells.itemAt(index);
        return entry ? entry.cell : null;
    }

    flow: vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rows: vertical ? -1 : 1
    columns: vertical ? 1 : -1
    rowSpacing: 0
    columnSpacing: 0

    Repeater {
        id: cells
        model: strip.items

        delegate: RowLayout {
            id: entry

            required property string modelData
            required property int index
            readonly property alias cell: cell
            // A hairline where the rings end and the rates begin.
            readonly property bool separated: index > 0 && strip.isRing(strip.items[index - 1]) !== strip.isRing(modelData)

            Layout.fillWidth: strip.vertical
            Layout.fillHeight: !strip.vertical
            spacing: 0

            Rectangle {
                visible: entry.separated && !strip.vertical
                Layout.preferredWidth: 1
                Layout.preferredHeight: Math.round(strip.thickness * 0.4)
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                Layout.alignment: Qt.AlignVCenter
                color: Qt.alpha(Kirigami.Theme.textColor, 0.14)
            }

            PanelCell {
                id: cell
                item: entry.modelData
                open: strip.openItem === entry.modelData
                vertical: strip.vertical
                Layout.fillWidth: strip.vertical
                Layout.fillHeight: !strip.vertical
                onActivated: strip.activated(entry.modelData, cell)

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: strip.isRing(entry.modelData) ? ringContent : rateContent
                    onLoaded: cell.contentItem = item
                }

                Component {
                    id: ringContent
                    RingCellContent {
                        monitor: strip.monitor
                        item: entry.modelData
                        ring: strip.ring
                        textShown: !strip.vertical && !strip.ringsOnly.includes(entry.modelData)
                        twoLines: strip.twoLines
                    }
                }

                Component {
                    id: rateContent
                    RateCellContent {
                        monitor: strip.monitor
                        item: entry.modelData
                        vertical: strip.vertical
                        singleRow: !strip.vertical && !strip.twoLines
                    }
                }
            }
        }
    }
}
