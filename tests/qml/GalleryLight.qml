// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A gallery section in Breeze Light's colours, for the contrast of dim text
// and level colours on a light scheme.
Rectangle {
    default property alias sections: light.data

    Layout.fillWidth: true
    implicitWidth: light.implicitWidth + 2 * light.x
    implicitHeight: light.implicitHeight + 2 * light.y
    color: Kirigami.Theme.backgroundColor

    Kirigami.Theme.inherit: false
    Kirigami.Theme.textColor: "#232629"
    Kirigami.Theme.disabledTextColor: "#707d8a"
    Kirigami.Theme.backgroundColor: "#eff0f1"
    Kirigami.Theme.alternateBackgroundColor: "#e3e5e7"
    Kirigami.Theme.highlightColor: "#3daee9"
    Kirigami.Theme.highlightedTextColor: "#ffffff"
    Kirigami.Theme.linkColor: "#2980b9"
    Kirigami.Theme.visitedLinkColor: "#9b59b6"
    Kirigami.Theme.negativeTextColor: "#da4453"
    Kirigami.Theme.neutralTextColor: "#f67400"
    Kirigami.Theme.positiveTextColor: "#27ae60"

    ColumnLayout {
        id: light

        x: 2 * Kirigami.Units.gridUnit
        y: x
        spacing: 2 * Kirigami.Units.gridUnit
    }
}
