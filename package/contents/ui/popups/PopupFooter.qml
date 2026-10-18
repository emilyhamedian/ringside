// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import "../code/style.js" as Style

PlasmaExtras.PlasmoidHeading {
    id: footer

    required property var monitor
    // Claude and Codex have nothing to show in System Monitor.
    property bool systemMonitorShown: true
    // A popup's own control, such as the usage popups' starter switch.
    property alias leading: lead.data
    // The readings' edge, from inside the footer's padding.
    readonly property real readingsEdge: Style.contentEdge(Kirigami.Units.largeSpacing) - leftPadding

    position: T.ToolBar.Footer

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.LinkButton {
            id: systemMonitor
            visible: footer.systemMonitorShown
            // On the readings' edge, as the lead is.
            Layout.leftMargin: footer.readingsEdge
            text: i18nc("@action:button", "System Monitor")
            Accessible.name: i18nc("@action:button", "Open System Monitor")
            normalColor: Style.dim(Kirigami.Theme.textColor)
            font.underline: mouseArea.containsMouse || activeFocus
            leftPadding: LayoutMirroring.enabled ? 0 : activity.width + Kirigami.Units.smallSpacing * 2
            rightPadding: LayoutMirroring.enabled ? activity.width + Kirigami.Units.smallSpacing * 2 : 0
            topPadding: Math.max(0, (activity.height - contentHeight) / 2)
            bottomPadding: topPadding
            onClicked: footer.monitor.systemMonitorRequested()

            KSvg.SvgItem {
                id: activity
                imagePath: Qt.resolvedUrl("../../icons/activity.svg")
                Kirigami.Theme.inherit: false
                Kirigami.Theme.textColor: Qt.rgba(systemMonitor.color.r, systemMonitor.color.g, systemMonitor.color.b, 1)
                opacity: systemMonitor.color.a
                width: Kirigami.Units.iconSizes.small
                height: width
                x: systemMonitor.LayoutMirroring.enabled ? systemMonitor.width - width : 0
                anchors.verticalCenter: parent.verticalCenter
                Accessible.ignored: true
            }
        }

        // Takes the room the System Monitor link leaves.
        ColumnLayout {
            id: lead
            visible: children.length > 0
            Layout.fillWidth: true
            // On the readings' edge.
            Layout.leftMargin: footer.readingsEdge
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
            Layout.rightMargin: Style.contentEdge(Kirigami.Units.largeSpacing) - footer.rightPadding - configure.rightPadding
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
