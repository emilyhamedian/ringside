// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format

// A process list's name column: the name in the fixed-width face, and how
// many run where several share it.
Text {
    // { name, count }, or null for an empty row.
    property var entry: null

    text: !entry ? " "
        : entry.count > 1 ? i18nc("@info a process and how many of it run, e.g. chrome ×12", "%1 ×%2",
                                  entry.name, Format.whole(entry.count))
        : entry.name
    color: Kirigami.Theme.textColor
    font.family: Kirigami.Theme.fixedWidthFont?.family ?? "monospace" // qmllint disable redundant-optional-chaining
    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.92
    elide: Text.ElideRight
    textFormat: Text.PlainText
    // Set, so the names move to the other edge in a mirrored layout.
    horizontalAlignment: Text.AlignLeft
    Accessible.ignored: true
}
