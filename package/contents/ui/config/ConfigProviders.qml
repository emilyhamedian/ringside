// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import org.kde.kirigami as Kirigami
import "../code/items.js" as Items
import "../code/style.js" as Style

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

    // The widget's last status per provider (see UsageData.merge()). Not
    // readonly: tests substitute a fixed one. Each provider carries
    // program: { path, chosen, problem }, path being where the helper found
    // the program or the chosen path with ~ expanded, and starter, whether
    // the session starter is on.
    property var usageStatus: page.report("usageStatus")
    readonly property bool claudeOn: Items.enabled(cfg_itemOrder, cfg_hiddenItems).includes("claude")
    readonly property string home: decodeURIComponent(StandardPaths.writableLocation(StandardPaths.HomeLocation)
                                                      .toString().replace(/^file:\/\//, ""))

    // A path with the home folder as ~, and back.
    function shortPath(path) {
        return path === home ? "~" : path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
    }
    function fullPath(path) {
        return path.replace(/^~(?=\/)/, home);
    }

    function program(id) {
        return usageStatus[id]?.program ?? { path: "", chosen: false, problem: "" };
    }

    // Whether a provider's program ran in the helper's last check: found by
    // itself, or chosen with nothing wrong. A path typed since counts once
    // Apply has had it checked, so nothing moves while it is typed. True
    // until the helper first reports, so nothing shows as missing before it
    // has looked.
    function runs(id) {
        const p = usageStatus[id]?.program;
        return !p || p.path !== "" && p.problem === "";
    }
    readonly property bool codexOn: Items.enabled(cfg_itemOrder, cfg_hiddenItems).includes("codex")
    readonly property bool codexRuns: runs("codex")
    // A Program line shows only where it has something to say: a path the
    // user chose, or a program that is needed and missing. Codex is needed
    // to read OpenAI's limits at all; Claude only by its session starter.
    readonly property bool codexProgramWanted: codexOn && (cfg_codexProgram !== "" || !codexRuns)
    readonly property bool claudeProgramWanted: claudeOn && (cfg_claudeProgram !== ""
                                                             || usageStatus.claude?.starter === true && !runs("claude"))
    // Once shown, a Program line stays while the page is open, so emptying
    // the field to type another path, or to go back to automatic, doesn't
    // take it away mid-edit.
    property bool codexProgramKept: false
    property bool claudeProgramKept: false
    onCodexProgramWantedChanged: if (codexProgramWanted) codexProgramKept = true
    onClaudeProgramWantedChanged: if (claudeProgramWanted) claudeProgramKept = true
    Component.onCompleted: {
        codexProgramKept = codexProgramWanted;
        claudeProgramKept = claudeProgramWanted;
    }
    readonly property bool codexProgramShown: codexOn && (codexProgramWanted || codexProgramKept)
    readonly property bool claudeProgramShown: claudeOn && (claudeProgramWanted || claudeProgramKept)

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

    // Where a provider's program is, as Folder View asks for a custom
    // location: a path field and a button that opens a file picker. An
    // empty field finds the program automatically. The page checks that a
    // typed path is a full one; the helper checks the rest. The field is
    // the row's direct child, as Kirigami 6.0 needs of a label's buddy, and
    // its note is a row of its own under it (see ProgramNote).
    component ProgramField: RowLayout {
        id: row

        required property string command
        required property string chosen
        required property var found
        // Said under the field when nothing is wrong, and when nothing is
        // found.
        property string note
        property string lostNote

        signal choose(string path)

        // The field shows the setting, and takes it again only when it
        // changes other than by typing there, as by the file picker or
        // Defaults, so a space or a ~ being typed stays as typed.
        onChosenChanged: if (chosen !== field.text.trim()) field.text = chosen

        readonly property string typed: field.text.trim()
        // The helper's verdict holds only for the path it checked, not one
        // being typed since.
        readonly property bool checked: found.chosen === true && found.path === page.fullPath(chosen)
        readonly property string problem: {
            if (typed !== "" && !/^(\/|~\/)/.test(typed)) {
                return i18nc("@info under a program's path", "Enter a full path, starting with / or ~/.");
            }
            switch (checked ? found.problem : "") {
            case "missing":
                return i18nc("@info under a program's path", "There is no file at this path.");
            case "not-executable":
                return i18nc("@info under a program's path", "This file can't be run: it isn't marked executable.");
            case "folder":
                return i18nc("@info under a program's path", "This is a folder. Choose the program inside it.");
            }
            return "";
        }
        readonly property bool lost: chosen === "" && found.path === ""
        // The line under the row: a problem, or else what to know.
        readonly property string noteText: problem !== "" ? problem : lost ? lostNote : note

        Kirigami.FormData.label: i18nc("@label:textbox the program the item runs, such as ~/.local/bin/codex", "Program:")
        Kirigami.FormData.buddyFor: field
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            id: field
            Layout.fillWidth: true
            // A path reads left to right in any language.
            LayoutMirroring.enabled: false
            horizontalAlignment: TextInput.AlignLeft
            placeholderText: i18nc("@info:placeholder %1 is a program name such as codex", "Path to %1…", row.command)
            inputMethodHints: Qt.ImhNoPredictiveText
            Accessible.name: i18nc("@label:textbox %1 is a program name such as codex", "Path to %1", row.command)
            Accessible.description: row.noteText
            onTextEdited: row.choose(text.trim())
            // A stored path opens at its start, not scrolled to its end.
            onTextChanged: if (!activeFocus) cursorPosition = 0
            Component.onCompleted: text = row.chosen
        }
        QQC2.Button {
            icon.name: "document-open"
            display: QQC2.AbstractButton.IconOnly
            text: i18nc("@action:button %1 is a program name such as codex", "Choose where %1 is", row.command)
            Accessible.name: text
            QQC2.ToolTip.text: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            onClicked: dialog.open()
        }

        FileDialog {
            id: dialog
            title: i18nc("@title:window %1 is a program name such as codex", "Choose the %1 Program", row.command)
            currentFolder: "file://" + (row.chosen.startsWith("/") || row.chosen.startsWith("~/")
                                        ? page.fullPath(row.chosen).replace(/\/[^\/]*$/, "") : page.home)
                .split("/").map(encodeURIComponent).join("/")
            onAccepted: row.choose(page.shortPath(decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))))
        }
    }

    // The line under a Program row: dimmed, or in the negative colour for
    // a problem.
    component ProgramNote: Note {
        // var: Qt 6.6 can't hold an inline component type here.
        required property var program

        visible: program.visible && program.noteText !== ""
        horizontalAlignment: Text.AlignLeft
        color: program.problem !== "" ? Kirigami.Theme.negativeTextColor : Style.dim(Kirigami.Theme.textColor)
        text: program.noteText
    }

    Kirigami.FormLayout {
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18nc("@title:group settings that apply to both Claude and OpenAI", "Claude and OpenAI")
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
            text: i18nc("@info", "Applies while the Claude or OpenAI item is on in Panel Items.")
        }

        // Each provider's section shows only while it has something to set.
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18nc("@title:group settings for the Claude item", "Claude")
            visible: page.claudeHasLimits || page.claudeProgramShown
        }

        Picker {
            visible: page.claudeHasLimits
            Kirigami.FormData.label: i18nc("@label:listbox which per-model limit the inner ring shows, under a Claude or OpenAI heading", "Inner ring:")
            Accessible.name: i18nc("@label:listbox", "Claude inner ring")
            current: page.cfg_claudeInnerLimit
            choices: page.limitChoices("claude")
            onPicked: value => page.cfg_claudeInnerLimit = value
        }

        Note {
            visible: page.claudeHasLimits
            text: page.automaticLine
        }

        ProgramField {
            id: claudeProgram
            visible: page.claudeProgramShown
            command: "claude"
            chosen: page.cfg_claudeProgram
            found: page.program("claude")
            note: i18nc("@info under Claude's Program", "Only starting sessions needs it. Usage is read without it.")
            lostNote: i18nc("@info under Claude's Program: Not found, shown while the session starter is on",
                            "Not in ~/.local/bin or on Plasma's PATH. Starting sessions needs it; if claude is installed elsewhere, choose it.")
            onChoose: path => page.cfg_claudeProgram = path
        }

        ProgramNote {
            program: claudeProgram
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18nc("@title:group settings for the OpenAI item, whose limits are read through Codex", "OpenAI")
            visible: page.codexShown && page.codexRuns || page.codexProgramShown
        }

        // Codex's settings wait until its program runs.
        Picker {
            visible: page.codexHasLimits && page.codexRuns
            Kirigami.FormData.label: i18nc("@label:listbox which per-model limit the inner ring shows, under a Claude or OpenAI heading", "Inner ring:")
            Accessible.name: i18nc("@label:listbox", "OpenAI inner ring")
            current: page.cfg_codexInnerLimit
            choices: page.limitChoices("codex")
            onPicked: value => page.cfg_codexInnerLimit = value
        }

        Note {
            visible: page.codexHasLimits && page.codexRuns
            text: page.automaticLine
        }

        ColumnLayout {
            visible: page.codexShown && page.codexRuns
            Kirigami.FormData.label: i18nc("@label the logo in the OpenAI ring, under an OpenAI heading", "Ring logo:")
            Kirigami.FormData.buddyFor: codexLogo

            QQC2.RadioButton {
                id: codexLogo
                text: i18nc("@option:radio the logo in the OpenAI ring: the Codex mark, and the item named Codex", "Codex")
                checked: page.cfg_codexMark !== "openai"
                onToggled: page.cfg_codexMark = "codex"
            }
            QQC2.RadioButton {
                text: i18nc("@option:radio the logo in the OpenAI ring: the OpenAI logo, and the item named ChatGPT", "ChatGPT")
                checked: page.cfg_codexMark === "openai"
                onToggled: page.cfg_codexMark = "openai"
            }
        }

        ProgramField {
            id: codexProgram
            visible: page.codexProgramShown
            command: "codex"
            chosen: page.cfg_codexProgram
            found: page.program("codex")
            lostNote: i18nc("@info under OpenAI's Program: Not found",
                            "Not in ~/.local/bin or on Plasma's PATH, which leaves out what your shell adds. If codex is installed elsewhere, choose it.")
            onChoose: path => page.cfg_codexProgram = path
        }

        ProgramNote {
            program: codexProgram
        }
    }
}
