// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import "../code/style.js" as Style

// The span on a graph's caption line, "1 min", which opens a menu of the
// spans the graphs can show. One choice serves every graph in every popup,
// so a caption always names what its neighbours show too. Drawn as the
// caption's own text and a small chevron, with a wash under it on hover,
// focus and while the menu is open, so the line reads as it did before it
// became a control. Space, Return or Down opens the menu on the span shown,
// and Escape closes it.
T.AbstractButton {
    id: button
    objectName: "span"

    // Monitor.qml: graphSpan, and chooseSpan() to change it.
    required property var monitor

    readonly property var spans: ["minute", "hour", "day"]
    // Short on the caption line; whole words in the menu and for a screen
    // reader.
    readonly property var labels: ({
        minute: i18nc("@title:group a graph's span, after its caption as in USAGE · 1 min", "1 min"),
        hour: i18nc("@title:group a graph's span, after its caption as in USAGE · 1 h", "1 h"),
        day: i18nc("@title:group a graph's span, after its caption as in USAGE · 1 day", "1 day")
    })
    readonly property var names: ({
        minute: i18nc("@item:inmenu a graph's span", "1 minute"),
        hour: i18nc("@item:inmenu a graph's span", "1 hour"),
        day: i18nc("@item:inmenu a graph's span", "1 day")
    })
    readonly property string span: spans.includes(monitor.graphSpan) ? monitor.graphSpan : "minute"
    readonly property alias menu: menu
    // Room round the text for the wash, outside the button's own box, so
    // the caption line doesn't move to make room for it.
    readonly property real washX: Math.round(Kirigami.Units.smallSpacing * 1.25)
    readonly property real washY: Math.round(Kirigami.Units.smallSpacing / 2)

    function openMenu() {
        if (!menu.visible) {
            menu.open();
        }
    }

    text: labels[span]
    font: Kirigami.Theme.smallFont
    hoverEnabled: true
    padding: 0
    spacing: Math.round(Kirigami.Units.smallSpacing * 0.75)
    implicitWidth: contentItem.implicitWidth
    implicitHeight: contentItem.implicitHeight
    baselineOffset: label.baselineOffset

    Accessible.role: Accessible.ButtonMenu
    Accessible.name: i18nc("@action:button accessible name of a graph's span, which opens a menu of spans; %1 is 1 minute, 1 hour or 1 day",
                           "Graph span: %1", names[span])
    Accessible.onPressAction: openMenu()

    onClicked: menu.visible ? menu.close() : menu.open()
    Keys.onPressed: event => {
        if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Down].includes(event.key)) {
            openMenu();
            event.accepted = true;
        }
    }

    contentItem: Row {
        spacing: button.spacing

        Text {
            id: label
            text: button.text
            font: button.font
            color: Style.dim(Kirigami.Theme.textColor)
            textFormat: Text.PlainText
        }

        // An open chevron, as on a menu button, sized to the caption's
        // capitals and centred on them.
        Shape {
            id: chevron
            readonly property real ink: capitals.tightBoundingRect.height
            y: label.baselineOffset - ink / 2 - height / 2
            width: Math.round(ink * 0.9)
            height: Math.round(width * 0.55)
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: label.color
                strokeWidth: 1.25
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: 0.6
                startY: 0.6
                PathLine { x: chevron.width / 2; y: chevron.height - 0.6 }
                PathLine { x: chevron.width - 0.6; y: 0.6 }
            }
        }

        TextMetrics {
            id: capitals
            font: button.font
            text: "H"
        }
    }

    background: Item {
        Rectangle {
            x: -button.washX
            y: -button.washY
            width: parent.width + 2 * button.washX
            height: parent.height + 2 * button.washY
            radius: Kirigami.Units.smallSpacing / 2
            color: Qt.alpha(Kirigami.Theme.textColor, button.down || menu.visible ? 0.14 : 0.08)
            border.width: button.visualFocus ? 1 : 0
            border.color: Kirigami.Theme.focusColor
            visible: button.hovered || button.down || menu.visible || button.visualFocus
        }
    }

    PlasmaComponents.Menu {
        id: menu

        // Opened from the keyboard, it starts on the span shown, so the
        // arrows move from there, and on closing gives the focus back with
        // its ring: Qt before 6.8 leaves it on the window, and later ones
        // give it back as if by the pointer, without the ring.
        property bool keyed: false

        onAboutToShow: {
            keyed = button.visualFocus;
            currentIndex = keyed ? button.spans.indexOf(button.span) : -1;
        }
        onClosed: {
            if (keyed) {
                button.forceActiveFocus(Qt.TabFocusReason);
                button.focusReason = Qt.TabFocusReason;
            }
        }

        // Under the wash, its items' text over the span's.
        y: button.height + button.washY + Kirigami.Units.smallSpacing / 2
        x: button.mirrored ? button.width - width + leftPadding : -leftPadding

        SpanItem { span: "minute" }
        SpanItem { span: "hour" }
        SpanItem { span: "day" }
    }

    component SpanItem: PlasmaComponents.MenuItem {
        required property string span
        text: button.names[span]
        checkable: true
        autoExclusive: true
        checked: button.span === span
        onTriggered: button.monitor.chooseSpan(span)
    }
}
