// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The frame every popup shares: a fixed width, its sections stacked, and the
// footer with the way to System Monitor, where it has something to show, or
// the popup's own control in its place, and to the settings.
ColumnLayout {
    id: page

    required property var monitor
    // The height the page has on screen: the screen's, less its panels and
    // the popup's frame. A page that can grow keeps within it.
    property real room: Infinity
    property alias systemMonitorShown: footer.systemMonitorShown
    property alias footerLeading: footer.leading
    property alias footerLeadingShown: footer.leadingShown
    // The moment marked across the popup's graphs. A popup with several
    // devices gives each its own, so a device's graphs follow only each other.
    readonly property GraphCursor graphCursor: GraphCursor {
        scope: page
        monitor: page.monitor
    }
    default property alias sections: body.data

    spacing: 0

    ColumnLayout {
        id: body
        // The page's width goes here: a ColumnLayout overwrites its own implicitWidth.
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.fillWidth: true
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        spacing: 0
    }

    PopupFooter {
        id: footer
        Layout.fillWidth: true
        monitor: page.monitor
    }
}
