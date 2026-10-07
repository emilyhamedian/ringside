// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "../code/style.js" as Style

KCM.SimpleKCM {
    id: page

    property int cfg_updateInterval
    property int cfg_historySeconds
    property bool cfg_fahrenheit
    property bool cfg_networkBits
    property bool cfg_highlightTemperatures
    property real cfg_warmCelsius
    property real cfg_hotCelsius
    property int cfg_usageRefreshMinutes

    readonly property var historyChoices: [30, 60, 120, 300, 600]
    readonly property string unit: cfg_fahrenheit ? i18nc("@label temperature unit", "°F")
                                                   : i18nc("@label temperature unit", "°C")

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

        Item {
            Kirigami.FormData.isSection: true
        }

        Kirigami.Separator {
            Kirigami.FormData.label: i18nc("@title:group", "Claude and Codex")
            Kirigami.FormData.isSection: true
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18nc("@label:spinbox", "Check every:")
            from: 5
            to: 60
            stepSize: 5
            // Stepped only, for the same reason as Update interval above.
            editable: false
            value: page.cfg_usageRefreshMinutes
            textFromValue: (value, locale) => i18ncp("@item:valuesuffix minutes between usage checks", "%1 minute", "%1 minutes", value)
            Accessible.name: i18nc("@label:spinbox", "Check every")
            onValueModified: page.cfg_usageRefreshMinutes = value
        }
        QQC2.Label {
            text: i18nc("@info", "Applies while the Claude or Codex item is on.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Style.dim(Kirigami.Theme.textColor)
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 11.5 / 13
        }
    }
}
