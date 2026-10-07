// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

// One setting's choices, as { text, value } rows. A stored value that isn't
// among them (the sensor tree still loading, a sensor or limit that has gone)
// stays listed under its raw value instead of being reset, and so does the
// value the page opened with.
QQC2.ComboBox {
    id: picker

    required property var choices
    required property string current
    signal picked(string value)

    property string opened
    readonly property var entries: {
        const list = choices.slice();
        for (const value of [opened, current]) {
            if (!list.some(e => e.value === value)) {
                list.push({ text: value, value: value });
            }
        }
        return list;
    }

    Layout.fillWidth: true
    textRole: "text"
    valueRole: "value"
    model: entries
    currentIndex: entries.findIndex(e => e.value === current)
    onActivated: index => picked(entries[index].value)
    Component.onCompleted: opened = current
}
