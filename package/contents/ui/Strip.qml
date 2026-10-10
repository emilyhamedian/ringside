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
    // up to a size that still sits well beside two lines of text. A ring held
    // at that size, or at the smallest, keeps the panel's parity, so its
    // readings centre on the same whole pixel as the rates beside them.
    readonly property real ring: {
        const inset = vertical ? Kirigami.Units.smallSpacing : Math.round(Kirigami.Units.smallSpacing / 2);
        const size = Math.max(16, Math.min(Math.round(Kirigami.Units.gridUnit * 2.5), thickness - 2 * inset));
        return Number.isInteger(size) && Number.isInteger(thickness) && (thickness - size) % 2 !== 0 ? size - 1 : size;
    }
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

        required property string item
        readonly property alias cell: cell
        readonly property bool textShown: !strip.isRing(item) || !strip.vertical && !strip.ringsOnly.includes(item)

        Layout.fillWidth: strip.vertical
        Layout.fillHeight: !strip.vertical
        implicitWidth: cell.implicitWidth
        implicitHeight: cell.implicitHeight
        // Where the readings are hidden, or a Claude or Codex check failed,
        // whose cause and times only the words give, or is still running.
        active: (!entry.textShown || Items.isUsage(entry.item) && (strip.monitor.usage.degraded(entry.item)
                                                                    || strip.monitor.usage.loading(entry.item)))
            && !cell.open
        mainText: cell.title
        subText: cell.description
        textFormat: Text.PlainText
        location: strip.location

        PanelCell {
            id: cell
            anchors.fill: parent
            item: entry.item
            open: strip.openItem === entry.item
            vertical: strip.vertical
            codexMark: strip.monitor.codexMark
            onActivated: strip.activated(entry.item, cell)

            // Along a horizontal panel the content keeps to the cell's start,
            // so the cell's rounding up to a whole pixel falls after it.
            // Along a vertical panel the content is centred.
            // Both in whole pixels, rounding as the ring cells' own layout
            // does, so a ring's readings and the rates land on the same rows.
            Loader {
                x: strip.vertical ? Math.round((parent.width - width) / 2)
                 : LayoutMirroring.enabled ? Math.round(parent.width - cell.padding - width) : cell.padding
                y: Math.round((parent.height - height) / 2)
                sourceComponent: Items.isUsage(entry.item) ? usageContent
                               : strip.isRing(entry.item) ? ringContent : rateContent
                onLoaded: cell.contentItem = item
            }

            Component {
                id: ringContent
                RingCellContent {
                    id: rings
                    monitor: strip.monitor
                    item: entry.item
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
                    item: entry.item
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
                    item: entry.item
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

    // The items as a model the strip keeps in step with `items`, so a cell
    // stays while others come and go. Handed a new array, the Repeater
    // would make every cell again, cutting short whatever its ring was
    // doing, such as a first reading filling it in.
    ListModel {
        id: shown
    }

    function follow() {
        for (let i = shown.count - 1; i >= 0; --i) {
            if (!items.includes(shown.get(i).item)) {
                shown.remove(i);
            }
        }
        items.forEach((item, i) => {
            let at = i;
            while (at < shown.count && shown.get(at).item !== item) {
                ++at;
            }
            if (at === shown.count) {
                shown.insert(i, { item: item });
            } else if (at !== i) {
                shown.move(at, i, 1);
            }
        });
    }

    onItemsChanged: follow()
    Component.onCompleted: follow()

    Repeater {
        id: cells
        model: shown
        delegate: Entry {}
    }
}
