// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami

// One item in the panel: a button that opens its popup, with the panel's
// hover and pressed looks. Across a horizontal panel the wash leaves a sliver
// of panel above and below, as Plasma's own panel buttons do; along a
// vertical one it spans the cell.
MouseArea {
    id: cell

    required property string item
    property bool open: false
    property bool vertical: false
    // The loaded content, which the cell sizes itself around.
    property Item contentItem: null
    // Its readings in words.
    property string description: ""
    // Whatever shapes the content other than its readings: whether the text
    // shows, the panel's thickness, the font, the units, the GPUs chosen, a
    // signed-out account. When it changes the cell takes its new width at
    // once.
    property string layoutKey: ""
    // Between the wash and the panel's edges, across a horizontal panel.
    readonly property real inset: vertical ? 0 : Math.round(Kirigami.Units.smallSpacing / 2)
    // Between the content and the cell's ends. Along a horizontal panel two
    // cells' padding makes the gap between items, twice the gap between a
    // ring and its readings, so readings read as the ring's beside them and
    // not the next one's.
    readonly property real padding: vertical ? Kirigami.Units.smallSpacing : Kirigami.Units.largeSpacing
    readonly property string title: item === "cpu" ? i18nc("@info:tooltip", "Processor")
                                  : item === "gpu" ? i18nc("@info:tooltip", "Graphics")
                                  : item === "memory" ? i18nc("@info:tooltip", "Memory")
                                  : item === "network" ? i18nc("@info:tooltip", "Network")
                                  : item === "disk" ? i18nc("@info:tooltip", "Disk activity")
                                  : item === "claude" ? i18nc("@info:tooltip the Claude Code weekly limits", "Claude")
                                  : i18nc("@info:tooltip the Codex weekly limits", "Codex")

    signal activated()

    // Along a horizontal panel the cell is as wide as its content: it grows
    // at once, but when the content narrows it keeps the room it had until
    // the content has stayed narrower for settleDelay, and then takes its
    // width at that moment, so a reading that keeps crossing between widths,
    // 9 % and 10 %, moves the items after it once rather than on every
    // update. Meanwhile, every trimDelay, it gives up all but a digit more
    // than the widest content it had in that time. A burst of traffic that
    // dies down then leaves a digit of extra room at most within two
    // trimDelays, while a rate that keeps going quiet and coming back within
    // one moves nothing. Being timed, the trim also skips the in-between
    // widths an update passes through as its readings change one at a time.
    // Until the cell settles a ring's extra room sits after its readings,
    // and rates keep theirs before their arrows or letters, so their
    // readings still end one padding before the next item. Whole pixels, so
    // a fraction of one doesn't count as a change.
    readonly property real contentWidth: contentItem ? Math.ceil(contentItem.implicitWidth) : 0
    property real settledWidth: 0
    // The widest digit in the readings' heavier weight, which covers the
    // lighter one.
    readonly property real digitWidth: face.room(face.strong, ["0"])
    property int settleDelay: 3 * 60 * 1000
    property int trimDelay: 10 * 1000
    // The widest content since the trim last ran.
    property real recentWidth: 0
    // A change of layout reaches the content's width a frame or two later,
    // once the layouts in it are polished; for this long after one, and
    // after the cell is made, a narrower content applies at once.
    property int relayoutWindow: 500

    implicitWidth: (vertical ? (contentItem ? contentItem.implicitWidth : 0) : Math.max(contentWidth, settledWidth)) + 2 * padding
    implicitHeight: (contentItem ? contentItem.implicitHeight : 0) + 2 * (vertical ? Kirigami.Units.smallSpacing : inset)
    hoverEnabled: true
    activeFocusOnTab: true
    // Rates squeezed onto a narrow vertical panel stop at its edge.
    clip: vertical

    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: description
    Accessible.onPressAction: activated()

    Component.onCompleted: relayout.start()
    onContentWidthChanged: {
        if (contentWidth >= settledWidth || relayout.running) {
            settledWidth = contentWidth;
            settle.stop();
            trim.stop();
        } else {
            recentWidth = trim.running ? Math.max(recentWidth, contentWidth) : contentWidth;
            trim.start();
            if (!settle.running) {
                settle.start();
            }
        }
    }
    onLayoutKeyChanged: {
        settledWidth = contentWidth;
        settle.stop();
        trim.stop();
        relayout.restart();
    }
    onClicked: activated()
    Keys.onPressed: event => {
        if ([Qt.Key_Space, Qt.Key_Enter, Qt.Key_Return, Qt.Key_Select].includes(event.key)) {
            activated();
            event.accepted = true;
        }
    }

    ReadoutFont {
        id: face
    }

    Timer {
        id: settle
        interval: cell.settleDelay
        onTriggered: {
            cell.settledWidth = cell.contentWidth;
            trim.stop();
        }
    }

    Timer {
        id: trim
        interval: cell.trimDelay
        repeat: true
        onTriggered: {
            cell.settledWidth = Math.min(cell.settledWidth, cell.recentWidth + cell.digitWidth);
            cell.recentWidth = cell.contentWidth;
        }
    }

    Timer {
        id: relayout
        interval: cell.relayoutWindow
    }

    // Keyboard focus also draws a line round the wash in the theme's focus
    // colour, so the focused item stands apart from one under a resting
    // pointer.
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: cell.inset
        anchors.bottomMargin: anchors.topMargin
        radius: Kirigami.Units.smallSpacing
        color: Qt.alpha(Kirigami.Theme.textColor, cell.open ? 0.14 : 0.1)
        border.width: cell.activeFocus ? 1 : 0
        border.color: Kirigami.Theme.focusColor
        visible: cell.open || cell.containsMouse || cell.activeFocus
    }
}
