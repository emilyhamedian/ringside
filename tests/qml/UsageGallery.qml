// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import "../../package/contents/ui"
import "../../package/contents/ui/popups"
import "../../package/contents/ui/code/items.js" as Items
import "../../package/contents/ui/code/style.js" as Style

// A section of Gallery.qml: Claude and Codex in the panel beside two system
// items, then their popups in each state, then a panel and a popup under
// Breeze Light. The readings are FakeUsage's, with made-up weeks of use.
ColumnLayout {
    id: section

    required property var monitor

    // A week's use so far, `days` long and ending at `percent`: busy
    // stretches with quiet nights between them, as [days ago, percent].
    function history(days, percent) {
        const steps = Math.round(days * 4);
        const weights = Array.from({ length: steps }, (_, i) => i % 4 === 1 || i % 4 === 2 ? 1 : 0.08);
        const sum = weights.reduce((a, b) => a + b, 0);
        const points = [[days, 0]];
        let total = 0;
        weights.forEach((weight, i) => {
            total += weight;
            points.push([Math.max(0, days - (i + 1) / 4), Math.round(total / sum * percent)]);
        });
        return points;
    }

    spacing: 2 * Kirigami.Units.gridUnit

    // Claude amber with Opus red inside it, Codex at its limit.
    FakeMonitor {
        id: hot
        usage: FakeUsage {
            id: hotUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: hotUsage.createdAt,
                    weekly: hotUsage.window(81, 2 * hotUsage.day + 21 * 3600, section.history(4.1, 81)),
                    scoped: [Object.assign({ id: "Opus", label: "Opus" },
                                           hotUsage.window(93, 2 * hotUsage.day + 21 * 3600, section.history(4.1, 93)))]
                },
                codex: {
                    status: "ok",
                    fetchedAt: hotUsage.createdAt,
                    weekly: hotUsage.window(100, 14 * 3600 + 5 * 60, section.history(6.4, 100)),
                    scoped: []
                }
            })
        }
    }

    // Two model limits and no choice between them: no inner ring, a row each.
    FakeMonitor {
        id: several
        usage: FakeUsage {
            id: severalUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: severalUsage.createdAt,
                    weekly: severalUsage.window(77, 2 * severalUsage.day + 21 * 3600, section.history(4.1, 77)),
                    scoped: [Object.assign({ id: "Opus", label: "Opus" },
                                           severalUsage.window(84, 2 * severalUsage.day + 21 * 3600, section.history(4.1, 84))),
                             Object.assign({ id: "Sonnet", label: "Sonnet" },
                                           severalUsage.window(12, 4 * severalUsage.day + 2 * 3600, section.history(3, 12)))]
                }
            })
        }
    }

    // The last hour of a week that ran close to its limit.
    FakeMonitor {
        id: fullWeek
        usage: FakeUsage {
            id: fullWeekUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: fullWeekUsage.createdAt,
                    weekly: fullWeekUsage.window(91, 3600, section.history(6.95, 91)),
                    scoped: []
                }
            })
        }
    }

    // The last check failed: the readings stay, dimmed.
    FakeMonitor {
        id: failed
        usage: FakeUsage {
            id: failedUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: failedUsage.createdAt - 3600,
                    weekly: failedUsage.window(58, 2 * failedUsage.day + 22 * 3600, section.history(4, 58)),
                    scoped: [Object.assign({ id: "Opus", label: "Opus" },
                                           failedUsage.window(71, 2 * failedUsage.day + 22 * 3600, section.history(4, 71)))],
                    lastError: "HTTP Error 500: Internal Server Error",
                    lastErrorAt: failedUsage.createdAt
                }
            })
        }
    }

    FakeMonitor {
        id: signedOut
        usage: FakeUsage {
            entries: ({ codex: { status: "signed_out" } })
        }
    }

    component Note: Text {
        color: Style.dim(Kirigami.Theme.textColor)
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        textFormat: Text.PlainText
    }

    // Cells as the strip lays them out, on a stretch of panel whose
    // thickness the outline marks.
    component Panel: ColumnLayout {
        id: panel

        required property string label
        required property real thickness
        property var monitor: section.monitor
        property var items: ["cpu", "memory", "claude", "codex"]
        readonly property real ring: Math.max(16, Math.min(30, thickness - 2 * Kirigami.Units.smallSpacing))
        readonly property bool twoLines: thickness >= Kirigami.Units.gridUnit * 2

        spacing: Kirigami.Units.smallSpacing

        Note {
            text: panel.label
        }

        Rectangle {
            color: "transparent"
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
            Layout.preferredWidth: row.implicitWidth + 4 * Kirigami.Units.gridUnit
            Layout.preferredHeight: panel.thickness

            RowLayout {
                id: row
                anchors.centerIn: parent
                height: parent.height
                spacing: 0

                Repeater {
                    model: panel.items

                    delegate: PanelCell {
                        id: cell

                        required property string modelData

                        Layout.fillHeight: true
                        item: modelData

                        Loader {
                            anchors.centerIn: parent
                            sourceComponent: Items.isUsage(cell.modelData) ? usageContent : ringContent
                            onLoaded: cell.contentItem = item
                        }

                        Component {
                            id: usageContent
                            UsageCellContent {
                                monitor: panel.monitor
                                item: cell.modelData
                                ring: panel.ring
                                textShown: true
                                twoLines: panel.twoLines
                            }
                        }

                        Component {
                            id: ringContent
                            RingCellContent {
                                monitor: panel.monitor
                                item: cell.modelData
                                ring: panel.ring
                                textShown: true
                                twoLines: panel.twoLines
                            }
                        }
                    }
                }
            }
        }
    }

    // A popup on the dialog background, or on a flat one where the colours
    // are overridden (the dialog SVG follows the system scheme).
    component Frame: ColumnLayout {
        id: frame

        required property string label
        property bool flat: false
        default property alias page: holder.data

        Layout.alignment: Qt.AlignTop
        spacing: Kirigami.Units.smallSpacing

        Note {
            text: frame.label
        }

        Item {
            id: dialog

            readonly property var margin: frame.flat
                ? { left: Kirigami.Units.smallSpacing, top: Kirigami.Units.smallSpacing,
                    right: Kirigami.Units.smallSpacing, bottom: Kirigami.Units.smallSpacing }
                : background.fixedMargins

            Layout.preferredWidth: holder.childrenRect.width + margin.left + margin.right
            Layout.preferredHeight: holder.childrenRect.height + margin.top + margin.bottom

            KSvg.FrameSvgItem {
                id: background
                anchors.fill: parent
                visible: !frame.flat
                imagePath: "dialogs/background"
            }

            Rectangle {
                anchors.fill: parent
                visible: frame.flat
                color: Kirigami.Theme.backgroundColor
                border.color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
                radius: Kirigami.Units.smallSpacing
            }

            Item {
                id: holder
                x: dialog.margin.left
                y: dialog.margin.top
            }
        }
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · Claude 62 % with Opus 78 % inside, Codex 34 %"
        thickness: 46
    }

    Panel {
        label: "Claude & Codex · panel · 30 px"
        thickness: 30
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · Claude 81 % (amber) with Opus 93 % (red), Codex 100 % (red)"
        thickness: 46
        monitor: hot
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · Claude's last check failed, Codex signed out (hidden)"
        thickness: 46
        monitor: failed
        items: ["cpu", "memory", "claude"]
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        Frame {
            label: "Claude · Opus on the inner ring"
            UsagePopup { monitor: section.monitor; item: "claude" }
        }

        Frame {
            label: "Codex"
            UsagePopup { monitor: section.monitor; item: "codex" }
        }

        Frame {
            label: "Claude · two model limits, none picked"
            UsagePopup { monitor: several; item: "claude" }
        }

        Frame {
            label: "Claude · full week, an hour left"
            UsagePopup { monitor: fullWeek; item: "claude" }
        }
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        Frame {
            label: "Claude · 81 % (amber), Opus 93 % (red)"
            UsagePopup { monitor: hot; item: "claude" }
        }

        Frame {
            label: "Codex · at its limit"
            UsagePopup { monitor: hot; item: "codex" }
        }

        Frame {
            label: "Claude · last check failed"
            UsagePopup { monitor: failed; item: "claude" }
        }

        Frame {
            label: "Codex · signed out"
            UsagePopup { monitor: signedOut; item: "codex" }
        }
    }

    // Breeze Light's colours, for the contrast of dim text and level colours
    // on a light scheme.
    Rectangle {
        Layout.fillWidth: true
        implicitWidth: light.implicitWidth + 2 * light.x
        implicitHeight: light.implicitHeight + 2 * light.y
        color: Kirigami.Theme.backgroundColor

        Kirigami.Theme.inherit: false
        Kirigami.Theme.textColor: "#232629"
        Kirigami.Theme.disabledTextColor: "#707d8a"
        Kirigami.Theme.backgroundColor: "#eff0f1"
        Kirigami.Theme.alternateBackgroundColor: "#e3e5e7"
        Kirigami.Theme.highlightColor: "#3daee9"
        Kirigami.Theme.highlightedTextColor: "#ffffff"
        Kirigami.Theme.linkColor: "#2980b9"
        Kirigami.Theme.visitedLinkColor: "#9b59b6"
        Kirigami.Theme.negativeTextColor: "#da4453"
        Kirigami.Theme.neutralTextColor: "#f67400"
        Kirigami.Theme.positiveTextColor: "#27ae60"

        ColumnLayout {
            id: light

            x: 2 * Kirigami.Units.gridUnit
            y: x
            spacing: 2 * Kirigami.Units.gridUnit

            Panel {
                label: "Breeze Light · Claude & Codex · panel · 46 px · amber and red"
                thickness: 46
                monitor: hot
            }

            Frame {
                label: "Breeze Light · Claude"
                flat: true
                UsagePopup { monitor: section.monitor; item: "claude" }
            }
        }
    }
}
