// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/style.js" as Style

// A percentage graph's top: a faint rule at 100 % with "100%" at one end,
// fills its graph and goes under the data. The label sits at the left end,
// where a graph's oldest data usually lies low, or at the right end with
// preferEnd, and moves to the other end when a line would run through it.
// The graph maps 100 % to limitY.
Item {
    id: rule

    // The graph's point lists ({ x, y }), which the label keeps clear of.
    property var series: []
    // For graphs whose right end is still to come, such as the week so far.
    property bool preferEnd: false

    readonly property real inkHeight: Math.ceil(ink.tightBoundingRect.height)
    // A full smallSpacing over the label, so it reads as part of the graph
    // and not as a second line of the tile's caption.
    readonly property real ruleY: Kirigami.Units.smallSpacing + Math.ceil(inkHeight / 2)
    readonly property real limitY: ruleY + 0.5
    readonly property real labelBottom: ruleY + Math.ceil(inkHeight / 2) + 1
    readonly property real span: label.implicitWidth + Kirigami.Units.smallSpacing
    readonly property bool atStart: preferEnd
        ? clearOf(0, span) && !clearOf(width - span, width)
        : clearOf(0, span) || !clearOf(width - span, width)

    // Whether every series stays below the label between x0 and x1, counting
    // segments that cross either end.
    function clearOf(x0, x1) {
        return series.every(list => list.every((p, i) => {
            if (p.x >= x0 && p.x <= x1 && p.y < labelBottom) {
                return false;
            }
            const q = i > 0 ? list[i - 1] : null;
            return !q || p.x <= q.x || [x0, x1].every(e => !(q.x < e && p.x > e)
                || q.y + (p.y - q.y) * (e - q.x) / (p.x - q.x) >= labelBottom);
        }));
    }

    Rectangle {
        x: rule.atStart ? rule.span : 0
        y: rule.ruleY
        width: Math.max(0, rule.width - rule.span)
        height: 1
        color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
    }

    Text {
        id: label
        x: rule.atStart ? 0 : rule.width - implicitWidth
        // Centres the digits' ink, not the line box, on the rule.
        y: Math.round(rule.limitY - (baselineOffset + ink.tightBoundingRect.y + ink.tightBoundingRect.height / 2))
        text: i18nc("@info a percentage", "%1%", Format.percent(100))
        color: Style.dim(Kirigami.Theme.textColor)
        font.family: Kirigami.Theme.defaultFont.family
        font.features: ({ "tnum": 1 })
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        textFormat: Text.PlainText
        Accessible.ignored: true
    }

    TextMetrics {
        id: ink
        font: label.font
        text: label.text
    }
}
