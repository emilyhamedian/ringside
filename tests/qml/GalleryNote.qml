// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import "../../package/contents/ui/code/style.js" as Style

// A gallery's caption for what a shot shows.
Text {
    color: Style.dim(Kirigami.Theme.textColor)
    font.pointSize: Kirigami.Theme.smallFont.pointSize
    textFormat: Text.PlainText
}
