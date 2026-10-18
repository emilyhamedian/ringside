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
    property GraphCursor cursor: null
    property bool inspectionEnabled: true
    property GraphCursor attachedCursor: null

    readonly property bool inspectable: inspectionEnabled && visible && enabled && width > 0
    readonly property int localIndex: inspectable && pointer.hovered ? nearest(pointer.point.position.x) : -1
    readonly property real markerX: !inspectable ? NaN
        : cursor ? cursor.owner !== null && Number.isFinite(cursor.position) ? cursor.position * width : NaN
        : localIndex >= 0 ? points[localIndex].x : NaN

    // The point shown, or -1.
    readonly property int index: !inspectable ? -1 : cursor ? matchingIndex() : localIndex
    readonly property var point: index >= 0 ? points[index] : null

    function matchingIndex() {
        if (!Number.isFinite(markerX)) {
            return -1;
        }
        const i = nearest(markerX);
        // A shorter history must not substitute its first reading for an
        // older slot, nor a neighbouring reading for a gap.
        return i >= 0 && Math.abs(points[i].x - markerX) < 0.000001 && Number.isFinite(points[i].y) ? i : -1;
    }

    function publish() {
        if (inspectable && pointer.hovered && cursor) {
            const i = nearest(pointer.point.position.x);
            cursor.publish(hover, i >= 0 ? Math.max(0, Math.min(1, points[i].x / width)) : NaN);
        }
    }

    function release() {
        if (cursor) {
            cursor.release(hover);
        }
    }

    function updateOwner() {
        if (!inspectable) {
            release();
        } else if (cursor && cursor.owner === hover) {
            publish();
        }
    }

    onCursorChanged: {
        if (attachedCursor) {
            attachedCursor.release(hover);
        }
        attachedCursor = cursor;
    }
    onInspectableChanged: updateOwner()
    onLocalIndexChanged: updateOwner()
    onPointsChanged: updateOwner()
    onWidthChanged: updateOwner()
    Component.onDestruction: release()

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
        enabled: hover.inspectable
        onHoveredChanged: {
            if (hovered) {
                hover.publish();
            } else {
                hover.release();
            }
        }
        onPointChanged: if (hovered) hover.publish()
    }

    Rectangle {
        visible: Number.isFinite(hover.markerX)
        x: visible ? Math.max(0, Math.min(hover.width - width, Math.round(hover.markerX))) : 0
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
