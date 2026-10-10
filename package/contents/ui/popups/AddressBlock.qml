// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/style.js" as Style

// The local address over the public one, each labelled, so the two read as a
// pair: a VPN that carries the traffic shows its interface by the public
// address, and one that doesn't shows the same public address as without it.
// `info` is the public lookup as the network popup puts it:
//   state     "checking", "shown", "failed", "offline", "unrouted" or
//             "invalid"
//   service   the service's name, such as "ipify.org"
//   unrouted  in that state, the family ("v4" or "v6") without a route
//   v4, v6    { address, via, tunnel, city, country } or null; via is set
//             only when the request left through another interface than
//             the local one, and city when the service's reply named one
//   note      { text, warn } under the addresses, or null
// Where the service places the addresses goes under them, before the note:
// one line when the families agree or only one says, else one each, so a
// family going around a VPN shows where it is seen.
// After a failure, "Try again" beside the message emits retryRequested.
GridLayout {
    id: block

    required property string localAddress
    required property string localInterface
    required property var info

    signal retryRequested()

    readonly property real valuePointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
    readonly property color dimColor: Style.dim(Kirigami.Theme.textColor)
    readonly property var lines: info.state === "shown" ? [info.v4, info.v6].filter(l => l) : []
    // The width an address line gets: the block's share of its parent, less
    // the captions' column. Whether an interface fits beside its address is
    // decided against this, settled before the block lays out, rather than
    // against the line's own width, which arrives only as the popup lays the
    // line out, and in a block shown afresh first at the block's implicit
    // width: on Qt 6.6 an interface moving under its address part way
    // through costs the popup more passes than the two it allows, and it
    // gives up as a polish loop.
    readonly property real lineWidth: (parent ? parent.width - Layout.leftMargin - Layout.rightMargin : 0)
        - Math.ceil(Math.max(localCaption.implicitWidth, publicCaption.implicitWidth)) - columnSpacing
    readonly property var places: {
        const p4 = place(info.v4);
        const p6 = place(info.v6);
        if (p4 !== "" && p6 !== "" && p4 !== p6) {
            return [i18nc("@info %1 is a place, such as Amsterdam, Netherlands", "IPv4 near %1", p4),
                    i18nc("@info %1 is a place, such as Amsterdam, Netherlands", "IPv6 near %1", p6)];
        }
        // With both addresses shown, a place only one of them has says which.
        if (lines.length === 2 && (p4 === "") !== (p6 === "")) {
            return [p4 !== "" ? i18nc("@info %1 is a place, such as Amsterdam, Netherlands", "IPv4 near %1", p4)
                              : i18nc("@info %1 is a place, such as Amsterdam, Netherlands", "IPv6 near %1", p6)];
        }
        const one = p4 || p6;
        return one !== "" ? [i18nc("@info %1 is a place, such as Amsterdam, Netherlands", "Near %1", one)] : [];
    }

    // An address line's city, with its country where the reply gave one.
    function place(line) {
        return !line || line.city === "" ? ""
            : line.country !== "" ? i18nc("@info %1 is a city, %2 its country", "%1, %2", line.city, line.country)
            : line.city;
    }

    columns: 2
    columnSpacing: Kirigami.Units.largeSpacing
    rowSpacing: 0

    // An address, then where it left from when that says something. The
    // pair stays left to right under RTL, as the header's address line does,
    // and sits on the right there. Where the interface doesn't fit beside a
    // long address, it goes on a line of its own under it. Read out as one
    // phrase.
    component AddressLine: ColumnLayout {
        id: line

        property string address: ""
        property string via: ""
        property bool tunnel: false
        property string spoken: ""
        // Until the popup is laid out, a line counts as having room, so the
        // usual short line isn't split and joined again on its way in.
        readonly property bool roomy: via === "" || block.lineWidth <= 0
            || block.lineWidth >= addressText.implicitWidth + inline.fullWidth

        Layout.fillWidth: true
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true
        spacing: 0
        Accessible.role: Accessible.StaticText
        Accessible.name: spoken

        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Item {
                visible: block.LayoutMirroring.enabled
                Layout.fillWidth: true
            }
            Text {
                id: addressText
                Layout.alignment: Qt.AlignBaseline
                text: line.address
                color: Kirigami.Theme.textColor
                font.pointSize: block.valuePointSize
                font.features: ({ "tnum": 1 })
                textFormat: Text.PlainText
                Accessible.ignored: true
            }
            Via {
                id: inline
                visible: line.via !== "" && line.roomy
                dotted: true
                name: line.via
                tunnel: line.tunnel
            }
            Item {
                visible: !block.LayoutMirroring.enabled
                Layout.fillWidth: true
            }
        }
        RowLayout {
            visible: line.via !== "" && !line.roomy
            Layout.fillWidth: true
            spacing: 0
            Item {
                visible: block.LayoutMirroring.enabled
                Layout.fillWidth: true
            }
            Via {
                name: line.via
                tunnel: line.tunnel
            }
            Item {
                visible: !block.LayoutMirroring.enabled
                Layout.fillWidth: true
            }
        }
    }

    // " · ", the shield for a tunnel, and the interface's name, cut short
    // only when it is wider than the whole line.
    component Via: RowLayout {
        id: via

        property string name: ""
        property bool tunnel: false
        property bool dotted: false
        // The width it takes in full, visible or not.
        readonly property real fullWidth: (dotted ? dot.implicitWidth : 0)
            + (tunnel ? shield.Layout.preferredWidth + shield.Layout.rightMargin : 0) + nameText.Layout.preferredWidth

        Layout.alignment: Qt.AlignBaseline
        baselineOffset: nameText.y + nameText.baselineOffset
        spacing: 0

        Text {
            id: dot
            visible: via.dotted
            Layout.alignment: Qt.AlignBaseline
            text: " · "
            color: block.dimColor
            font.pointSize: block.valuePointSize
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
        Kirigami.Icon {
            id: shield
            visible: via.tunnel
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            Layout.rightMargin: Math.round(Kirigami.Units.smallSpacing / 2)
            Layout.alignment: Qt.AlignVCenter
            source: "network-vpn-symbolic"
            color: block.dimColor
            isMask: true
            Accessible.ignored: true
        }
        Text {
            id: nameText
            Layout.fillWidth: true
            // Whole pixels up: a layout rounding a fractional width down
            // would elide a name that fits.
            Layout.preferredWidth: Math.ceil(implicitWidth)
            Layout.maximumWidth: Layout.preferredWidth
            Layout.alignment: Qt.AlignBaseline
            text: via.name
            color: block.dimColor
            font.pointSize: block.valuePointSize
            elide: Text.ElideRight
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
            Accessible.ignored: true
        }
    }

    component Plain: Text {
        Layout.fillWidth: true
        color: block.dimColor
        font.pointSize: block.valuePointSize
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
        wrapMode: Text.Wrap
    }

    Caption {
        id: localCaption
        Layout.alignment: Qt.AlignBaseline | Qt.AlignLeft
        label: i18nc("@label the address this computer has on its own network", "Local")
        // The line beside it says so.
        Accessible.ignored: true
    }
    AddressLine {
        address: block.localAddress !== "" ? block.localAddress : i18nc("@info no local address", "No address")
        via: block.localInterface
        spoken: block.localAddress === ""
            ? (block.localInterface !== "" ? i18nc("@info accessible, %1 is a network interface", "No local address on %1", block.localInterface)
                                          : i18nc("@info accessible", "No local address"))
            : block.localInterface !== ""
            ? i18nc("@info accessible, %1 is an address, %2 a network interface", "Local address %1 on %2", block.localAddress, block.localInterface)
            : i18nc("@info accessible, %1 is an address", "Local address %1", block.localAddress)
    }

    Caption {
        id: publicCaption
        Layout.alignment: Qt.AlignTop | Qt.AlignLeft
        // On the first line's baseline: the caption is smaller than the values.
        Layout.topMargin: Math.round(publicFirst.baselineOffset - baselineOffset)
        label: i18nc("@label the address websites see", "Public")
        Accessible.ignored: block.lines.length > 0
    }
    ColumnLayout {
        id: publicColumn
        Layout.fillWidth: true
        spacing: 0

        Text {
            id: publicFirst
            visible: false
            font.pointSize: block.valuePointSize
            text: " "
        }

        Repeater {
            model: block.lines
            delegate: AddressLine {
                required property var modelData
                address: modelData.address
                via: modelData.via
                tunnel: modelData.tunnel
                readonly property string said: modelData.via === ""
                    ? i18nc("@info accessible, %1 is an address", "Public address %1", modelData.address)
                    : modelData.tunnel
                    ? i18nc("@info accessible, %1 is an address, %2 a VPN's network interface", "Public address %1 through VPN %2", modelData.address, modelData.via)
                    : i18nc("@info accessible, %1 is an address, %2 a network interface", "Public address %1 through %2", modelData.address, modelData.via)
                readonly property string near: block.place(modelData)
                // The place is heard with its address, so its line under them is skipped.
                spoken: near === "" ? said
                    : i18nc("@info accessible, %1 is the public address as said above, %2 a place, such as Amsterdam, Netherlands",
                            "%1, near %2", said, near)
            }
        }

        Plain {
            visible: block.info.state === "checking"
            text: i18nc("@info %1 is the service asked, such as ipify.org", "Asking %1…", block.info.service ?? "")
        }
        // The message, the link after it and room after that, in the block's
        // direction. The link takes no more height than the line it joins, so
        // the block keeps its size when the next check replaces it. Placed by
        // hand rather than by a RowLayout, so the message wraps to the room
        // the column leaves it as soon as it shows, not when the popup lays
        // it out: on Qt 6.6 a height that changes in the middle of laying out
        // the popup costs it two more passes, and it gives up as a polish
        // loop.
        Item {
            id: failure
            readonly property real spacing: Kirigami.Units.largeSpacing
            visible: block.info.state === "failed"
            Layout.fillWidth: true
            // On one line, so the message doesn't wrap to a column that
            // hasn't been laid out yet.
            implicitWidth: Math.ceil(unwrapped.advanceWidth) + retry.width + 2 * spacing
            implicitHeight: message.implicitHeight

            Plain {
                id: message
                anchors.left: parent.left
                // As wide as the text, so the link follows it, and no wider
                // than the room left, so a long name wraps. The text's width
                // comes from its metrics: a wrapping Text's implicitWidth
                // moves with its width on Qt 6.6.
                width: Math.max(0, Math.min(Math.ceil(unwrapped.advanceWidth),
                                            publicColumn.width - retry.width - 2 * failure.spacing))
                color: Kirigami.Theme.textColor
                text: i18nc("@info %1 is the service asked, such as ipify.org", "Can't reach %1", block.info.service ?? "")
            }
            Kirigami.LinkButton {
                id: retry
                // Whole pixels, so the message beside it ends on one too.
                width: Math.ceil(implicitWidth)
                anchors.left: message.right
                anchors.leftMargin: failure.spacing
                anchors.baseline: message.baseline
                text: i18nc("@action:button asks the address service again after it couldn't be reached", "Try again")
                font.pointSize: block.valuePointSize
                font.underline: false
                Accessible.description: i18nc("@info accessible, %1 is the service asked, such as ipify.org",
                                              "Ask %1 for the public address again", block.info.service ?? "")
                onClicked: block.retryRequested()
            }
            TextMetrics {
                id: unwrapped
                font: message.font
                text: message.text
            }
        }
        Plain {
            visible: block.info.state === "offline"
            text: i18nc("@info", "Waiting for a connection")
        }
        Plain {
            visible: block.info.state === "unrouted"
            text: block.info.unrouted === "v4" ? i18nc("@info", "No IPv4 connection") : i18nc("@info", "No IPv6 connection")
        }
        Plain {
            visible: block.info.state === "invalid"
            color: Kirigami.Theme.textColor
            text: i18nc("@info", "Check the address service in the settings")
        }

        // The places and the note, set apart from the addresses as one.
        Item {
            visible: block.places.length > 0 || block.info.note ? true : false
            implicitHeight: Math.round(Kirigami.Units.smallSpacing / 2)
        }

        Repeater {
            model: block.places
            delegate: Text {
                required property string modelData
                Layout.fillWidth: true
                text: modelData
                color: block.dimColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                elide: Text.ElideRight
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
                Accessible.ignored: true
            }
        }

        RowLayout {
            visible: block.info.note ? true : false
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                visible: block.info.note?.warn ?? false
                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                source: "data-warning-symbolic"
                color: Kirigami.Theme.neutralTextColor
                isMask: true
                Accessible.ignored: true
            }
            Text {
                Layout.fillWidth: true
                text: block.info.note?.text ?? ""
                // The icon carries the amber; amber text is too faint on the light scheme.
                color: block.info.note?.warn ? Kirigami.Theme.textColor : block.dimColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
                Accessible.name: block.info.note?.warn ? i18nc("@info accessible, %1 is a warning", "Warning: %1", text) : text
            }
        }
    }
}
