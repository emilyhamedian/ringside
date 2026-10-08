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

    readonly property var historyChoices: [30, 60, 120, 300, 600]
    readonly property var service: Lookup.service(cfg_publicAddressUrl4, cfg_publicAddressUrl6)
    // An invalid service asks nothing, so it goes unnamed rather than named
    // after the one URL that is fine.
    readonly property string serviceName: !service.valid
        ? i18nc("@info a public address service whose URL isn't valid", "the address service")
        : service.hosts.length === 2
        ? i18nc("@info two services' host names", "%1 and %2", service.hosts[0], service.hosts[1])
        : service.hosts[0]
    readonly property string unit: cfg_fahrenheit ? i18nc("@label temperature unit", "°F")
                                                   : i18nc("@label temperature unit", "°C")

    // A public address service's URL, and what's wrong with it, if anything.
    component UrlField: ColumnLayout {
        id: field

        property string url
        property string placeholder
        property string name
        readonly property bool invalid: url.trim() !== "" && Lookup.host(url.trim()) === ""

        signal edited(string text)

        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 16
            text: field.url
            placeholderText: field.placeholder
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            Accessible.name: field.name
            Accessible.description: field.invalid ? error.text : ""
            onTextEdited: field.edited(text)
        }
        Note {
            id: error
            visible: field.invalid
            color: Kirigami.Theme.negativeTextColor
            text: i18nc("@info under a URL field", "Use an https:// address with a host name and no user name or password.")
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

        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "Graph history:")
            model: page.historyChoices.map(s => s < 60
                ? i18ncp("@item:inlistbox how far back the graphs reach", "%1 second", "%1 seconds", s)
                : i18ncp("@item:inlistbox how far back the graphs reach", "%1 minute", "%1 minutes", s / 60))
            // The nearest choice, should the stored value be one the list doesn't offer.
            currentIndex: {
                const d = page.historyChoices.map(s => Math.abs(s - page.cfg_historySeconds));
                return d.indexOf(Math.min(...d));
            }
            Accessible.name: i18nc("@label:listbox", "Graph history")
            onActivated: index => page.cfg_historySeconds = page.historyChoices[index]
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

        QQC2.CheckBox {
            Kirigami.FormData.label: i18nc("@label", "Public address:")
            text: i18nc("@option:check %1 is the service asked, such as ipify.org", "Ask %1 for it", page.serviceName)
            checked: page.cfg_publicAddress
            onToggled: page.cfg_publicAddress = checked
        }

        Note {
            text: !page.service.valid
                ? i18nc("@info", "Shows the address websites see under the local one in the Network popup. Ringside asks nothing until the addresses below are fixed.")
                : page.service.custom
                ? i18nc("@info %1 is the service asked, such as ip.example.org", "Shows the address websites see under the local one in the Network popup. Ringside asks only %1, at the addresses below, when that popup opens or the connection changes, at most once a minute. The service sees your address, as every website does.", page.serviceName)
                : i18nc("@info %1 and %2 are the service's host names", "Shows the address websites see under the local one in the Network popup. Ringside asks %1 and %2 when that popup opens or the connection changes, at most once a minute. ipify.org sees your address, as every website does.",
                        Lookup.host(Lookup.IPIFY.v4), Lookup.host(Lookup.IPIFY.v6))
        }

        UrlField {
            Kirigami.FormData.label: i18nc("@label:textbox", "IPv4 address URL:")
            name: i18nc("@label:textbox", "IPv4 address URL")
            url: page.cfg_publicAddressUrl4
            placeholder: Lookup.IPIFY.v4
            onEdited: text => page.cfg_publicAddressUrl4 = text
        }

        UrlField {
            Kirigami.FormData.label: i18nc("@label:textbox", "IPv6 address URL:")
            name: i18nc("@label:textbox", "IPv6 address URL")
            url: page.cfg_publicAddressUrl6
            placeholder: Lookup.IPIFY.v6
            onEdited: text => page.cfg_publicAddressUrl6 = text
        }

        Note {
            text: i18nc("@info", "Leave both empty for ipify.org. With either set, only that service is asked, and a field left empty isn't checked. The service has to answer with the address alone, as plain text, without redirecting to another host or to http.")
        }
    }
}
