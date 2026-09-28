// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

// The Standalone strip's fold and unfold button. Its chevron points the way
// the strip will move.
QQC2.AbstractButton {
    id: handle

    property real sizeFactor: 1
    property bool expanded: false
    // Lying across the strip's end lane, or filling the folded tab.
    property bool compact: false
    property bool vertical: true
    property int location: PlasmaCore.Types.RightEdge
    readonly property real stroke: 3.5 * sizeFactor
    readonly property real glyphWidth: 8 * sizeFactor
    readonly property real glyphHeight: 14 * sizeFactor
    readonly property bool wide: vertical !== compact
    // 1 shows the fold chevron, 0 the unfold chevron. Bound to expanded, not
    // the panel's size, so the chevron switches on click and switches back if
    // clicked again mid-animation.
    property real flip: expanded ? 1 : 0
    // Drawn as "<" for the right edge, turned to face away from whichever
    // edge the panel sits on; folding points the other way, at the edge.
    readonly property real edgeRotation: location === PlasmaCore.Types.LeftEdge ? 180
                                       : location === PlasmaCore.Types.TopEdge ? 270
                                       : location === PlasmaCore.Types.BottomEdge ? 90 : 0

    implicitWidth: (wide ? 52 : 28) * sizeFactor
    implicitHeight: (wide ? 28 : 52) * sizeFactor
    text: expanded ? i18nc("@action:button", "Fold Ringside") : i18nc("@action:button", "Unfold Ringside")
    Accessible.name: text
    Accessible.role: Accessible.Button
    Accessible.onPressAction: handle.clicked()
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    padding: 0

    Behavior on flip {
        NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.InOutQuad }
    }

    background: Rectangle {
        radius: 6 * handle.sizeFactor
        color: handle.down ? Qt.alpha(Kirigami.Theme.textColor, 0.16)
                           : handle.hovered ? Qt.alpha(Kirigami.Theme.textColor, 0.08)
                                            : "transparent"
        border.width: handle.visualFocus ? 2 : 0
        border.color: Kirigami.Theme.focusColor
    }

    component Chevron: Shape {
        id: glyph
        anchors.centerIn: parent
        width: handle.glyphWidth + handle.stroke
        height: handle.glyphHeight + handle.stroke
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Kirigami.Theme.textColor
            strokeWidth: handle.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: glyph.width - handle.stroke / 2
            startY: handle.stroke / 2
            PathLine { x: handle.stroke / 2; y: glyph.height / 2 }
            PathLine { x: glyph.width - handle.stroke / 2; y: glyph.height - handle.stroke / 2 }
        }
    }

    contentItem: Item {
        opacity: handle.hovered || handle.visualFocus ? 1 : 0.7

        Chevron {
            objectName: "expandGlyph"
            rotation: handle.edgeRotation
            opacity: 1 - handle.flip
        }
        Chevron {
            objectName: "collapseGlyph"
            rotation: handle.edgeRotation + 180
            opacity: handle.flip
        }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
