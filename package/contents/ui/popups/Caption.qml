// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import "../code/style.js" as Style

// The small, dim title over a reading: an upper-case label and an optional
// detail that keeps its case, as in "USAGE · 60 s" or "SWAP (zram)".
Text {
    property string label: ""
    property string detail: ""

    text: [label.toLocaleUpperCase(), detail].filter(s => s !== "").join(" ")
    color: Style.dim(Kirigami.Theme.textColor)
    font.pointSize: Kirigami.Theme.smallFont.pointSize
    textFormat: Text.PlainText
    // Set rather than implied, so it follows layout mirroring; an implied
    // alignment follows the text's own direction instead.
    horizontalAlignment: Text.AlignLeft
    elide: Text.ElideRight
}
