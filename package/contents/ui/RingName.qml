// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import "code/items.js" as Items
import "code/style.js" as Style

// An item's name inside its ring: CPU, GPU or MEM, or the Claude or Codex
// mark. It sits in the clear middle, inside the inner ring when one is drawn,
// the name shrinking to fit. Where even its smallest readable size would not
// fit, or the caller turns it off, it is left out; the tooltip and the popup
// still name the item.
Item {
    id: name

    required property string item
    // RingGauge.centreWidth: the clear width inside the innermost ring.
    required property real room
    property real sizeFactor: 1
    property bool active: true

    readonly property bool usage: Items.isUsage(item)
    readonly property real minimumPointSize: Kirigami.Theme.smallFont.pointSize * 0.7 * sizeFactor
    // The middle is round, so a name's ink has less room than the middle's
    // width: only the chord at its cap height.
    readonly property real chord: 2 * Math.sqrt(Math.max(0, room * room / 4 - smallest.tightBoundingRect.height ** 2 / 4))
    // The Standalone dial's proportion: a 15 px mark in a 52 px ring.
    readonly property real markSize: Math.round(width * 15 / 52)
    readonly property bool fits: usage ? markSize >= Kirigami.Units.iconSizes.small / 2 && markSize <= room
                                       : smallest.advanceWidth <= chord

    anchors.fill: parent
    visible: active && fits
    // The cell's description names the item.
    Accessible.ignored: true

    TextMetrics {
        id: smallest
        font.pointSize: name.minimumPointSize
        font.letterSpacing: label.font.letterSpacing
        text: label.text
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        visible: name.usage
        width: name.markSize
        height: width
        source: name.item === "claude" ? Qt.resolvedUrl("../icons/claude.svg") : Qt.resolvedUrl("../icons/openai.svg")
        isMask: true
        color: Kirigami.Theme.textColor
    }

    Text {
        id: label
        anchors.centerIn: parent
        visible: !name.usage
        width: Math.floor(name.chord)
        horizontalAlignment: Text.AlignHCenter
        text: name.item === "cpu" ? i18nc("@label short for processor", "CPU")
            : name.item === "gpu" ? i18nc("@label short for graphics card", "GPU")
            : i18nc("@label short for memory", "MEM")
        color: Style.dim(Kirigami.Theme.textColor)
        font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.95 * name.sizeFactor
        font.letterSpacing: Kirigami.Theme.smallFont.pointSize * 0.08 * name.sizeFactor
        fontSizeMode: Text.HorizontalFit
        minimumPointSize: Math.floor(name.minimumPointSize)
        textFormat: Text.PlainText
    }
}
