// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// What Ringside knows of each provider it reads usage limits for: the
// company that sets them, the command a user signs in with, and the product
// that command is. Proper names, which the words put into translated
// sentences as they are; usage.py keeps the same facts for the journal.
// `monthly` marks a provider whose limit is always a month, which the popup
// says before a first reading has shown it.
var FACTS = {
    claude: { company: "Anthropic", command: "claude", product: "Claude Code" },
    codex: { company: "OpenAI", command: "codex", product: "Codex" },
    kimi: { company: "Moonshot AI", command: "kimi", product: "Kimi Code", monthly: true },
    // Go's limits are read with OpenCode's sign-in to the OpenCode Console.
    opencode: { company: "OpenCode", command: "opencode auth login opencode", product: "OpenCode", monthly: true }
};
