// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "../code/publicaddress.js" as Lookup

ConfigPage {
    id: page

    readonly property string unit: cfg_fahrenheit ? i18nc("@label temperature unit", "°F")
                                                   : i18nc("@label temperature unit", "°C")
    readonly property var service: Lookup.service(cfg_publicAddressUrl4, cfg_publicAddressUrl6)
    // Custom is shown while either URL is set, or once picked or typed in,
    // so the fields stay open while both are empty. Picking ipify.org
    // empties them, which is what selects it; picking Custom again brings
    // back what they held.
    property bool customPicked: false
    readonly property bool custom: customPicked || service.custom
    property var keptUrls: ["", ""]

    // Whom Ringside asks and what they learn, under the box whether it's
    // ticked or not. "Until you enter a URL" only while the fields show.
    readonly property string line: {
        if (cfg_publicAddress && custom && !service.custom) {
            return i18nc("@info Custom picked, both URLs still empty; %1 is ipify.org",
                         "Asks %1, which sees your address, until you enter a URL.", Lookup.IPIFY.name);
        }
        if (!service.valid) {
            return i18nc("@info", "Asks nothing while a URL isn't valid.");
        }
        const n = service.hosts.length;
        const who = n === 2 ? i18nc("@info two host names", "%1 and %2", service.hosts[0], service.hosts[1]) : service.hosts[0];
        return i18ncp("@info %2 names the service", "Asks %2, which sees your address, when the popup opens.",
                      "Asks %2, which see your address, when the popup opens.", n, who);
    }
    // How far the box's text sits from its edge. FormLayout ignores layout
    // margins, so the line under the box takes this as padding.
    readonly property real boxIndent: (publicAddress.mirrored ? publicAddress.rightPadding : publicAddress.leftPadding)
                                      + publicAddress.indicator.width + publicAddress.spacing

    function pickCustom(yes) {
        if (yes === custom) {
            return;
        }
        // Custom is flagged only after the URLs are back, so settle() can't
        // take it for Defaults when a stored blank URL turns empty.
        if (yes) {
            cfg_publicAddressUrl4 = keptUrls[0];
            cfg_publicAddressUrl6 = keptUrls[1];
            customPicked = true;
        } else {
            customPicked = false;
            keptUrls = [cfg_publicAddressUrl4, cfg_publicAddressUrl6];
            cfg_publicAddressUrl4 = "";
            cfg_publicAddressUrl6 = "";
        }
    }
    // Both URLs emptied from outside the fields, as Defaults does, means
    // ipify.org again, so Custom closes with them.
    function settle() {
        if (customPicked && cfg_publicAddressUrl4 === "" && cfg_publicAddressUrl6 === ""
                && !url4.input.activeFocus && !url6.input.activeFocus) {
            customPicked = false;
        }
    }
    onCfg_publicAddressUrl4Changed: settle()
    onCfg_publicAddressUrl6Changed: settle()

    // What's wrong with a service URL, in a few words, or "".
    function urlProblem(url) {
        const u = String(url).trim();
        if (u === "" || Lookup.host(u) !== "") {
            return "";
        }
        if (!/^https:\/\//i.test(u)) {
            return i18nc("@info under a URL field", "Only https:// addresses work.");
        }
        if (/^https:\/\/[^\/?#]*@/i.test(u)) {
            return i18nc("@info under a URL field", "Leave out the user name and password.");
        }
        return i18nc("@info under a URL field", "Check the host name.");
    }

    // A public address service's URL, and what's wrong with it, if anything.
    component UrlField: ColumnLayout {
        id: field

        property string url
        property string name
        readonly property alias input: input
        readonly property string problem: page.urlProblem(url)

        signal edited(string text)

        Kirigami.FormData.buddyFor: input
        Layout.fillWidth: false
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            id: input
            Layout.fillWidth: true
            // A URL reads left to right in any language.
            LayoutMirroring.enabled: false
            horizontalAlignment: TextInput.AlignLeft
            text: field.url
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            Accessible.name: field.name
            Accessible.description: field.problem
            onTextEdited: {
                page.customPicked = true;
                field.edited(text);
            }
            // A stored URL opens at its start, not scrolled to its end.
            onTextChanged: if (!activeFocus) cursorPosition = 0
        }
        Note {
            visible: field.problem !== ""
            color: Kirigami.Theme.negativeTextColor
            horizontalAlignment: Text.AlignLeft
            text: field.problem
        }
    }

    Kirigami.FormLayout {
        id: form

        QQC2.SpinBox {
            Kirigami.FormData.label: i18nc("@label:spinbox", "Update interval:")
            from: 500
            to: 10000
            stepSize: 500
            value: page.cfg_updateInterval
            // Stepped only: the desktop style rewrites the text on every
            // keystroke, which fights the unit suffix.
            editable: false
            textFromValue: (value, locale) => i18nc("@item:valuesuffix seconds between panel updates", "%1 s",
                                                    Number(value / 1000).toLocaleString(locale, "f", 1))
            Accessible.name: i18nc("@label:spinbox", "Update interval")
            onValueModified: page.cfg_updateInterval = value
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        ColumnLayout {
            Kirigami.FormData.label: i18nc("@label", "Temperature unit:")
            Kirigami.FormData.buddyFor: celsius

            QQC2.RadioButton {
                id: celsius
                text: i18nc("@option:radio", "Celsius")
                checked: !page.cfg_fahrenheit
                onToggled: page.cfg_fahrenheit = !checked
            }
            QQC2.RadioButton {
                text: i18nc("@option:radio", "Fahrenheit")
                checked: page.cfg_fahrenheit
                onToggled: page.cfg_fahrenheit = checked
            }
        }

        // The sentence around the two thresholds, in two parts: one line
        // while the form has room for it, two once it goes narrow. Both parts
        // are rebuilt whenever the unit changes, so each box counts whole
        // degrees of the unit it shows and a switch stores nothing.
        GridLayout {
            columns: form.wideMode ? 2 : 1
            columnSpacing: Kirigami.Units.smallSpacing

            Repeater {
                model: [false, true].map(red => ({ red: red, fahrenheit: page.cfg_fahrenheit }))

                RowLayout {
                    id: part

                    required property var modelData
                    readonly property bool red: modelData.red
                    readonly property bool fahrenheit: modelData.fahrenheit

                    function shown(celsius) {
                        return Math.round(fahrenheit ? celsius * 9 / 5 + 32 : celsius);
                    }

                    spacing: Kirigami.Units.smallSpacing

                    QQC2.CheckBox {
                        visible: !part.red
                        text: i18nc("@option:check followed by a temperature box", "Highlight temperatures above")
                        checked: page.cfg_highlightTemperatures
                        onToggled: page.cfg_highlightTemperatures = checked
                    }
                    QQC2.SpinBox {
                        enabled: page.cfg_highlightTemperatures
                        // Amber stays at least a degree below red.
                        from: part.red ? part.shown(page.cfg_warmCelsius) + 1 : part.shown(30)
                        to: part.red ? part.shown(120) : part.shown(page.cfg_hotCelsius) - 1
                        value: part.shown(part.red ? page.cfg_hotCelsius : page.cfg_warmCelsius)
                        Accessible.name: part.red ? i18nc("@label:spinbox", "Red threshold")
                                                  : i18nc("@label:spinbox", "Amber threshold")
                        onValueModified: {
                            const celsius = part.fahrenheit ? (value - 32) * 5 / 9 : value;
                            if (part.red) {
                                page.cfg_hotCelsius = celsius;
                            } else {
                                page.cfg_warmCelsius = celsius;
                            }
                        }
                    }
                    QQC2.Label {
                        enabled: page.cfg_highlightTemperatures
                        text: part.red ? i18nc("@label after the red temperature box; %1 is °C or °F", "%1 in red", page.unit)
                                       : i18nc("@label between the two temperature boxes; %1 is °C or °F", "%1 in amber and above", page.unit)
                        textFormat: Text.PlainText
                    }
                }
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        ColumnLayout {
            Kirigami.FormData.label: i18nc("@label", "Network speeds:")
            Kirigami.FormData.buddyFor: bits

            QQC2.RadioButton {
                id: bits
                text: i18nc("@option:radio", "Bits per second (Mb/s)")
                checked: page.cfg_networkBits
                onToggled: page.cfg_networkBits = checked
            }
            QQC2.RadioButton {
                text: i18nc("@option:radio", "Bytes per second (MiB/s)")
                checked: !page.cfg_networkBits
                onToggled: page.cfg_networkBits = !checked
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: publicAddress
            Kirigami.FormData.label: i18nc("@label", "Public address:")
            text: i18nc("@option:check", "Show in the Network popup")
            checked: page.cfg_publicAddress
            Accessible.description: page.line
            onToggled: page.cfg_publicAddress = checked
        }

        Note {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 30
            leftPadding: publicAddress.mirrored ? 0 : page.boxIndent
            rightPadding: publicAddress.mirrored ? page.boxIndent : 0
            // Mirrored with the page, whatever the text's own direction.
            horizontalAlignment: Text.AlignLeft
            text: page.line
        }

        QQC2.ComboBox {
            id: serviceChoice
            Kirigami.FormData.label: i18nc("@label:listbox", "Service:")
            visible: page.cfg_publicAddress
            model: [Lookup.IPIFY.name, i18nc("@item:inlistbox a public address service", "Custom")]
            currentIndex: page.custom ? 1 : 0
            Accessible.name: i18nc("@label:listbox", "Service")
            Accessible.description: page.line
            // Picking ipify.org empties the URLs, so a stray scroll mustn't.
            wheelEnabled: false
            onActivated: index => {
                page.pickCustom(index === 1);
                // From the open list only: arrow keys on the closed one
                // leave the focus where it is, so they can step back.
                if (index === 1 && popup.visible) {
                    url4.input.forceActiveFocus();
                }
            }
        }

        UrlField {
            id: url4
            Kirigami.FormData.label: i18nc("@label:textbox", "IPv4 URL:")
            visible: page.cfg_publicAddress && page.custom
            name: i18nc("@label:textbox", "IPv4 URL")
            url: page.cfg_publicAddressUrl4
            onEdited: text => page.cfg_publicAddressUrl4 = text
        }

        UrlField {
            id: url6
            Kirigami.FormData.label: i18nc("@label:textbox", "IPv6 URL:")
            visible: page.cfg_publicAddress && page.custom
            name: i18nc("@label:textbox", "IPv6 URL")
            url: page.cfg_publicAddressUrl6
            onEdited: text => page.cfg_publicAddressUrl6 = text
        }
    }
}
