// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/style.js" as Style
import ".."

// Claude's or Codex's weekly limits: the all-models week in the header with
// the time left until it resets, a bar for it and for each model's own
// limit, and the week so far as a graph. A failed check or a signed-out CLI
// is said in a line under the header.
PopupPage {
    id: popup

    required property string item

    readonly property var usage: monitor.usage
    readonly property var entry: usage.entry(item)
    readonly property var weekly: entry && entry.weekly ? entry.weekly : null
    readonly property var innerLimit: usage.inner(item)
    readonly property bool claude: item === "claude"
    // All models first, then every model's own limit, whichever the ring shows.
    readonly property var limits: weekly
        ? [{ id: "", label: i18nc("@label the weekly limit shared by every model", "All models"),
             percent: weekly.percent, resetsAt: weekly.resetsAt }].concat(Array.from(entry.scoped ?? []))
        : []
    // Stepped by the timer below, for the countdowns.
    property real nowMs: Date.now()

    function tone(percent) {
        const level = Format.level(percent);
        return level === 2 ? Kirigami.Theme.negativeTextColor
             : level === 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor;
    }

    systemMonitorShown: false

    Words {
        id: words
        monitor: popup.monitor
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: popup.nowMs = Date.now()
    }

    PopupHeader {
        ringValue: popup.weekly ? popup.weekly.percent : NaN
        title: popup.claude ? i18nc("@title", "Claude") : i18nc("@title", "Codex")
        subtitle: i18nc("@info under Claude or Codex: what the popup shows", "Weekly limits")
        value: popup.weekly ? words.countdown(popup.weekly.resetsAt, popup.nowMs) || "–" : ""
        valueColor: popup.tone(ringValue)
        caption: i18nc("@info:label under the time left, e.g. 2d 21h until reset", "until reset")
    }

    // The last check's failure, or why there is nothing to show.
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.bottomMargin: Kirigami.Units.largeSpacing
        visible: text !== ""
        text: {
            const e = popup.entry;
            if (e && e.lastError !== undefined) {
                return i18nc("@info %1 is a time, %2 the error as the helper reported it", "Last check failed at %1: %2",
                             words.timeOfDay(e.lastErrorAt, popup.nowMs), e.lastError);
            }
            if (!e || e.status === "signed_out") {
                return popup.usage.helperError
                    || (popup.claude ? i18nc("@info", "Run claude in a terminal to sign in.")
                                     : i18nc("@info", "Run codex in a terminal to sign in."));
            }
            return "";
        }
        color: Style.dim(Kirigami.Theme.textColor)
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
    }

    ColumnLayout {
        visible: popup.weekly !== null
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.25)
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: popup.limits

            delegate: ColumnLayout {
                id: row

                required property var modelData
                // A model's limit that resets apart from the week says when.
                readonly property string resets: modelData.id !== "" && popup.weekly
                    && Math.abs(modelData.resetsAt - popup.weekly.resetsAt) >= 60
                    ? words.countdown(modelData.resetsAt, popup.nowMs) : ""

                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Accessible.role: Accessible.ProgressBar
                Accessible.name: modelData.label
                Accessible.description: words.percentText(modelData.percent)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.label
                        color: Kirigami.Theme.textColor
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        horizontalAlignment: Text.AlignLeft
                    }

                    Text {
                        visible: row.resets !== ""
                        text: i18nc("@info time left until this limit resets, e.g. resets in 4d 2h", "resets in %1", row.resets)
                        color: Style.dim(Kirigami.Theme.textColor)
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        textFormat: Text.PlainText
                    }

                    Text {
                        text: i18nc("@info a percentage", "%1%", Format.percent(row.modelData.percent))
                        color: popup.tone(row.modelData.percent)
                        font.family: Kirigami.Theme.defaultFont.family
                        font.features: ({ "tnum": 1 })
                        textFormat: Text.PlainText
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Math.round(Kirigami.Units.smallSpacing * 1.5)
                    radius: height / 2
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.08)

                    Rectangle {
                        anchors.left: parent.left
                        width: parent.width * Math.max(0, Math.min(100, row.modelData.percent)) / 100
                        height: parent.height
                        radius: parent.radius
                        color: popup.tone(row.modelData.percent)
                    }
                }
            }
        }
    }

    GridLayout {
        visible: popup.weekly !== null
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        Layout.rightMargin: Layout.leftMargin
        Layout.bottomMargin: Layout.leftMargin
        columns: 1

        Tile {
            caption: i18nc("@title:group the current weekly window", "This week")
            detail: {
                const date = words.resetDate(popup.weekly);
                return date ? i18nc("@title:group after THIS WEEK: when the week starts over, e.g. · resets Sun 7:00 AM EDT",
                                    "· resets %1", date) : "";
            }

            WeekGraph {
                Layout.fillWidth: true
                window: popup.weekly
                secondWindow: popup.innerLimit
                nowMs: popup.nowMs
            }

            RowLayout {
                visible: popup.innerLimit !== null
                Layout.fillWidth: true
                Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)
                spacing: Math.round(Kirigami.Units.largeSpacing * 1.75)

                Caption {
                    Layout.minimumWidth: implicitWidth
                    text: i18nc("@label graph legend, the solid line", "— All models")
                }

                Caption {
                    Layout.fillWidth: true
                    text: popup.innerLimit ? i18nc("@label graph legend, the dashed line; %1 is a model", "- - %1",
                                                   popup.innerLimit.label) : ""
                }
            }
        }
    }
}
