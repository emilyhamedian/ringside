// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import org.kde.ksysguard.sensors as Sensors
import "../../package/contents/ui/config"

// The three settings pages load with their cfg_ properties set and without a
// script error. Outside Plasma there is no Plasmoid, so the pages see no
// hardware report. The Sensors page builds its pickers from a fixed sensor
// list here rather than from this machine's ksystemstats, whose sensors
// depend on the hardware, udisks and the network the tests run with. One
// test reads the real tree, and skips where it lists nothing to read.

Item {
    id: root
    width: 660
    height: 560

    // A bare qml runtime has no KI18n; the pages find these on the root.
    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }
    function i18n(text, ...args) { return substitute(text, args); }
    function i18nc(context, text, ...args) { return substitute(text, args); }
    function i18np(s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }
    function i18ncp(c, s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }

    Component {
        id: general
        ConfigGeneral {
            width: root.width
            height: root.height
            cfg_updateInterval: 1000
            cfg_historySeconds: 60
            cfg_networkBits: true
            cfg_highlightTemperatures: true
            cfg_warmCelsius: 75
            cfg_hotCelsius: 90
            cfg_usageRefreshMinutes: 5
        }
    }

    Component {
        id: items
        ConfigItems {
            width: root.width
            height: root.height
            cfg_itemOrder: ["cpu", "gpu", "memory", "network", "disk"]
            cfg_hiddenItems: ["disk"]
        }
    }

    Component {
        id: sensors
        ConfigSensors {
            width: root.width
            height: root.height
        }
    }

    // This machine's sensor tree, walked directly rather than through the
    // page, to tell whether it lists anything for the page to read.
    Sensors.SensorTreeModel {
        id: tree
    }

    // What ksystemstats' sensor tree might list, as the Sensors page reads
    // it: an "all" group to skip, names to fall back from, a temperature's
    // unit to drop, a network connection named apart from its interface, a
    // whole disk, and a volume that reports free space.
    readonly property string volume: "0f3c6a1e-9b2d-4c55-8e7f-3a1b2c4d5e6f"
    readonly property var listed: [
        { id: "lmsensors/k10temp-pci-00c3/temp1", name: "Tctl (°C)", groupName: "k10temp-pci-00c3" },
        { id: "lmsensors/acpitz-acpi-0/temp1", name: "", groupName: "" },
        { id: "network/all/download", name: "Download Rate", groupName: "All Network Devices" },
        { id: "network/enp5s0/download", name: "Download Rate", groupName: "enp5s0" },
        { id: "network/wlp9s0/download", name: "Download Rate", groupName: "Home Wi-Fi" },
        { id: "disk/all/free", name: "Free Space", groupName: "All Disks" },
        { id: "disk/all/read", name: "Read Rate", groupName: "All Disks" },
        { id: "disk/nvme0n1/read", name: "Read Rate", groupName: "1 TB Internal Drive" },
        { id: "disk/sda/read", name: "Read Rate", groupName: "" },
        { id: "disk/" + volume + "/free", name: "Free Space", groupName: "Home" },
        { id: "disk/" + volume + "/read", name: "Read Rate", groupName: "Home" }
    ]
    readonly property var found: ({
        temperatures: [{ text: "k10temp-pci-00c3 · Tctl", value: "lmsensors/k10temp-pci-00c3/temp1" },
                       { text: "acpitz-acpi-0 · temp1", value: "lmsensors/acpitz-acpi-0/temp1" }],
        interfaces: [{ text: "enp5s0", value: "enp5s0" }, { text: "Home Wi-Fi (wlp9s0)", value: "wlp9s0" }],
        devices: [{ text: "1 TB Internal Drive (nvme0n1)", value: "nvme0n1" }, { text: "sda", value: "sda" }],
        volumes: [{ text: "Home", value: volume }]
    })
    // Each picker's values for that list. Without a hardware report the GPU
    // pickers offer only their fixed choices.
    readonly property var pickers: [
        { name: "CPU temperature", setting: "cfg_cpuTemperatureSensor",
          values: ["", "cpu/all/maximumTemperature", "cpu/all/averageTemperature",
                   "lmsensors/k10temp-pci-00c3/temp1", "lmsensors/acpitz-acpi-0/temp1"] },
        { name: "GPU on the outer ring", setting: "cfg_outerGpu", values: ["", "none"] },
        { name: "GPU on the inner ring", setting: "cfg_innerGpu", values: ["", "none"] },
        { name: "Network interface", setting: "cfg_networkInterface", values: ["", "enp5s0", "wlp9s0"] },
        { name: "Disk activity", setting: "cfg_diskDevice", values: ["", "all", "nvme0n1", "sda"] },
        { name: "Free space on", setting: "cfg_diskVolume", values: ["", volume] },
        { name: "Disk temperature", setting: "cfg_diskTemperatureSensor",
          values: ["", "none", "lmsensors/k10temp-pci-00c3/temp1", "lmsensors/acpitz-acpi-0/temp1"] }
    ]

    TestCase {
        name: "Config"
        when: windowShown

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
        }

        function make(component, properties) {
            const page = createTemporaryObject(component, root, properties);
            verify(page);
            waitForRendering(page);
            return page;
        }

        function find(item, pred) {
            if (pred(item)) return item;
            for (let i = 0; i < item.children.length; ++i) {
                const r = find(item.children[i], pred);
                if (r) return r;
            }
            return null;
        }
        function combo(page, name) {
            return find(page, i => i.Accessible && i.Accessible.name === name);
        }

        function test_general_data() {
            return [
                { tag: "celsius", fahrenheit: false },
                { tag: "fahrenheit", fahrenheit: true }
            ];
        }
        function test_general(data) {
            make(general, { cfg_fahrenheit: data.fahrenheit });
        }

        function test_items_data() {
            return [
                { tag: "defaults", ringsOnly: [] },
                { tag: "ringsOnly", ringsOnly: ["cpu", "memory"] }
            ];
        }
        function test_items(data) {
            make(items, { cfg_ringsOnly: data.ringsOnly });
        }

        // Each picker offers its fixed choices and what the list gives it, and
        // shows the stored value as selected. Stored ids that the list doesn't
        // offer stay listed as they are.
        function test_sensors_data() {
            return [
                { tag: "automatic", stored: {} },
                { tag: "offered", stored: { cfg_cpuTemperatureSensor: "lmsensors/k10temp-pci-00c3/temp1",
                                            cfg_outerGpu: "none", cfg_innerGpu: "",
                                            cfg_networkInterface: "wlp9s0", cfg_diskDevice: "sda",
                                            cfg_diskVolume: root.volume,
                                            cfg_diskTemperatureSensor: "lmsensors/acpitz-acpi-0/temp1" } },
                { tag: "notOffered", stored: { cfg_cpuTemperatureSensor: "lmsensors/k10temp-pci-00c3/temp2",
                                               cfg_outerGpu: "gpu9", cfg_innerGpu: "none",
                                               cfg_networkInterface: "wlp8s0", cfg_diskDevice: "sdz",
                                               cfg_diskVolume: "all", cfg_diskTemperatureSensor: "none" } }
            ];
        }
        function test_sensors(data) {
            const page = make(sensors, Object.assign({ listed: root.listed }, data.stored));
            compare(page.found, root.found);
            for (const p of root.pickers) {
                const stored = data.stored[p.setting] || "";
                const values = p.values.includes(stored) ? p.values : p.values.concat([stored]);
                const picker = combo(page, p.name);
                compare(picker.entries.map(e => e.value), values, p.name);
                compare(picker.currentIndex, values.indexOf(stored), p.name);
            }
        }

        // What the page takes from the sensor tree.
        function test_offeredSensors_data() {
            return [
                { tag: "temperature", id: "lmsensors/k10temp-pci-00c3/temp1", offered: true },
                { tag: "interface", id: "network/wlp9s0/download", offered: true },
                { tag: "disk", id: "disk/nvme0n1/read", offered: true },
                { tag: "volume", id: "disk/5e1f0c2a-7b3d-4c8e-9a61-2d4b8f0e3c17/free", offered: true },
                { tag: "otherReading", id: "network/wlp9s0/upload", offered: false },
                { tag: "fan", id: "lmsensors/nct6798-isa-0290/fan1", offered: false },
                { tag: "cpu", id: "cpu/all/usage", offered: false },
                { tag: "branch", id: "", offered: false },
                { tag: "group", id: "network/(?!all).*/download", offered: false },
                { tag: "nested", id: "disk/nvme0n1/extra/read", offered: false }
            ];
        }
        function test_offeredSensors(data) {
            compare(make(sensors).offered(data.id), data.offered);
        }

        // Outside tests the list is what collect() last read from the tree.
        function test_sensorsFromTheTree() {
            const page = make(sensors);
            page.fromTree = root.listed;
            compare(page.found, root.found);
        }

        // The ids in this machine's sensor tree that the page offers.
        function offeredInTree(page) {
            const ids = [];
            const walk = parent => {
                const count = parent ? tree.rowCount(parent) : tree.rowCount();
                for (let row = 0; row < count; ++row) {
                    const index = parent ? tree.index(row, 0, parent) : tree.index(row, 0);
                    const id = String(tree.data(index, Sensors.SensorTreeModel.SensorId) || "");
                    if (page.offered(id)) {
                        ids.push(id);
                    }
                    walk(index);
                }
            };
            walk(null);
            return ids;
        }

        // collect() reads the rows the pickers use from the real tree, once
        // ksystemstats answers. What it lists depends on the machine: a
        // container may have no sensors, network devices or disks for it.
        function test_sensorsReadFromTheTree() {
            const page = make(sensors);
            const deadline = Date.now() + 10000;
            while (offeredInTree(page).length === 0 && Date.now() < deadline) {
                wait(50);
            }
            if (offeredInTree(page).length === 0) {
                skip("ksystemstats lists no temperature, network or disk sensor here, or isn't reachable");
            }
            tryVerify(() => page.fromTree.length > 0, 10000, "the page read nothing from the tree");
            for (const row of Array.from(page.fromTree)) {
                compare(Object.keys(row).sort(), ["groupName", "id", "name"], JSON.stringify(row));
                for (const key of ["id", "name", "groupName"]) {
                    compare(typeof row[key], "string", key + " of " + JSON.stringify(row));
                }
                verify(page.offered(row.id), row.id);
            }
        }

        // The inner-limit pickers read Plasmoid.configuration.knownLimits;
        // tests substitute it directly, since there's no live Plasmoid to fake.
        function test_innerLimitPickers_data() {
            return [
                { tag: "hiddenWithoutKnownLimits",
                  known: {}, claudeChoice: "", codexChoice: "",
                  claudeVisible: false, codexVisible: false },
                { tag: "entriesFromKnownLimits",
                  known: { claude: [{ id: "opus", label: "Opus", reported: true }], codex: [] },
                  claudeChoice: "", codexChoice: "",
                  claudeVisible: true, codexVisible: false,
                  claudeEntries: [{ text: "Automatic", value: "" }, { text: "None", value: "none" },
                                  { text: "Opus", value: "opus" }] },
                { tag: "notReportedSuffix",
                  known: { claude: [{ id: "old", label: "Old Model", reported: false }] },
                  claudeChoice: "old", codexChoice: "",
                  claudeVisible: true, codexVisible: false,
                  claudeEntries: [{ text: "Automatic", value: "" }, { text: "None", value: "none" },
                                  { text: "Old Model (not reported)", value: "old" }] },
                { tag: "storedChoiceShownWithoutKnownLimits",
                  known: {}, claudeChoice: "bogus", codexChoice: "",
                  claudeVisible: true, codexVisible: false }
            ];
        }
        function test_innerLimitPickers(data) {
            const page = make(sensors, { knownLimits: data.known,
                                         cfg_claudeInnerLimit: data.claudeChoice, cfg_codexInnerLimit: data.codexChoice });
            const claude = combo(page, "Claude inner ring");
            const codex = combo(page, "Codex inner ring");
            compare(claude.visible, data.claudeVisible);
            compare(codex.visible, data.codexVisible);
            if (data.claudeEntries) {
                compare(claude.entries.map(e => ({ text: e.text, value: e.value })), data.claudeEntries);
            }
            if (data.claudeChoice === "bogus") {
                // A stored choice that isn't among the choices still shows as selected.
                const index = claude.entries.findIndex(e => e.value === "bogus");
                verify(index >= 0);
                compare(claude.currentIndex, index);
            }
        }

        function test_choosingAnInnerLimitWritesTheValue() {
            const page = make(sensors, { knownLimits: { claude: [{ id: "opus", label: "Opus", reported: true }] } });
            const claude = combo(page, "Claude inner ring");
            const index = claude.entries.findIndex(e => e.value === "opus");
            verify(index >= 0);
            claude.activated(index);
            compare(page.cfg_claudeInnerLimit, "opus");
        }
    }
}
