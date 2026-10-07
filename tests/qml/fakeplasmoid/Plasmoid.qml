// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma Singleton
import QtQuick
import org.kde.plasma.core as PlasmaCore

// The applet main.qml reads through Plasmoid, with the panel set by the test.
QtObject {
    property int formFactor: PlasmaCore.Types.Horizontal
    property int location: PlasmaCore.Types.BottomEdge
    property var configuration: ({ ringsOnly: [] })
    property int containmentDisplayHints: 0
    property int status: PlasmaCore.Types.PassiveStatus
    property bool userConfiguring: false
    property string icon: "utilities-system-monitor"
    // KPluginMetaData, as far as main.qml reads it.
    property var metaData: ({ version: "0.3.0" })
    // How often the configure action was triggered.
    property int configured: 0

    signal activated()
    signal contextualActionsAboutToShow()

    function internalAction(name) {
        return { trigger: () => ++configured };
    }
}
