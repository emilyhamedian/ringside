// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "code/style.js" as Style

// A ring's readings, beside it in the panel: the ring's own reading, heavier
// and in the ring's colour, over a second one, dimmer: a temperature, memory
// in use or the time to a reset. On a thin panel they share a line,
// "23% · 61°". Each line keeps the room of the widest text it can show, so
// the panel never moves as readings change; the readings keep to the ring and
// what they leave free falls after them. A line with nothing to show keeps
// its room, and on one line its dot goes. Each reading is one text, so
// mirroring never parts a number from its sign. The cell describes the
// readings to screen readers, so the texts themselves stay out of the
// accessibility tree.
GridLayout {
    id: readout

    // Words.readout(): { first, level, off, second, heat }.
    required property var lines
    // Words.widest(): { first, second }, the texts each line keeps room for.
    required property var widest
    // The room each line takes.
    readonly property var rooms: [face.room(face.strong, widest.first), face.room(face.plain, widest.second)]
    property bool oneLine: false
    readonly property alias face: face
    readonly property real dotRoom: face.room(face.plain, ["·"])
    // The width the readings take, from the rooms rather than the layout,
    // which follows them a frame later.
    readonly property real textWidth: !oneLine ? Math.max(rooms[0], rooms[1]) : rooms[0] + dotRoom + rooms[1] + 2 * columnSpacing

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
        visible: readout.oneLine
        Layout.preferredWidth: readout.dotRoom
        Layout.preferredHeight: face.lineHeight
        horizontalAlignment: Text.AlignHCenter
        text: readout.lines.second !== "" ? "·" : ""
        color: Style.dim(Kirigami.Theme.textColor)
        font: face.plain.font
        textFormat: Text.PlainText
        Accessible.ignored: true
    }

    Text {
        objectName: "second"
        Layout.preferredWidth: readout.rooms[1]
        Layout.preferredHeight: face.lineHeight
        Layout.fillWidth: !readout.oneLine
        horizontalAlignment: Text.AlignLeft
        text: readout.lines.second
        color: readout.lines.heat === 2 ? Kirigami.Theme.negativeTextColor
             : readout.lines.heat === 1 ? Kirigami.Theme.neutralTextColor
             : Style.dim(Kirigami.Theme.textColor)
        font: face.plain.font
        textFormat: Text.PlainText
        Accessible.ignored: true
    }
}
