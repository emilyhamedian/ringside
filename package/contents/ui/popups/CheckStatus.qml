// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/style.js" as Style
import ".."

// A failed Claude or Codex check, under the popup's header: a small struck
// ring beside when the check failed, with "Try again" while a check would
// really ask (see UsageData.canRetry()), and under that why it failed, when
// the readings below were taken, or once they are struck the last one, and
// when the next check runs.
GridLayout {
    id: status

    required property string item
    required property var usage
    required property var entry
    // The popup shows no reading: see UsageData.struck().
    required property bool struck
    required property var texts
    required property real nowMs

    readonly property var weekly: entry && entry.weekly ? entry.weekly : null
    // "Try again" comes and goes to the second, as the hold ends and the
    // next tick nears; the popup's own clock steps every half minute.
    property real retryClock: Date.now()

    Timer {
        interval: 1000
        repeat: true
        running: status.visible
        onTriggered: status.retryClock = Date.now()
    }

    columns: 2
    columnSpacing: Kirigami.Units.smallSpacing * 2
    rowSpacing: Math.round(Kirigami.Units.smallSpacing / 2)

    // The panel's sign at the height of the line it leads.
    RingGauge {
        Layout.preferredWidth: Math.round(headline.implicitHeight * 0.8)
        Layout.preferredHeight: Layout.preferredWidth
        Layout.alignment: Qt.AlignVCenter
        strokeWidth: 1.5
        cancelled: true
        settle: 0
        Accessible.ignored: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        Text {
            id: headline
            Layout.fillWidth: true
            text: status.entry ? i18nc("@info %1 is a time", "Last check failed at %1",
                                       status.texts.timeOfDay(status.entry.lastErrorAt, status.nowMs)) : ""
            color: Kirigami.Theme.textColor
            elide: Text.ElideRight
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
        }

        Kirigami.LinkButton {
            visible: status.usage.canRetry(status.item, status.retryClock)
            Layout.alignment: Qt.AlignBaseline
            text: i18nc("@action:button checks the Claude or Codex limits again now", "Try again")
            font.underline: false
            Accessible.description: i18nc("@info accessible; %1 is Claude, Codex or ChatGPT", "Check %1's limits now",
                                          status.texts.providerName(status.item))
            onClicked: status.usage.checkNow()
        }
    }

    Item {
        Layout.preferredWidth: 1
    }

    Text {
        Layout.fillWidth: true
        text: {
            const e = status.entry;
            if (!e) {
                return "";
            }
            const parts = [status.texts.failureReason(status.item, e)];
            if (status.weekly && status.weekly.resetsAt <= status.nowMs / 1000) {
                parts.push(i18nc("@info %1 is a weekday and time, with a time zone where the reset has one, as in Sun 7:00 AM EDT",
                                 "The week reset at %1, with no reading since.", status.texts.resetDate(status.weekly)));
            } else if (status.weekly) {
                const at = status.texts.timeOfDay(e.fetchedAt, status.nowMs);
                parts.push(status.struck ? i18nc("@info %1 is a time", "The last reading is from %1.", at)
                                         : i18nc("@info %1 is a time", "The readings below are from %1.", at));
            }
            parts.push(status.texts.nextCheckText(status.item, status.nowMs));
            return parts.join(" ");
        }
        // The helper's own message, which names the error, for a screen
        // reader as the settings page shows it.
        Accessible.description: status.entry && (status.entry.reason === "files" || status.entry.reason === "helper")
            ? status.entry.lastError : ""
        color: Style.dim(Kirigami.Theme.textColor)
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
    }
}
