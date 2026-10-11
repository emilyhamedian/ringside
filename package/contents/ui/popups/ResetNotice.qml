// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/style.js" as Style
import ".."

// A weekly limit that started over before its reset time, under the popup's
// header, laid out as CheckStatus is: a star beside the news and how long
// ago it came, and under that which limit it was and what it gave back. It
// says nothing of who reset it, since a reset the user redeemed themselves
// looks the same as one the provider gave everyone.
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

        Text {
            id: headline
            Layout.fillWidth: true
            text: i18nc("@info under Claude's or Codex's header: a weekly limit started over before its reset time",
                        "You got an early reset")
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
        }

        Text {
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
            text: {
                if (!notice.early) {
                    return "";
                }
                const used = notice.texts.percent(notice.early.from);
                return notice.window.label
                    ? i18nc("@info under 'You got an early reset'; %1 is a model, %2 a percentage, e.g. Fable, 81%",
                            "Your %1 limit started over before it was due. The %2 you had used is back.",
                            notice.window.label, used)
                    : i18nc("@info under 'You got an early reset'; %1 is a percentage, e.g. 62%",
                            "Your weekly limit started over before it was due. The %1 you had used is back.", used);
            }
            color: Style.dim(Kirigami.Theme.textColor)
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
        }
    }
}
