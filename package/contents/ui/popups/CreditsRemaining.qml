// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/style.js" as Style
import ".."

RowLayout {
    id: row

    required property var credit
    readonly property var balance: credit?.balance
    readonly property bool cached: credit?.status !== "ok"
    readonly property bool shown: ["ok", "error", "unavailable"].includes(credit?.status)
        && Format.usable(balance?.amount) && balance.amount > 0
        && typeof balance.currency === "string" && /^(|[A-Z]{3})$/.test(balance.currency)
        && [0, 2].includes(balance.precision) && Format.usable(credit?.fetchedAt) && credit.fetchedAt > 0
    readonly property var formatted: shown ? Format.credit(balance.amount, balance.precision, balance.currency === "")
                                          : ({ value: "", below: false })
    readonly property string value: formatted.below
        ? i18nc("@info a positive credit balance smaller than the shown precision, e.g. <0.01", "<%1", formatted.value)
        : formatted.value
    readonly property string unit: shown ? balance.currency || i18nc("@label credit balance unit", "credits") : ""
    readonly property string label: cached
        ? i18nc("@label the last known credit balance after a failed check", "Credits remaining · cached")
        : i18nc("@label", "Credits remaining")
    readonly property string detail: {
        if (!shown) {
            return "";
        }
        const observed = i18nc("@info:tooltip when the credit balance was read, %1 is a local date and time", "Checked %1",
                              new Date(credit.fetchedAt * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat));
        if (!cached) {
            return observed;
        }
        switch (credit.reason) {
        case "rate-limited":
            return observed + "\n" + i18nc("@info:tooltip", "The service limited credit checks. Showing the last known balance.");
        case "offline":
            return observed + "\n" + i18nc("@info:tooltip", "The service could not be reached. Showing the last known balance.");
        case "signed-out":
            return observed + "\n" + i18nc("@info:tooltip", "Sign in to check credits again. Showing the last known balance.");
        default:
            return observed + "\n" + i18nc("@info:tooltip", "Credits could not be checked. Showing the last known balance.");
        }
    }

    visible: shown
    Layout.fillWidth: true
    Layout.leftMargin: shown ? Style.contentEdge(Kirigami.Units.largeSpacing) : 0
    Layout.rightMargin: Layout.leftMargin
    Layout.bottomMargin: shown ? Kirigami.Units.largeSpacing : 0
    spacing: Kirigami.Units.largeSpacing
    Accessible.role: Accessible.StaticText
    Accessible.name: i18nc("@info:accessible credit label, value and unit", "%1: %2 %3", label, value, unit)
    Accessible.description: detail
    Accessible.ignored: !shown
    QQC2.ToolTip.text: detail
    QQC2.ToolTip.visible: hovered.hovered && shown
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

    HoverHandler {
        id: hovered
    }

    Text {
        Layout.fillWidth: true
        text: row.label
        color: Style.dim(Kirigami.Theme.textColor)
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
        Accessible.ignored: true
    }

    Reading {
        value: row.value
        unit: row.unit
        color: row.cached ? Style.dim(Kirigami.Theme.textColor) : Kirigami.Theme.textColor
        accessibleIgnored: true
    }
}
