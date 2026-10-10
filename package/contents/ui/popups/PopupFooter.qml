// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras

PlasmaExtras.PlasmoidHeading {
    id: footer

    required property var monitor
    // Claude and Codex have nothing to show in System Monitor.
    property bool systemMonitorShown: true
    // A popup's own control, such as the usage popups' starter switch.
    property alias leading: lead.data

    position: T.ToolBar.Footer

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.LinkButton {
            visible: footer.systemMonitorShown
            // On the readings' edge, as the lead is.
            Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2) - footer.leftPadding
            text: i18nc("@action:button", "Open System Monitor")
            font.underline: false
            onClicked: footer.monitor.systemMonitorRequested()
        }

        // Takes the room the System Monitor link leaves.
        ColumnLayout {
            id: lead
            visible: children.length > 0
            Layout.fillWidth: true
            // On the readings' edge.
            Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 2) - footer.leftPadding
            // Clear of the configure button, so a long status doesn't run into it.
            Layout.rightMargin: Kirigami.Units.largeSpacing
            spacing: 0
        }

        Item {
            visible: !lead.visible
            Layout.fillWidth: true
        }

        PlasmaComponents.ToolButton {
            id: configure
            // Level with the lead's content. The lead's own room above and
            // below it is the button's too, or the button would be centred on
            // that room instead.
            readonly property Item leadItem: lead.visible ? lead.children[0] : null
            Layout.alignment: Qt.AlignVCenter
            Layout.topMargin: leadItem?.Layout.topMargin ?? 0
            Layout.bottomMargin: leadItem?.Layout.bottomMargin ?? 0
            // The icon's drawing on the readings' far edge, in every popup
            // alike. Breeze's 22 px icons keep 3 px free around the drawing,
            // so the icon sits that much past the edge.
            Layout.rightMargin: Math.round(Kirigami.Units.largeSpacing * 2) - footer.rightPadding - configure.rightPadding
                                - Kirigami.Units.iconSizes.smallMedium * 3 / 22
            icon.name: "configure"
            display: T.AbstractButton.IconOnly
            text: i18nc("@action:button", "Configure Ringside…")
            onClicked: footer.monitor.configureRequested()

            PlasmaComponents.ToolTip.text: text
            PlasmaComponents.ToolTip.visible: hovered
            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
    }
}
