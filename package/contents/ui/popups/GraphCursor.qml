// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQml

// One selected time across a popup, in graph coordinates from 0 to 1.
QtObject {
    property QtObject owner: null
    property real position: NaN

    function publish(source, at) {
        if (source) {
            // An empty graph keeps ownership while waiting for its first sample.
            position = Number.isFinite(at) && at >= 0 && at <= 1 ? at : NaN;
            owner = source;
        }
    }

    function release(source) {
        if (owner === source) {
            reset();
        }
    }

    function reset() {
        owner = null;
        position = NaN;
    }
}
