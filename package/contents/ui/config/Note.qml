// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../code/style.js" as Style

// A dimmed line of help under the settings it explains.
QQC2.Label {
    Layout.fillWidth: true
    Layout.maximumWidth: Kirigami.Units.gridUnit * 22
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    font: Kirigami.Theme.smallFont
    color: Style.dim(Kirigami.Theme.textColor)
}
