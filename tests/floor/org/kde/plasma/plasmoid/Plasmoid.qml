// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma Singleton
import QtQuick

// What the popups reach through PlasmaExtras.PlasmoidHeading, whose
// background metrics read the applet's form factor: a horizontal panel's.
QtObject {
    property int formFactor: 2
}
