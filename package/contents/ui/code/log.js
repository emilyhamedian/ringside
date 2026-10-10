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

// level is "debug", "info" or "warning". The journal keeps the category in
// its QT_CATEGORY field, not in the text, which is how the README finds
// Ringside's lines. Up to Qt 6.6 at least, a LoggingCategory written to
// before its component completes, as from a handler that runs while the
// widget is being built, throws; the line then goes out a moment later,
// once it has, so it keeps its category.
function write(category, level, text) {
    emit(category, level, text, true);
    for (const listener of listeners.slice()) {
        listener(category.name, level, text);
    }
}

function emit(category, level, text, retry) {
    try {
        if (level === "debug") {
            console.debug(category, text);
        } else if (level === "info") {
            console.info(category, text);
        } else {
            console.warn(category, text);
        }
    } catch (err) {
        if (retry) {
            Qt.callLater(() => emit(category, level, text, false));
        }
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
