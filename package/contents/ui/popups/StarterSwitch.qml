// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../code/style.js" as Style
import ".."

// The footer's switch that starts Claude's next session, or Codex's next
// week, as soon as the last one ends, with what the starter is doing under
// its label. The switch is per user: every widget shows the same one. While
// the item is struck (see UsageData.struck()) the switch keeps its position
// but can't be turned, and the line under it says so; the starter itself
// runs as it would.
RowLayout {
    id: row

    required property string item
    // UsageData, or FakeUsage in the tests.
    required property var usage
    required property real nowMs
    required property Words texts

    readonly property var starter: usage.starter(item)
    readonly property bool struck: usage.struck(item, nowMs)
    readonly property string status: struck
        ? i18nc("@info under the session starter's switch, which can't be turned while the Claude or Codex limits can't be checked",
                "Can be changed once Ringside can check your usage again.")
        : texts.starterStatus(item, starter, nowMs)
    // Something the user has to fix, or a send that didn't take, rather than
    // the starter holding as planned.
    readonly property bool failed: !struck && ["failed", "retrying", "paused"].includes(starter?.state)

    spacing: Kirigami.Units.largeSpacing

    // Takes the footer's width rather than setting it: a long label
    // would otherwise widen the popup.
    Layout.fillWidth: true
    Layout.preferredWidth: 0
    // Clear of the footer's rule, as the tile is clear of it above.
    Layout.topMargin: Kirigami.Units.smallSpacing
    // The last line's baseline as far from the popup's edge as the
    // label is from the footer's rule, as a tile's foot is, whether the
    // status takes one line or two. The room under the baseline is
    // measured on a laid-out line, not the font's metrics: Qt 6.6 rounds
    // each line up.
    Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 2 - (line.implicitHeight - line.baselineOffset))

    // The track alone, centred on the label and the status together. The
    // label is a text beside it that turns it too, as a switch's own label
    // does. The status is no part of the switch, so a click on it does
    // nothing: turning the switch spends usage.
    PlasmaComponents.Switch {
        id: toggle
        Layout.alignment: Qt.AlignVCenter
        enabled: !row.struck
        text: row.item === "claude" ? i18nc("@option:check", "Start a new session when one ends")
                                    : i18nc("@option:check", "Start a new week when one ends")
        contentItem: Item {}
        // The change asked for until the helper reports, then what the
        // helper reports. Turning the switch writes checked from C++, which
        // keeps this binding.
        checked: row.usage.starterOn(row.item)
        onToggled: row.usage.setStarter(row.item, checked)
        // Space turns it; Return and Enter too, as on a check box. Not
        // click(), which Qt 6.6 lacks.
        Keys.onReturnPressed: row.usage.setStarter(row.item, !checked)
        Keys.onEnterPressed: row.usage.setStarter(row.item, !checked)

        Accessible.name: text
        Accessible.description: row.status
    }

    // The label with the status under it, as KDE puts a check box's
    // explanation, a large spacing clear of the track.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        spacing: 0

        Text {
            id: label
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            // As tall as the track, as Plasma's switch is with a label alone,
            // so the status keeps its distance from the label.
            Layout.preferredHeight: Math.max(implicitHeight, toggle.implicitHeight)
            enabled: toggle.enabled
            text: toggle.text
            textFormat: Text.PlainText
            font: toggle.font
            color: Kirigami.Theme.textColor
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            // Set, not left to the layout's mirroring: Qt leaves left-aligned
            // text at the left in a mirrored layout otherwise (QTBUG-95873).
            horizontalAlignment: Text.AlignLeft
            // The switch says it; read once, not twice.
            Accessible.ignored: true

            TapHandler {
                enabled: toggle.enabled
                onTapped: row.usage.setStarter(row.item, !toggle.checked)
            }
        }

        Text {
            id: statusText
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            // A longer status, such as one with the helper's error, elides at
            // two lines and reads in full from a tool tip, or from the switch's
            // description in a screen reader.
            maximumLineCount: 2
            elide: Text.ElideRight
            text: row.status
            color: row.failed ? Kirigami.Theme.textColor : Style.dim(Kirigami.Theme.textColor)
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignTop
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
            // The switch says it; read once, not twice.
            Accessible.ignored: true

            Text {
                id: line
                visible: false
                text: " "
                font: statusText.font
                textFormat: Text.PlainText
            }

            HoverHandler {
                id: statusHover
            }

            PlasmaComponents.ToolTip {
                text: row.status
                visible: statusText.truncated && (statusHover.hovered || toggle.hovered || toggle.visualFocus)
                delay: Kirigami.Units.toolTipDelay
            }
        }
    }
}
