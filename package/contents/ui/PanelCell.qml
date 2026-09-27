import QtQuick
import org.kde.kirigami as Kirigami

// One item in the panel: a button that opens its popup, with the panel's
// hover and pressed looks.
MouseArea {
    id: cell

    required property string item
    property bool open: false
    property bool vertical: false
    // The loaded content, which the cell sizes itself around.
    property Item contentItem: null
    // Its readings in words.
    property string description: ""
    readonly property string title: item === "cpu" ? i18nc("@info:tooltip", "Processor")
                                  : item === "gpu" ? i18nc("@info:tooltip", "Graphics")
                                  : item === "memory" ? i18nc("@info:tooltip", "Memory")
                                  : item === "network" ? i18nc("@info:tooltip", "Network")
                                  : i18nc("@info:tooltip", "Disk activity")

    signal activated()

    implicitWidth: (contentItem ? contentItem.implicitWidth : 0) + 2 * (vertical ? Kirigami.Units.smallSpacing
                                                                                 : Math.round(Kirigami.Units.largeSpacing * 1.5))
    implicitHeight: (contentItem ? contentItem.implicitHeight : 0) + 2 * Kirigami.Units.smallSpacing
    hoverEnabled: true
    activeFocusOnTab: true
    // Rates squeezed onto a narrow vertical panel stop at its edge.
    clip: vertical

    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: description
    Accessible.onPressAction: activated()

    onClicked: activated()
    Keys.onPressed: event => {
        if ([Qt.Key_Space, Qt.Key_Enter, Qt.Key_Return, Qt.Key_Select].includes(event.key)) {
            activated();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: cell.vertical ? 0 : Kirigami.Units.smallSpacing
        anchors.bottomMargin: anchors.topMargin
        radius: Kirigami.Units.smallSpacing
        color: Qt.alpha(Kirigami.Theme.textColor, cell.open ? 0.14 : 0.1)
        visible: cell.open || cell.containsMouse || cell.activeFocus
    }
}
