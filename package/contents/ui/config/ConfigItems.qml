pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid
import "../code/format.js" as Format

KCM.SimpleKCM {
    id: page

    property var cfg_itemOrder: []
    property var cfg_hiddenItems: []
    property var cfg_ringsOnly: []
    property int cfg_ringSize

    readonly property var names: ({
        cpu: i18nc("@item panel item", "CPU"),
        gpu: i18nc("@item panel item", "GPU"),
        memory: i18nc("@item panel item", "Memory"),
        network: i18nc("@item panel item", "Network"),
        disk: i18nc("@item panel item", "Disk")
    })
    readonly property var rings: ["cpu", "gpu", "memory"]

    // What the widget found on this machine, for the hints. Read from the live
    // configuration rather than a cfg_ property: Apply writes back every cfg_
    // property a page declares, which would undo a report the widget saved
    // while this page was open.
    readonly property var hardware: {
        try {
            const report = JSON.parse(Plasmoid.configuration.detectedHardware);
            return report && typeof report === "object" ? report : {};
        } catch (err) {
            return {};
        }
    }
    readonly property var hints: ({
        cpu: hardware.cpu ? Format.cpuModel(hardware.cpu.model) : "",
        gpu: (Array.isArray(hardware.gpus) ? hardware.gpus : []).filter(g => g)
            .map(g => Format.gpuModel(g.name, "", g.pciName, g.vendor)).join(" + "),
        memory: Format.memoryModules(hardware.memory),
        network: String(hardware.defaultInterface || ""),
        disk: hardware.root ? String(hardware.root.disk || "") : ""
    })

    // Every edit assigns a new array: the dialog learns of changes from the
    // cfg_ properties' change signals, which an in-place edit never sends.
    function including(list, key, included) {
        const rest = list.filter(k => k !== key);
        return included ? rest.concat([key]) : rest;
    }

    function move(from, to) {
        if (from === to || from < 0 || to < 0 || to >= items.count) {
            return;
        }
        items.move(from, to, 1);
        const order = [];
        for (let i = 0; i < items.count; ++i) {
            order.push(items.get(i).key);
        }
        cfg_itemOrder = order;
    }

    // Unknown ids are dropped and missing ones appended, as main.qml does.
    Component.onCompleted: {
        const known = Object.keys(names);
        const order = cfg_itemOrder.filter((k, i, all) => known.includes(k) && all.indexOf(k) === i);
        known.forEach(k => { if (!order.includes(k)) order.push(k); });
        order.forEach(k => items.append({ key: k }));
    }

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.fillWidth: true
            text: i18nc("@info:usagetip", "Drag to reorder · uncheck to hide")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
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
                    // Unused here, but ListItemDragHandle looks it up by name.
                    required property int index
                    readonly property bool ring: page.rings.includes(key)

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
                                checked: !page.cfg_hiddenItems.includes(entry.key)
                                onImplicitWidthChanged: list.checkWidth = Math.max(list.checkWidth, implicitWidth)
                                onToggled: page.cfg_hiddenItems = page.including(page.cfg_hiddenItems, entry.key, !checked)
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: page.hints[entry.key]
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 11.5 / 13
                            }
                            QQC2.ComboBox {
                                id: mode
                                visible: entry.ring
                                model: [i18nc("@item:inlistbox what a ring item shows", "Ring and text"),
                                        i18nc("@item:inlistbox what a ring item shows", "Ring only")]
                                currentIndex: page.cfg_ringsOnly.includes(entry.key) ? 1 : 0
                                Accessible.name: i18nc("@label:listbox %1 is a panel item", "What %1 shows",
                                                       page.names[entry.key])
                                onActivated: index => page.cfg_ringsOnly = page.including(page.cfg_ringsOnly, entry.key, index === 1)
                            }
                        }
                    }
                }
            }
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            RowLayout {
                Kirigami.FormData.label: i18nc("@label:slider", "Ring size:")
                spacing: Kirigami.Units.largeSpacing

                QQC2.Slider {
                    id: size
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                    from: 16
                    to: 64
                    stepSize: 2
                    snapMode: QQC2.Slider.SnapAlways
                    value: page.cfg_ringSize
                    Accessible.name: i18nc("@label:slider", "Ring size")
                    onMoved: page.cfg_ringSize = value
                }
                QQC2.Label {
                    text: i18nc("@label ring diameter in pixels", "%1 px", size.value)
                    textFormat: Text.PlainText
                    font.family: Kirigami.Theme.fixedWidthFont.family
                }
            }
            QQC2.Label {
                text: i18nc("@info", "Rings shrink to fit a thinner panel.")
                textFormat: Text.PlainText
                color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 11.5 / 13
            }
        }
    }
}
