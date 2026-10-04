// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/items.js" as Items

// The Standalone layout without the applet around it: a single row or column
// of large dials that folds into a small tab. Standalone.qml feeds it the
// panel and the settings; the tests and the gallery feed it fakes.
Item {
    id: strip

    required property var monitor
    // The items to show, in order, each with something to show.
    property var items: []
    // The items switched on, including those with nothing to show now.
    property var enabledItems: []
    // The item whose popup is open, for its pressed look.
    property string openItem: ""
    signal activated(string item, Item cell)

    // 0 automatic, 1 expanded, 2 collapsed. The handle requests 1 or 2; only
    // the settings page sets automatic again.
    property int visibilityMode: 0
    property bool covered: false
    readonly property bool collapsed: visibilityMode === 2 || (visibilityMode === 0 && covered)
    signal visibilityModeRequested(int mode)

    property bool vertical: true
    property int location: PlasmaCore.Types.RightEdge

    readonly property real contentThickness: vertical ? width : height
    // Plasma sets the panel's thickness in one jump, so the panel grows before
    // opening and shrinks after closing, and the dials animate in between.
    // Opening waits for the grown thickness to arrive, so the dials never
    // spread inside a window that is still the folded tab.
    readonly property bool geometryReady: contentThickness >= expandedThickness - 0.5
    property bool waitingForPanel: false
    property real expansionProgress: collapsed || waitingForPanel ? 0 : 1
    readonly property bool compactLayout: collapsed && expansionProgress === 0
    readonly property bool transitioning: expansionProgress > 0 && expansionProgress < 1
    // Content thickness of the folded tab. The host sets it for a panel it
    // manages; elsewhere the strip keeps its size.
    property real compactThickness: contentThickness
    readonly property bool tabLanded: contentThickness <= compactThickness + 0.5
    // The handle keeps the tab footprint until the panel has grown for opening.
    readonly property bool tabLayout: compactLayout || waitingForPanel
    readonly property bool tabVisible: compactLayout && tabLanded

    function cellAt(index) {
        return dials.itemAt(index)?.dial ?? null; // qmllint disable missing-property
    }

    onCollapsedChanged: {
        waitingForPanel = !collapsed && !geometryReady;
        if (waitingForPanel) {
            panelWait.restart();
        } else {
            panelWait.stop();
        }
    }
    onGeometryReadyChanged: {
        if (geometryReady) {
            waitingForPanel = false;
            panelWait.stop();
        }
    }
    // A compositor that never delivers the size must not leave the dials shut.
    Timer {
        id: panelWait
        interval: Kirigami.Units.veryLongDuration
        onTriggered: strip.waitingForPanel = false
    }

    Behavior on expansionProgress {
        id: expansionMotion
        NumberAnimation {
            // The Behavior starts before bindings to the requested mode settle;
            // its own target value already identifies the direction.
            duration: Kirigami.Units.longDuration
            easing.type: expansionMotion.targetValue === 0 ? Easing.OutQuad : Easing.OutCubic
        }
    }
    readonly property bool closing: expansionMotion.targetValue === 0
    // Closing fades with the progress, so the dials are gone when the panel
    // snaps to the tab. Opening reaches full opacity at 56% progress, early in
    // the ease-out, so the dials are there while they finish moving.
    readonly property real contentOpacity: closing ? expansionProgress
                                                   : Math.min(1, 1.8 * expansionProgress)
    readonly property real contentScale: 0.72 + 0.28 * expansionProgress

    // Everything below is measured at the system font size, independently of
    // the panel's geometry: deriving it from the scaled dials would loop
    // between the panel's minimum thickness and the dials' scale.
    ReadoutFont {
        id: base
        pointSize: Kirigami.Theme.smallFont.pointSize
    }
    Words {
        id: words
        monitor: strip.monitor
    }
    // Each readout line's width, per item, for the widest text it can show:
    // the ring's own reading, then a temperature, memory in use or the time to
    // a reset; for the rates a marker column and a value column. room() reads
    // the line height, which ties this to the theme font once it has loaded,
    // as FontMetrics' methods alone would not.
    readonly property var partWidths: {
        const lines = item => {
            const widest = words.widestReadout(item);
            return [base.room(base.strong, widest[0]), base.room(base.plain, widest[1])];
        };
        const amount = base.room(base.plain, [Format.whole(1000) + "M"]);
        return {
            cpu: lines("cpu"),
            gpu: lines("gpu"),
            memory: lines("memory"),
            claude: lines("claude"),
            codex: lines("codex"),
            network: [Math.round(base.plain.height * 0.62) * 0.8 + 4, amount],
            disk: [base.room(base.plain, [i18nc("@label short for disk reads", "R"),
                                          i18nc("@label short for disk writes", "W")]) + 4, amount]
        };
    }
    // The widest dial among the items switched on, so neither readings nor an
    // item coming and going rescale the others. A ring's lines stack; a
    // rate's columns sit side by side.
    readonly property real baseDialWidth: Math.max(52, ...Array.from(items).concat(Array.from(enabledItems))
        .filter(item => partWidths[item] !== undefined)
        .map(item => Items.isRing(item) ? Math.max(...partWidths[item])
                                        : partWidths[item][0] + partWidths[item][1]))
    // Across a vertical panel, the widest dial keeps 8 px either side, the
    // padding a dial keeps along the strip; text drawn larger can come out a
    // little wider than its room scaled, and spills into it. Across a
    // horizontal one: the ring, the gap under it, both lines down to the
    // second one's baseline, and a pixel either side for the scaled fonts'
    // rounding. Whole pixels, and fixed while the panel folds, so it changes
    // thickness once each way.
    readonly property real minimumThickness: vertical ? Math.ceil(baseDialWidth) + 16
        : 60 + Math.ceil(base.lineHeight + base.plain.ascent - base.strong.ascent + base.capHeight) + 2
    // The content thickness with the panel fully open, so the folded tab
    // cannot rescale the dials while it is the only thing on screen.
    property real expandedThickness: contentThickness
    property bool editing: false
    readonly property real sizeFactor: Math.max(1, expandedThickness / minimumThickness)
    // Along the strip: a margin before the first dial, a gap between dials,
    // then a lane for the chevron at the far end. The lane is reserved even
    // while the chevron is faint, so revealing it never resizes the panel or
    // moves the dials. Each dial's cell reaches dialPadding into these, so
    // they are measured between faces.
    readonly property real endPadding: Math.round(10 * sizeFactor)
    readonly property real gap: Math.round(24 * sizeFactor)
    readonly property real dialPadding: Math.round(8 * sizeFactor)
    readonly property real handleExtent: 28 * sizeFactor
    readonly property real laneGap: gap
    readonly property real laneEnd: Math.round(4 * sizeFactor)
    readonly property real laneExtent: laneGap - dialPadding + handleExtent + laneEnd
    readonly property bool handleRevealed: editing || hover.hovered || handle.visualFocus || hideDelay.running
    property real handleProgress: handleRevealed ? 1 : 0
    // At rest the chevron stays faintly visible, so the lane reads as a
    // control rather than as extra padding. Hovering the dials brings it up
    // smoothly; the pointer on the control itself lights it at once.
    readonly property real restingHandleOpacity: 0.35
    readonly property real laneHandleOpacity: handle.hovered || handle.visualFocus ? 1
        : restingHandleOpacity + (1 - restingHandleOpacity) * handleProgress
    // Whether the screen edge lies at the end of the thickness axis.
    readonly property bool edgeAtEnd: vertical ? location !== PlasmaCore.Types.LeftEdge
                                               : location !== PlasmaCore.Types.TopEdge

    implicitWidth: compactLayout ? handle.implicitWidth
                                 : dialGrid.implicitWidth + (vertical ? 0 : endPadding - dialPadding + laneExtent)
    implicitHeight: compactLayout ? handle.implicitHeight
                                  : dialGrid.implicitHeight + (vertical ? endPadding - dialPadding + laneExtent : 0)

    Behavior on handleProgress {
        id: handleMotion
        enabled: !strip.editing
        NumberAnimation {
            duration: Kirigami.Units.longDuration
            easing.type: handleMotion.targetValue === 0 ? Easing.InCubic : Easing.OutCubic
        }
    }

    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered) {
                hideDelay.stop();
            } else {
                hideDelay.restart();
            }
        }
    }
    Timer { id: hideDelay; interval: 180 }

    // Where the folded tab's content will sit, in this strip's coordinates.
    readonly property real compactCenterX: vertical
        ? (edgeAtEnd ? width - compactThickness / 2 : compactThickness / 2) : width / 2
    readonly property real compactCenterY: vertical ? height / 2
        : (edgeAtEnd ? height - compactThickness / 2 : compactThickness / 2)

    GridLayout {
        id: dialGrid
        objectName: "dials"
        visible: strip.expansionProgress > 0
        opacity: strip.contentOpacity
        // The dials keep their open layout and slide toward the tab while
        // scaling uniformly, so circles stay circles. The slide is a
        // transform because Qt 6.6 and 6.7.0 re-measure a layout as soon as
        // it moves, and its new size, passed on to the strip's, loops back
        // into the position being set.
        x: strip.vertical ? 0 : strip.endPadding - strip.dialPadding
        y: strip.vertical ? strip.endPadding - strip.dialPadding : 0
        width: strip.vertical ? strip.width : implicitWidth
        height: strip.vertical ? implicitHeight : strip.height
        transform: [
            Scale {
                origin.x: dialGrid.width / 2
                origin.y: dialGrid.height / 2
                xScale: strip.contentScale
                yScale: strip.contentScale
            },
            // After the scale, so the slide itself is not scaled.
            Translate {
                x: (strip.compactCenterX - dialGrid.width / 2 - dialGrid.x) * (1 - strip.expansionProgress)
                y: (strip.compactCenterY - dialGrid.height / 2 - dialGrid.y) * (1 - strip.expansionProgress)
            }
        ]
        columns: strip.vertical ? 1 : -1
        rowSpacing: strip.gap - 2 * strip.dialPadding
        columnSpacing: rowSpacing

        Repeater {
            id: dials
            model: strip.items

            // The cell spans the strip's thickness, and reaches dialPadding
            // beyond the face along it. The tooltip wraps the cell, as in the
            // inline strip: inside it, it would take the first hover from the
            // cell and from the strip's chevron reveal.
            delegate: PlasmaCore.ToolTipArea {
                id: entry

                required property string modelData
                readonly property alias dial: dial

                Layout.fillWidth: strip.vertical
                Layout.fillHeight: !strip.vertical
                implicitWidth: dial.faceWidth + (strip.vertical ? 0 : 2 * strip.dialPadding)
                implicitHeight: dial.faceHeight + (strip.vertical ? 2 * strip.dialPadding : 0)
                // Not while the dials move, nor over the dial's own popup.
                active: !strip.collapsed && !strip.transitioning && !dial.open
                mainText: dial.title
                subText: dial.description
                textFormat: Text.PlainText
                location: strip.location
                onAboutToShow: dial.nowMs = Date.now()

                StandaloneDial {
                    id: dial
                    anchors.fill: parent
                    item: entry.modelData
                    monitor: strip.monitor
                    parts: strip.partWidths[entry.modelData]
                    sizeFactor: strip.sizeFactor
                    open: strip.openItem === entry.modelData
                    onActivated: {
                        if (!strip.collapsed) {
                            strip.activated(entry.modelData, dial);
                        }
                    }
                }
            }
        }

        EmptyRing {
            visible: strip.items.length === 0
            Layout.alignment: Qt.AlignCenter
            Layout.topMargin: strip.vertical ? strip.dialPadding : 0
            Layout.bottomMargin: Layout.topMargin
            Layout.leftMargin: strip.vertical ? 0 : strip.dialPadding
            Layout.rightMargin: Layout.leftMargin
            sizeFactor: strip.sizeFactor
            interactive: !strip.collapsed && !strip.transitioning
            location: strip.location
            helperError: strip.monitor.usage.helperError
            statuses: strip.monitor.usage.statuses
            enabledItems: strip.enabledItems
        }
    }

    // The control's footprint: the lane at the strip's end, or the whole tab.
    Item {
        id: handleSlot
        x: strip.tabLayout ? strip.compactCenterX - width / 2
                           : strip.vertical ? (strip.width - width) / 2 : strip.width - strip.laneEnd - width
        y: strip.tabLayout ? strip.compactCenterY - height / 2
                           : strip.vertical ? strip.height - strip.laneEnd - height : (strip.height - height) / 2
        width: strip.tabLayout ? (strip.vertical ? strip.compactThickness : handle.implicitWidth)
                               : strip.vertical ? handle.implicitWidth : strip.handleExtent
        height: strip.tabLayout ? (strip.vertical ? handle.implicitHeight : strip.compactThickness)
                                : strip.vertical ? strip.handleExtent : handle.implicitHeight

        DrawerHandle {
            id: handle
            objectName: "drawerHandle"
            expanded: !strip.collapsed
            compact: strip.tabLayout
            vertical: strip.vertical
            location: strip.location
            sizeFactor: strip.sizeFactor
            // The tab's arrow appears once the panel has shrunk around it,
            // never inside the still-wide window about to snap.
            property real tabOpacity: strip.tabVisible ? 1 : 0
            Behavior on tabOpacity {
                NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic }
            }
            opacity: strip.tabLayout ? tabOpacity : strip.laneHandleOpacity * strip.contentOpacity
            x: (handleSlot.width - width) / 2
            y: (handleSlot.height - height) / 2
            width: strip.tabLayout ? handleSlot.width : implicitWidth
            height: strip.tabLayout ? handleSlot.height : implicitHeight
            onClicked: strip.visibilityModeRequested(strip.collapsed ? 1 : 2)
        }
    }
}
