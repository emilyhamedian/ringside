// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A faint rule between sections of a popup's body, inset to the content's
// edge. The footer brings its own.
Rectangle {
    Layout.fillWidth: true
    Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
    Layout.rightMargin: Layout.leftMargin
    Layout.preferredHeight: 1
    color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
}
