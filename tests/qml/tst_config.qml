// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
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
            cfg_graphSpan: "minute"
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
        function findAll(item, pred, found = []) {
            if (pred(item)) found.push(item);
            for (let i = 0; i < item.children.length; ++i) {
                findAll(item.children[i], pred, found);
            }
            return found;
        }
        // A form section's heading, which FormLayout draws at level 3.
        function heading(page, text) {
            return find(page, i => i.text === text && i.level === 3);
        }
        // Whether one item sits just under another: starting below it, in
        // the same column.
        function below(item, above) {
            const a = above.mapToItem(null, 0, 0);
            const b = item.mapToItem(null, 0, 0);
            return b.y >= a.y + above.height && b.y - (a.y + above.height) < 30 && Math.abs(b.x - a.x) < 1;
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

        // Graph history: a box that keeps the hour and the day across
        // restarts, off by default, with a line under it saying where they
        // go. Where Qt's LocalStorage module is missing the box is greyed
        // out and the line says what is needed; the setting goes untouched.
        function test_keepGraphHistory_data() {
            return [{ tag: "available", url: Qt.resolvedUrl("../../package/contents/ui/HistoryStore.qml"), available: true,
                      line: "Saved on this computer only. Turning this off deletes it." },
                    { tag: "missing", url: Qt.resolvedUrl("data/MissingStore.qml"), available: false,
                      line: "Needs Qt's LocalStorage module (qml6-module-qtquick-localstorage)." }];
        }
        function test_keepGraphHistory(data) {
            const page = make(general, { storeUrl: data.url, cfg_keepGraphHistory: false });
            compare(page.storeAvailable, data.available);
            const box = find(page, i => i.text === "Keep the last hour and day across restarts" && i.checked !== undefined);
            verify(box && box.visible);
            compare(box.enabled, data.available);
            compare(box.checked, false);
            compare(box.Accessible.description, data.line);
            verify(find(page, i => i.text === data.line && i.visible), "the line under the box");
            verify(!find(page, i => i.Accessible && i.Accessible.name === "Graph history"), "the old Graph history list is gone");
            box.forceActiveFocus();
            keyClick(Qt.Key_Space);
            compare(page.cfg_keepGraphHistory, data.available, "ticked only where it can be kept");
            if (data.available) {
                keyClick(Qt.Key_Space);
                compare(page.cfg_keepGraphHistory, false);
            }
        }

        // A setting left on where the module has since gone shows ticked,
        // and can be switched off, but not on again.
        function test_keepGraphHistoryLeftOnWithoutTheModule() {
            const page = make(general, { storeUrl: Qt.resolvedUrl("data/MissingStore.qml"), cfg_keepGraphHistory: true });
            const box = find(page, i => i.text === "Keep the last hour and day across restarts" && i.checked !== undefined);
            verify(box.enabled);
            verify(box.checked);
            box.forceActiveFocus();
            keyClick(Qt.Key_Space);
            compare(page.cfg_keepGraphHistory, false);
            verify(!box.checked);
            verify(!box.enabled, "greyed out once off");
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
                for (const name of ["Check every", "Claude inner ring", "OpenAI inner ring"]) {
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
        // of a page's own. Each setting is then assigned by one page, and the
        // reports and the graphs' span by none; another page may read it.
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
            // The graphs' span is chosen on a graph's caption, not here.
            const unedited = reports().concat(["graphSpan"]);
            for (const entry of entries()) {
                const owners = pages().filter(source => new RegExp("\\bcfg_" + entry.name + "\\s*=(?!=)").test(texts[source]));
                compare(owners.length, unedited.includes(entry.name) ? 0 : 1, entry.name + " is edited by " + JSON.stringify(owners));
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
                { tag: "GeneralPublicAddress", source: "config/ConfigGeneral.qml", key: "publicAddress", value: true },
                { tag: "GeneralKeepGraphHistory", source: "config/ConfigGeneral.qml", key: "keepGraphHistory", value: true },
                { tag: "GeneralPublicAddressUrl4", source: "config/ConfigGeneral.qml", key: "publicAddressUrl4",
                  value: "https://ip.example.org/" },
                { tag: "Items", source: "config/ConfigItems.qml", key: "ringsOnly", value: ["cpu"] },
                { tag: "Sensors", source: "config/ConfigSensors.qml", key: "diskDevice", value: "sda" },
                { tag: "Providers", source: "config/ConfigProviders.qml", key: "usageRefreshMinutes", value: 10 },
                { tag: "ProvidersCodexMark", source: "config/ConfigProviders.qml", key: "codexMark", value: "openai" },
                { tag: "ProvidersClaudeProgram", source: "config/ConfigProviders.qml", key: "claudeProgram",
                  value: "~/.bun/bin/claude" },
                { tag: "ProvidersCodexProgram", source: "config/ConfigProviders.qml", key: "codexProgram",
                  value: "/opt/my tools/codex" }
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

        // The public address's controls save its keys through Apply: the
        // box, a Custom service's URLs, and ipify.org again as empty URLs.
        function test_applySavesThePublicAddress_data() {
            return orders([{ tag: "General" }]);
        }
        function test_applySavesThePublicAddress(data) {
            const config = fakeConfiguration(settings());
            const page = open("config/ConfigGeneral.qml", config, data.order);
            const d = dialog(page, config, data.order);
            waitForRendering(page);
            const box = find(page, i => i.text === "Show in the Network popup" && i.checked !== undefined);
            box.forceActiveFocus();
            keyClick(Qt.Key_Space);
            const service = combo(page, "Service");
            verify(service.visible, "the service list shows once the box is ticked");
            // Custom, the third choice after ipify.org and Mullvad, from the
            // open list, which moves on to the first URL.
            service.forceActiveFocus();
            keyClick(Qt.Key_Space);
            tryCompare(service.popup, "opened", true);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            tryCompare(service.popup, "visible", false);
            const url4 = combo(page, "IPv4 URL");
            verify(url4.activeFocus, "Custom focuses the IPv4 URL");
            for (const c of "https://ip.example.org/") {
                keyClick(c);
            }
            verify(d.applyEnabled, "the changes left Apply off");
            d.apply();
            compare([config.publicAddress, config.publicAddressUrl4, config.publicAddressUrl6], [true, "https://ip.example.org/", ""]);
            compare([config.file.publicAddress, config.file.publicAddressUrl4, config.file.publicAddressUrl6],
                    [true, "https://ip.example.org/", ""]);
            verify(!d.changed(), "Apply would stay enabled");

            // Up the closed list: Mullvad saves its own pair, then ipify.org none.
            service.forceActiveFocus();
            keyClick(Qt.Key_Up);
            verify(d.applyEnabled, "Mullvad left Apply off");
            d.apply();
            compare([config.file.publicAddress, config.file.publicAddressUrl4, config.file.publicAddressUrl6],
                    [true, "https://ipv4.am.i.mullvad.net/json", "https://ipv6.am.i.mullvad.net/json"]);
            keyClick(Qt.Key_Up);
            verify(d.applyEnabled, "ipify.org left Apply off");
            d.apply();
            compare([config.file.publicAddress, config.file.publicAddressUrl4, config.file.publicAddressUrl6], [true, "", ""]);
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
            const page = host.page;
            // Both Program rows, one with a problem under it.
            showPrograms(page, "broken-claude");
            waitForRendering(host);
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
            for (const name of ["Check every", "Claude inner ring", "OpenAI inner ring", "Path to claude", "Path to codex",
                                "Choose where claude is", "Choose where codex is"]) {
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

        // What the helper reports of each program, and what the user chose,
        // in the mock's five states and the moment before the first report.
        // HOME stands for the home folder.
        function program(path, chosen, problem) {
            return { path: path, chosen: chosen, problem: problem ?? "" };
        }
        function programStates() {
            return {
                found: { claude: "", codex: "", status: {
                    claude: { status: "ok", starter: true, program: program("HOME/.local/bin/claude", false) },
                    codex: { status: "ok", starter: false, program: program("HOME/.local/bin/codex", false) } } },
                "notfound-off": { claude: "", codex: "", status: {
                    claude: { status: "ok", starter: false, program: program("", false) },
                    codex: { status: "error", starter: false, program: program("", false) } } },
                "notfound-on": { claude: "", codex: "", status: {
                    claude: { status: "ok", starter: true, program: program("", false) },
                    codex: { status: "error", starter: false, program: program("", false) } } },
                custom: { claude: "~/.bun/bin/claude", codex: "HOME/.nvm/versions/node/v22.12.0/bin/codex", status: {
                    claude: { status: "ok", starter: true, program: program("HOME/.bun/bin/claude", true) },
                    codex: { status: "ok", starter: false, program: program("HOME/.nvm/versions/node/v22.12.0/bin/codex", true) } } },
                broken: { claude: "/opt/claude-code/claude", codex: "~/.npm-global/bin/codex", status: {
                    claude: { status: "ok", starter: true, program: program("/opt/claude-code/claude", true, "not-executable") },
                    codex: { status: "error", starter: false, program: program("HOME/.npm-global/bin/codex", true, "missing") } } },
                "broken-claude": { claude: "/opt/claude-code/claude", codex: "~/bin/codex", status: {
                    claude: { status: "ok", starter: true, program: program("/opt/claude-code/claude", true, "not-executable") },
                    codex: { status: "ok", starter: false, program: program("HOME/bin/codex", true) } } },
                first: { claude: "", codex: "", status: {} }
            };
        }

        // Puts a page in one of programStates() with both items on and both
        // providers' limits known.
        function showPrograms(page, state, items) {
            const s = JSON.parse(JSON.stringify(programStates()[state]).replace(/HOME/g, page.home));
            page.cfg_itemOrder = ["cpu", "claude", "codex"];
            page.cfg_hiddenItems = items ?? [];
            page.cfg_claudeProgram = s.claude;
            page.cfg_codexProgram = s.codex;
            page.usageStatus = s.status;
            return s;
        }

        function field(page, command) {
            return combo(page, "Path to " + command);
        }
        // The line under a program's row, which sits just under its field,
        // or "" while none shows.
        function noteItem(page, command) {
            const row = field(page, command).parent;
            return find(page, i => i.program === row);
        }
        function programNote(page, command) {
            const note = noteItem(page, command);
            if (note.visible) {
                // Once the form has laid out the row it just showed.
                tryVerify(() => below(note, field(page, command)), 2000, command + "'s note sits under its field");
            }
            return note.visible ? note.text : "";
        }
        function programNoteColor(page, command) {
            return noteItem(page, command).color;
        }

        readonly property string claudeNote: "Only starting sessions needs it. Usage is read without it."
        readonly property string claudeLost: "Not in ~/.local/bin or on Plasma's PATH. Starting sessions needs it; if claude is installed elsewhere, choose it."
        readonly property string codexLost: "Not in ~/.local/bin or on Plasma's PATH, which leaves out what your shell adds. If codex is installed elsewhere, choose it."

        // Which Program rows, notes and Codex settings show in each state.
        // Codex's row shows while its item is on and a path is chosen or
        // codex can't run; its inner ring and logo need codex to run.
        // Claude's shows while its item is on and a path is chosen, or its
        // starter is on and claude isn't found.
        function test_programRows_data() {
            return [
                { tag: "1 found", state: "found", claude: null, codex: null, ring: true, logo: true, openai: true },
                { tag: "2 notfound-off", state: "notfound-off", claude: null, codex: codexLost, ring: false, logo: false,
                  openai: true },
                { tag: "3 notfound-on", state: "notfound-on", claude: claudeLost, codex: codexLost, ring: false, logo: false,
                  openai: true },
                { tag: "4 custom", state: "custom", claude: claudeNote, codex: "", ring: true, logo: true, openai: true },
                { tag: "5 broken", state: "broken", claude: "This file can't be run: it isn't marked executable.",
                  codex: "There is no file at this path.", ring: false, logo: false, openai: true },
                { tag: "before the first report", state: "first", claude: null, codex: null, ring: true, logo: true,
                  openai: true },
                { tag: "items off", state: "broken", items: ["claude", "codex"], claude: null, codex: null, ring: false,
                  logo: false, openai: false },
                { tag: "claude chosen, starter off", state: "custom", starter: false, claude: claudeNote, codex: "",
                  ring: true, logo: true, openai: true }
            ];
        }
        function test_programRows(data) {
            const page = make(providers, { knownLimits: { claude: [{ id: "opus", label: "Opus", reported: true }],
                                                          codex: [{ id: "gpt", label: "GPT-5.5-Codex", reported: true }] } });
            showPrograms(page, data.state, data.items);
            if (data.starter === false) {
                page.usageStatus = Object.assign({}, page.usageStatus,
                                                 { claude: Object.assign({}, page.usageStatus.claude, { starter: false }) });
            }
            waitForRendering(page);
            for (const command of ["claude", "codex"]) {
                const shown = data[command] !== null;
                compare(field(page, command).visible, shown, command + "'s field");
                if (shown) {
                    compare(programNote(page, command), data[command], command + "'s note");
                }
            }
            compare(combo(page, "OpenAI inner ring").visible, data.ring, "the OpenAI inner ring");
            compare(findAll(page, i => i.text === page.automaticLine && i.visible).length, 1 + Number(data.ring),
                    "the inner rings' notes");
            compare(logoChoice(page, "Codex").visible, data.logo, "the ring logo");
            compare(heading(page, "OpenAI").visible, data.openai, "the OpenAI heading");
            compare(findAll(page, i => i.text === "Program:" && i.visible).length,
                    Number(data.claude !== null) + Number(data.codex !== null), "Program: labels");
        }

        // A problem is said in the negative colour, an explanation dimmed.
        function test_programNoteColours() {
            const page = make(providers);
            showPrograms(page, "broken");
            verify(Qt.colorEqual(programNoteColor(page, "codex"), Kirigami.Theme.negativeTextColor));
            showPrograms(page, "custom");
            verify(!Qt.colorEqual(programNoteColor(page, "claude"), Kirigami.Theme.negativeTextColor));
        }

        function typeInto(item, text) {
            item.forceActiveFocus();
            item.selectAll();
            keyClick(Qt.Key_Delete);
            for (const c of text) {
                keyClick(c);
            }
        }

        // Emptying a field to type another path, or to go back to
        // automatic, leaves the row where it is; nothing above it moves
        // until Apply has had the new path checked.
        function test_programRowStaysWhileEditing() {
            const page = make(providers, { knownLimits: { codex: [{ id: "gpt", label: "GPT-5.5-Codex", reported: true }] } });
            showPrograms(page, "custom");
            const codex = field(page, "codex");
            typeInto(codex, "");
            compare(page.cfg_codexProgram, "");
            verify(codex.visible, "the row went while its field was emptied");
            compare(programNote(page, "codex"), "");

            const lost = make(providers);
            showPrograms(lost, "notfound-on");
            typeInto(field(lost, "codex"), "/opt/codex");
            compare(lost.cfg_codexProgram, "/opt/codex");
            verify(!logoChoice(lost, "Codex").visible, "the logo showed before the path was checked");
            compare(programNote(lost, "codex"), "", "the not-found note stays under a typed path");
            typeInto(field(lost, "codex"), "");
            verify(field(lost, "codex").visible);
            compare(programNote(lost, "codex"), codexLost);
        }

        // What is typed stays as typed, spaces and ~ among it, and the
        // setting holds it without the spaces around it.
        function test_programTypedAsIs() {
            const page = make(providers);
            showPrograms(page, "notfound-on");
            const codex = field(page, "codex");
            typeInto(codex, page.home + "/my tools/codex ");
            compare(codex.text, page.home + "/my tools/codex ");
            compare(page.cfg_codexProgram, page.home + "/my tools/codex");
            // A path set elsewhere, as by the file picker, shows.
            page.cfg_codexProgram = "~/bin/codex";
            compare(codex.text, "~/bin/codex");
        }

        // A path the helper can't take is caught as it is typed.
        function test_programTypedPathCheck_data() {
            return [
                { tag: "a name", text: "codex", note: "Enter a full path, starting with / or ~/." },
                { tag: "relative", text: "bin/codex", note: "Enter a full path, starting with / or ~/." },
                { tag: "another user's home", text: "~bob/codex", note: "Enter a full path, starting with / or ~/." },
                { tag: "full", text: "/usr/local/bin/codex", note: "" },
                { tag: "home", text: "~/bin/codex", note: "" },
                { tag: "spaces around", text: "  /opt/codex", note: "" }
            ];
        }
        function test_programTypedPathCheck(data) {
            const page = make(providers);
            showPrograms(page, "custom");
            typeInto(field(page, "codex"), data.text);
            compare(programNote(page, "codex"), data.note);
            if (data.note !== "") {
                verify(Qt.colorEqual(programNoteColor(page, "codex"), Kirigami.Theme.negativeTextColor));
            }
            compare(field(page, "codex").Accessible.description, data.note);
        }

        // The helper's problem with a path shows only under that path, the
        // stored ~ form and the reported full one being the same path.
        function test_programStaleProblemHidden() {
            const page = make(providers);
            showPrograms(page, "broken");
            const codex = field(page, "codex");
            compare(programNote(page, "codex"), "There is no file at this path.");
            typeInto(codex, "~/.npm-global/bin/codex2");
            compare(programNote(page, "codex"), "");
            typeInto(codex, page.home + "/.npm-global/bin/codex");
            compare(programNote(page, "codex"), "There is no file at this path.", "the same path, written in full");
            // A problem reported for automatic isn't the chosen path's.
            page.usageStatus = { codex: { status: "error", starter: false,
                                          program: program(page.home + "/.npm-global/bin/codex", false, "missing") } };
            compare(programNote(page, "codex"), "");
        }

        // As Folder View has it: a field that fills the row and an icon-only
        // button that names what it does to screen readers and in its tooltip.
        function test_programControls() {
            const page = make(providers);
            showPrograms(page, "custom");
            for (const command of ["claude", "codex"]) {
                const f = field(page, command);
                compare(f.placeholderText, "Path to " + command + "…");
                verify(f.inputMethodHints & Qt.ImhNoPredictiveText);
                const button = combo(page, "Choose where " + command + " is");
                verify(button && button.visible, command + "'s button");
                compare(button.text, "Choose where " + command + " is");
                compare(button.display, 0 /* AbstractButton.IconOnly */);
                compare(button.icon.name, "document-open");
                compare(button.QQC2.ToolTip.text, button.text);
                const row = f.parent;
                fuzzyCompare(f.width + button.width + row.spacing, row.width, 1, command + "'s field fills the row");
            }
        }

        // The file picker opens in the chosen program's folder, or at home
        // while no full path is chosen. Qt's own dialog stands in for the
        // desktop's here and picks differently, so what it stores is left
        // to a check by hand.
        function test_programFilePicker() {
            const page = make(providers);
            showPrograms(page, "custom");
            page.cfg_codexProgram = "~/my tools/#1/codex";
            const row = field(page, "codex").parent;
            const picker = row.data.find(o => o.selectedFile !== undefined);
            // As QUrl prints it: the # still escaped, which a bare path would
            // have turned into a fragment.
            compare(String(picker.currentFolder), "file://" + page.home + "/my tools/%231");
            page.cfg_codexProgram = "codex";
            compare(String(picker.currentFolder), "file://" + encodeURI(page.home));
        }

        // The path stays left to right in a right-to-left layout, the
        // button beside it on the leading side and the label on the right.
        function test_programRightToLeft() {
            const host = createTemporaryObject(stretchedProviders, root, { mirrored: true, width: 660, height: root.height });
            const page = host.page;
            showPrograms(page, "custom");
            waitForRendering(host);
            const f = combo(page, host.stretch("Path to codex"));
            const button = combo(page, host.stretch("Choose where codex is"));
            compare(f.effectiveHorizontalAlignment, TextInput.AlignLeft);
            verify(button.mapToItem(page, 0, 0).x + button.width <= f.mapToItem(page, 0, 0).x, "the button sits left of the field");
            const label = findAll(page, i => i.text === host.stretch("Program:") && i.visible)[0];
            verify(label.mapToItem(page, 0, 0).x >= f.mapToItem(page, 0, 0).x + f.width, "the label sits right of the field");
        }

        // Typing a path and pressing Apply saves it, as typed, under its key.
        function test_applySavesTheTypedProgram_data() {
            return orders([{ tag: "codex" }]);
        }
        function test_applySavesTheTypedProgram(data) {
            const config = fakeConfiguration(Object.assign(settings(), { itemOrder: ["cpu", "codex"], hiddenItems: [] }));
            const page = open("config/ConfigProviders.qml", config, data.order);
            const d = dialog(page, config, data.order);
            page.usageStatus = programStates()["notfound-off"].status;
            waitForRendering(page);
            typeInto(field(page, "codex"), "~/.npm-global/bin/codex");
            verify(d.applyEnabled, "typing left Apply off");
            d.apply();
            compare(config.file.codexProgram, "~/.npm-global/bin/codex");
            compare(config.file.claudeProgram, "");
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
                  claudeVisible: false, codexVisible: false },
                { tag: "entriesFromKnownLimits",
                  known: { claude: [{ id: "opus", label: "Opus", reported: true }], codex: [] },
                  claudeChoice: "", codexChoice: "",
                  claudeVisible: true, codexVisible: false,
                  claudeEntries: [{ text: "Automatic", value: "" }, { text: "None", value: "none" },
                                  { text: "Opus", value: "opus" }] },
                { tag: "eachPickerShowsItsOwnChoice",
                  known: { claude: [{ id: "opus", label: "Opus", reported: true }],
                           codex: [{ id: "gpt5", label: "GPT-5", reported: true },
                                   { id: "spark", label: "Spark", reported: true }] },
                  claudeChoice: "opus", codexChoice: "spark",
                  claudeVisible: true, codexVisible: true,
                  codexEntries: [{ text: "Automatic", value: "" }, { text: "None", value: "none" },
                                 { text: "GPT-5", value: "gpt5" }, { text: "Spark", value: "spark" }] },
                { tag: "codexOnly",
                  known: { codex: [{ id: "gpt5", label: "GPT-5", reported: true }] },
                  claudeChoice: "", codexChoice: "",
                  claudeVisible: false, codexVisible: true },
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
            const page = make(providers, { knownLimits: data.known,
                                           cfg_claudeInnerLimit: data.claudeChoice, cfg_codexInnerLimit: data.codexChoice });
            const claude = combo(page, "Claude inner ring");
            const codex = combo(page, "OpenAI inner ring");
            compare(claude.visible, data.claudeVisible);
            compare(codex.visible, data.codexVisible);
            // Each picker has its own heading and its own note under it.
            compare(heading(page, "Claude").visible, data.claudeVisible);
            const notes = findAll(page, i => typeof i.text === "string" && i.text.startsWith("Automatic shows") && i.visible);
            compare(notes.length, Number(data.claudeVisible) + Number(data.codexVisible));
            for (const [picker, shown] of [[claude, data.claudeVisible], [codex, data.codexVisible]]) {
                if (shown) {
                    verify(notes.some(note => below(note, picker)), picker.Accessible.name + "'s note");
                }
            }
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
                { tag: "codex", name: "OpenAI inner ring", value: "gpt5",
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

        function logoChoice(page, text) {
            return find(page, i => i.text === text && i.autoExclusive !== undefined);
        }

        // The Codex ring's logo is offered while Codex is on in Panel Items
        // or has reported its limits, and not for a Codex never switched on.
        function test_codexLogoShown_data() {
            return [
                { tag: "defaults", order: ["cpu", "gpu", "memory", "network", "disk"], hidden: ["disk"], known: {}, shown: false },
                { tag: "claudeOnly", order: ["cpu", "claude"], hidden: [], known: {}, shown: false },
                { tag: "codexOn", order: ["cpu", "codex"], hidden: [], known: {}, shown: true },
                { tag: "codexSwitchedOff", order: ["cpu", "codex"], hidden: ["codex"], known: {}, shown: false },
                { tag: "codexReported", order: ["cpu"], hidden: [],
                  known: { codex: [{ id: "gpt5", label: "GPT-5", reported: true }] }, shown: true },
                { tag: "claudeReported", order: ["cpu"], hidden: [],
                  known: { claude: [{ id: "opus", label: "Opus", reported: true }] }, shown: false }
            ];
        }
        function test_codexLogoShown(data) {
            const page = make(providers, { cfg_itemOrder: data.order, cfg_hiddenItems: data.hidden, knownLimits: data.known });
            for (const text of ["Codex", "ChatGPT"]) {
                compare(logoChoice(page, text).visible, data.shown, text);
            }
            const label = find(page, i => i.text === "Ring logo:");
            verify(label);
            compare(label.visible, data.shown);
            compare(heading(page, "OpenAI").visible, data.shown, "the OpenAI heading");
        }

        // Settings for both providers come first under their own heading,
        // then Claude's, then Codex's, each control under its own.
        function test_providerSections() {
            const page = make(providers, { cfg_itemOrder: ["claude", "codex"], cfg_hiddenItems: [],
                                           knownLimits: { claude: [{ id: "opus", label: "Opus", reported: true }],
                                                          codex: [{ id: "gpt5", label: "GPT-5", reported: true }] } });
            const y = item => item.mapToItem(null, 0, 0).y;
            const both = heading(page, "Claude and OpenAI");
            const claude = heading(page, "Claude");
            const codex = heading(page, "OpenAI");
            for (const h of [both, claude, codex]) {
                verify(h && h.visible, h ? h.text : "a heading");
            }
            const every = combo(page, "Check every");
            const claudeRing = combo(page, "Claude inner ring");
            const codexRing = combo(page, "OpenAI inner ring");
            const logo = logoChoice(page, "Codex");
            verify(y(both) < y(every) && y(every) < y(claude));
            verify(y(claude) < y(claudeRing) && y(claudeRing) < y(codex));
            verify(y(codex) < y(codexRing) && y(codexRing) < y(logo));
            compare(findAll(page, i => i.text === "Inner ring:" && i.visible).length, 2);

            // With neither provider to set, only the shared section shows.
            const bare = make(providers);
            verify(heading(bare, "Claude and OpenAI").visible);
            verify(!heading(bare, "Claude").visible);
            verify(!heading(bare, "OpenAI").visible);
        }

        // Codex is chosen until the setting says openai, and each choice
        // writes its own value.
        function test_choosingTheCodexLogo() {
            const page = make(providers, { cfg_itemOrder: ["codex"], cfg_hiddenItems: [] });
            const codex = logoChoice(page, "Codex");
            const openai = logoChoice(page, "ChatGPT");
            verify(codex.checked);
            verify(!openai.checked);
            mouseClick(openai);
            compare(page.cfg_codexMark, "openai");
            verify(!codex.checked);
            mouseClick(codex);
            compare(page.cfg_codexMark, "codex");
            verify(!openai.checked);

            const stored = make(providers, { cfg_itemOrder: ["codex"], cfg_hiddenItems: [], cfg_codexMark: "openai" });
            verify(logoChoice(stored, "ChatGPT").checked);
            verify(!logoChoice(stored, "Codex").checked);
        }
    }
}
