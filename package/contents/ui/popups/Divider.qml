// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A faint rule between sections of a popup's body, inset to the content's
// edge. The footer brings its own. A whole number of the screen's pixels
// tall, one at 125 %: a logical pixel there would cover one row or two,
// depending on where the rule lands.
Rectangle {
    // The window's scale: with Wayland's fractional scaling the screen
    // reports 2 at 125 %. Qt 6.6 knows only the screen's.
    readonly property real ratio: Window.window?.devicePixelRatio ?? Screen.devicePixelRatio // qmllint disable missing-property

    Layout.fillWidth: true
    Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2)
    Layout.rightMargin: Layout.leftMargin
    Layout.preferredHeight: Math.max(1, Math.floor(ratio)) / ratio
    color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
}
