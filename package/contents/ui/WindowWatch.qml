// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.taskmanager as TaskManager

// Whether a window on this applet's screen, desktop and activity is
// maximized or fullscreen, which is when the Standalone strip would sit on
// top of it. Every property used here exists in Plasma 6.0.
Item {
    id: watch

    property bool active: true
    readonly property bool covered: active && windows.covered

    visible: false

    TaskManager.VirtualDesktopInfo {
        id: virtualDesktopInfo
    }

    TaskManager.ActivityInfo {
        id: activityInfo
    }

    TaskManager.TasksModel {
        id: windows

        property bool covered: false

        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByScreen: true
        screenGeometry: Plasmoid.containment.screenGeometry
        filterByVirtualDesktop: true
        virtualDesktop: virtualDesktopInfo.currentDesktop
        filterByActivity: true
        activity: activityInfo.currentActivity
        filterMinimized: true
        filterHidden: true

        // A maximize or fullscreen toggle changes a role without changing the
        // row count, so data changes matter as much as rows coming and going.
        onCountChanged: Qt.callLater(windows.update)
        onDataChanged: Qt.callLater(windows.update)
        onModelReset: Qt.callLater(windows.update)

        function update() {
            for (let row = 0; row < windows.count; ++row) {
                const window = windows.index(row, 0);
                if (windows.data(window, TaskManager.AbstractTasksModel.IsMaximized)
                        || windows.data(window, TaskManager.AbstractTasksModel.IsFullScreen)) {
                    windows.covered = true;
                    return;
                }
            }
            windows.covered = false;
        }
    }
}
