// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "code/processes.js" as Processes

// The user's processes using AMD and Intel GPUs, from the helper's gpuprocs,
// which reads them from /proc and /sys and wakes no GPU. It runs while the
// GPU popup is open: at once, a second later for the first usage, then every
// four seconds.
QtObject {
    id: reader

    // The helper's gpuprocs, ready to run.
    required property string command
    property bool active: false
    // { name, usage, memory, gpu: BDF } for each process on each GPU.
    property var processes: []
    // Set once two runs have given the processes their usage.
    property bool scanned: false

    property var last: null
    property int runs: 0

    onActiveChanged: {
        if (!active) {
            processes = [];
            scanned = false;
            last = null;
            runs = 0;
        }
    }

    property P5Support.DataSource source: P5Support.DataSource {
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            if (!reader.active || data["exit code"] !== 0) {
                return;
            }
            const scan = Processes.gpuScan(data.stdout ?? "");
            reader.processes = Processes.gpuProcesses(reader.last, scan);
            reader.scanned = reader.last !== null;
            reader.last = scan;
        }
    }

    // Two names in turn: the engine can hand back a source's last answer,
    // without running it, when it is asked for again too soon.
    property Timer clock: Timer {
        interval: reader.runs < 2 ? 1000 : 4000
        running: reader.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            reader.source.connectSource(reader.command + (reader.runs % 2 === 0 ? " a" : " b"));
            reader.runs += 1;
        }
    }
}
