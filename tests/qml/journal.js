// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library
.import "../../package/contents/ui/code/log.js" as Log

// Hands a test what Ringside writes to the journal, as (category name,
// level, text), while each line still goes out. Every component in the
// engine shares log.js, so swapping its write() reaches the ones under
// test; unlisten() puts the original back.

const write = Log.write;

function listen(listener) {
    Log.write = (category, level, text) => {
        listener(category.name, level, text);
        write(category, level, text);
    };
}

function unlisten() {
    Log.write = write;
}
