// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami

// A percentage graph's top: a faint rule at 100 % across the whole graph,
// under the data. Its label, "100%", is on the tile's caption line over the
// rule's end (Tile.graphTop), where no line can run through it. The graph
// maps 100 % to limitY.
Item {
    id: rule

    // The rule's colour, which the week graph's frame shares.
    readonly property color lineColor: Qt.alpha(Kirigami.Theme.textColor, 0.12)
    // Room over the rule for a line at 100 %, whose stroke and round joins
    // would otherwise be cut off at the graph's top.
    readonly property real ruleY: 3
    readonly property real limitY: ruleY + 0.5

    Rectangle {
        y: rule.ruleY
        width: rule.width
        height: 1
        color: rule.lineColor
    }
}
