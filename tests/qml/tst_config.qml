// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import org.kde.ksysguard.sensors as Sensors
import "../../package/contents/ui/config"

// The settings pages load with their cfg_ properties set and without a
// script error, and between them take every setting in main.xml the way
// Plasma's settings dialog hands them over. Reading main.xml and config.qml
// needs QML_XHR_ALLOW_FILE_READ=1, which scripts/test.sh sets. Outside
// Plasma there is no Plasmoid, so the pages see no hardware report. The
// Sensors page builds its pickers from a fixed sensor list here rather than
// from this machine's ksystemstats, whose sensors depend on the hardware,
// udisks and the network the tests run with. One test reads the real tree,
// and skips where it lists nothing to read.

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

    Component {
        id: providers
        ConfigProviders {
            width: root.width
            height: root.height
            cfg_usageRefreshMinutes: 5
        }
    }

    // The AI Providers page with every string about a third longer, as German
    // and the Romance languages often run, and laid out right to left or not.
    // The page finds these functions before the root's, as this component's
    // root is the nearer context object.
    component StretchedProviders: Item {
        id: stretched

        property alias page: page
        property bool mirrored

        function i18n(text, ...args) { return stretch(root.i18n(text, ...args)); }
        function i18nc(context, text, ...args) { return stretch(root.i18nc(context, text, ...args)); }
        function i18np(s, p, n, ...args) { return stretch(root.i18np(s, p, n, ...args)); }
        function i18ncp(c, s, p, n, ...args) { return stretch(root.i18ncp(c, s, p, n, ...args)); }
        function stretch(s) {
            return s + "ß".repeat(Math.round(s.length * 0.35));
        }

        LayoutMirroring.enabled: mirrored
        LayoutMirroring.childrenInherit: true

        ConfigProviders {
            id: page
            anchors.fill: parent
            cfg_usageRefreshMinutes: 15
            knownLimits: ({ claude: [{ id: "opus", label: "Opus", reported: true }],
                            codex: [{ id: "gpt", label: "GPT-5.5-Codex", reported: true }] })
        }
    }

    Component {
        id: stretchedProviders
        StretchedProviders {}
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

        function test_providers() {
            const page = make(providers);
            const every = combo(page, "Check every");
            verify(every.visible);
            compare(every.value, 5);
            every.increase();
            every.valueModified();
            compare(page.cfg_usageRefreshMinutes, 10);
            compare(every.displayText, "10 minutes");
        }

        // How often Claude and Codex are checked and their inner rings moved
        // to AI Providers; General and Sensors keep nothing about either.
        function test_providerSettingsLeftTheOldPages() {
            for (const page of [make(general), make(sensors)]) {
                compare(page.cfg_usageRefreshMinutes, undefined);
                compare(page.cfg_claudeInnerLimit, undefined);
                compare(page.cfg_codexInnerLimit, undefined);
                compare(page.knownLimits, undefined);
                for (const name of ["Check every", "Claude inner ring", "Codex inner ring"]) {
                    compare(combo(page, name), null, name);
                }
                compare(find(page, i => typeof i.text === "string" && /Claude|Codex/.test(i.text)), null);
            }
        }

        function read(path) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl(path), false);
            request.send();
            verify(request.responseText !== "", path + " read; set QML_XHR_ALLOW_FILE_READ=1");
            return request.responseText;
        }

        // Every <entry> in main.xml, with its default as the value Plasma's
        // dialog would hand a page.
        function settings() {
            const xml = read("../../package/contents/config/main.xml");
            const pattern = /<entry name="(\w+)" type="(\w+)">([\s\S]*?)<\/entry>/g;
            const found = {};
            for (let m = pattern.exec(xml); m; m = pattern.exec(xml)) {
                const text = (/<default>([^<]*)<\/default>/.exec(m[3]) || ["", ""])[1];
                found[m[1]] = m[2] === "Int" || m[2] === "Double" ? Number(text)
                            : m[2] === "Bool" ? text === "true"
                            : m[2] === "StringList" ? text.split(",").filter(s => s)
                            : text;
            }
            verify(Object.keys(found).length > 0, "main.xml lists no entry");
            return found;
        }

        function declared(page) {
            const keys = [];
            for (const name in page) {
                if (name.startsWith("cfg_") && typeof page[name] !== "function") {
                    keys.push(name.slice(4));
                }
            }
            return keys;
        }

        // Plasma's dialog hands each page every setting as a cfg_ property
        // and saves back the ones the page declares. So every setting needs
        // exactly one page declaring it with a type its value assigns to, and
        // a page may declare nothing main.xml lacks. The reports the widget
        // writes for the pages are read live, never declared, or Apply would
        // write back the report a page opened with.
        function test_everySettingHasOnePage() {
            const values = settings();
            const reports = ["knownLimits", "usageStatus", "detectedHardware"];
            const config = read("../../package/contents/config/config.qml");
            const pattern = /source: "([^"]+)"/g;
            const owner = {};
            for (let m = pattern.exec(config); m; m = pattern.exec(config)) {
                const component = Qt.createComponent(Qt.resolvedUrl("../../package/contents/ui/" + m[1]));
                compare(component.status, Component.Ready, m[1] + ": " + component.errorString());
                const keys = declared(createTemporaryObject(component, root));
                const handed = {};
                for (const key of keys) {
                    verify(key in values, m[1] + " declares cfg_" + key + ", which main.xml lacks");
                    verify(!reports.includes(key), m[1] + " declares the report cfg_" + key);
                    verify(!(key in owner), "cfg_" + key + " on both " + owner[key] + " and " + m[1]);
                    owner[key] = m[1];
                    handed["cfg_" + key] = values[key];
                }
                const page = createTemporaryObject(component, root, handed);
                for (const key of keys) {
                    compare(JSON.stringify(page["cfg_" + key]), JSON.stringify(values[key]), m[1] + " cfg_" + key);
                }
            }
            const missing = Object.keys(values).filter(key => !reports.includes(key) && !(key in owner));
            compare(missing, [], "settings no page declares");
            for (const key of ["usageRefreshMinutes", "claudeInnerLimit", "codexInnerLimit"]) {
                compare(owner[key], "config/ConfigProviders.qml", key);
            }
        }

        // The dialog's categories, as Plasma's own model reads config.qml.
        // Plasma 6.0 registers that model only inside plasmashell.
        function test_categories() {
            const component = Qt.createComponent(Qt.resolvedUrl("../../package/contents/config/config.qml"));
            if (component.status === Component.Error && /org\.kde\.plasma\.configuration/.test(component.errorString())) {
                skip("org.kde.plasma.configuration isn't importable outside plasmashell here");
            }
            compare(component.status, Component.Ready, component.errorString());
            const model = createTemporaryObject(component, root);
            const rows = [];
            for (let i = 0; i < model.count; ++i) {
                const row = model.get(i);
                rows.push({ name: row.name, icon: row.icon, source: row.source });
            }
            compare(rows, [
                { name: "General", icon: "configure", source: "config/ConfigGeneral.qml" },
                { name: "Panel Items", icon: "view-list-details", source: "config/ConfigItems.qml" },
                { name: "Sensors", icon: "cpu", source: "config/ConfigSensors.qml" },
                { name: "AI Providers", icon: "dialog-messages", source: "config/ConfigProviders.qml" }
            ]);
        }

        function within(page, item) {
            const at = item.mapToItem(page, 0, 0);
            return at.x >= -0.5 && at.x + item.width <= page.width + 0.5;
        }

        // Longer strings wrap inside the page rather than running off it,
        // whether the form has room for labels beside their fields or not,
        // and right to left the labels sit on the right.
        function test_providersStretchedAndMirrored_data() {
            return [
                { tag: "wide", mirrored: false, width: 660 },
                { tag: "wideMirrored", mirrored: true, width: 660 },
                { tag: "narrow", mirrored: false, width: 320 },
                { tag: "narrowMirrored", mirrored: true, width: 320 }
            ];
        }
        function test_providersStretchedAndMirrored(data) {
            const host = createTemporaryObject(stretchedProviders, root,
                                               { mirrored: data.mirrored, width: data.width, height: root.height });
            verify(host);
            waitForRendering(host);
            const page = host.page;
            const texts = [];
            const walk = item => {
                if (!item.visible) {
                    return;
                }
                if (typeof item.text === "string" && item.text !== "" && item.width > 0 && item.contentWidth !== undefined) {
                    texts.push(item);
                }
                for (const child of item.children) {
                    walk(child);
                }
            };
            walk(page);
            verify(texts.length >= 6, "found " + texts.length + " texts");
            for (const text of texts) {
                verify(within(page, text), "runs off the page: " + text.text);
                if (text.elide === Text.ElideNone) {
                    verify(text.contentWidth <= text.width + 0.5, "overflows its line: " + text.text);
                }
            }
            const note = texts.find(t => t.text.startsWith("Automatic shows"));
            verify(note.lineCount > 1, "the inner rings' note wraps");
            for (const name of ["Check every", "Claude inner ring", "Codex inner ring"]) {
                const control = combo(page, host.stretch(name));
                verify(control && control.visible, name);
                verify(within(page, control), name + " runs off the page");
            }
            const form = find(page, i => i.wideMode !== undefined);
            if (form.wideMode) {
                const label = texts.find(t => t.text.startsWith("Check every:"));
                const field = combo(page, host.stretch("Check every"));
                const labelX = label.mapToItem(page, 0, 0).x;
                const fieldX = field.mapToItem(page, 0, 0).x;
                if (data.mirrored) {
                    verify(labelX >= fieldX + field.width, "the label sits right of its field");
                } else {
                    verify(labelX + label.width <= fieldX, "the label sits left of its field");
                }
            } else {
                verify(data.width < 660, "the form went narrow at full width");
            }
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
                  claudeVisible: false, codexVisible: false, noteVisible: false },
                { tag: "entriesFromKnownLimits",
                  known: { claude: [{ id: "opus", label: "Opus", reported: true }], codex: [] },
                  claudeChoice: "", codexChoice: "",
                  claudeVisible: true, codexVisible: false, noteVisible: true,
                  claudeEntries: [{ text: "Automatic", value: "" }, { text: "None", value: "none" },
                                  { text: "Opus", value: "opus" }] },
                { tag: "eachPickerShowsItsOwnChoice",
                  known: { claude: [{ id: "opus", label: "Opus", reported: true }],
                           codex: [{ id: "gpt5", label: "GPT-5", reported: true },
                                   { id: "spark", label: "Spark", reported: true }] },
                  claudeChoice: "opus", codexChoice: "spark",
                  claudeVisible: true, codexVisible: true, noteVisible: true,
                  codexEntries: [{ text: "Automatic", value: "" }, { text: "None", value: "none" },
                                 { text: "GPT-5", value: "gpt5" }, { text: "Spark", value: "spark" }] },
                { tag: "codexOnly",
                  known: { codex: [{ id: "gpt5", label: "GPT-5", reported: true }] },
                  claudeChoice: "", codexChoice: "",
                  claudeVisible: false, codexVisible: true, noteVisible: true },
                { tag: "notReportedSuffix",
                  known: { claude: [{ id: "old", label: "Old Model", reported: false }] },
                  claudeChoice: "old", codexChoice: "",
                  claudeVisible: true, codexVisible: false, noteVisible: true,
                  claudeEntries: [{ text: "Automatic", value: "" }, { text: "None", value: "none" },
                                  { text: "Old Model (not reported)", value: "old" }] },
                { tag: "storedChoiceShownWithoutKnownLimits",
                  known: {}, claudeChoice: "bogus", codexChoice: "",
                  claudeVisible: true, codexVisible: false, noteVisible: true }
            ];
        }
        function test_innerLimitPickers(data) {
            const page = make(providers, { knownLimits: data.known,
                                           cfg_claudeInnerLimit: data.claudeChoice, cfg_codexInnerLimit: data.codexChoice });
            const claude = combo(page, "Claude inner ring");
            const codex = combo(page, "Codex inner ring");
            compare(claude.visible, data.claudeVisible);
            compare(codex.visible, data.codexVisible);
            const note = find(page, i => typeof i.text === "string" && i.text.startsWith("Automatic shows"));
            verify(note);
            compare(note.visible, data.noteVisible);
            if (data.claudeEntries) {
                compare(claude.entries.map(e => ({ text: e.text, value: e.value })), data.claudeEntries);
            }
            if (data.codexEntries) {
                compare(codex.entries.map(e => ({ text: e.text, value: e.value })), data.codexEntries);
            }
            // Each picker selects its own stored choice, even one that isn't
            // among the reported limits.
            for (const [picker, choice] of [[claude, data.claudeChoice], [codex, data.codexChoice]]) {
                const index = picker.entries.findIndex(e => e.value === choice);
                verify(index >= 0);
                compare(picker.currentIndex, index);
            }
        }

        // Each picker writes its own provider's setting and leaves the other's alone.
        function test_choosingAnInnerLimitWritesTheValue_data() {
            return [
                { tag: "claude", name: "Claude inner ring", value: "opus",
                  key: "cfg_claudeInnerLimit", other: "cfg_codexInnerLimit" },
                { tag: "codex", name: "Codex inner ring", value: "gpt5",
                  key: "cfg_codexInnerLimit", other: "cfg_claudeInnerLimit" }
            ];
        }
        function test_choosingAnInnerLimitWritesTheValue(data) {
            const page = make(providers, { knownLimits: { claude: [{ id: "opus", label: "Opus", reported: true }],
                                                          codex: [{ id: "gpt5", label: "GPT-5", reported: true }] } });
            const picker = combo(page, data.name);
            const index = picker.entries.findIndex(e => e.value === data.value);
            verify(index >= 0);
            picker.activated(index);
            compare(page[data.key], data.value);
            compare(page[data.other], "");
        }
    }
}
