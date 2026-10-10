// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
// qmllint disable import
import QtQuick.LocalStorageNotInstalled

// A store whose module isn't installed, as HistoryStore.qml is where Qt's
// LocalStorage module is missing.
QtObject {
    property string widget
}
