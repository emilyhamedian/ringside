// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A popup in its dialog under a caption.
ColumnLayout {
    id: frame

    required property string label
    property alias flat: dialog.flat
    default property alias page: dialog.page

    Layout.alignment: Qt.AlignTop
    spacing: Kirigami.Units.smallSpacing

    GalleryNote {
        text: frame.label
    }

    GalleryDialog {
        id: dialog
    }
}
