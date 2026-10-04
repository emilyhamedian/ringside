// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import "code/items.js" as Items

// The row of items in the panel, in the user's order: rings with the item's
// name inside them and their readings beside them, and the transfer rates on
// the same two lines. On a vertical panel the items stack and show their
// rings alone. A ring without its text shows the readings in a tooltip
// instead.
GridLayout {
    id: strip

    required property var monitor
    required property var items
    required property bool vertical
    required property real thickness
    required property var ringsOnly
    // The item whose popup is open, for its pressed look.
    property string openItem: ""
    // Plasmoid.location, for the tooltips.
    property int location: PlasmaCore.Types.Floating

    signal activated(string item, Item cell)

    // Rings fill the panel inside the cell's hover wash (PanelCell.inset
    // across a horizontal panel, a margin either side across a vertical one),
    // up to a size that still sits well beside two lines of text.
    readonly property real ring: Math.max(16, Math.min(Math.round(Kirigami.Units.gridUnit * 2.5),
        thickness - 2 * (vertical ? Kirigami.Units.smallSpacing : Math.round(Kirigami.Units.smallSpacing / 2))))
    // Two lines need room for both; otherwise they share one.
    readonly property bool twoLines: thickness >= Kirigami.Units.gridUnit * 2

    function isRing(item) {
        return Items.isRing(item);
    }

    function cellAt(index) {
        const entry = cells.itemAt(index);
        return entry ? entry.cell : null; // qmllint disable missing-property
    }

    flow: vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rows: vertical ? -1 : 1
    columns: vertical ? 1 : -1
    rowSpacing: 0
    columnSpacing: 0

    component Entry: PlasmaCore.ToolTipArea {
        id: entry

        required property string modelData
        readonly property alias cell: cell
        readonly property bool textShown: !strip.isRing(modelData) || !strip.vertical && !strip.ringsOnly.includes(modelData)

        Layout.fillWidth: strip.vertical
        Layout.fillHeight: !strip.vertical
        implicitWidth: cell.implicitWidth
        implicitHeight: cell.implicitHeight
        active: !entry.textShown && !cell.open
        mainText: cell.title
        subText: cell.description
        textFormat: Text.PlainText
        location: strip.location

        PanelCell {
            id: cell
            anchors.fill: parent
            item: entry.modelData
            open: strip.openItem === entry.modelData
            vertical: strip.vertical
            onActivated: strip.activated(entry.modelData, cell)

            // Centred to whole pixels, rounding as the ring cells' own layout
            // does, so a ring's readings and the rates land on the same rows.
            Loader {
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
                sourceComponent: Items.isUsage(entry.modelData) ? usageContent
                               : strip.isRing(entry.modelData) ? ringContent : rateContent
                onLoaded: cell.contentItem = item
            }

            Component {
                id: ringContent
                RingCellContent {
                    id: rings
                    monitor: strip.monitor
                    item: entry.modelData
                    ring: strip.ring
                    textShown: entry.textShown
                    twoLines: strip.twoLines

                    Binding {
                        target: cell
                        property: "description"
                        value: rings.accessibleDescription
                    }
                }
            }

            Component {
                id: usageContent
                UsageCellContent {
                    id: usage
                    monitor: strip.monitor
                    item: entry.modelData
                    ring: strip.ring
                    textShown: entry.textShown
                    twoLines: strip.twoLines

                    Binding {
                        target: cell
                        property: "description"
                        value: usage.accessibleDescription
                    }
                }
            }

            Component {
                id: rateContent
                RateCellContent {
                    id: rates
                    monitor: strip.monitor
                    item: entry.modelData
                    vertical: strip.vertical
                    singleRow: !strip.vertical && !strip.twoLines
                    availableWidth: strip.vertical ? cell.width - 2 * Kirigami.Units.smallSpacing : Infinity

                    Binding {
                        target: cell
                        property: "description"
                        value: rates.accessibleDescription
                    }
                }
            }
        }
    }

    Repeater {
        id: cells
        model: strip.items
        delegate: Entry {}
    }
}
