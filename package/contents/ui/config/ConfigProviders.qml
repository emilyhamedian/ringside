// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/items.js" as Items

// The settings for the Claude and Codex items. Switching the items on and
// ordering them stays on Panel Items.
ConfigPage {
    id: page

    // The per-model limits the widget has reported so far. Not readonly:
    // tests substitute a fixed set here.
    property var knownLimits: page.report("knownLimits")
    // Array.from rather than Array.isArray: a value crossing from outside
    // the QML/JS engine (a test's initial property) arrives as a Qt
    // sequence, not a JS Array.
    readonly property bool claudeHasLimits: Array.from(knownLimits.claude || []).length > 0 || cfg_claudeInnerLimit !== ""
    readonly property bool codexHasLimits: Array.from(knownLimits.codex || []).length > 0 || cfg_codexInnerLimit !== ""
    // The Codex ring's logo is offered while the item is on or Codex has
    // reported its limits.
    readonly property bool codexShown: Items.enabled(cfg_itemOrder, cfg_hiddenItems).includes("codex") || codexHasLimits

    // Under each inner ring picker.
    readonly property string automaticLine: i18nc("@info", "Automatic shows the per-model limit when your plan has just one. With more than one, pick it here.")

    // Automatic, none, then each limit reported for this provider so far. A
    // limit that was picked but is no longer reported still shows, as "…
    // (not reported)", so choosing it back off is possible.
    function limitChoices(id) {
        const list = Array.from(knownLimits[id] || []);
        return [
            { text: i18nc("@item:inlistbox automatic per-model limit", "Automatic"), value: "" },
            { text: i18nc("@item:inlistbox no per-model limit on the inner ring", "None"), value: "none" }
        ].concat(list.filter(limit => limit && typeof limit.id === "string" && limit.id).map(limit => ({
            text: limit.reported === false
                ? i18nc("@item:inlistbox %1 is a model's limit name", "%1 (not reported)", limit.label)
                : String(limit.label),
            value: limit.id
        })));
    }

    Kirigami.FormLayout {
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18nc("@title:group settings that apply to both Claude and Codex", "Claude and Codex")
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18nc("@label:spinbox", "Check every:")
            from: 5
            to: 60
            stepSize: 5
            // Stepped only: the desktop style rewrites the text on every
            // keystroke, which fights the unit suffix.
            editable: false
            value: page.cfg_usageRefreshMinutes
            textFromValue: (value, locale) => i18ncp("@item:valuesuffix minutes between usage checks", "%1 minute", "%1 minutes", value)
            Accessible.name: i18nc("@label:spinbox", "Check every")
            onValueModified: page.cfg_usageRefreshMinutes = value
        }

        Note {
            text: i18nc("@info", "Applies while the Claude or Codex item is on in Panel Items.")
        }

        // Each provider's section shows only while it has something to set.
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18nc("@title:group settings for the Claude item", "Claude")
            visible: page.claudeHasLimits
        }

        Picker {
            visible: page.claudeHasLimits
            Kirigami.FormData.label: i18nc("@label:listbox which per-model limit the inner ring shows, under a Claude or Codex heading", "Inner ring:")
            Accessible.name: i18nc("@label:listbox", "Claude inner ring")
            current: page.cfg_claudeInnerLimit
            choices: page.limitChoices("claude")
            onPicked: value => page.cfg_claudeInnerLimit = value
        }

        Note {
            visible: page.claudeHasLimits
            text: page.automaticLine
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18nc("@title:group settings for the Codex item", "Codex")
            visible: page.codexShown
        }

        Picker {
            visible: page.codexHasLimits
            Kirigami.FormData.label: i18nc("@label:listbox which per-model limit the inner ring shows, under a Claude or Codex heading", "Inner ring:")
            Accessible.name: i18nc("@label:listbox", "Codex inner ring")
            current: page.cfg_codexInnerLimit
            choices: page.limitChoices("codex")
            onPicked: value => page.cfg_codexInnerLimit = value
        }

        Note {
            visible: page.codexHasLimits
            text: page.automaticLine
        }

        ColumnLayout {
            visible: page.codexShown
            Kirigami.FormData.label: i18nc("@label the logo in the Codex ring, under a Codex heading", "Ring logo:")
            Kirigami.FormData.buddyFor: codexLogo

            QQC2.RadioButton {
                id: codexLogo
                text: i18nc("@option:radio the logo in the Codex ring", "Codex")
                checked: page.cfg_codexMark !== "openai"
                onToggled: page.cfg_codexMark = "codex"
            }
            QQC2.RadioButton {
                text: i18nc("@option:radio the logo in the Codex ring", "OpenAI")
                checked: page.cfg_codexMark === "openai"
                onToggled: page.cfg_codexMark = "openai"
            }
        }
    }
}
