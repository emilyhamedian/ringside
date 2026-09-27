import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras

PlasmaExtras.PlasmoidHeading {
    id: footer

    required property var monitor

    position: T.ToolBar.Footer

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.LinkButton {
            Layout.leftMargin: Kirigami.Units.largeSpacing
            text: i18nc("@action:button", "Open System Monitor")
            font.underline: false
            onClicked: footer.monitor.systemMonitorRequested()
        }

        Item {
            Layout.fillWidth: true
        }

        PlasmaComponents.ToolButton {
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
