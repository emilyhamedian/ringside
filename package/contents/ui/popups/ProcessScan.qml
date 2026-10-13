// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import org.kde.ksysguard.process as Process
import "../code/processes.js" as Processes

// Every process libksysguard's process model sees, read after each of its
// scans. The model scans /proc every two seconds and its plugins may run
// helpers of their own, so it only exists while the scan is active. Its first
// scan, made with it, has each process's memory; a share of the CPU or a GPU
// is the time a process used it between two scans, so that comes with the
// second.
QtObject {
    id: scan

    property bool active: true
    // The attributes to ask for, given those offered, and how to make one
    // process from a row of their values.
    property var attributes: Processes.attributes
    property var reading: Processes.reading

    readonly property var model: instantiator.object
    // The attributes the model took; none where it offers too few.
    readonly property var columns: model ? Array.from(model.enabledAttributes) : []
    property var processes: []
    // Set once the scans that bring readings have run, so a list with none
    // to show stops waiting.
    property bool scanned: false

    function refresh() {
        // The instantiator's object, which a binding to it may not have
        // caught up with as the model is made.
        const model = instantiator.object as Process.ProcessDataModel;
        if (!model) {
            return;
        }
        // The columns are the attributes the model took, in order.
        const columns = Array.from(model.enabledAttributes);
        const n = model.rowCount();
        const found = [];
        for (let r = 0; r < n; ++r) {
            const values = [];
            for (let c = 0; c < columns.length; ++c) {
                values.push(model.data(model.index(r, c), Process.ProcessDataModel.Value));
            }
            found.push(reading(columns, values));
        }
        processes = found;
    }

    property Instantiator instantiator: Instantiator {
        active: scan.active

        Process.ProcessDataModel {
            id: processModel
            // The model drops an attribute it lacks but then lists it as
            // offered, so the choice is made before asking.
            enabledAttributes: scan.attributes(processModel.availableAttributes)
        }

        // The model's first scan runs as it is made, so it is read here.
        onObjectAdded: {
            scan.scanned = false;
            scan.refresh();
            scan.secondScan.restart();
        }
        onObjectRemoved: {
            scan.secondScan.stop();
            scan.processes = [];
        }
    }

    // Each scan as soon as it lands, read once however many rows it changed.
    property Connections scans: Connections {
        target: scan.model
        function onModelReset() { Qt.callLater(scan.refresh); }
        function onRowsInserted() { Qt.callLater(scan.refresh); }
        function onRowsRemoved() { Qt.callLater(scan.refresh); }
        function onDataChanged() { Qt.callLater(scan.refresh); }
    }

    // The model's timer starts a moment before its first scan, and a tick
    // less than two seconds after the last scan scans nothing, so its first
    // tick often goes by and the second scan waits until four seconds.
    // Asked for its attributes again just after two seconds, the model scans
    // then, unless a tick just has; either way the readings are in.
    property Timer secondScan: Timer {
        interval: 2250
        onTriggered: {
            if (scan.model) {
                scan.model.enabledAttributes = scan.attributes(scan.model.availableAttributes);
            }
            scan.refresh();
            scan.scanned = true;
        }
    }
}
