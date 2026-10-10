// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Whether a key press presses a focused button: Space, Enter, Return or
// Select, as Qt Quick Controls' own buttons take them.
function pressedBy(event) {
    return [Qt.Key_Space, Qt.Key_Enter, Qt.Key_Return, Qt.Key_Select].includes(event.key);
}
