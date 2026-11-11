// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../code/style.js" as Style
import ".."

// The footer's switches that start the provider's next session or week as
// soon as the last one ends: one for each window its plan lets Ringside
// start (see UsageData.startable()), a session's above a week's, with what
// the starter is doing under their labels. The switches are per user:
// every widget shows the same ones. While the item is struck (see
// UsageData.struck()) the switches keep their positions but can't be
// turned, and the line under them says so; the starter itself runs as it
// would.
GridLayout {
    id: row

    required property string item
    // UsageData, or anything shaped like it.
    required property var usage
    required property real nowMs
    required property Words texts

    readonly property var windows: usage.startable(item)
    // A lone switch is centred on its label and the status together, as a
    // check box is on its text and explanation; two are each level with
    // their own label, and the status goes under both.
    readonly property bool lone: windows.length === 1
    readonly property var starter: usage.starter(item)
    readonly property bool struck: usage.struck(item, nowMs)
    readonly property string status: struck
        ? i18nc("@info under the session starter's switch, which can't be turned while the Claude or Codex limits can't be checked",
                "Can be changed once Ringside can check your usage again.")
        : texts.starterStatus(item, starter, nowMs)
    // Something the user has to fix, or a send that didn't take, rather than
    // the starter holding as planned.
    readonly property bool failed: !struck && ["failed", "retrying", "paused"].includes(starter?.state)

    columns: 2
    columnSpacing: Kirigami.Units.largeSpacing
    rowSpacing: 0

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

    // The track alone. Its label is a text beside it that turns it too, as
    // a switch's own label does. The status is no part of any switch, so a
    // click on it does nothing: turning a switch spends usage.
    component Track: PlasmaComponents.Switch {
        id: toggle

        required property string window

        Layout.column: 0
        Layout.rowSpan: row.lone ? 2 : 1
        Layout.alignment: Qt.AlignVCenter
        enabled: !row.struck
        contentItem: Item {}
        // The change asked for until the helper reports, then what the
        // helper reports. Turning the switch writes checked from C++, which
        // keeps this binding.
        checked: row.usage.starterOn(row.item, window)
        onToggled: row.usage.setStarter(row.item, window, checked)
        // Space turns it; Return and Enter too, as on a check box. Not
        // click(), which Qt 6.6 lacks.
        Keys.onReturnPressed: row.usage.setStarter(row.item, window, !checked)
        Keys.onEnterPressed: row.usage.setStarter(row.item, window, !checked)

        Accessible.name: text
        Accessible.description: row.status
    }

    // A track's label, a large spacing clear of it.
    component Label: Text {
        id: label

        // var: Qt 6.6 can't hold an inline component type here.
        required property var toggle

        Layout.column: 1
        Layout.row: toggle.Layout.row
        Layout.topMargin: toggle.Layout.topMargin
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        // As tall as the track, as Plasma's switch is with a label alone,
        // so the status keeps its distance from the label.
        Layout.preferredHeight: Math.max(implicitHeight, toggle.implicitHeight)
        visible: toggle.visible
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
            enabled: label.toggle.enabled
            onTapped: row.usage.setStarter(row.item, label.toggle.window, !label.toggle.checked)
        }
    }

    Track {
        id: sessionToggle
        window: "session"
        visible: row.windows.includes("session")
        Layout.row: 0
        text: i18nc("@option:check", "Auto start session")
    }

    Label {
        toggle: sessionToggle
    }

    Track {
        id: weekToggle
        window: "week"
        visible: row.windows.includes("week")
        Layout.row: sessionToggle.visible ? 1 : 0
        // Clear of the session's switch above it.
        Layout.topMargin: sessionToggle.visible ? Kirigami.Units.smallSpacing : 0
        text: i18nc("@option:check", "Auto start week")
    }

    Label {
        toggle: weekToggle
    }

    // Under the labels, as KDE puts a check box's explanation.
    Text {
        id: statusText
        Layout.column: 1
        Layout.row: row.windows.length
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        // A longer status, such as one with the helper's error, elides at
        // two lines and reads in full from a tool tip, or from each switch's
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
        // The switches say it; read once, not twice.
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
            visible: statusText.truncated && (statusHover.hovered || [sessionToggle, weekToggle].some(t => t.visible && (t.hovered || t.visualFocus)))
            delay: Kirigami.Units.toolTipDelay
        }
    }
}
