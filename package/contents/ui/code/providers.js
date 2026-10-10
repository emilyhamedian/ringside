// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// What Ringside knows of each provider it reads weekly limits for: the
// company that sets them, the command a user signs in with, and the product
// that command is. Proper names, which the words put into translated
// sentences as they are; usage.py keeps the same facts for the journal.
var FACTS = {
    claude: { company: "Anthropic", command: "claude", product: "Claude Code" },
    codex: { company: "OpenAI", command: "codex", product: "Codex" }
};

function facts(id) {
    return FACTS[id];
}
