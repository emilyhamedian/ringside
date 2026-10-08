// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import "../../package/contents/ui"
import "../../package/contents/ui/config"
import "../../package/contents/ui/code/items.js" as Items

// The settings pages load with their cfg_ properties set and without a
// script error, and each takes every setting in main.xml, and its Default,
// the way Plasma's settings dialog hands them over, keeping the reports the
// widget writes meanwhile through Apply, including what the widget writes
// in answer to Apply itself. Reading main.xml, config.qml and the pages
// needs QML_XHR_ALLOW_FILE_READ=1, which scripts/test.sh sets.
// Outside Plasma there is no Plasmoid, so the pages see no hardware report
// unless a test hands them a stand-in for the configuration. The
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

    // Plasma 6.4's dialog, as far as a page can tell: a root with
    // isConfigurationChanged() over a Kirigami page stack the page is pushed
    // onto, as AppletConfiguration.qml does.
    Component {
        id: comparingDialog
        Item {
            property alias pageStack: app.pageStack
            function isConfigurationChanged() { return false; }
            Kirigami.ApplicationItem {
                id: app
                anchors.fill: parent
            }
        }
    }

    // The widget's Claude and Codex readings, polled from the stub report
    // tst_usage uses, on the stand-in configuration a test hands over.
    Component {
        id: usageComponent
        UsageData {
            helperPath: decodeURIComponent(Qt.resolvedUrl("data/fake-usage-ok.py").toString().replace(/^file:\/\//, ""))
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

        // Stand-ins for Plasmoid.configuration made by fakeConfiguration().
        property var fakes: []

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop|Setting initial properties failed/);
        }

        function cleanup() {
            fakes.forEach(fake => fake.destroy());
            fakes = [];
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
        // to AI Providers; General and Sensors show nothing about either.
        function test_providerSettingsLeftTheOldPages() {
            for (const page of [make(general), make(sensors)]) {
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

        // Every <entry> in main.xml as { name, type, value }, the value being
        // the default, as Plasma's dialog would hand a page.
        function entries() {
            const xml = read("../../package/contents/config/main.xml");
            const pattern = /<entry name="(\w+)" type="(\w+)">([\s\S]*?)<\/entry>/g;
            const list = [];
            for (let m = pattern.exec(xml); m; m = pattern.exec(xml)) {
                const text = (/<default>([^<]*)<\/default>/.exec(m[3]) || ["", ""])[1];
                list.push({ name: m[1], type: m[2],
                            value: m[2] === "Int" || m[2] === "Double" ? Number(text)
                                 : m[2] === "Bool" ? text === "true"
                                 : m[2] === "StringList" ? text.split(",").filter(s => s)
                                 : text });
            }
            verify(list.length > 0, "main.xml lists no entry");
            return list;
        }

        function settings() {
            const values = {};
            for (const entry of entries()) {
                values[entry.name] = entry.value;
            }
            return values;
        }

        // The pages' sources, as config.qml lists them.
        function pages() {
            const config = read("../../package/contents/config/config.qml");
            const pattern = /source: "([^"]+)"/g;
            const list = [];
            for (let m = pattern.exec(config); m; m = pattern.exec(config)) {
                list.push(m[1]);
            }
            verify(list.length > 0, "config.qml lists no page");
            return list;
        }

        function pageComponent(source) {
            const component = Qt.createComponent(Qt.resolvedUrl("../../package/contents/ui/" + source));
            compare(component.status, Component.Ready, source + ": " + component.errorString());
            return component;
        }

        // What Plasma's dialog hands a page: a title and a cfg_ property for
        // every key in Plasmoid.configuration.keys(), which lists each entry
        // and its Default.
        function handed(values) {
            const props = { title: "Page" };
            for (const key in values) {
                props["cfg_" + key] = values[key];
                props["cfg_" + key + "Default"] = values[key];
            }
            return props;
        }

        // A stand-in for Plasmoid.configuration, as KConfigPropertyMap looks
        // to the pages and the dialog: keys() lists each entry's Default and
        // then the entry, in main.xml's order, as loadConfig() inserts them;
        // a value that changes rings valueChanged; and writeConfig() saves
        // the entries, never the Defaults, into file.
        function fakeConfiguration(values) {
            const names = Object.keys(values);
            const keys = names.map(n => [n + "Default", n]).reduce((all, pair) => all.concat(pair), []);
            let source = "import QtQuick\nQtObject {\n    id: fake\n"
                + "    signal valueChanged(string key, var value)\n"
                + "    property var file: ({})\n"
                + "    function keys() { return " + JSON.stringify(keys) + "; }\n"
                + "    function writeConfig() {\n        const saved = {};\n"
                + "        for (const name of " + JSON.stringify(names) + ") {\n            saved[name] = fake[name];\n        }\n"
                + "        file = saved;\n    }\n";
            for (const name of names) {
                source += "    property var " + name + "\n    property var " + name + "Default\n"
                        + "    on" + name[0].toUpperCase() + name.slice(1) + "Changed: valueChanged(\"" + name + "\", " + name + ")\n";
            }
            const fake = Qt.createQmlObject(source + "}\n", root, "FakeConfiguration.qml");
            for (const name of names) {
                fake[name] = values[name];
                fake[name + "Default"] = values[name];
            }
            fakes.push(fake);
            return fake;
        }

        // Plasma's dialog on a page, as plasma-desktop's AppletConfiguration.qml
        // has it, in its three shapes. Every version connects the page's cfg_
        // change signals: 6.0 to 6.3 ("plasma60") turn Apply on at any of
        // them, 6.4 and later only when changed() finds a copy that differs
        // from the live value. On Apply, 6.0 to 6.3 write the cfg_ copies
        // back, save, then call the page's saveConfig(), found with
        // hasOwnProperty; 6.4.0 ("plasma64") calls it first, found the same
        // way; 6.4.2 and later ("plasma67") find it as a truthy property.
        function dialog(page, config, order) {
            const d = { signals: 0, applyEnabled: false };
            d.changed = () => config.keys().some(key => {
                const cfgKey = "cfg_" + key;
                if (!page.hasOwnProperty(cfgKey)) {
                    return false;
                }
                return config[key] != page[cfgKey] && config[key].toString() != page[cfgKey].toString();
            });
            config.keys().forEach(key => {
                const changed = page["cfg_" + key + "Changed"];
                if (changed) {
                    changed.connect(() => {
                        ++d.signals;
                        d.applyEnabled = order === "plasma60" ? true : d.changed();
                    });
                }
            });
            d.writeBack = () => {
                config.keys().forEach(key => {
                    const cfgKey = "cfg_" + key;
                    if (cfgKey in page) {
                        config[key] = page[cfgKey];
                    }
                });
                config.writeConfig();
            };
            d.apply = () => {
                if (order === "plasma60") {
                    d.writeBack();
                    if (page.hasOwnProperty("saveConfig")) {
                        page.saveConfig();
                    }
                } else if (order === "plasma64") {
                    if (page.hasOwnProperty("saveConfig")) {
                        page.saveConfig();
                    }
                    d.writeBack();
                } else {
                    if (page.saveConfig) {
                        page.saveConfig();
                    }
                    d.writeBack();
                }
                d.applyEnabled = false;
            };
            return d;
        }

        // A page opened on the stand-in with Plasma's full property set, as
        // the dialog builds it: a cfg_ property per key, from the
        // configuration as it stands. Under 6.4 and later the page sits on
        // the dialog's page stack, where it can find the dialog's root. The
        // page is made here and pushed as an item: pushed as a component,
        // Kirigami would make it under a plain object and Qt would warn that
        // it isn't in the scene, as it does under Plasma's dialog too.
        function open(source, config, order) {
            const props = { title: "Page", live: config };
            config.keys().forEach(key => { props["cfg_" + key] = config[key]; });
            let page;
            if (order === "plasma60") {
                page = createTemporaryObject(pageComponent(source), root, props);
            } else {
                const host = createTemporaryObject(comparingDialog, root, { width: root.width, height: root.height });
                page = createTemporaryObject(pageComponent(source), host, props);
                host.pageStack.push(page);
            }
            verify(page, source);
            return page;
        }

        // The widget's Claude and Codex readings on the stand-in, polled from
        // the items the stand-in switches on, as Monitor.qml polls them.
        function usageOn(config) {
            const usage = createTemporaryObject(usageComponent, root, { config: config });
            verify(usage);
            usage.providers = Qt.binding(() => Items.enabled(config.itemOrder, config.hiddenItems).filter(Items.isUsage));
            return usage;
        }

        // The reports the widget writes, as ConfigPage names them.
        function reports() {
            return Array.from(createTemporaryObject(pageComponent(pages()[0]), root).reports);
        }

        // Plasma's dialog warns about every key a page lacks, so each page
        // declares all of them, and their Defaults, through ConfigPage: typed
        // as main.xml types them, nothing main.xml lacks, and no declaration
        // of a page's own. Each setting is then edited by one page, and the
        // reports by none.
        function test_everyPageDeclaresEverySetting() {
            const types = { Int: "int", Bool: "bool", Double: "real", String: "string", StringList: "var" };
            const expected = {};
            for (const entry of entries()) {
                verify(entry.type in types, entry.name + " has a type this test doesn't know: " + entry.type);
                expected[entry.name] = types[entry.type];
                expected[entry.name + "Default"] = types[entry.type];
            }
            const declared = {};
            const base = read("../../package/contents/ui/config/ConfigPage.qml");
            const pattern = /^\s*property (\w+) cfg_(\w+)/gm;
            for (let m = pattern.exec(base); m; m = pattern.exec(base)) {
                declared[m[2]] = m[1];
            }
            for (const key in expected) {
                compare(declared[key], expected[key], "cfg_" + key + " in ConfigPage.qml");
            }
            for (const key in declared) {
                verify(key in expected, "ConfigPage.qml declares cfg_" + key + ", which main.xml lacks");
            }
            const texts = {};
            for (const source of pages()) {
                const text = read("../../package/contents/ui/" + source);
                texts[source] = text;
                verify(/^ConfigPage \{/m.test(text), source + " isn't rooted on ConfigPage");
                verify(!/property \w+ cfg_/.test(text), source + " declares a cfg_ property of its own");
                const page = createTemporaryObject(pageComponent(source), root);
                for (const key in expected) {
                    verify(("cfg_" + key) in page, source + " lacks cfg_" + key);
                    verify(page.hasOwnProperty("cfg_" + key), source + " doesn't own cfg_" + key);
                }
            }
            const written = reports();
            for (const entry of entries()) {
                const owners = pages().filter(source => new RegExp("\\bcfg_" + entry.name + "\\b").test(texts[source]));
                compare(owners.length, written.includes(entry.name) ? 0 : 1, entry.name + " is edited by " + JSON.stringify(owners));
            }
        }

        // Each page, created as Plasma's dialog creates it, takes every key
        // and Default without a warning (init() fails the test on one) and
        // holds each as the type main.xml gives it. Outside Plasma, with no
        // live configuration, a report's copy keeps what it was handed.
        function test_pagesTakePlasmasProperties_data() {
            return pages().map(source => ({ tag: source, source: source }));
        }
        function test_pagesTakePlasmasProperties(data) {
            const page = createTemporaryObject(pageComponent(data.source), root, handed(settings()));
            verify(page);
            for (const entry of entries()) {
                for (const key of [entry.name, entry.name + "Default"]) {
                    compare(JSON.stringify(page["cfg_" + key]), JSON.stringify(entry.value), "cfg_" + key);
                    compare(typeof page["cfg_" + key], typeof entry.value, "cfg_" + key);
                }
            }
            compare(page.cfg_knownLimits, "");
        }

        function orders(rows) {
            const all = [];
            for (const order of ["plasma60", "plasma64", "plasma67"]) {
                for (const row of rows) {
                    all.push(Object.assign({}, row, { tag: order + "/" + row.tag, order: order }));
                }
            }
            return all;
        }

        // A report the widget writes while a page is open reaches the page's
        // copy at once and is what Apply saves, whichever order the dialog
        // saves in. Under 6.4 and later the report leaves Apply to the page's
        // own changes; 6.0 to 6.3 turn Apply on at the copy's change signal,
        // and their Apply then saves what is stored already.
        function test_runtimeReportSurvivesApply_data() {
            const rows = [];
            for (const source of pages()) {
                for (const key of reports()) {
                    rows.push({ tag: source.replace(/^config\/Config|\.qml$/g, "") + "/" + key, source: source, key: key });
                }
            }
            return orders(rows);
        }
        function test_runtimeReportSurvivesApply(data) {
            const config = fakeConfiguration(settings());
            const page = open(data.source, config, data.order);
            const d = dialog(page, config, data.order);
            const report = JSON.stringify({ written: "while the page was open" });
            config[data.key] = report;
            compare(page["cfg_" + data.key], report, "the page's copy after the report");
            compare(d.applyEnabled, data.order === "plasma60", "Apply after the report");
            d.apply();
            compare(config[data.key], report, "the configuration after Apply");
            compare(config.file[data.key], report, "the file after Apply");
            compare(page["cfg_" + data.key], report, "the page's copy after Apply");
            verify(!d.changed(), "Apply would stay enabled");
        }

        // Under 6.4 and later, a setting changed and changed back after a
        // report arrived leaves Apply off, as the report's copy is current.
        // 6.0 to 6.3 turn Apply on at any cfg_ change signal, whatever the
        // value, and this change keeps that as it was.
        function test_restoredSettingLeavesApplyOff_data() {
            return orders([{ tag: "General" }]);
        }
        function test_restoredSettingLeavesApplyOff(data) {
            const config = fakeConfiguration(settings());
            const page = open("config/ConfigGeneral.qml", config, data.order);
            const d = dialog(page, config, data.order);
            const status = JSON.stringify({ claude: { status: "ok" } });
            config.usageStatus = status;
            compare(page.cfg_usageStatus, status);
            page.cfg_fahrenheit = true;
            verify(d.applyEnabled, "the change left Apply off");
            page.cfg_fahrenheit = false;
            compare(d.applyEnabled, data.order === "plasma60", "Apply after the change was undone");
        }

        // Apply writes the settings back one by one, and the widget answers
        // some of them with a report: the inner-ring choices with knownLimits,
        // and the items switched on with usageStatus, each written back after
        // its answer in main.xml's order. The answer lands during Apply, the
        // open page shows it, Apply ends off, and the next Apply saves it.
        function test_applyKeepsTheWidgetsAnswer_data() {
            return orders([
                { tag: "limitPickedBackToAutomatic", source: "config/ConfigProviders.qml",
                  // Haiku was picked earlier and is no longer reported.
                  before: { claudeInnerLimit: "Haiku" }, key: "claudeInnerLimit", value: "",
                  report: "knownLimits",
                  answer: JSON.stringify({ claude: [{ id: "Fable", label: "Fable", reported: true }], codex: [] }) },
                { tag: "bothItemsSwitchedOff", source: "config/ConfigItems.qml",
                  before: {}, key: "hiddenItems", value: ["disk", "claude", "codex"],
                  report: "usageStatus", answer: JSON.stringify({ helperError: "" }) }
            ]);
        }
        function test_applyKeepsTheWidgetsAnswer(data) {
            const values = Object.assign(settings(), { itemOrder: Items.SYSTEM.concat(Items.USAGE), hiddenItems: ["disk"] },
                                         data.before);
            const config = fakeConfiguration(values);
            const usage = usageOn(config);
            compare(usage.providers, ["claude", "codex"]);
            tryVerify(() => config.knownLimits !== "" && config.usageStatus !== "", 10000, "no report from the stub");
            compare(JSON.parse(config.knownLimits).claude.map(l => l.id), data.before.claudeInnerLimit ? ["Fable", "Haiku"] : ["Fable"]);
            compare(JSON.parse(config.usageStatus).codex.status, "ok");

            const page = open(data.source, config, data.order);
            const d = dialog(page, config, data.order);
            if (data.report === "knownLimits") {
                verify(page.limitChoices("claude").some(c => c.text === "Haiku (not reported)"), "the picker offers the old choice");
            } else {
                compare(page.hints.claude, "Signed in");
            }
            page["cfg_" + data.key] = data.value;
            verify(d.applyEnabled, "the change left Apply off");
            d.apply();
            compare(JSON.stringify(config[data.key]), JSON.stringify(data.value), "the change after Apply");
            tryCompare(config, data.report, data.answer, 5000, "the widget's answer in the configuration");
            compare(page["cfg_" + data.report], data.answer, "the page's copy after the answer");
            if (data.report === "knownLimits") {
                verify(!page.limitChoices("claude").some(c => /not reported/.test(c.text)), "the picker still offers the old choice");
            } else {
                compare(usage.providers, []);
                compare(page.hints.claude, "Shows while Claude Code is signed in");
            }
            verify(!d.applyEnabled, "the widget's answer enabled Apply");
            d.apply();
            compare(config[data.report], data.answer, "the configuration after the next Apply");
            compare(config.file[data.report], data.answer, "the file after the next Apply");
        }

        // A change made on a page is saved, alongside a report written
        // meanwhile; everything else, the Defaults included, is as it was,
        // and nothing reaches the file under a Default's name.
        function test_applySavesTheChange_data() {
            return orders([
                { tag: "General", source: "config/ConfigGeneral.qml", key: "updateInterval", value: 2000 },
                { tag: "Items", source: "config/ConfigItems.qml", key: "ringsOnly", value: ["cpu"] },
                { tag: "Sensors", source: "config/ConfigSensors.qml", key: "diskDevice", value: "sda" },
                { tag: "Providers", source: "config/ConfigProviders.qml", key: "usageRefreshMinutes", value: 10 }
            ]);
        }
        function test_applySavesTheChange(data) {
            const config = fakeConfiguration(settings());
            const page = open(data.source, config, data.order);
            const d = dialog(page, config, data.order);
            page["cfg_" + data.key] = data.value;
            verify(d.signals > 0, "the change rang no cfg_ change signal");
            verify(d.applyEnabled, "the change left Apply off");
            const status = JSON.stringify({ claude: { status: "ok" } });
            config.usageStatus = status;
            compare(page.cfg_usageStatus, status);
            verify(d.applyEnabled, "the report turned Apply off");
            d.apply();
            compare(JSON.stringify(config[data.key]), JSON.stringify(data.value), "the configuration after Apply");
            compare(JSON.stringify(config.file[data.key]), JSON.stringify(data.value), "the file after Apply");
            compare(config.usageStatus, status);
            compare(config.file.usageStatus, status);
            for (const entry of entries()) {
                if (entry.name !== data.key && entry.name !== "usageStatus") {
                    compare(JSON.stringify(config.file[entry.name]), JSON.stringify(entry.value), entry.name);
                }
                compare(JSON.stringify(config[entry.name + "Default"]), JSON.stringify(entry.value), entry.name + "Default");
                verify(!((entry.name + "Default") in config.file), entry.name + "Default reached the file");
            }
            verify(!d.changed(), "Apply would stay enabled");
        }

        // The hints read the reports as the widget writes them.
        function test_pagesFollowTheReports_data() {
            return orders([{ tag: "pages" }]);
        }
        function test_pagesFollowTheReports(data) {
            const config = fakeConfiguration(settings());
            const items = open("config/ConfigItems.qml", config, data.order);
            const sensors = open("config/ConfigSensors.qml", config, data.order);
            const providers = open("config/ConfigProviders.qml", config, data.order);
            config.usageStatus = JSON.stringify({ claude: { status: "ok" } });
            config.detectedHardware = JSON.stringify({ root: { disk: "nvme0n1" } });
            config.knownLimits = JSON.stringify({ claude: [{ id: "opus", label: "Opus", reported: true }] });
            tryVerify(() => items.hints.claude === "Signed in", 5000);
            tryCompare(sensors, "rootDisk", "nvme0n1");
            tryCompare(providers, "claudeHasLimits", true);
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

        // The inner-limit pickers read knownLimits from the page; these rows
        // set that property directly, and test_pagesFollowTheReports covers
        // the live path.
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
