// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami

// One item in the panel: a button that opens its popup, with the panel's
// hover and pressed looks. Across a horizontal panel the wash leaves a sliver
// of panel above and below, as Plasma's own panel buttons do; along a
// vertical one, and in a Standalone dial, it spans the cell.
MouseArea {
    id: cell

    required property string item
    property bool open: false
    property bool vertical: false
    // The loaded content, which the cell sizes itself around.
    property Item contentItem: null
    // Its readings in words.
    property string description: ""
    // Between the wash and the panel's edges, across a horizontal panel.
    readonly property real inset: vertical ? 0 : Math.round(Kirigami.Units.smallSpacing / 2)
    readonly property string title: item === "cpu" ? i18nc("@info:tooltip", "Processor")
                                  : item === "gpu" ? i18nc("@info:tooltip", "Graphics")
                                  : item === "memory" ? i18nc("@info:tooltip", "Memory")
                                  : item === "network" ? i18nc("@info:tooltip", "Network")
                                  : item === "disk" ? i18nc("@info:tooltip", "Disk activity")
                                  : item === "claude" ? i18nc("@info:tooltip the Claude Code weekly limits", "Claude")
                                  : i18nc("@info:tooltip the Codex weekly limits", "Codex")

    signal activated()

    implicitWidth: (contentItem ? contentItem.implicitWidth : 0) + 2 * Kirigami.Units.smallSpacing
    implicitHeight: (contentItem ? contentItem.implicitHeight : 0) + 2 * (vertical ? Kirigami.Units.smallSpacing : inset)
    hoverEnabled: true
    activeFocusOnTab: true
    // Rates squeezed onto a narrow vertical panel stop at its edge.
    clip: vertical

    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: description
    Accessible.onPressAction: activated()

    onClicked: activated()
    Keys.onPressed: event => {
        if ([Qt.Key_Space, Qt.Key_Enter, Qt.Key_Return, Qt.Key_Select].includes(event.key)) {
            activated();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: cell.inset
        anchors.bottomMargin: anchors.topMargin
        radius: Kirigami.Units.smallSpacing
        color: Qt.alpha(Kirigami.Theme.textColor, cell.open ? 0.14 : 0.1)
        visible: cell.open || cell.containsMouse || cell.activeFocus
    }
}
