// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import org.kde.kirigami as Kirigami

// The point of a graph under the pointer: a line down the graph through it and a
// dot on each series there. The tile around the graph writes that point's
// reading in its caption line (Tile.graphReading), which is also what a
// screen reader hears.
Item {
    id: hover

    // A point per sample, as History.points() gives them, NaN y where there
    // is no reading; and the second series', when there is one.
    property var points: []
    property var secondPoints: []
    property color color: Kirigami.Theme.textColor
    // The selected reading, also exposed to assistive technology.
    property string reading: ""

    // The point shown, or -1.
    readonly property int index: pointer.hovered ? nearest(pointer.point.position.x) : -1
    readonly property var point: index >= 0 ? points[index] : null

    function nearest(x) {
        let best = -1;
        let distance = Infinity;
        for (let i = 0; i < points.length; ++i) {
            const d = Math.abs(points[i].x - x);
            if (d < distance) {
                distance = d;
                best = i;
            }
        }
        return best;
    }

    // Time runs left to right in every language.
    LayoutMirroring.enabled: false

    Accessible.role: Accessible.StaticText
    Accessible.name: reading

    HoverHandler {
        id: pointer
    }

    Rectangle {
        visible: hover.point !== null
        x: hover.point ? Math.round(hover.point.x) : 0
        width: 1
        height: parent.height
        color: Qt.alpha(hover.color, 0.45 * hover.color.a)
    }

    Dot {
        at: hover.point
    }

    Dot {
        at: hover.index >= 0 && hover.index < hover.secondPoints.length ? hover.secondPoints[hover.index] : null
    }

    component Dot: Rectangle {
        required property var at

        visible: at !== null && Number.isFinite(at.y)
        x: at ? at.x - width / 2 : 0
        y: at && Number.isFinite(at.y) ? at.y - height / 2 : 0
        width: Math.round(Kirigami.Units.smallSpacing * 1.5)
        height: width
        radius: width / 2
        color: hover.color
    }
}
