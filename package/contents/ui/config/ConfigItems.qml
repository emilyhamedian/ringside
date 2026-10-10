// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "../code/format.js" as Format
import "../code/style.js" as Style
import "../code/items.js" as Items
import "../code/providers.js" as Providers

ConfigPage {
    id: page

    readonly property var names: ({
        cpu: i18nc("@item panel item", "CPU"),
        gpu: i18nc("@item panel item", "GPU"),
        memory: i18nc("@item panel item", "Memory"),
        network: i18nc("@item panel item", "Network"),
        disk: i18nc("@item panel item", "Disk"),
        claude: i18nc("@item panel item", "Claude"),
        codex: i18nc("@item panel item: the OpenAI weekly limits, read through Codex", "OpenAI")
    })
    // A vertical panel shows rings without their readings, whatever the setting.
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // What the widget found on this machine, for the hints.
    readonly property var hardware: page.report("detectedHardware")
    // Not readonly: tests substitute a fixed status here.
    property var usageStatus: page.report("usageStatus")
    readonly property var hints: ({
        cpu: hardware.cpu ? Format.cpuModel(hardware.cpu.model) : "",
        gpu: (Array.isArray(hardware.gpus) ? hardware.gpus : []).filter(g => g)
            .map(g => Format.gpuModel(g.name, "", g.pciName, g.vendor)).join(" + "),
        memory: Format.memoryModules(hardware.memory),
        network: String(hardware.defaultInterface || ""),
        disk: hardware.root ? String(hardware.root.disk || "") : "",
        claude: usageHint("claude"),
        codex: usageHint("codex")
    })

    function usageHint(id) {
        if (usageStatus.helperError) {
            return String(usageStatus.helperError);
        }
        const entry = usageStatus[id];
        if (!entry || !entry.status) {
            return i18nc("@info:usagetip shown before it has been checked; %1 is a program, such as Claude Code",
                         "Shows while %1 is signed in", Providers.facts(id).product);
        }
        switch (entry.status) {
        case "ok":
            return i18nc("@info:usagetip", "Signed in");
        case "signed_out":
            return i18nc("@info:usagetip %1 is a command, such as claude", "Not signed in: run %1 in a terminal",
                         Providers.facts(id).command);
        case "error":
        case "rate_limited":
            return String(entry.message || "");
        default:
            return "";
        }
    }

    // Every edit assigns a new array: the dialog learns of changes from the
    // cfg_ properties' change signals, which an in-place edit never sends.
    function including(list, key, included) {
        const rest = list.filter(k => k !== key);
        return included ? rest.concat([key]) : rest;
    }

    // Writes the order and hidden lists together, from the rows as shown.
    // Items.order() always lists every known item regardless of its checked
    // state, so writing cfg_itemOrder alone would switch an opted-out Claude
    // or Codex row on the moment it appears in the stored order; writing the
    // normalised hidden set alongside it every time keeps that from happening.
    function save() {
        const order = [];
        const off = [];
        for (let i = 0; i < items.count; ++i) {
            const row = items.get(i);
            order.push(row.key);
            if (!row.checked) {
                off.push(row.key);
            }
        }
        cfg_itemOrder = order;
        cfg_hiddenItems = off;
    }

    function move(from, to) {
        if (from === to || from < 0 || to < 0 || to >= items.count) {
            return;
        }
        items.move(from, to, 1);
        save();
    }

    // The checked state starts from Items.hidden(), so Claude and Codex show
    // unchecked unless the stored order already lists them, without writing
    // anything back until the user acts (save() only runs from a toggle or a
    // move).
    Component.onCompleted: {
        const off = Items.hidden(cfg_itemOrder, cfg_hiddenItems);
        Items.order(cfg_itemOrder).forEach(k => items.append({ key: k, checked: !off.includes(k) }));
    }

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.fillWidth: true
            text: i18nc("@info:usagetip", "Drag or use the arrows to reorder. Uncheck an item to hide it.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Style.dim(Kirigami.Theme.textColor)
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 11.5 / 13
        }

        QQC2.Frame {
            Layout.fillWidth: true
            padding: 1

            contentItem: ListView {
                id: list

                // The widest check box, so the hints start in one column.
                property real checkWidth: 0

                implicitHeight: contentHeight
                interactive: false
                model: ListModel {
                    id: items
                }
                moveDisplaced: Transition {
                    YAnimator {
                        duration: Kirigami.Units.longDuration
                        easing.type: Easing.InOutQuad
                    }
                }

                // ListItemDragHandle drags a child of the delegate, not the delegate itself.
                delegate: Item {
                    id: entry

                    required property string key
                    // ListItemDragHandle also looks it up by name.
                    required property int index
                    required property bool checked
                    readonly property bool ring: Items.isRing(key)

                    // Moves the row one place. The pressed button travels with
                    // its row and keeps focus, unless the move took the row to
                    // the end of the list and disabled it: then its twin takes
                    // focus, so keyboard users stay in the row.
                    function step(by, button, twin) {
                        const focused = button.activeFocus;
                        const reason = button.visualFocus ? Qt.TabFocusReason : Qt.OtherFocusReason;
                        const to = index + by;
                        page.move(index, to);
                        if (focused && (to === 0 || to === list.count - 1)) {
                            twin.forceActiveFocus(reason);
                        }
                    }

                    width: list.width
                    implicitHeight: row.implicitHeight

                    QQC2.Control {
                        id: row

                        width: entry.width
                        // As tall as a row with a combo box, so every row matches.
                        implicitHeight: Math.max(implicitContentHeight, mode.implicitHeight) + topPadding + bottomPadding
                        hoverEnabled: true
                        leftPadding: Kirigami.Units.smallSpacing
                        rightPadding: Kirigami.Units.largeSpacing
                        topPadding: Kirigami.Units.smallSpacing
                        bottomPadding: Kirigami.Units.smallSpacing

                        // While dragged, the handle lifts the row into the view,
                        // over its neighbours.
                        background: Rectangle {
                            visible: row.parent === list
                            color: Kirigami.Theme.backgroundColor
                        }

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.largeSpacing

                            Kirigami.ListItemDragHandle {
                                listItem: row
                                listView: list
                                onMoveRequested: (from, to) => page.move(from, to)
                            }
                            QQC2.CheckBox {
                                Layout.preferredWidth: list.checkWidth
                                text: page.names[entry.key]
                                checked: entry.checked
                                onImplicitWidthChanged: list.checkWidth = Math.max(list.checkWidth, implicitWidth)
                                onToggled: {
                                    items.setProperty(entry.index, "checked", checked);
                                    page.save();
                                }
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: page.hints[entry.key]
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: Style.dim(Kirigami.Theme.textColor)
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 11.5 / 13
                            }
                            QQC2.ComboBox {
                                id: mode
                                visible: entry.ring
                                enabled: !page.vertical
                                model: [i18nc("@item:inlistbox what a ring item shows", "Ring and text"),
                                        i18nc("@item:inlistbox what a ring item shows", "Ring only")]
                                currentIndex: page.cfg_ringsOnly.includes(entry.key) ? 1 : 0
                                Accessible.name: i18nc("@label:listbox %1 is a panel item", "What %1 shows",
                                                       page.names[entry.key])
                                onActivated: index => page.cfg_ringsOnly = page.including(page.cfg_ringsOnly, entry.key, index === 1)
                            }
                            QQC2.ToolButton {
                                id: upButton
                                icon.name: "go-up"
                                display: QQC2.AbstractButton.IconOnly
                                text: i18nc("@action:button %1 is a panel item", "Move %1 up", page.names[entry.key])
                                enabled: entry.index > 0
                                QQC2.ToolTip.text: text
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                onClicked: entry.step(-1, upButton, downButton)
                            }
                            QQC2.ToolButton {
                                id: downButton
                                icon.name: "go-down"
                                display: QQC2.AbstractButton.IconOnly
                                text: i18nc("@action:button %1 is a panel item", "Move %1 down", page.names[entry.key])
                                enabled: entry.index < list.count - 1
                                QQC2.ToolTip.text: text
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                                onClicked: entry.step(1, downButton, upButton)
                            }
                        }
                    }
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            visible: page.vertical
            text: i18nc("@info", "This panel is vertical, so the rings show without their readings.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Style.dim(Kirigami.Theme.textColor)
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 11.5 / 13
        }
    }
}
