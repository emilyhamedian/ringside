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
PlasmaComponents.Switch {
    id: toggle

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
    // Where the label and the status start: past the track. The track's
    // implicit width, not its width: the switch's own implicit width is built
    // from the content, and Qt 6.6 reports a binding loop through the width.
    readonly property real textInset: leftPadding + indicator.implicitWidth + spacing

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

    enabled: !struck
    // Plasma's small spacing leaves the label against the knob.
    spacing: Kirigami.Units.largeSpacing
    text: item === "claude" ? i18nc("@option:check", "Start a new session when one ends")
                            : i18nc("@option:check", "Start a new week when one ends")
    // The change asked for until the helper reports, then what the
    // helper reports. Turning the switch writes checked from C++, which
    // keeps this binding.
    checked: usage.starterOn(item)
    onToggled: usage.setStarter(item, checked)
    // Space turns it; Return and Enter too, as on a check box. Not
    // click(), which Qt 6.6 lacks.
    Keys.onReturnPressed: usage.setStarter(item, !checked)
    Keys.onEnterPressed: usage.setStarter(item, !checked)

    Accessible.name: text
    Accessible.description: status

    // The label with the status under it, as KDE puts a check box's
    // explanation, are the switch's content, so the track is centred on both
    // together rather than on the label alone.
    contentItem: ColumnLayout {
        spacing: 0

        Text {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.leftMargin: toggle.textInset
            // As tall as the track, as Plasma's switch is with a label alone,
            // so the status keeps its distance from the label.
            Layout.preferredHeight: Math.max(implicitHeight, toggle.indicator.height)
            verticalAlignment: Text.AlignVCenter
            text: toggle.text
            textFormat: Text.PlainText
            font: toggle.font
            color: Kirigami.Theme.textColor
            linkColor: Kirigami.Theme.linkColor
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            // Not left to the layout's mirroring: Qt leaves left-aligned text
            // at the left in a mirrored layout unless this is set (QTBUG-95873).
            horizontalAlignment: Text.AlignLeft
        }

        Text {
            id: statusText
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.leftMargin: toggle.textInset
            // A longer status, such as one with the helper's error, elides at
            // two lines and reads in full from a tool tip, or from the switch's
            // description in a screen reader.
            maximumLineCount: 2
            elide: Text.ElideRight
            text: toggle.status
            // From the footer's enabled colours: the reason the switch can't
            // be turned stays as legible as it is otherwise, rather than greyed
            // with the switch that holds it.
            color: toggle.failed ? toggle.parent.Kirigami.Theme.textColor : Style.dim(toggle.parent.Kirigami.Theme.textColor)
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
                text: toggle.status
                visible: statusText.truncated && (statusHover.hovered || toggle.hovered || toggle.visualFocus)
                delay: Kirigami.Units.toolTipDelay
            }
        }
    }
}
