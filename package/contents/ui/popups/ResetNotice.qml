// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/style.js" as Style
import ".."

// A weekly limit that started over before its reset time, under the popup's
// header, laid out as CheckStatus is: a star beside which limit reset and
// how long ago, and under that how far its usage fell. It says nothing of
// who reset it, since a reset the user redeemed themselves looks the same
// as one the provider gave everyone.
GridLayout {
    id: notice

    // The window that reset early (see UsageData.earlyReset()), or null.
    required property var window
    required property Words texts
    required property real nowMs

    readonly property var early: window ? window.earlyReset : null

    visible: early !== null
    columns: 2
    columnSpacing: Kirigami.Units.smallSpacing * 2
    rowSpacing: Math.round(Kirigami.Units.smallSpacing / 2)

    Kirigami.Icon {
        id: sign
        Layout.preferredWidth: Math.round(headline.implicitHeight * 0.9)
        Layout.preferredHeight: Layout.preferredWidth
        Layout.alignment: Qt.AlignVCenter
        source: "starred-symbolic"
        color: Kirigami.Theme.positiveTextColor
        isMask: true
        Accessible.ignored: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        // The time is set smaller, so it sits on the headline's baseline
        // rather than in the middle of its line.
        Text {
            id: headline
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBaseline
            text: notice.window?.label
                ? i18nc("@info under Claude's or Codex's header: a model's weekly limit started over before its reset time; %1 is the model, e.g. Fable",
                        "%1 limit reset early", notice.window.label)
                : i18nc("@info under Claude's or Codex's header: the weekly limit started over before its reset time",
                        "Weekly limit reset early")
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
        }

        Text {
            Layout.alignment: Qt.AlignBaseline
            text: notice.early ? notice.texts.ago(notice.early.at, notice.nowMs) : ""
            color: Style.dim(Kirigami.Theme.textColor)
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            textFormat: Text.PlainText
            Accessible.name: notice.early ? notice.texts.agoSpoken(notice.early.at, notice.nowMs) : ""
        }
    }

    Item {
        Layout.preferredWidth: 1
    }

    // Wrapped to its room as soon as it shows, as CheckStatus's reason is,
    // so its height never changes while the popup is laid out (a polish
    // loop on Qt 6.6).
    Item {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight

        Text {
            id: body
            anchors.left: parent.left
            width: notice.parent ? notice.parent.width - notice.Layout.leftMargin - notice.Layout.rightMargin
                                   - sign.Layout.preferredWidth - notice.columnSpacing : 0
            text: notice.early
                ? i18nc("@info under 'Weekly limit reset early': how much of the limit was used before and after, e.g. 80% and 0%",
                        "Your usage went from %1 to %2.", notice.texts.percent(notice.early.from), notice.texts.percent(0))
                : ""
            color: Style.dim(Kirigami.Theme.textColor)
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
        }
    }
}
