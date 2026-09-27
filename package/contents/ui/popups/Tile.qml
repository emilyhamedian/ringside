import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// A captioned reading on a faint rounded panel.
Rectangle {
    id: tile

    property string caption: ""
    default property alias content: body.data

    readonly property real horizontalPadding: Math.round(Kirigami.Units.largeSpacing * 1.5)
    readonly property real verticalPadding: Math.round(Kirigami.Units.largeSpacing * 1.25)

    Layout.fillWidth: true
    implicitWidth: column.implicitWidth + 2 * horizontalPadding
    implicitHeight: column.implicitHeight + 2 * verticalPadding
    radius: Kirigami.Units.cornerRadius
    color: Qt.alpha(Kirigami.Theme.textColor, 0.05)

    ColumnLayout {
        id: column

        anchors.fill: parent
        anchors.leftMargin: tile.horizontalPadding
        anchors.rightMargin: tile.horizontalPadding
        anchors.topMargin: tile.verticalPadding
        anchors.bottomMargin: tile.verticalPadding
        spacing: Math.round(Kirigami.Units.smallSpacing / 2)

        Caption {
            visible: text !== ""
            text: tile.caption
            Layout.fillWidth: true
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
        }
    }
}
