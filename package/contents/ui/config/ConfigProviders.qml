// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

// The settings for the Claude and Codex items. Switching the items on and
// ordering them stays on Panel Items, and the session starter's switch in
// their popups.
KCM.SimpleKCM {
    id: page

    property int cfg_usageRefreshMinutes
    property string cfg_claudeInnerLimit
    property string cfg_codexInnerLimit
    // The per-model limits the widget has reported so far, read straight
    // from the configuration: declaring cfg_knownLimits would make Apply
    // write back the report the page opened with. Not readonly: there is no
    // live Plasmoid to fake outside a real applet, so tests substitute a
    // fixed value here instead.
    property var knownLimits: {
        try {
            const report = JSON.parse(Plasmoid.configuration.knownLimits || "{}");
            return report && typeof report === "object" ? report : {};
        } catch (err) {
            return {};
        }
    }
    // Array.from rather than Array.isArray: a value crossing from outside
    // the QML/JS engine (the settings dialog's own config binding, or a
    // test's initial property) arrives as a Qt sequence, not a JS Array.
    readonly property bool claudeHasLimits: Array.from(knownLimits.claude || []).length > 0 || cfg_claudeInnerLimit !== ""
    readonly property bool codexHasLimits: Array.from(knownLimits.codex || []).length > 0 || cfg_codexInnerLimit !== ""

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

        Item {
            Kirigami.FormData.isSection: true
            visible: page.claudeHasLimits || page.codexHasLimits
        }

        Picker {
            visible: page.claudeHasLimits
            Kirigami.FormData.label: i18nc("@label:listbox", "Claude inner ring:")
            Accessible.name: i18nc("@label:listbox", "Claude inner ring")
            current: page.cfg_claudeInnerLimit
            choices: page.limitChoices("claude")
            onPicked: value => page.cfg_claudeInnerLimit = value
        }

        Picker {
            visible: page.codexHasLimits
            Kirigami.FormData.label: i18nc("@label:listbox", "Codex inner ring:")
            Accessible.name: i18nc("@label:listbox", "Codex inner ring")
            current: page.cfg_codexInnerLimit
            choices: page.limitChoices("codex")
            onPicked: value => page.cfg_codexInnerLimit = value
        }

        Note {
            visible: page.claudeHasLimits || page.codexHasLimits
            text: i18nc("@info", "Automatic shows the per-model limit when your plan has just one. With more than one, pick it here.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        Note {
            text: i18nc("@info", "The switch that starts a new session or week when one ends is in the Claude and Codex popups.")
        }
    }
}
