// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

// One selected time across the graphs of one device, in graph coordinates
// from 0 to 1. It clears when its scope hides or the graphs change span.
QtObject {
    id: cursor

    property QtObject owner: null
    property real position: NaN
    property Item scope: null
    property QtObject monitor: null

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

    readonly property Connections scopeWatch: Connections {
        target: cursor.scope

        function onVisibleChanged() {
            if (!cursor.scope.visible) {
                cursor.reset();
            }
        }
    }

    readonly property Connections spanWatch: Connections {
        target: cursor.monitor

        function onGraphSpanChanged() {
            cursor.reset();
        }
    }
}
