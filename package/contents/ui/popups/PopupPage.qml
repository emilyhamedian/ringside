import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The frame every popup shares: a fixed width, its sections stacked, and the
// footer with the way to System Monitor and to the settings.
ColumnLayout {
    id: page

    required property var monitor
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
        Layout.fillWidth: true
        monitor: page.monitor
    }
}
