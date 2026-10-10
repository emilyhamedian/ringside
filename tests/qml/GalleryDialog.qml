// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg

// A popup on the theme's dialog background, sized to its implicit size as
// AppletPopup sizes its main item.
Item {
    id: dialog

    // The dialog SVG follows the system colour scheme, not the colours set
    // on the item, so a section that overrides them draws a flat background.
    property bool flat: false
    default property alias page: holder.data

    readonly property var margin: flat
        ? { left: Kirigami.Units.smallSpacing, top: Kirigami.Units.smallSpacing,
            right: Kirigami.Units.smallSpacing, bottom: Kirigami.Units.smallSpacing }
        : frame.fixedMargins

    implicitWidth: holder.childrenRect.width + margin.left + margin.right
    implicitHeight: holder.childrenRect.height + margin.top + margin.bottom

    KSvg.FrameSvgItem {
        id: frame
        anchors.fill: parent
        visible: !dialog.flat
        imagePath: "dialogs/background"
    }

    Rectangle {
        anchors.fill: parent
        visible: dialog.flat
        color: Kirigami.Theme.backgroundColor
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.2)
        radius: Kirigami.Units.smallSpacing
    }

    Item {
        id: holder
        x: dialog.margin.left
        y: dialog.margin.top
    }
}
