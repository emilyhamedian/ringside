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
// its label. The switch is per user: every widget shows the same one.
ColumnLayout {
    id: row

    required property string item
    // UsageData, or FakeUsage in the tests.
    required property var usage
    required property real nowMs
    required property Words texts

    readonly property var starter: usage.starter(item)
    readonly property string status: texts.starterStatus(item, starter, nowMs)
    // Something the user has to fix, or a send that didn't take, rather than
    // the starter holding as planned.
    readonly property bool failed: ["failed", "retrying", "paused"].includes(starter?.state)

    spacing: 0

    PlasmaComponents.Switch {
        id: toggle
        Layout.fillWidth: true
        // Clear of the footer's rule, as the tile is clear of it above.
        Layout.topMargin: Kirigami.Units.smallSpacing
        // Takes the footer's width rather than setting it: a long label
        // would otherwise widen the popup.
        Layout.preferredWidth: 0
        text: row.item === "claude" ? i18nc("@option:check", "Start a new session when one ends")
                                    : i18nc("@option:check", "Start a new week when one ends")
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

    // Under the label, past the switch's track, as KDE puts a check box's
    // explanation.
    Text {
        id: statusText
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        Layout.leftMargin: toggle.leftPadding + toggle.indicator.width + toggle.spacing
        // The last line's baseline as far from the popup's edge as the
        // switch's label is from the footer's rule, as a tile's foot is,
        // whether the status takes one line or two. The room under the
        // baseline is measured on a laid-out line, not the font's metrics:
        // Qt 6.6 rounds each line up.
        Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 2 - (line.implicitHeight - line.baselineOffset))
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
