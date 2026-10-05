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
    // How long a cell keeps its width after its readings narrow, and how
    // long after a change of layout it takes its new width at once (see
    // PanelCell); writable for the tests.
    property int settleDelay: 3 * 60 * 1000
    property int relayoutWindow: 500

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
    // The room the rates keep for their widest readings and don't use now,
    // kept after the last item, so the strip's width, and with it whatever
    // follows the strip in the panel, doesn't change as rates do. itemAt()
    // doesn't notify, so this follows the cells the Repeater adds.
    readonly property real rateSlack: {
        if (vertical) {
            return 0;
        }
        cells.built;
        let slack = 0;
        for (let i = 0; i < cells.count; ++i) {
            const entry = cells.itemAt(i);
            slack += entry ? entry.cell.slack : 0; // qmllint disable missing-property
        }
        return slack;
    }

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
        required property int index
        readonly property alias cell: cell
        readonly property bool textShown: !strip.isRing(modelData) || !strip.vertical && !strip.ringsOnly.includes(modelData)
        // Rates with no ring after them: their changes move nothing but the
        // room kept at the strip's end, so they needn't hold their width.
        readonly property bool trailingRate: !strip.isRing(modelData) && strip.items.slice(index + 1).every(k => !strip.isRing(k))

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
            holdsWidth: !entry.trailingRate
            settleDelay: strip.settleDelay
            relayoutWindow: strip.relayoutWindow
            layoutKey: [entry.textShown, strip.vertical, strip.thickness, strip.twoLines,
                        Kirigami.Theme.defaultFont.family, Kirigami.Theme.defaultFont.pointSize,
                        strip.monitor.fahrenheit, strip.monitor.networkBits,
                        strip.monitor.gpuOuter.name, strip.monitor.gpuInner.name,
                        Items.isUsage(entry.modelData) && strip.monitor.usage.entry(entry.modelData)?.status].join()
            onActivated: strip.activated(entry.modelData, cell)

            // Along a horizontal panel the content keeps to the cell's start,
            // so room the cell holds on to, and the cell's rounding up to a
            // whole pixel, fall after it. Along a vertical one it is centred.
            // Both in whole pixels, rounding as the ring cells' own layout
            // does, so a ring's readings and the rates land on the same rows.
            Loader {
                x: strip.vertical ? Math.round((parent.width - width) / 2)
                 : LayoutMirroring.enabled ? Math.round(parent.width - cell.padding - width) : cell.padding
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

                    Binding {
                        target: cell
                        property: "reservedWidth"
                        value: rates.reservedWidth + 2 * cell.padding
                    }
                }
            }
        }
    }

    Repeater {
        id: cells

        // Counts the cells added, for rateSlack.
        property int built: 0

        model: strip.items
        delegate: Entry {}
        onItemAdded: ++built
    }

    // The rates' slack, after the last item.
    Item {
        visible: !strip.vertical
        Layout.preferredWidth: strip.rateSlack
        Layout.fillHeight: true
    }
}
