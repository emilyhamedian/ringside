// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format

// A captioned reading on a faint rounded panel.
Rectangle {
    id: tile

    property string caption: ""
    property string detail: ""
    // The time the tile's graph spans, shown after the caption in place of
    // the detail: "USAGE · 60 s", "USAGE · 2 min".
    property int graphSeconds: 0
    default property alias content: body.data

    readonly property real horizontalPadding: Math.round(Kirigami.Units.largeSpacing * 1.5)
    readonly property real verticalPadding: Math.round(Kirigami.Units.largeSpacing * 1.25)

    Layout.fillWidth: true
    implicitWidth: column.implicitWidth + 2 * horizontalPadding
    implicitHeight: column.implicitHeight + 2 * verticalPadding
    radius: Kirigami.Units.smallSpacing
    color: Qt.alpha(Kirigami.Theme.textColor, 0.05)

    ColumnLayout {
        id: column

        // Anchored at the top rather than filling the tile, whose height comes
        // from this layout's: Qt 6.6 rearranges a layout as soon as its height
        // changes, and when the content depends on the tile's width (the CPU
        // popup's bar rows) that re-enters the tile's implicitHeight binding.
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: tile.horizontalPadding
        anchors.rightMargin: tile.horizontalPadding
        anchors.topMargin: tile.verticalPadding
        spacing: Math.round(Kirigami.Units.smallSpacing / 2)

        Caption {
            visible: text !== ""
            label: tile.caption
            detail: {
                if (tile.graphSeconds <= 0) {
                    return tile.detail;
                }
                const minutes = Format.spanMinutes(tile.graphSeconds);
                return "· " + (minutes > 0
                    ? i18nc("@title:group time a graph spans, as in USAGE · 2 min", "%1 min", minutes)
                    : i18nc("@title:group time a graph spans, as in USAGE · 60 s", "%1 s", tile.graphSeconds));
            }
            Layout.fillWidth: true
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
        }
    }
}
