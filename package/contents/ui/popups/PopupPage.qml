import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import ".."

// The frame every popup shares: a fixed width, its sections stacked, and the
// footer with the way to System Monitor and to the settings.
ColumnLayout {
    id: page

    required property Monitor monitor
    default property alias sections: body.data

    implicitWidth: Kirigami.Units.gridUnit * 20
    spacing: 0

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        spacing: 0
    }

    PopupFooter {
        Layout.fillWidth: true
        monitor: page.monitor
    }
}
