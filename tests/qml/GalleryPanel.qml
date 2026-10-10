// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"

// The strip centred on a stretch of panel under a caption, as main.qml
// places it. The outline marks the panel's thickness; Breeze's panel keeps
// 4 px of margin either side of an applet.
ColumnLayout {
    id: panel

    required property string label
    required property real thickness
    required property var monitor
    required property var items
    property var ringsOnly: []
    // Right to left, as main.qml lays the strip out in such a locale.
    property bool mirrored: false

    spacing: Kirigami.Units.smallSpacing

    GalleryNote {
        text: panel.label
    }

    Rectangle {
        color: "transparent"
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
        Layout.preferredWidth: strip.implicitWidth + 4 * Kirigami.Units.gridUnit
        Layout.preferredHeight: panel.thickness

        Strip {
            id: strip
            anchors.centerIn: parent
            height: panel.thickness - 8
            monitor: panel.monitor
            items: panel.items
            vertical: false
            thickness: panel.thickness - 8
            ringsOnly: panel.ringsOnly
            LayoutMirroring.enabled: panel.mirrored
            LayoutMirroring.childrenInherit: true
        }
    }
}
