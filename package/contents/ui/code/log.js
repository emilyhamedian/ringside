// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Every line Ringside writes to Plasma's journal goes through write(), under
// a LoggingCategory whose name starts "ringside." and whose default level is
// info, so debug lines show only once kdebugsettings or QT_LOGGING_RULES
// turn them on. Info and warning are for failures and changes, debug for
// each check. A line never carries a token, an address, a place, an
// account or a file's contents. Lines are in English: the journal isn't
// translated.
//
// Every widget in plasmashell shares this module, and the tests listen to
// what is written through listen().

const listeners = [];

// level is "debug", "info" or "warning". Up to Qt 6.6 at least, a
// LoggingCategory written to before its component completes, as from a
// handler that runs while the widget is being built, throws; the line then
// goes out under Qt's own category with the name in front, and a debug
// line is dropped, since that category shows debug lines by default.
function write(category, level, text) {
    try {
        if (level === "debug") {
            console.debug(category, text);
        } else if (level === "info") {
            console.info(category, text);
        } else {
            console.warn(category, text);
        }
    } catch (err) {
        if (level === "info") {
            console.info(category.name + ": " + text);
        } else if (level !== "debug") {
            console.warn(category.name + ": " + text);
        }
    }
    for (const listener of listeners.slice()) {
        listener(category.name, level, text);
    }
}

function listen(listener) {
    listeners.push(listener);
}

function unlisten(listener) {
    const at = listeners.indexOf(listener);
    if (at >= 0) {
        listeners.splice(at, 1);
    }
}
