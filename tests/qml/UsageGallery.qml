// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import "../../package/contents/ui"
import "../../package/contents/ui/popups"
import "../../package/contents/ui/code/style.js" as Style

// A section of Gallery.qml: Claude and Codex in the panel beside two system
// items, then their popups in each state, then panels and popups under
// Breeze Light. The monitor's readings are FakeUsage's; the section's own
// come with made-up weeks of use.
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

    // Red three ways: Claude at 81 % only from its pace, Fable over 90 %,
    // Codex at its limit.
    FakeMonitor {
        id: hot
        usage: FakeUsage {
            id: hotUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: hotUsage.createdAt,
                    weekly: hotUsage.window(81, 2 * hotUsage.day + 21 * 3600, section.history(4.1, 81)),
                    scoped: [Object.assign({ id: "Fable", label: "Fable" },
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
    // A day before the reset, Claude and Fable are amber and last to it.
    FakeMonitor {
        id: several
        usage: FakeUsage {
            id: severalUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: severalUsage.createdAt,
                    weekly: severalUsage.window(77, severalUsage.day, section.history(6, 77)),
                    scoped: [Object.assign({ id: "Fable", label: "Fable" },
                                           severalUsage.window(82, severalUsage.day, section.history(6, 82))),
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

    // The last check, an hour after the one that worked, failed: the
    // readings stay, marked with a dot. At this pace both last the week.
    FakeMonitor {
        id: failed
        usage: FakeUsage {
            id: failedUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: failedUsage.createdAt - 3600,
                    weekly: failedUsage.window(48, 2 * failedUsage.day + 22 * 3600, section.history(4, 48)),
                    scoped: [Object.assign({ id: "Fable", label: "Fable" },
                                           failedUsage.window(52, 2 * failedUsage.day + 22 * 3600, section.history(4, 52)))],
                    lastError: "HTTP Error 500: Internal Server Error",
                    lastErrorAt: failedUsage.createdAt
                }
            })
        }
    }

    // Two days into the week, Claude at 25 % lasts it, while Fable at 55 %
    // is red only because it runs out before the reset at this pace.
    FakeMonitor {
        id: fablePace
        usage: FakeUsage {
            id: fablePaceUsage
            entries: ({
                claude: {
                    status: "ok",
                    fetchedAt: fablePaceUsage.createdAt,
                    weekly: fablePaceUsage.window(25, 5 * fablePaceUsage.day, section.history(2, 25)),
                    scoped: [Object.assign({ id: "Fable", label: "Fable" },
                                           fablePaceUsage.window(55, 5 * fablePaceUsage.day, section.history(2, 55)))]
                }
            })
        }
    }

    // Codex's one limit at 40 % two days in, on pace to run out.
    FakeMonitor {
        id: codexPace
        usage: FakeUsage {
            id: codexPaceUsage
            entries: ({
                codex: {
                    status: "ok",
                    fetchedAt: codexPaceUsage.createdAt,
                    weekly: codexPaceUsage.window(40, 5 * codexPaceUsage.day, section.history(2, 40)),
                    scoped: []
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

    // The strip on a stretch of panel whose thickness the outline marks.
    // Breeze's panel keeps 4 px of margin either side of an applet.
    component Panel: ColumnLayout {
        id: panel

        required property string label
        required property real thickness
        property var monitor: section.monitor
        property var items: ["cpu", "memory", "claude", "codex"]

        spacing: Kirigami.Units.smallSpacing

        Note {
            text: panel.label
        }

        Rectangle {
            color: "transparent"
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
            Layout.preferredWidth: strip.implicitWidth + 4 * Kirigami.Units.gridUnit
            Layout.preferredHeight: panel.thickness

            Strip {
                id: strip
                anchors.centerIn: parent
                height: panel.thickness - 8
                monitor: panel.monitor
                items: panel.items
                vertical: false
                thickness: panel.thickness - 8
                ringsOnly: []
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
        label: "Claude & Codex · panel · 46 px · Claude 52 % with Fable 78 % inside (red, on pace to run out), Codex 24 %"
        thickness: 46
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · Claude 25 %, Fable 55 % (red only from its pace)"
        thickness: 46
        monitor: fablePace
        items: ["cpu", "memory", "claude"]
    }

    Panel {
        label: "Claude & Codex · panel · 30 px"
        thickness: 30
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · Claude 81 % (red, on pace to run out) with Fable 93 % (red), Codex 100 % (red)"
        thickness: 46
        monitor: hot
    }

    Panel {
        label: "Claude & Codex · panel · 46 px · Claude's last check failed (dot), Codex signed out (hidden)"
        thickness: 46
        monitor: failed
        items: ["cpu", "memory", "claude"]
    }

    Panel {
        label: "Claude & Codex · panel · 30 px · Claude's last check failed (dot)"
        thickness: 30
        monitor: failed
        items: ["cpu", "memory", "claude"]
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        Frame {
            label: "Claude · Fable on the inner ring, on pace to run out"
            UsagePopup { monitor: section.monitor; item: "claude" }
        }

        Frame {
            label: "Codex · one limit, lasts to the reset"
            UsagePopup { monitor: section.monitor; item: "codex" }
        }

        Frame {
            label: "Claude · two model limits, none picked, amber, both last"
            UsagePopup { monitor: several; item: "claude" }
        }

        Frame {
            label: "Claude · 91 % (red), an hour left"
            UsagePopup { monitor: fullWeek; item: "claude" }
        }
    }

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        Frame {
            label: "Claude · 81 % (red, on pace to run out), Fable 93 % (red)"
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

    RowLayout {
        spacing: 2 * Kirigami.Units.gridUnit

        Frame {
            label: "Claude · 25 %, Fable 55 % (red only from its pace)"
            UsagePopup { monitor: fablePace; item: "claude" }
        }

        Frame {
            label: "Codex · one limit at 40 %, on pace to run out"
            UsagePopup { monitor: codexPace; item: "codex" }
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
                label: "Breeze Light · Claude & Codex · panel · 46 px · Claude 81 % (red, on pace to run out), Codex 100 % (red)"
                thickness: 46
                monitor: hot
            }

            Panel {
                label: "Breeze Light · Claude · panel · 46 px · Claude 77 % (amber), lasts to the reset"
                thickness: 46
                monitor: several
                items: ["cpu", "memory", "claude"]
            }

            RowLayout {
                spacing: 2 * Kirigami.Units.gridUnit

                Frame {
                    label: "Breeze Light · Claude · the pace sentence on Fable"
                    flat: true
                    UsagePopup { monitor: section.monitor; item: "claude" }
                }

                Frame {
                    label: "Breeze Light · Codex · one limit, the pace sentence"
                    flat: true
                    UsagePopup { monitor: codexPace; item: "codex" }
                }
            }
        }
    }
}
