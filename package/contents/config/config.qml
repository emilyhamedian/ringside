// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18nc("@title", "General")
        icon: "configure"
        source: "config/ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18nc("@title", "Panel Items")
        icon: "view-list-details"
        source: "config/ConfigItems.qml"
    }
    ConfigCategory {
        name: i18nc("@title", "Sensors")
        icon: "cpu"
        source: "config/ConfigSensors.qml"
    }
    ConfigCategory {
        name: i18nc("@title", "AI Providers")
        icon: "dialog-messages"
        source: "config/ConfigProviders.qml"
    }
}
