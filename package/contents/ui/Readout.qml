// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "code/style.js" as Style

// A ring's readings, beside it in the panel: the ring's own reading, heavier
// and in the ring's colour, over a second one, dimmer: a temperature, memory
// in use or the time to a reset. On a thin panel they share a line,
// "23% · 61°". Each line is as wide as its text, with every digit counted as
// the widest, so the gap after the readings is the same for every ring and a
// reading moves only when it gains or loses a character. A second line with
// nothing to show keeps its height; on one line it goes, with its dot. Each
// reading is one text, so mirroring never parts a number from its sign. A
// countdown sets its units small, "23h 5m", in one styled text so each
// number keeps its unit. The cell describes the readings to screen readers,
// so the texts themselves stay out of the accessibility tree.
GridLayout {
    id: readout

    // Words.readout(): { first, level, off, second, heat, parts }.
    required property var lines
    readonly property bool counted: (lines.parts ?? []).length > 0
    // The room each line takes. A countdown's is measured by a hidden twin
    // with every digit at its widest, as styled text has no FontMetrics.
    readonly property var rooms: [face.room(face.strong, [lines.first]),
                                  counted ? Math.ceil(widestCount.implicitWidth) : face.room(face.plain, [lines.second])]
    property bool oneLine: false
    readonly property alias face: face
    // How far a dim second line, longer than the first, may run past the
    // readings' width into the gap after them. A coloured one stays inside.
    readonly property real overhang: oneLine || lines.heat ? 0
        : Math.min(Kirigami.Units.smallSpacing, Math.round(Math.max(0, rooms[1] - rooms[0]) * 0.4))
    readonly property real dotRoom: face.room(face.plain, ["·"])
    // The width the readings take, less the overhang. It comes from the rooms
    // rather than the layout, which follows them a frame later: until then a
    // width from both would be one the readings never have, and a cell would
    // hold on to it.
    readonly property real textWidth: (!oneLine ? Math.max(rooms[0], rooms[1])
                                       : rooms[0] + (secondShown ? dotRoom + rooms[1] + 2 * columnSpacing : 0)) - overhang
    readonly property bool secondShown: !oneLine || lines.second !== ""

    // The countdown's parts as styled text: each number with its unit at the
    // smallest size, the pairs a thin space apart. Styled text turns a typed
    // thin space into a full one, so it goes in as a character reference.
    // Mirrored, a leading right-to-left mark sets the line's direction, so
    // the days come first from the right as in the popup, whatever script
    // the units are in.
    function styled(parts, widest) {
        const escaped = text => String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        return (LayoutMirroring.enabled ? "\u200f" : "")
            + parts.map(part => escaped(widest ? face.widestDigits(face.plain, part.value) : part.value)
                                + '<font size="1">' + escaped(part.unit) + '</font>').join("&#8201;");
    }

    columns: oneLine ? 3 : 1
    rowSpacing: 0
    columnSpacing: oneLine ? Math.round(Kirigami.Units.smallSpacing * 0.75) : 0

    ReadoutFont {
        id: face
    }

    Text {
        objectName: "first"
        Layout.preferredWidth: readout.rooms[0]
        Layout.preferredHeight: face.lineHeight
        Layout.fillWidth: !readout.oneLine
        horizontalAlignment: readout.oneLine ? Text.AlignRight : Text.AlignLeft
        text: readout.lines.first
        color: readout.lines.off ? Style.dim(Kirigami.Theme.textColor)
             : readout.lines.level === 2 ? Kirigami.Theme.negativeTextColor
             : readout.lines.level === 1 ? Kirigami.Theme.neutralTextColor
             : Kirigami.Theme.textColor
        font: face.strong.font
        textFormat: Text.PlainText
        Accessible.ignored: true
    }

    Text {
        visible: readout.oneLine && readout.secondShown
        Layout.preferredWidth: readout.dotRoom
        Layout.preferredHeight: face.lineHeight
        horizontalAlignment: Text.AlignHCenter
        text: "·"
        color: Style.dim(Kirigami.Theme.textColor)
        font: face.plain.font
        textFormat: Text.PlainText
        Accessible.ignored: true
    }

    Text {
        objectName: "second"
        visible: readout.secondShown
        Layout.preferredWidth: readout.rooms[1]
        Layout.preferredHeight: face.lineHeight
        Layout.fillWidth: !readout.oneLine
        horizontalAlignment: Text.AlignLeft
        text: readout.counted ? readout.styled(readout.lines.parts, false) : readout.lines.second
        color: readout.lines.heat === 2 ? Kirigami.Theme.negativeTextColor
             : readout.lines.heat === 1 ? Kirigami.Theme.neutralTextColor
             : Style.dim(Kirigami.Theme.textColor)
        font: face.plain.font
        textFormat: readout.counted ? Text.StyledText : Text.PlainText
        Accessible.ignored: true
    }

    Text {
        id: widestCount
        visible: false
        text: readout.counted ? readout.styled(readout.lines.parts, true) : ""
        font: face.plain.font
        textFormat: Text.StyledText
        Accessible.ignored: true
    }
}
