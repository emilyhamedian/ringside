// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import org.kde.kitemmodels as KItemModels
import "../code/format.js" as Format

// Which sensors the widget reads. Each setting stores a ksystemstats id, or
// one of the words Monitor.qml understands ("" for automatic, "none", "all").
// The choices come from ksystemstats' sensor tree, which lists sensors
// without subscribing to any, and from the helper's last hardware report.
ConfigPage {
    id: page

    readonly property var hardware: page.report("detectedHardware")
    readonly property var gpus: Array.isArray(hardware.gpus)
        ? hardware.gpus.filter(g => g && typeof g.id === "string" && g.id) : []
    readonly property string cpuSensorLabel: hardware.cpu && hardware.cpu.tempLabel ? String(hardware.cpu.tempLabel) : ""
    readonly property string rootDisk: hardware.root && hardware.root.disk ? String(hardware.root.disk) : ""

    // The sensors a picker can use, as { id, name, groupName } rows: the
    // ksystemstats id and the tree's names for the sensor and its group, ""
    // where the tree gives none. collect() reads them from the tree into
    // fromTree. Not readonly: tests substitute fixed rows, so they don't
    // depend on this machine's sensors.
    property var listed: fromTree
    property var fromTree: []

    // What the sensor tree offers so far, as { text, value } lists.
    readonly property var found: {
        const temperatures = [];
        const interfaces = [];
        const disks = [];
        for (const row of Array.from(listed)) {
            const [kind, group, sensor] = row.id.split("/");
            if (group === "all") {
                continue;
            }
            const groupName = row.groupName || group;
            if (kind === "lmsensors") {
                // The tree appends the unit, "Composite (°C)"; every entry here is a temperature.
                const name = (row.name || sensor).replace(/\s*\([^()]*\)$/, "");
                temperatures.push({ text: groupName + " · " + name, value: row.id });
            } else if (kind === "network") {
                interfaces.push({ text: groupName === group ? group
                                      : i18nc("@item:inlistbox network interface: name (interface)", "%1 (%2)", groupName, group),
                                  value: group });
            } else {
                // Block devices report I/O only; volumes (UUID-named) also report free space.
                let disk = disks.find(d => d.value === group);
                if (!disk) {
                    disk = { name: groupName, value: group, volume: false };
                    disks.push(disk);
                }
                disk.volume = disk.volume || sensor === "free";
            }
        }
        return {
            temperatures: temperatures,
            interfaces: interfaces,
            devices: disks.filter(d => !d.volume).map(d => ({
                text: d.name.includes(d.value) ? d.name
                    : i18nc("@item:inlistbox disk: name (device)", "%1 (%2)", d.name, d.value),
                value: d.value
            })),
            volumes: disks.filter(d => d.volume).map(d => ({ text: d.name, value: d.value }))
        };
    }

    function gpuName(gpu) {
        return Format.gpuModel(gpu.name, "", gpu.pciName, gpu.vendor) || gpu.id;
    }

    function gpuText(gpu) {
        const name = gpuName(gpu);
        // Two identical cards need their ids to tell them apart.
        const shown = gpus.some(g => g !== gpu && gpuName(g) === name) ? name + " · " + gpu.id : name;
        return gpu.kind === "discrete" ? i18nc("@item:inlistbox %1 is a GPU name", "%1 (discrete)", shown)
             : gpu.kind === "integrated" ? i18nc("@item:inlistbox %1 is a GPU name", "%1 (integrated)", shown)
             : shown;
    }

    function collect() {
        const rows = [];
        for (let i = 0; i < matches.count; ++i) {
            const index = matches.index(i, 0);
            rows.push({
                id: String(matches.data(index, Sensors.SensorTreeModel.SensorId)),
                name: String(matches.data(index, Qt.DisplayRole) || ""),
                groupName: String(tree.data(flat.mapToSource(matches.mapToSource(index)).parent, Qt.DisplayRole) || "")
            });
        }
        fromTree = rows;
    }

    // The sensor ids the pickers are built from: temperatures, and one id
    // per network interface and per disk or volume. Branch rows have no id,
    // and "[Group]" rows carry a regex instead of one.
    function offered(id) {
        return !/[\\()*]/.test(id)
            && /^(lmsensors\/[^\/]+\/temp\d+|network\/[^\/]+\/download|disk\/[^\/]+\/(read|free))$/.test(id);
    }

    Sensors.SensorTreeModel {
        id: tree
    }

    // Fills asynchronously once ksystemstats answers.
    KItemModels.KSortFilterProxyModel {
        id: matches
        sourceModel: KItemModels.KDescendantsProxyModel {
            id: flat
            model: tree
        }
        filterRowCallback: (row, parent) => page.offered(String(flat.data(flat.index(row, 0, parent),
                                                                         Sensors.SensorTreeModel.SensorId)))
        onCountChanged: Qt.callLater(page.collect)
        onDataChanged: Qt.callLater(page.collect)
    }

    Kirigami.FormLayout {
        Picker {
            Kirigami.FormData.label: i18nc("@label:listbox", "CPU temperature:")
            Accessible.name: i18nc("@label:listbox", "CPU temperature")
            current: page.cfg_cpuTemperatureSensor
            choices: [
                { text: page.cpuSensorLabel
                      ? i18nc("@item:inlistbox %1 is the sensor's name, such as Tctl", "Automatic: the CPU's own reading (%1)", page.cpuSensorLabel)
                      : i18nc("@item:inlistbox", "Automatic: the CPU's own reading"),
                  value: "" },
                { text: i18nc("@item:inlistbox CPU temperature", "Hottest core"), value: "cpu/all/maximumTemperature" },
                { text: i18nc("@item:inlistbox CPU temperature", "Average of cores"), value: "cpu/all/averageTemperature" }
            ].concat(page.found.temperatures)
            onPicked: value => page.cfg_cpuTemperatureSensor = value
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        Picker {
            Kirigami.FormData.label: i18nc("@label:listbox", "Outer ring:")
            Accessible.name: i18nc("@label:listbox", "GPU on the outer ring")
            current: page.cfg_outerGpu
            choices: [{ text: i18nc("@item:inlistbox", "Automatic"), value: "" }]
                .concat(page.gpus.map(g => ({ text: page.gpuText(g), value: g.id })))
                .concat([{ text: i18nc("@item:inlistbox no GPU on this ring", "None"), value: "none" }])
            onPicked: value => page.cfg_outerGpu = value
        }

        Picker {
            Kirigami.FormData.label: i18nc("@label:listbox", "Inner ring:")
            Accessible.name: i18nc("@label:listbox", "GPU on the inner ring")
            current: page.cfg_innerGpu
            choices: [{ text: i18nc("@item:inlistbox", "Automatic"), value: "" }]
                .concat(page.gpus.map(g => ({ text: page.gpuText(g), value: g.id })))
                .concat([{ text: i18nc("@item:inlistbox no GPU on this ring", "None"), value: "none" }])
            onPicked: value => page.cfg_innerGpu = value
        }

        Note {
            text: i18nc("@info", "Automatic puts a discrete GPU on the outer ring and an integrated one on the inner ring. A discrete GPU that powers down is read only while it is awake.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        Picker {
            Kirigami.FormData.label: i18nc("@label:listbox", "Network:")
            Accessible.name: i18nc("@label:listbox", "Network interface")
            current: page.cfg_networkInterface
            choices: [{ text: i18nc("@item:inlistbox", "All interfaces"), value: "" }].concat(page.found.interfaces)
            onPicked: value => page.cfg_networkInterface = value
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        Picker {
            Kirigami.FormData.label: i18nc("@label:listbox", "Disk activity:")
            Accessible.name: i18nc("@label:listbox", "Disk activity")
            current: page.cfg_diskDevice
            choices: [
                { text: page.rootDisk
                      ? i18nc("@item:inlistbox %1 is a disk device such as nvme0n1", "Automatic: the disk holding / (%1)", page.rootDisk)
                      : i18nc("@item:inlistbox", "Automatic: the disk holding /"),
                  value: "" },
                { text: i18nc("@item:inlistbox", "All disks"), value: "all" }
            ].concat(page.found.devices)
            onPicked: value => page.cfg_diskDevice = value
        }

        Picker {
            Kirigami.FormData.label: i18nc("@label:listbox", "Free space on:")
            Accessible.name: i18nc("@label:listbox", "Free space on")
            current: page.cfg_diskVolume
            choices: [{ text: i18nc("@item:inlistbox", "Automatic: the root file system"), value: "" }]
                .concat(page.found.volumes)
            onPicked: value => page.cfg_diskVolume = value
        }

        Picker {
            Kirigami.FormData.label: i18nc("@label:listbox", "Disk temperature:")
            Accessible.name: i18nc("@label:listbox", "Disk temperature")
            current: page.cfg_diskTemperatureSensor
            // Monitor only looks the sensor up for the disk holding /.
            choices: [
                { text: page.cfg_diskDevice
                      ? i18nc("@item:inlistbox disk temperature", "Automatic: none for the chosen disk")
                      : i18nc("@item:inlistbox disk temperature", "Automatic: the NVMe sensor of the disk holding /"),
                  value: "" },
                { text: i18nc("@item:inlistbox no disk temperature", "None"), value: "none" }
            ].concat(page.found.temperatures)
            onPicked: value => page.cfg_diskTemperatureSensor = value
        }
    }
}
