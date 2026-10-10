// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/config"
import "../../package/contents/ui/code/log.js" as Log
import "../../package/contents/ui/code/publicaddress.js" as Lookup

// The public address in the network popup: the service's URLs and replies,
// when the checker may send anything, the minute between checks shared by
// every checker, the popup's states and notes, the settings, and Monitor's
// route facts and User-Agent. Requests are fakes that record what they were
// asked and answer when a test says so: nothing here reaches a network.
// Each test that keeps results asks a service of its own, since checkers
// share their records through code/publicaddress.js.
Item {
    id: root
    width: 800
    height: 900

    // A bare qml runtime has no KI18n; the views find these on the root.
    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (m, n) => n <= args.length ? String(args[n - 1]) : m);
    }
    function i18n(text, ...args) { return substitute(text, args); }
    function i18nc(context, text, ...args) { return substitute(text, args); }
    function i18np(s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }
    function i18ncp(c, s, p, n, ...args) { return substitute(n === 1 ? s : p, [n].concat(args)); }

    // The checkers' clock, moved on by the tests.
    property real now: 1.8e12
    // The Service list's rows.
    readonly property int ipifyRow: 0
    readonly property int mullvadRow: 1
    readonly property int customRow: 2

    Component {
        id: configComponent
        QtObject {
            // var, so a test can hand over what a missing or mistyped setting would.
            property var publicAddress: true
            property string publicAddressUrl4: ""
            property string publicAddressUrl6: ""
        }
    }

    Component {
        id: checkerComponent
        PublicAddress {
            clock: () => root.now
        }
    }

    Component {
        id: host
        Loader {}
    }

    Component {
        id: mirroredHost
        Loader {
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: true
        }
    }

    Component {
        id: generalComponent
        ConfigGeneral {
            property bool rightToLeft
            width: root.width
            height: root.height
            LayoutMirroring.enabled: rightToLeft
            LayoutMirroring.childrenInherit: true
            cfg_updateInterval: 1000
            cfg_graphSpan: "minute"
            cfg_networkBits: true
            cfg_highlightTemperatures: true
            cfg_warmCelsius: 75
            cfg_hotCelsius: 90
        }
    }

    Component {
        id: realConfigComponent
        QtObject {
            property int updateInterval: 1000
            property string graphSpan: "minute"
            property bool keepGraphHistory: false
            property bool fahrenheit: false
            property bool networkBits: true
            property bool highlightTemperatures: true
            property real warmCelsius: 75
            property real hotCelsius: 90
            property var itemOrder: ["network"]
            property var hiddenItems: []
            property var ringsOnly: []
            property string cpuTemperatureSensor: ""
            property string outerGpu: ""
            property string innerGpu: ""
            property string networkInterface: ""
            property string diskDevice: ""
            property string diskVolume: ""
            property string diskTemperatureSensor: ""
            property string detectedHardware: ""
            property int usageRefreshMinutes: 5
            property string claudeInnerLimit: ""
            property string codexInnerLimit: ""
            property string knownLimits: ""
            property string usageStatus: ""
            property var publicAddress: true
            property string publicAddressUrl4: "https://monitor.example/ip"
            property string publicAddressUrl6: "https://monitor6.example/ip"
        }
    }

    Component {
        id: realMonitorComponent
        Monitor {}
    }

    FakeMonitor {
        id: plain
    }

    // The popups' monitor, outliving every popup; each test gives it a checker.
    FakeMonitor {
        id: popupMonitor
        networkConnection: "Framework 10G Adapter"
        networkAddress: "192.168.99.123"
        networkInterface: "enp195s0f3u1"
    }

    Words {
        id: words
        monitor: plain
    }

    TestCase {
        id: testCase
        name: "PublicAddress"
        when: windowShown

        function init() {
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop|polish loop/);
            // Well past any check an earlier test made.
            root.now += 1e9;
        }

        property var monitors: []

        function cleanup() {
            Log.unlisten(listener);
            popupMonitor.publicAddress = null;
            for (const m of monitors) {
                m.destroy();
            }
            monitors = [];
            wait(0);
        }

        // Requests that record what they were asked and answer on demand.
        function requests() {
            const made = [];
            const make = () => {
                const r = {
                    readyState: 0, status: 0, responseText: "", responseURL: "", method: "", url: "", headers: {},
                    sent: false, aborted: false, onreadystatechange: null,
                    open(method, url) { this.method = method; this.url = url; this.readyState = 1; },
                    setRequestHeader(name, value) { this.headers[name] = value; },
                    send() { this.sent = true; },
                    abort() {
                        this.aborted = true;
                        if (this.sent && this.readyState !== 4) {
                            this.readyState = 4;
                            this.status = 0;
                            this.onreadystatechange();
                        }
                    },
                    // `from`: the URL the request ended at, after any redirect.
                    answer(status, body, from) {
                        this.status = status;
                        this.responseURL = from ?? this.url;
                        this.responseText = body;
                        this.readyState = 3;
                        this.onreadystatechange();
                        if (this.readyState !== 4) {
                            this.readyState = 4;
                            this.onreadystatechange();
                        }
                    }
                };
                made.push(r);
                return r;
            };
            return { made: made, make: make };
        }

        function route(v4, v6, tunnel4, tunnel6) {
            return { known: true, v4: { device: v4, tunnel: !!tunnel4 }, v6: { device: v6, tunnel: !!tunnel6 } };
        }

        // A service of the test's own, so no other test's checks count.
        function own(tag, both) {
            return { publicAddressUrl4: "https://" + tag + ".example/ip",
                     publicAddressUrl6: both === false ? "" : "https://" + tag + "-6.example/ip" };
        }

        // A checker with an open popup on a connection through enp5s0.
        function checker(props, config) {
            const c = createTemporaryObject(configComponent, root, config || {});
            const fake = requests();
            const checker = createTemporaryObject(checkerComponent, root, Object.assign({
                config: c, makeRequest: fake.make, open: true, egress: route("enp5s0", "enp5s0"),
                localAddress: "192.168.1.2"
            }, props || {}));
            verify(checker);
            return { checker: checker, config: c, made: fake.made, make: fake.make };
        }

        function answer(made, family, status, body, from) {
            const r = made.find(m => !m.aborted && m.readyState !== 4 && (family === "v6") === /-6\.|api6\.|ipv6\./.test(m.url));
            verify(r, "a " + family + " request under way");
            r.answer(status, body, from);
        }

        function timer(object, name) {
            return Array.from(object.data).find(o => o && o.objectName === name);
        }

        function find(item, test) {
            if (test(item)) {
                return item;
            }
            for (const child of item.children) {
                const found = find(child, test);
                if (found) {
                    return found;
                }
            }
            return null;
        }

        function all(item, test) {
            const found = [];
            const collect = i => {
                if (test(i)) {
                    found.push(i);
                }
                i.children.forEach(collect);
            };
            collect(item);
            return found;
        }

        function popup(monitor, mirrored) {
            const loader = createTemporaryObject(mirrored ? mirroredHost : host, root);
            loader.setSource(Qt.resolvedUrl("../../package/contents/ui/popups/NetworkPopup.qml"), { monitor: monitor });
            compare(loader.status, Loader.Ready);
            waitForRendering(loader.item);
            return loader.item;
        }

        function header(page) {
            return find(page, i => i.detail !== undefined && i.subtitle !== undefined);
        }

        function block(page) {
            return find(page, i => i.info !== undefined && i.localInterface !== undefined);
        }

        function addressLines(page) {
            return all(page, i => i.spoken !== undefined && i.visible);
        }

        function visibleTexts(item) {
            return all(item, i => i.visible && typeof i.text === "string" && i.text !== "" && i.spoken === undefined)
                .filter(i => {
                    for (let p = i; p; p = p.parent) {
                        if (!p.visible) {
                            return false;
                        }
                    }
                    return true;
                })
                .map(i => i.text);
        }

        // A checker shown in a popup, as Monitor would give it.
        function shownIn(props, config) {
            const set = checker(Object.assign({ localAddress: "192.168.99.123", egress: route("enp195s0f3u1", "enp195s0f3u1") }, props), config);
            popupMonitor.publicAddress = set.checker;
            set.monitor = popupMonitor;
            return set;
        }

        // ---- The service's URL, its replies, the route report ----

        function test_host_data() {
            return [
                { tag: "ipify", url: "https://api.ipify.org", host: "api.ipify.org" },
                { tag: "path and query", url: "https://API.Example.org/ip?format=text", host: "api.example.org" },
                { tag: "scheme in capitals", url: "HTTPS://ip.example", host: "ip.example" },
                { tag: "port", url: "https://ip.example:8443/", host: "ip.example" },
                { tag: "trailing dot", url: "https://ip.example./", host: "ip.example." },
                { tag: "IPv6 host", url: "https://[2001:db8::1]/ip", host: "[2001:db8::1]" },
                { tag: "http", url: "http://api.ipify.org", host: "" },
                { tag: "other scheme", url: "ftp://ip.example/", host: "" },
                { tag: "file", url: "file:///etc/hostname", host: "" },
                { tag: "no scheme", url: "//ip.example/", host: "" },
                { tag: "no host", url: "https://", host: "" },
                { tag: "path only", url: "https:///ip", host: "" },
                { tag: "user and password", url: "https://me:secret@ip.example/", host: "" },
                { tag: "user", url: "https://me@ip.example/", host: "" },
                { tag: "port zero", url: "https://ip.example:0/", host: "" },
                { tag: "port too high", url: "https://ip.example:70000/", host: "" },
                { tag: "space in host", url: "https://ip .example/", host: "" },
                { tag: "space in path", url: "https://ip.example/a b", host: "" },
                { tag: "label starts with a hyphen", url: "https://-ip.example/", host: "" },
                { tag: "percent in host", url: "https://ip%2eexample/", host: "" },
                { tag: "bad IPv6 host", url: "https://[2001:zz::1]/", host: "" },
                { tag: "non-ASCII host", url: "https://bücher.example/", host: "" }
            ];
        }
        function test_host(data) {
            compare(Lookup.host(data.url), data.host);
        }

        function test_service() {
            const ipify = { custom: false, preset: "ipify", json: false, valid: true, v4: "https://api.ipify.org",
                            v6: "https://api6.ipify.org", hosts: ["ipify.org"], key: "ipify" };
            compare(Lookup.service("", ""), ipify);
            compare(Lookup.service(undefined, null), ipify);
            compare(Lookup.service("  ", "\t"), ipify, "white space alone is empty");

            const mullvad = Lookup.service(" https://ipv4.am.i.mullvad.net/json ", "https://ipv6.am.i.mullvad.net/json");
            compare([mullvad.custom, mullvad.preset, mullvad.json, mullvad.valid, mullvad.hosts, mullvad.key],
                    [false, "mullvad", true, true, ["am.i.mullvad.net"], "mullvad"]);
            compare(Lookup.service("https://ipv4.am.i.mullvad.net/json", "").preset, "", "half of Mullvad's pair is Custom");

            const one = Lookup.service(" https://a.example/ip ", "");
            compare(one.valid, true);
            compare([one.v4, one.v6], ["https://a.example/ip", ""], "an empty field leaves its family unchecked");
            compare(one.hosts, ["a.example"]);
            compare([one.custom, one.preset, one.json], [true, "", true]);

            compare(Lookup.service("https://a.example/4", "https://a.example/6").hosts, ["a.example"]);
            compare(Lookup.service("https://a.example/4", "https://b.example/6").hosts, ["a.example", "b.example"]);
            compare(Lookup.service("", "https://b.example/6").v4, "", "never ipify.org beside a custom URL");

            const bad = Lookup.service("http://a.example/ip", "https://b.example/6");
            compare([bad.valid, bad.v4, bad.v6, bad.key], [false, "", "", ""], "one invalid URL invalidates both");
            compare(bad.hosts, ["b.example"]);
        }

        function test_address_data() {
            const tooLong = "1".repeat(65);
            return [
                { tag: "IPv4", body: "203.0.113.7", family: "v4", address: "203.0.113.7" },
                { tag: "IPv4 with a newline", body: "203.0.113.7\n", family: "v4", address: "203.0.113.7" },
                { tag: "IPv4 in white space", body: " \t198.51.100.24\r\n", family: "v4", address: "198.51.100.24" },
                { tag: "IPv4 edges", body: "255.255.255.0", family: "v4", address: "255.255.255.0" },
                { tag: "IPv4 unspecified", body: "0.0.0.0", family: "v4", address: "" },
                { tag: "IPv4 in 0.0.0.0/8", body: "0.1.2.3", family: "v4", address: "" },
                { tag: "IPv4 loopback", body: "127.0.0.1", family: "v4", address: "" },
                { tag: "IPv4 elsewhere in 127.0.0.0/8", body: "127.200.1.1", family: "v4", address: "" },
                { tag: "IPv4 starting 10", body: "10.0.0.1", family: "v4", address: "10.0.0.1" },
                { tag: "IPv4 part over 255", body: "256.1.1.1", family: "v4", address: "" },
                { tag: "IPv4 leading zero", body: "01.2.3.4", family: "v4", address: "" },
                { tag: "IPv4 three parts", body: "1.2.3", family: "v4", address: "" },
                { tag: "IPv4 five parts", body: "1.2.3.4.5", family: "v4", address: "" },
                { tag: "IPv4 and more", body: "1.2.3.4 is your address", family: "v4", address: "" },
                { tag: "HTML", body: "<html><body>1.2.3.4</body></html>", family: "v4", address: "" },
                { tag: "JSON", body: "{\"ip\":\"1.2.3.4\"}", family: "v4", address: "" },
                { tag: "empty", body: "", family: "v4", address: "" },
                { tag: "not text", body: null, family: "v4", address: "" },
                { tag: "too long", body: tooLong, family: "v4", address: "" },
                { tag: "IPv6 asked for IPv4", body: "2001:db8::1", family: "v4", address: "" },
                { tag: "IPv6", body: "2001:db8::1c\n", family: "v6", address: "2001:db8::1c" },
                { tag: "IPv6 in capitals", body: "2001:DB8::1C", family: "v6", address: "2001:db8::1c" },
                { tag: "IPv6 padded and uncompressed", body: "2001:0DB8:0000:0:0:0:0:001C", family: "v6", address: "2001:db8::1c" },
                { tag: "IPv6 longest zero run, the first of equal ones", body: "1:0:0:1:0:0:1:1", family: "v6", address: "1::1:0:0:1:1" },
                { tag: "IPv6 later zero run longer", body: "1:0:1:0:0:0:1:1", family: "v6", address: "1:0:1::1:1" },
                { tag: "IPv6 lone zero group", body: "2001:db8:0:1:1:1:1:1", family: "v6", address: "2001:db8:0:1:1:1:1:1" },
                { tag: "IPv6 zero run at the end", body: "2001:db8:1:0:0:0:0:0", family: "v6", address: "2001:db8:1::" },
                { tag: "IPv6 in full", body: "2001:db8:85a3:4d1c:9d2e:51f4:c8a3:7e61", family: "v6",
                  address: "2001:db8:85a3:4d1c:9d2e:51f4:c8a3:7e61" },
                { tag: "IPv6 unspecified", body: "::", family: "v6", address: "" },
                { tag: "IPv6 unspecified in full", body: "0:0:0:0:0:0:0:0", family: "v6", address: "" },
                { tag: "IPv6 loopback", body: "::1", family: "v6", address: "" },
                { tag: "IPv6 ::2", body: "::2", family: "v6", address: "::2" },
                { tag: "IPv6 nine groups", body: "1:2:3:4:5:6:7:8:9", family: "v6", address: "" },
                { tag: "IPv6 seven groups", body: "1:2:3:4:5:6:7", family: "v6", address: "" },
                { tag: "IPv6 two gaps", body: "2001::db8::1", family: "v6", address: "" },
                { tag: "IPv6 triple colon", body: "2001:db8:::1", family: "v6", address: "" },
                { tag: "IPv6 lone colon", body: ":1::", family: "v6", address: "" },
                { tag: "IPv6 group too long", body: "2001:db8::12345", family: "v6", address: "" },
                { tag: "IPv6 zone id", body: "fe80::1%eth0", family: "v6", address: "" },
                { tag: "IPv4-mapped, dotted", body: "::ffff:203.0.113.7", family: "v6", address: "" },
                { tag: "IPv4-mapped, hex", body: "::ffff:cb00:7107", family: "v6", address: "" },
                { tag: "embedded IPv4", body: "64:ff9b::203.0.113.7", family: "v6", address: "" },
                { tag: "IPv4 asked for IPv6", body: "203.0.113.7", family: "v6", address: "" },
                { tag: "IPv6 too long", body: "2001:db8::1" + " ".repeat(10) + "x".repeat(60), family: "v6", address: "" },
                { tag: "no such family", body: "203.0.113.7", family: "v5", address: "" }
            ];
        }
        function test_address(data) {
            compare(Lookup.address(data.body, data.family), data.address);
        }

        // A reply is the bare address or, from a Custom service, JSON of
        // which only "ip", "city" and "country" are read; a place goes only
        // with a valid address.
        function test_reply_data() {
            const json = (fields, family) => ({ body: JSON.stringify(fields), family: family ?? "v4" });
            const ams = { ip: "198.51.100.24", city: "Amsterdam", country: "Netherlands" };
            const row = (tag, input, address, city, country) =>
                Object.assign({ tag: tag, address: address, city: city ?? "", country: country ?? "" }, input);
            const c64 = "C".repeat(64);
            return [
                row("bare IPv4", { body: "203.0.113.7\n", family: "v4" }, "203.0.113.7"),
                row("bare IPv6, respelled", { body: "2001:DB8:0::1C", family: "v6" }, "2001:db8::1c"),
                row("bare from ipify.org", { body: "203.0.113.7\n", family: "v4", custom: false }, "203.0.113.7"),
                row("JSON from ipify.org", Object.assign(json(ams), { custom: false }), ""),
                row("JSON", json(ams), "198.51.100.24", "Amsterdam", "Netherlands"),
                row("JSON in white space", { body: "\n " + JSON.stringify(ams) + "\r\n", family: "v4" },
                    "198.51.100.24", "Amsterdam", "Netherlands"),
                row("JSON IPv6, respelled", json({ ip: "2001:0DB8::001C", city: "Frankfurt am Main", country: "Germany" }, "v6"),
                    "2001:db8::1c", "Frankfurt am Main", "Germany"),
                row("extra fields ignored", json(Object.assign({ latitude: 52.37, organization: "Example <b>ISP</b>",
                                                                 mullvad_exit_ip: true, region: "North Holland",
                                                                 nested: { city: "Elsewhere" } }, ams)),
                    "198.51.100.24", "Amsterdam", "Netherlands"),
                row("__proto__ ignored", { body: "{\"__proto__\":{\"city\":\"Elsewhere\"},\"ip\":\"198.51.100.24\"}", family: "v4" },
                    "198.51.100.24"),
                row("only ip", json({ ip: "198.51.100.24" }), "198.51.100.24"),
                row("city without country", json({ ip: "198.51.100.24", city: "Amsterdam" }), "198.51.100.24", "Amsterdam"),
                row("country without city", json({ ip: "198.51.100.24", country: "Netherlands" }), "198.51.100.24"),
                row("no ip", json({ city: "Amsterdam", country: "Netherlands" }), ""),
                row("ip a number", json({ ip: 3325256824, city: "Amsterdam" }), ""),
                row("ip null", json({ ip: null, city: "Amsterdam" }), ""),
                row("ip a list", json({ ip: ["198.51.100.24"], city: "Amsterdam" }), ""),
                row("ip of the other family", json(ams, "v6"), ""),
                row("IPv6 ip for IPv4", json({ ip: "2001:db8::1c", city: "Amsterdam" }), ""),
                row("ip loopback", json({ ip: "127.0.0.1", city: "Amsterdam" }), ""),
                row("ip and more", json({ ip: "198.51.100.24 Amsterdam", city: "Amsterdam" }), ""),
                row("ip IPv4-mapped", json({ ip: "::ffff:198.51.100.24", city: "Amsterdam" }, "v6"), ""),
                row("malformed", { body: "{\"ip\":\"198.51.100.24\",\"city\":\"Amsterdam\"", family: "v4" }, ""),
                row("JSON then text", { body: JSON.stringify(ams) + " ok", family: "v4" }, ""),
                row("two objects", { body: JSON.stringify(ams) + JSON.stringify(ams), family: "v4" }, ""),
                row("a list", { body: JSON.stringify([ams]), family: "v4" }, ""),
                row("a JSON string", { body: "\"198.51.100.24\"", family: "v4" }, ""),
                row("just a brace", { body: "{", family: "v4" }, ""),
                row("not text", { body: null, family: "v4" }, ""),
                row("city a number", json({ ip: "198.51.100.24", city: 1, country: "Netherlands" }), "198.51.100.24"),
                row("city an object", json({ ip: "198.51.100.24", city: { name: "Amsterdam" }, country: "Netherlands" }),
                    "198.51.100.24"),
                row("city a list", json({ ip: "198.51.100.24", city: ["Amsterdam"] }), "198.51.100.24"),
                row("city true", json({ ip: "198.51.100.24", city: true }), "198.51.100.24"),
                row("city null", json({ ip: "198.51.100.24", city: null, country: "Netherlands" }), "198.51.100.24"),
                row("country not text", json({ ip: "198.51.100.24", city: "Amsterdam", country: { iso: "NL" } }),
                    "198.51.100.24", "Amsterdam"),
                row("control characters", json({ ip: "198.51.100.24", city: "Ams\u0000ter\u0007dam\u001b[31m", country: "Nether\u0085lands" }),
                    "198.51.100.24", "Ams ter dam [31m", "Nether lands"),
                row("control character edges", json({ ip: "198.51.100.24", city: "Den\u001fHaag\u007fZuid\u009fWest" }),
                    "198.51.100.24", "Den Haag Zuid West"),
                row("line breaks", json({ ip: "198.51.100.24", city: "Den\nHaag\r\n", country: "Nether\u2028lands\u2029" }),
                    "198.51.100.24", "Den Haag", "Nether lands"),
                row("direction characters", json({ ip: "198.51.100.24", city: "\u202eAmsterdam\u202c\u2066\u2069",
                                                   country: "\u200fNether\u061clands\u200e\u202a" }),
                    "198.51.100.24", "Amsterdam", "Netherlands"),
                row("invisible characters", json({ ip: "198.51.100.24", city: "\ufeffAms\u200bter\u200ddam\u2060\u00ad",
                                                   country: "Nether\u200clands" }),
                    "198.51.100.24", "Amsterdam", "Netherlands"),
                row("invisible character edges", json({ ip: "198.51.100.24", city: "Ams\ufeffter\u180edam\u206a\u206fx" }),
                    "198.51.100.24", "Amsterdamx"),
                row("tag characters", json({ ip: "198.51.100.24", city: "Ams\udb40\udc00\udb40\udc41\udb40\udc7fterdam\ufff9x\ufffa\ufffb" }),
                    "198.51.100.24", "Amsterdamx"),
                row("markup kept as text", json({ ip: "198.51.100.24", city: "<b>Oslo</b> &amp; <a href=\"https://x.example\">x</a>" }),
                    "198.51.100.24", "<b>Oslo</b> &amp; <a href=\"https://x.example\">x</a>"),
                row("white space", json({ ip: "198.51.100.24", city: "  Frankfurt \t am\u00a0\u00a0Main ", country: "\tGermany\n" }),
                    "198.51.100.24", "Frankfurt am Main", "Germany"),
                row("blank city", json({ ip: "198.51.100.24", city: " \t\u200b ", country: "Netherlands" }), "198.51.100.24"),
                row("blank country", json({ ip: "198.51.100.24", city: "Amsterdam", country: " \u202e " }),
                    "198.51.100.24", "Amsterdam"),
                row("64 characters", json({ ip: "198.51.100.24", city: c64, country: c64 }), "198.51.100.24", c64, c64),
                row("64 once trimmed", json({ ip: "198.51.100.24", city: "  " + c64 + "\u202e ", country: c64 }),
                    "198.51.100.24", c64, c64),
                row("65 characters", json({ ip: "198.51.100.24", city: c64 + "D", country: "Netherlands" }), "198.51.100.24"),
                row("country 65 characters", json({ ip: "198.51.100.24", city: "Amsterdam", country: c64 + "D" }),
                    "198.51.100.24", "Amsterdam"),
                row("up to the size limit", json(Object.assign({ pad: "x".repeat(Lookup.REPLY_LIMIT - 74) }, ams)),
                    "198.51.100.24", "Amsterdam", "Netherlands"),
                row("over the size limit", json(Object.assign({ pad: "x".repeat(Lookup.REPLY_LIMIT - 73) }, ams)), ""),
                row("bare over the size limit", { body: "203.0.113.7" + " ".repeat(Lookup.REPLY_LIMIT), family: "v4" }, "")
            ];
        }
        function test_reply(data) {
            if (data.tag.indexOf("size limit") > 0 && data.tag.indexOf("bare") < 0) {
                compare(data.body.length, Lookup.REPLY_LIMIT + (data.tag.indexOf("over") === 0 ? 1 : 0), "the row is at the edge");
            }
            compare(Lookup.reply(data.body, data.family, data.custom ?? true),
                    { address: data.address, city: data.city, country: data.country });
        }

        function test_cameFrom_data() {
            const asked = "https://ip.example/v4";
            return [
                { tag: "as asked", from: asked, asked: asked, ok: true },
                { tag: "another path on the host", from: "https://IP.example:443/other", asked: asked, ok: true },
                { tag: "plain http", from: "http://ip.example/v4", asked: asked, ok: false },
                { tag: "another host", from: "https://elsewhere.example/v4", asked: asked, ok: false },
                { tag: "a subdomain", from: "https://a.ip.example/v4", asked: asked, ok: false },
                { tag: "nothing", from: "", asked: asked, ok: false },
                { tag: "undefined", from: "undefined", asked: asked, ok: false }
            ];
        }
        function test_cameFrom(data) {
            compare(Lookup.cameFrom(data.from, data.asked), data.ok);
        }

        function test_egressReport() {
            compare(Lookup.egress(0, "4 wg0-mullvad 1\n6 enp5s0 0\n"),
                    { known: true, v4: { device: "wg0-mullvad", tunnel: true }, v6: { device: "enp5s0", tunnel: false } });
            compare(Lookup.egress(0, "4  0\n6  0\n"),
                    { known: true, v4: { device: "", tunnel: false }, v6: { device: "", tunnel: false } }, "no routes");
            compare(Lookup.egress(0, "4  1\n6  0\n").v4.tunnel, false, "no tunnel without a device");
            compare(Lookup.egress(3, "4  0\n6  0\n"), { known: false }, "no ip");
            compare(Lookup.egress(0, "4 eth0 0\n"), { known: false }, "a family missing");
            compare(Lookup.egress(0, "4 a/b 0\n6 eth0 0\n"), { known: false }, "a name Linux wouldn't allow");
            compare(Lookup.egress(0, "4 .. 0\n6 eth0 0\n"), { known: false });
            compare(Lookup.egress(0, "4 sixteen-chars-xy 0\n6 eth0 0\n"), { known: false });
            compare(Lookup.egress(0, ""), { known: false });
        }

        function test_lines() {
            const result = { v4: "198.51.100.24", v6: "2001:db8::1c" };
            const vpn = Lookup.lines(result, route("wg0", "enp5s0", true, false), "enp5s0");
            compare(vpn.v4, { address: "198.51.100.24", via: "wg0", tunnel: true, city: "", country: "" });
            compare(vpn.v6, { address: "2001:db8::1c", via: "", tunnel: false, city: "", country: "" },
                    "no via through the local interface");
            const placed = Lookup.lines(Object.assign({ places: { v4: { city: "Amsterdam", country: "Netherlands" },
                                                                   v6: { city: "", country: "" } } }, result), { known: false }, "enp5s0");
            compare([placed.v4.city, placed.v4.country, placed.v6.city], ["Amsterdam", "Netherlands", ""]);
            compare(vpn.leak, { family: "v6", through: "wg0" });

            const reverse = Lookup.lines(result, route("enp5s0", "wg0", false, true), "enp5s0");
            compare(reverse.leak, { family: "v4", through: "wg0" });

            compare(Lookup.lines(result, route("wg0", "wg0", true, true), "enp5s0").leak, null, "both through the tunnel");
            compare(Lookup.lines({ v4: result.v4, v6: "" }, route("wg0", "enp5s0", true, false), "enp5s0").leak, null,
                    "no IPv6 address shown");
            compare(Lookup.lines(result, route("wg0", "", true, false), "enp5s0").leak, null, "no IPv6 route");
            compare(Lookup.lines(result, route("enp5s0", "wlan0", false, false), "enp5s0").leak, null, "no tunnel");
            const unknown = Lookup.lines(result, { known: false }, "enp5s0");
            compare([unknown.v4.via, unknown.v6.via, unknown.leak], ["", "", null], "without route facts");
            compare(Lookup.lines({ v4: "", v6: "" }, null, "enp5s0"), { v4: null, v6: null, leak: null });
        }

        // ---- When the checker sends ----

        function test_nothingSent_data() {
            return [
                { tag: "off", config: { publicAddress: false }, status: "off" },
                { tag: "no setting", config: { publicAddress: undefined }, status: "off" },
                { tag: "setting not a Bool", config: { publicAddress: "on" }, status: "off" },
                { tag: "popup closed", props: { open: false }, status: "checking" },
                { tag: "routes not read yet", props: { egress: null }, status: "checking" },
                { tag: "no route", props: { egress: route("", "") }, status: "offline" },
                { tag: "no ip and no local address", props: { egress: { known: false }, localAddress: "" }, status: "offline" },
                { tag: "custom family without a route", props: { egress: route("", "enp5s0") },
                  config: { publicAddressUrl4: "https://only4.example/ip" }, status: "unrouted" },
                { tag: "invalid custom URL", config: { publicAddressUrl4: "http://insecure.example/ip" }, status: "invalid" },
                { tag: "invalid beside a valid one", config: { publicAddressUrl4: "https://me:pw@a.example/",
                                                              publicAddressUrl6: "https://b.example/" }, status: "invalid" }
            ];
        }
        function test_nothingSent(data) {
            const set = checker(data.props, data.config);
            wait(50);
            compare(set.made.length, 0, "no request");
            compare(set.checker.status, data.status);
            compare(timer(set.checker, "wait").running, false, "nothing scheduled");
        }

        // The same checker sends once each condition is met, so the cases
        // above are held back by what they name.
        function test_sendsOnceAllowed() {
            const set = checker({ open: false, egress: null }, Object.assign({ publicAddress: false }, own("allowed")));
            set.config.publicAddress = true;
            set.checker.open = true;
            compare(set.made.length, 0, "routes not read");
            set.checker.egress = route("enp5s0", "enp5s0");
            compare(set.made.length, 2);
        }

        function test_asksIpifyByDefault() {
            const set = checker({ version: "9.9.9" });
            compare(set.made.map(r => r.url), ["https://api.ipify.org", "https://api6.ipify.org"]);
            for (const r of set.made) {
                compare(r.method, "GET");
                compare(r.sent, true);
                compare(r.headers, { "User-Agent": "ringside/9.9.9", "Accept-Language": "*" });
            }
            compare(set.checker.status, "checking");
            compare(set.checker.floorMs, 60000);
            compare(set.checker.timeoutMs, 10000);
        }

        function test_customOnlyAsksCustom_data() {
            return [
                { tag: "IPv4 only", config: { publicAddressUrl4: "https://four.example/ip" }, urls: ["https://four.example/ip"] },
                { tag: "IPv6 only", config: { publicAddressUrl6: "https://six.example/ip" }, urls: ["https://six.example/ip"] },
                { tag: "both", config: { publicAddressUrl4: "https://four.example/ip", publicAddressUrl6: "https://six.example/ip" },
                  urls: ["https://four.example/ip", "https://six.example/ip"] }
            ];
        }
        function test_customOnlyAsksCustom(data) {
            const set = checker({}, data.config);
            compare(set.made.map(r => r.url), data.urls);
            verify(!set.made.some(r => /ipify/.test(r.url)), "ipify.org never asked");
        }

        // Fixing the URL sends to it, and still not to ipify.org.
        function test_invalidCustomNeverFallsBack() {
            const set = checker({}, { publicAddressUrl4: "http://fixed.example/ip" });
            compare(set.made.length, 0);
            set.config.publicAddressUrl4 = "https://fixed.example/ip";
            compare(set.made.map(r => r.url), ["https://fixed.example/ip"]);
        }

        function test_familyWithoutARouteIsNotAsked() {
            const set = checker({ egress: route("enp5s0", "") }, own("noroute6"));
            compare(set.made.map(r => r.url), ["https://noroute6.example/ip"]);
        }

        // Without `ip` the local address stands for a connection.
        function test_withoutIp() {
            const set = checker({ egress: { known: false } }, own("noip"));
            compare(set.made.length, 2);
            answer(set.made, "v4", 200, "203.0.113.7");
            answer(set.made, "v6", 200, "2001:db8::1c");
            compare(set.checker.status, "shown");
            compare(set.checker.route, "", "no route to follow");
        }

        // A check any checker made in the last minute serves the others,
        // and one under way is waited for rather than repeated.
        function test_minuteSharedAcrossCheckers() {
            const config = own("shared");
            const a = checker({}, config);
            compare(a.made.length, 2);
            const b = checker({}, config);
            compare(b.made.length, 0, "a check under way is waited for");
            compare(b.checker.status, "checking");
            answer(a.made, "v4", 200, "203.0.113.7");
            answer(a.made, "v6", 200, "2001:db8::1c");
            compare(b.checker.status, "shown");
            compare(b.checker.record.result.v4, "203.0.113.7");

            root.now += 30000;
            const c = checker({}, config);
            compare(c.made.length, 0, "within the minute");
            compare(c.checker.status, "shown");
            c.checker.open = false;
            root.now += 29999;
            c.checker.open = true;
            compare(c.made.length, 0, "a millisecond short of the minute");
            c.checker.open = false;
            root.now += 1;
            c.checker.open = true;
            compare(c.made.length, 2, "a minute on");
            compare(a.made.length + b.made.length, 2, "only the one that opened asked");
        }

        // A route change while open asks once, a minute after the last check.
        function test_routeChangeWaitsForTheMinute() {
            const set = checker({ clock: () => Date.now(), floorMs: 600 }, own("routechange"));
            const started = Date.now();
            answer(set.made, "v4", 200, "203.0.113.7");
            answer(set.made, "v6", 200, "2001:db8::1c");
            set.checker.egress = route("wg0", "enp5s0", true, false);
            compare(set.made.length, 2, "not at once");
            verify(timer(set.checker, "wait").running, "scheduled");
            set.checker.egress = route("wg1", "enp5s0", true, false);
            tryCompare(set.made, "length", 4, 3000);
            verify(Date.now() - started >= 600 - 20, "not before the minute: " + (Date.now() - started));
            answer(set.made, "v4", 200, "198.51.100.24");
            answer(set.made, "v6", 200, "2001:db8::1c");
            wait(900);
            compare(set.made.length, 4, "one check for both changes, and nothing after");
        }

        function test_routeChangeAfterTheMinuteAsksAtOnce() {
            const set = checker({}, own("routelate"));
            answer(set.made, "v4", 200, "203.0.113.7");
            answer(set.made, "v6", 200, "2001:db8::1c");
            root.now += 60000;
            compare(set.made.length, 2, "no polling");
            set.checker.egress = route("wg0", "enp5s0", true, false);
            compare(set.made.length, 4);
            compare(set.checker.record.route, "enp5s0 enp5s0", "the result's own route until the answer");
            answer(set.made, "v4", 200, "198.51.100.24");
            answer(set.made, "v6", 200, "2001:db8::1c");
            compare(set.checker.record.route, "wg0 enp5s0");
        }

        // A check a minute on keeps the addresses already found on screen,
        // with the route they came through, until its answer replaces them.
        function test_recheckKeepsTheAddresses() {
            const set = shownIn({ egress: route("wg0-mullvad", "wg0-mullvad", true, true) }, own("recheck"));
            answer(set.made, "v4", 200, "198.51.100.24");
            answer(set.made, "v6", 200, "2001:db8::1c");
            const page = popup(set.monitor);
            const before = addressLines(page).map(l => l.spoken);
            const height = block(page).implicitHeight;

            root.now += 61000;
            set.checker.open = false;
            set.checker.egress = route("enp195s0f3u1", "enp195s0f3u1");
            set.checker.open = true;
            compare(set.made.length, 4, "asked again");
            compare(set.checker.status, "shown");
            waitForRendering(page);
            compare(addressLines(page).map(l => l.spoken), before);
            verify(before[1].indexOf("through VPN wg0-mullvad") >= 0, before);
            compare(visibleTexts(page).filter(t => t.indexOf("Asking") === 0), []);
            compare(block(page).implicitHeight, height, "the popup keeps its size");

            answer(set.made, "v4", 200, "203.0.113.7");
            answer(set.made, "v6", 200, "2001:db8::1c");
            compare(addressLines(page).map(l => l.spoken).slice(1),
                    ["Public address 203.0.113.7", "Public address 2001:db8::1c"]);
        }

        // A failure isn't left on screen while the service is asked again.
        function test_recheckAfterFailureAsks() {
            const set = checker({}, own("recheckfail", false));
            answer(set.made, "v4", 503, "");
            compare(set.checker.status, "failed");
            root.now += 61000;
            set.checker.open = false;
            set.checker.open = true;
            compare(set.made.length, 2);
            compare(set.checker.status, "checking");
        }

        // ---- The journal ----

        property var logged: []
        readonly property var listener: (category, level, text) => { logged = logged.concat([category + " " + level + " " + text]); }

        function journal() {
            logged = [];
            Log.listen(listener);
        }

        // Each request is debug with the host asked and how long it took;
        // neither the address nor the place it names is ever written.
        function test_journalNamesTheHostNotTheAddress() {
            journal();
            const set = checker({}, own("journal"));
            root.now += 230;
            answer(set.made, "v4", 200, JSON.stringify({ ip: "203.0.113.7", city: "Oslo", country: "Norway" }));
            answer(set.made, "v6", 200, "2001:db8::1c");
            Log.unlisten(listener);
            compare(set.checker.status, "shown");
            compare(set.checker.record.result.places.v4.city, "Oslo");
            compare(logged, ["ringside.network debug asked journal.example: answered after 230 ms",
                             "ringside.network debug asked journal-6.example: answered after 230 ms"]);
            for (const secret of ["203.0.113", "2001:db8", "Oslo", "Norway"]) {
                verify(logged.every(line => !line.includes(secret)), secret);
            }
        }

        // A failure is a warning when it starts or changes, debug while it
        // repeats, and its end is info.
        function test_journalFailureRepeatAndRecovery() {
            journal();
            const set = checker({}, own("journal-fails", false));
            const again = () => {
                root.now += 61000;
                set.checker.retry();
            };
            answer(set.made, "v4", 503, "");
            again();
            answer(set.made, "v4", 503, "");
            again();
            answer(set.made, "v4", 200, "<html>203.0.113.7</html>");
            again();
            answer(set.made, "v4", 200, "203.0.113.7");
            again();
            compare(set.checker.status, "shown");
            Log.unlisten(listener);
            compare(logged, ["ringside.network warning asked journal-fails.example: HTTP 503 after 0 ms",
                             "ringside.network debug asked journal-fails.example: HTTP 503 after 0 ms",
                             "ringside.network warning asked journal-fails.example: a reply that isn't an address after 0 ms",
                             "ringside.network info asked journal-fails.example: answered after 0 ms, working again"]);
        }

        function test_journalTimeoutAndRedirect() {
            journal();
            const late = checker({ clock: () => root.now, timeoutMs: 100 }, own("journal-late", false));
            tryCompare(late.checker, "status", "failed", 2000);
            const moved = checker({}, own("journal-moved", false));
            answer(moved.made, "v4", 200, "203.0.113.7", "https://elsewhere.example/ip");
            Log.unlisten(listener);
            compare(logged, ["ringside.network warning asked journal-late.example: no answer in 0.1 s after 0 ms",
                             "ringside.network warning asked journal-moved.example: an answer from another address after 0 ms"]);
        }

        // A custom service given as an address goes unnamed.
        function test_journalLeavesOutAnAddressAsHost_data() {
            return [{ tag: "IPv4", url: "https://203.0.113.50/ip" }, { tag: "IPv6", url: "https://[2001:db8::50]/ip" }];
        }
        function test_journalLeavesOutAnAddressAsHost(data) {
            journal();
            const set = checker({}, { publicAddressUrl4: data.url, publicAddressUrl6: "" });
            answer(set.made, "v4", 503, "");
            Log.unlisten(listener);
            compare(logged, ["ringside.network warning asked the custom service: HTTP 503 after 0 ms"]);
        }

        // A clock set back reads as a long time since, not as a check to come.
        function test_clockSteppedBack() {
            const set = checker({}, own("clockback"));
            answer(set.made, "v4", 200, "203.0.113.7");
            answer(set.made, "v6", 200, "2001:db8::1c");
            root.now -= 3600000;
            set.checker.open = false;
            set.checker.open = true;
            compare(set.made.length, 4, "asked at once");
            compare(timer(set.checker, "wait").running, false);
        }

        function test_noPolling() {
            const set = checker({ clock: () => Date.now(), floorMs: 150 }, own("nopoll"));
            answer(set.made, "v4", 200, "203.0.113.7");
            answer(set.made, "v6", 500, "");
            set.checker.egress = route("enp5s0", "enp5s0");
            wait(600);
            compare(set.made.length, 2, "the same route asks nothing");
            // Another widget's check tells every checker; this one stays put.
            const other = checker({}, own("nopoll-other"));
            answer(other.made, "v4", 200, "203.0.113.8");
            answer(other.made, "v6", 500, "");
            compare(set.made.length, 2, "another check asks nothing here");
        }

        function test_timeoutAborts() {
            const set = checker({ clock: () => Date.now(), timeoutMs: 150 }, own("timeout"));
            answer(set.made, "v4", 200, "203.0.113.7");
            tryCompare(set.checker, "status", "shown", 2000);
            compare(set.made.map(r => r.aborted), [false, true]);
            compare(set.checker.record.result.v6, "", "the late family failed");
            set.made[1].answer(200, "2001:db8::1c");
            compare(set.checker.record.result.v6, "", "an answer after the timeout is ignored");

            const none = checker({ clock: () => Date.now(), timeoutMs: 150 }, own("timeout-both"));
            tryCompare(none.checker, "status", "failed", 2000);
            compare(none.made.map(r => r.aborted), [true, true]);
        }

        function test_badRepliesFail_data() {
            return [
                { tag: "not found", status: 404, body: "203.0.113.7" },
                { tag: "server error", status: 500, body: "" },
                { tag: "HTML", status: 200, body: "<html><title>Blocked</title></html>" },
                { tag: "wrong family", status: 200, body: "2001:db8::1" },
                { tag: "network error", status: 0, body: "" },
                { tag: "malformed JSON", status: 200, body: "{\"ip\":\"203.0.113.7\",\"city\":\"Oslo\"" },
                { tag: "JSON of the wrong family", status: 200, body: "{\"ip\":\"2001:db8::1\",\"city\":\"Oslo\"}" },
                { tag: "JSON without ip", status: 200, body: "{\"address\":\"203.0.113.7\",\"city\":\"Oslo, Norway\"}" }
            ];
        }
        function test_badRepliesFail(data) {
            const set = shownIn({}, own("bad-" + data.status + "-" + data.body.length, false));
            answer(set.made, "v4", data.status, data.body);
            compare(set.checker.status, "failed");
            compare(set.checker.record.result.v4, "");
            const page = popup(set.monitor);
            const shown = visibleTexts(page).join("\n");
            verify(shown.indexOf("Can't reach bad-") >= 0, shown);
            if (data.body !== "") {
                verify(shown.indexOf(data.body) < 0, "the reply never shows: " + shown);
                verify(shown.indexOf("Oslo") < 0, "nor its city: " + shown);
            }
        }

        // Qt follows a redirect itself; an answer that ends up anywhere but
        // https at the host asked is dropped, whatever it says.
        function test_redirectedReplyFails_data() {
            return [
                { tag: "to plain http", from: "http://redirect-http.example/ip", ok: false },
                { tag: "to another host", from: "https://elsewhere.example/ip", ok: false },
                { tag: "within the host", from: "https://redirect-%1.example/other", ok: true }
            ];
        }
        function test_redirectedReplyFails(data) {
            const tag = data.tag.replace(/ /g, "-");
            const set = checker({}, own("redirect-" + tag, false));
            answer(set.made, "v4", 200, "203.0.113.7", data.from.replace("%1", tag));
            compare(set.checker.status, data.ok ? "shown" : "failed");
            compare(set.checker.record.result.v4, data.ok ? "203.0.113.7" : "");
        }

        function test_endlessReplyAborted() {
            const set = checker({}, own("endless", false));
            const r = set.made[0];
            r.status = 200;
            compare(Lookup.REPLY_LIMIT, 16384, "16 KB, as SECURITY.md says");
            r.responseText = "1".repeat(Lookup.REPLY_LIMIT + 1);
            r.readyState = 3;
            r.onreadystatechange();
            compare(r.aborted, true);
            compare(set.checker.status, "failed");
        }

        // A JSON reply as long as one may be is read to its end.
        function test_longJsonReplyRead() {
            const set = checker({}, own("longjson", false));
            const r = set.made[0];
            const body = JSON.stringify({ ip: "203.0.113.7", city: "Amsterdam", note: "x".repeat(Lookup.REPLY_LIMIT - 60) });
            verify(body.length <= Lookup.REPLY_LIMIT && body.length > 16000, body.length);
            r.answer(200, body);
            compare(r.aborted, false);
            compare(set.checker.status, "shown");
            compare(set.checker.record.result.places.v4, { city: "Amsterdam", country: "" });
        }

        function test_changedAndLastSeen() {
            const set = checker({}, own("changes", false));
            answer(set.made, "v4", 200, "203.0.113.7");
            compare(set.checker.record.changed.v4, null, "nothing to compare the first address with");
            const first = root.now;

            root.now += 61000;
            set.checker.egress = route("wg0", "enp5s0", true, false);
            answer(set.made, "v4", 200, "198.51.100.24");
            compare(set.checker.record.changed.v4, { at: root.now, was: "203.0.113.7" });

            root.now += 61000;
            set.checker.open = false;
            set.checker.open = true;
            answer(set.made, "v4", 200, "198.51.100.24");
            compare(set.checker.record.changed.v4, null, "the same again");

            root.now += 61000;
            set.checker.open = false;
            set.checker.open = true;
            answer(set.made, "v4", 0, "");
            compare(set.checker.status, "failed");
            compare(set.checker.record.seen.v4, { address: "198.51.100.24", at: root.now - 61000 });
            verify(first < root.now);
        }

        // Switching off mid-check stops it: nothing more is sent or kept.
        function test_switchingOffAbandons() {
            const set = checker({}, own("abandon"));
            const key = Lookup.service(set.config.publicAddressUrl4, set.config.publicAddressUrl6).key;
            set.config.publicAddress = false;
            compare(set.made.map(r => r.aborted), [true, true]);
            compare(set.checker.status, "off");
            compare(Lookup.peek(key).asking, null, "the check it began under is forgotten");
            set.config.publicAddress = true;
            compare(set.made.length, 2, "within the minute, nothing new");
            compare(set.checker.status, "checking");
            verify(timer(set.checker, "wait").running, "waits out the minute instead");
        }

        // The same address spelled another way by the service is no change.
        function test_respelledAddressIsNotAChange() {
            const set = checker({}, { publicAddressUrl4: "", publicAddressUrl6: "https://respelled-6.example/ip" });
            answer(set.made, "v6", 200, "2001:db8::1c");
            compare(set.checker.record.seen.v6.address, "2001:db8::1c");
            root.now += 61000;
            set.checker.open = false;
            set.checker.open = true;
            answer(set.made, "v6", 200, "2001:0DB8:0000:0000:0000:0000:0000:001C");
            compare(set.checker.record.changed.v6, null);
            compare(set.checker.record.seen.v6, { address: "2001:db8::1c", at: root.now });
            compare(set.checker.record.result.v6, "2001:db8::1c");
        }

        function test_destroyedCheckerAborts() {
            const set = checker({}, own("destroyed"));
            const other = checker({}, own("destroyed"));
            set.checker.destroy();
            wait(0);
            compare(set.made.map(r => r.aborted), [true, true]);
            compare(other.checker.record.busy, false);
            compare(other.made.length, 0);
        }

        // ---- The popup ----

        // With the setting off, which is how it ships, the popup is the one
        // there would be without the feature, and nothing is asked.
        function test_offIsToday() {
            const snapshot = page => ({
                detail: header(page).detail,
                texts: visibleTexts(page),
                height: page.implicitHeight,
                block: block(page).visible
            });
            const set = shownIn({}, { publicAddress: false });
            const off = snapshot(popup(set.monitor));
            popupMonitor.publicAddress = null;
            const without = snapshot(popup(popupMonitor));
            compare(off, without);
            compare(off.detail, "192.168.99.123 · enp195s0f3u1");
            compare(off.block, false, "no address block");
            wait(50);
            compare(set.made.length, 0, "nothing asked");
        }

        // The checker's status, and so the popup's block, follow the setting.
        function test_switchedOnInTheSettings() {
            const set = shownIn({}, Object.assign({ publicAddress: false }, own("switchedon", false)));
            const page = popup(set.monitor);
            compare(block(page).visible, false);
            compare(set.made.length, 0);
            set.config.publicAddress = true;
            compare(set.made.length, 1, "asked as soon as it is on");
            compare(block(page).visible, true);
            compare(header(page).detail, "");
            verify(visibleTexts(page).includes("Asking switchedon.example…"), visibleTexts(page).join("\n"));
        }

        // The block names the service it asks; one that is invalid, which
        // asks nothing, goes unnamed.
        function test_popupNamesTheService_data() {
            return [
                { tag: "custom", config: { publicAddressUrl4: "https://ip.example/v4" }, text: "Asking ip.example…" },
                { tag: "two hosts", config: { publicAddressUrl4: "https://a.example/", publicAddressUrl6: "https://b.example/" },
                  text: "Asking a.example and b.example…" },
                { tag: "invalid", config: { publicAddressUrl4: "http://typo.example/ip" },
                  text: "Check the address service in the settings" },
                { tag: "invalid beside a valid one",
                  config: { publicAddressUrl4: "http://typo.example/ip", publicAddressUrl6: "https://ok.example/ip" },
                  text: "Check the address service in the settings" }
            ];
        }
        function test_popupNamesTheService(data) {
            const set = shownIn({}, data.config);
            const shown = visibleTexts(popup(set.monitor)).join("\n");
            verify(shown.indexOf(data.text) >= 0, shown);
            verify(shown.indexOf("ipify") < 0, shown);
        }

        function test_shownLinesAndLeak() {
            const set = shownIn({ egress: route("wg0-mullvad", "enp5s0", true, false) }, own("lines"));
            answer(set.made, "v4", 200, "198.51.100.24");
            answer(set.made, "v6", 200, "2001:db8::1c");
            const page = popup(set.monitor);
            compare(header(page).detail, "");
            const lines = addressLines(page);
            compare(lines.map(l => l.Accessible.name), [
                "Local address 192.168.99.123 on enp195s0f3u1",
                "Public address 198.51.100.24 through VPN wg0-mullvad",
                "Public address 2001:db8::1c through enp5s0"
            ]);
            for (const line of lines) {
                compare(line.Accessible.role, Accessible.StaticText);
                const parts = all(line, i => i instanceof Text || i.source !== undefined);
                verify(parts.length > 0);
                for (const part of parts) {
                    verify(part.Accessible.ignored, "read as part of the line: " + (part.text ?? part.source));
                }
            }
            const shields = all(page, i => i.source === "network-vpn-symbolic" && i.visible);
            compare(shields.length, 1, "one tunnel");
            const warning = all(page, i => i.source === "data-warning-symbolic" && i.visible);
            compare(warning.length, 1);
            const shown = visibleTexts(page);
            verify(shown.includes("IPv6 doesn't go through wg0-mullvad"), shown);
            const note = all(page, i => i.text === "IPv6 doesn't go through wg0-mullvad")[0];
            compare(note.Accessible.name, "Warning: IPv6 doesn't go through wg0-mullvad");
        }

        function test_notesInThePopup() {
            const set = shownIn({}, own("popupnotes", false));
            answer(set.made, "v4", 200, "203.0.113.7");
            const firstAt = root.now;
            const page = popup(set.monitor);
            compare(addressLines(page).map(l => l.spoken)[1], "Public address 203.0.113.7");

            root.now += 61000;
            set.checker.egress = route("wg0", "enp195s0f3u1", true, false);
            answer(set.made, "v4", 200, "198.51.100.24");
            const time = words.timeOfDay(root.now / 1000, root.now);
            verify(visibleTexts(page).includes("Changed at " + time + ", was 203.0.113.7"), visibleTexts(page));

            root.now += 61000;
            set.checker.open = false;
            set.checker.open = true;
            compare(set.made.length, 3, "asked again");
            compare(addressLines(page).map(l => l.spoken)[1], "Public address 198.51.100.24 through VPN wg0");
            answer(set.made, "v4", 503, "");
            const seen = words.timeOfDay((root.now - 61000) / 1000, root.now);
            const shown = visibleTexts(page);
            verify(shown.includes("Can't reach popupnotes.example"), shown);
            verify(shown.includes("Last seen 198.51.100.24 at " + seen), shown);
            verify(firstAt < root.now);

            // Asked again after the failure, the last address stays in view
            // and the block keeps its height.
            waitForRendering(page);
            const height = block(page).implicitHeight;
            root.now += 61000;
            set.checker.open = false;
            set.checker.open = true;
            compare(set.made.length, 4, "asked again");
            compare(set.checker.status, "checking");
            waitForRendering(page);
            const asking = visibleTexts(page);
            verify(asking.includes("Asking popupnotes.example…"), asking);
            verify(asking.includes("Last seen 198.51.100.24 at " + seen), asking);
            compare(block(page).implicitHeight, height, "the block keeps its height");
        }

        // ---- The place a service names ----

        readonly property string osl4: JSON.stringify({ ip: "198.51.100.24", city: "Oslo", country: "Norway" })
        readonly property string fra4: JSON.stringify({ ip: "198.51.100.24", city: "Frankfurt am Main", country: "Germany" })
        readonly property string fra6: JSON.stringify({ ip: "2001:db8::1c", city: "Frankfurt am Main", country: "Germany" })

        // The visible place lines under the addresses, top to bottom.
        function placeTexts(page) {
            const b = block(page);
            return all(b, i => i instanceof Text && onScreen(i) && /^(Near|IPv4 near|IPv6 near) /.test(i.text))
                .sort((a, z) => a.mapToItem(b, Qt.point(0, 0)).y - z.mapToItem(b, Qt.point(0, 0)).y);
        }

        function placeY(item, page) {
            return item.mapToItem(block(page), Qt.point(0, 0)).y;
        }

        // One line when the families agree or only one address is shown, a
        // family's own line when they differ or only one of two addresses
        // has a place, none without a city; each address line is
        // read out with its own place, and the place lines aren't read again.
        function test_placesInThePopup_data() {
            const v6 = "2001:db8::1c";
            return [
                { tag: "IPv4 places", v4: [200, osl4], v6: [200, v6], places: ["IPv4 near Oslo, Norway"],
                  spoken: ["Public address 198.51.100.24, near Oslo, Norway", "Public address 2001:db8::1c"] },
                { tag: "IPv6 places", v4: [200, "198.51.100.24"], v6: [200, JSON.stringify({ ip: v6, city: "Bergen", country: "Norway" })],
                  places: ["IPv6 near Bergen, Norway"], spoken: ["Public address 198.51.100.24", "Public address 2001:db8::1c, near Bergen, Norway"] },
                { tag: "two places", v4: [200, osl4], v6: [200, JSON.stringify({ ip: v6, city: "Bergen", country: "Norway" })],
                  places: ["IPv4 near Oslo, Norway", "IPv6 near Bergen, Norway"],
                  spoken: ["Public address 198.51.100.24, near Oslo, Norway", "Public address 2001:db8::1c, near Bergen, Norway"] },
                { tag: "the same place", v4: [200, fra4], v6: [200, fra6], places: ["Near Frankfurt am Main, Germany"],
                  spoken: ["Public address 198.51.100.24, near Frankfurt am Main, Germany",
                           "Public address 2001:db8::1c, near Frankfurt am Main, Germany"] },
                { tag: "a city alone", v4: [200, JSON.stringify({ ip: "198.51.100.24", city: "Amsterdam" })], v6: [200, v6],
                  places: ["IPv4 near Amsterdam"], spoken: ["Public address 198.51.100.24, near Amsterdam", "Public address 2001:db8::1c"] },
                { tag: "a country alone", v4: [200, JSON.stringify({ ip: "198.51.100.24", country: "Netherlands" })], v6: [200, v6],
                  places: [], spoken: ["Public address 198.51.100.24", "Public address 2001:db8::1c"] },
                { tag: "no city", v4: [200, JSON.stringify({ ip: "198.51.100.24" })], v6: [200, JSON.stringify({ ip: v6 })],
                  places: [], spoken: ["Public address 198.51.100.24", "Public address 2001:db8::1c"] },
                { tag: "bare addresses", v4: [200, "198.51.100.24"], v6: [200, v6],
                  places: [], spoken: ["Public address 198.51.100.24", "Public address 2001:db8::1c"] },
                { tag: "IPv6 failed", v4: [200, osl4], v6: [503, fra6], places: ["Near Oslo, Norway"],
                  spoken: ["Public address 198.51.100.24, near Oslo, Norway"] }
            ];
        }
        function test_placesInThePopup(data) {
            const set = shownIn({}, own("places-" + data.tag.replace(/ /g, "")));
            const bare = popup(set.monitor);
            const before = block(bare).width;
            answer(set.made, "v4", data.v4[0], data.v4[1]);
            answer(set.made, "v6", data.v6[0], data.v6[1]);
            compare(set.made.length, 2, "one request per family");
            const page = popup(set.monitor);
            compare(placeTexts(page).map(t => t.text), data.places);
            compare(addressLines(page).slice(1).map(l => l.Accessible.name), data.spoken);
            const lastAddress = addressLines(page).pop();
            for (const t of placeTexts(page)) {
                verify(t.Accessible.ignored, "heard with its address: " + t.text);
                verify(!t.truncated, t.text + " fits");
                verify(placeY(t, page) >= placeY(lastAddress, page) + lastAddress.height - 1, "under the addresses: " + t.text);
            }
            compare(block(page).width, before, "the popup keeps its width");
        }

        // The places sit between the addresses and the note, as one group.
        function test_placeAboveTheNotes() {
            const set = shownIn({ egress: route("wg0-mullvad", "enp195s0f3u1", true, false) }, own("placenote"));
            answer(set.made, "v4", 200, osl4);
            answer(set.made, "v6", 200, fra6);
            const page = popup(set.monitor);
            const places = placeTexts(page);
            compare(places.map(t => t.text), ["IPv4 near Oslo, Norway", "IPv6 near Frankfurt am Main, Germany"]);
            const warning = all(page, i => i.text === "IPv6 doesn't go through wg0-mullvad")[0];
            verify(onScreen(warning));
            verify(placeY(places[0], page) < placeY(places[1], page));
            verify(placeY(places[1], page) + places[1].height <= placeY(warning, page) + 1, "the warning under the places");
            compare(visibleTexts(page).filter(t => /near/i.test(t)).length, 2, "said once each");
        }

        // A place goes with the address it came with: kept while the next
        // check is under way, replaced by the next answer's, and never kept
        // once the addresses go, as after a failure.
        function test_placeGoesWithTheAddress() {
            const set = shownIn({}, own("placefollows", false));
            answer(set.made, "v4", 200, osl4);
            const page = popup(set.monitor);
            compare(placeTexts(page).map(t => t.text), ["Near Oslo, Norway"]);

            root.now += 61000;
            set.checker.open = false;
            set.checker.open = true;
            compare(set.made.length, 2, "asked again");
            compare(placeTexts(page).map(t => t.text), ["Near Oslo, Norway"], "kept while asking");
            answer(set.made, "v4", 200, "198.51.100.24");
            compare(placeTexts(page).length, 0, "a bare answer names no place");
            compare(set.checker.record.result.places.v4, { city: "", country: "" });

            root.now += 61000;
            set.checker.open = false;
            set.checker.open = true;
            answer(set.made, "v4", 200, osl4);
            compare(placeTexts(page).map(t => t.text), ["Near Oslo, Norway"]);

            root.now += 61000;
            set.checker.open = false;
            set.checker.open = true;
            answer(set.made, "v4", 503, osl4);
            compare(set.checker.status, "failed");
            const shown = visibleTexts(page);
            verify(shown.some(t => t.indexOf("Last seen 198.51.100.24 at ") === 0), shown);
            compare(placeTexts(page).length, 0, "no place without its address");
            verify(!shown.some(t => t.indexOf("Oslo") >= 0), shown);
            compare(Object.keys(set.checker.record.seen.v4).sort(), ["address", "at"], "only the address is remembered");
        }

        // ipify.org answers with the address alone, so JSON from it is no
        // answer and never names a place.
        function test_ipifyJsonIsNoAnswer() {
            try {
                const set = shownIn({}, {});
                compare(set.made.map(r => r.url), ["https://api.ipify.org", "https://api6.ipify.org"]);
                answer(set.made, "v4", 200, osl4);
                answer(set.made, "v6", 200, JSON.stringify({ ip: "2001:db8::1c", city: "Oslo", country: "Norway" }));
                compare(set.checker.status, "failed");
                compare(set.checker.record.result.places, { v4: { city: "", country: "" }, v6: { city: "", country: "" } });
                const shown = visibleTexts(popup(set.monitor));
                verify(!shown.some(t => t.indexOf("Oslo") >= 0), shown);
            } finally {
                // So the tests after this one find ipify.org never asked.
                Lookup.forget();
            }
        }

        // Mullvad's JSON replies are read, so its place shows; still one
        // request per family, to its own hosts.
        function test_mullvadNamesThePlace() {
            const set = shownIn({}, { publicAddressUrl4: "https://ipv4.am.i.mullvad.net/json",
                                      publicAddressUrl6: "https://ipv6.am.i.mullvad.net/json" });
            compare(set.made.map(r => r.url), ["https://ipv4.am.i.mullvad.net/json", "https://ipv6.am.i.mullvad.net/json"]);
            answer(set.made, "v4", 200, JSON.stringify({ ip: "198.51.100.24", city: "Amsterdam", country: "Netherlands",
                                                         mullvad_exit_ip: true, blacklisted: { blacklisted: false, results: [] } }));
            answer(set.made, "v6", 503, "");
            compare(set.checker.status, "shown");
            compare(placeTexts(popup(set.monitor)).map(t => t.text), ["Near Amsterdam, Netherlands"]);
        }

        // A place is shown as the service spelled it, never as markup.
        function test_placeIsPlainText() {
            const city = "<a href=\"o\">Oslo</a>";
            const set = shownIn({}, own("markup", false));
            answer(set.made, "v4", 200, JSON.stringify({ ip: "198.51.100.24", city: city }));
            const page = popup(set.monitor);
            const t = placeTexts(page)[0];
            compare(t.text, "Near " + city);
            compare(t.textFormat, Text.PlainText);
            verify(!t.truncated, "fits");
            const links = [];
            for (let x = 0; x < t.width; x += 2) {
                const link = t.linkAt(x, t.height / 2);
                if (link !== "") {
                    links.push(link);
                }
            }
            compare(links, [], "no link in the line");
            compare(addressLines(page)[1].Accessible.name, "Public address 198.51.100.24, near " + city);
        }

        // A little room sets the places and the note apart from the addresses.
        function test_placesAndNotesSetApart_data() {
            const leak = route("wg0-mullvad", "enp195s0f3u1", true, false);
            return [{ tag: "a place alone", egress: route("enp195s0f3u1", "enp195s0f3u1"), v4: osl4,
                      first: "IPv4 near Oslo, Norway", note: false },
                    { tag: "a note alone", egress: leak, v4: "198.51.100.24", first: "IPv6 doesn't go through wg0-mullvad", note: true }];
        }
        function test_placesAndNotesSetApart(data) {
            const set = shownIn({ egress: data.egress }, own("apart-" + data.tag.replace(/ /g, "")));
            answer(set.made, "v4", 200, data.v4);
            answer(set.made, "v6", 200, "2001:db8::1c");
            const page = popup(set.monitor);
            const found = all(block(page), i => i.text === data.first && onScreen(i));
            compare(found.length, 1, data.first);
            // The note's text sits in a row with its icon.
            const first = data.note ? found[0].parent : found[0];
            const lastAddress = addressLines(page).pop();
            const room = Math.round(Kirigami.Units.smallSpacing / 2);
            verify(room > 0);
            fuzzyCompare(placeY(first, page) - placeY(lastAddress, page) - lastAddress.height, room, 0.5);
        }

        // Every checker of the service sees the place one of them was told.
        function test_sharedResultCarriesThePlace() {
            const config = own("placeshared");
            const a = checker({}, config);
            answer(a.made, "v4", 200, osl4);
            answer(a.made, "v6", 200, fra6);
            const b = shownIn({}, config);
            compare(b.made.length, 0, "within the minute, nothing more is asked");
            compare(a.made.length, 2, "one request per family");
            compare(b.checker.record.result.places, { v4: { city: "Oslo", country: "Norway" },
                                                      v6: { city: "Frankfurt am Main", country: "Germany" } });
            const page = popup(b.monitor);
            compare(placeTexts(page).map(t => t.text), ["IPv4 near Oslo, Norway", "IPv6 near Frankfurt am Main, Germany"]);
        }

        // Right to left, a place line starts at the right, as the notes do.
        function test_placeMirrored_data() {
            return [{ tag: "leftToRight", mirrored: false }, { tag: "rightToLeft", mirrored: true }];
        }
        function test_placeMirrored(data) {
            const set = shownIn({}, own("placemirror" + data.mirrored, false));
            answer(set.made, "v4", 200, osl4);
            const page = popup(set.monitor, data.mirrored);
            const t = placeTexts(page)[0];
            compare(t.effectiveHorizontalAlignment, data.mirrored ? Text.AlignRight : Text.AlignLeft);
            const b = block(page);
            const left = t.mapToItem(b, Qt.point(0, 0)).x;
            const right = t.mapToItem(b, Qt.point(t.width, 0)).x;
            verify(left >= -1 && right <= b.width + 1, "inside the block");
            const address = addressLines(page)[1];
            fuzzyCompare(left, address.mapToItem(b, Qt.point(0, 0)).x, 1, "in the addresses' column");
            fuzzyCompare(right, address.mapToItem(b, Qt.point(address.width, 0)).x, 1, "as wide as it");
        }

        // A long name is cut short at the end of its one line; the popup
        // keeps its width and the screen reader hears the whole name.
        function test_longPlaceElides_data() {
            return [{ tag: "leftToRight", mirrored: false }, { tag: "rightToLeft", mirrored: true }];
        }
        function test_longPlaceElides(data) {
            const city = "Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch";
            const country = "United Kingdom of Great Britain and Northern Ireland";
            const set = shownIn({}, own("placelong" + data.mirrored, false));
            const page = popup(set.monitor, data.mirrored);
            const width = block(page).width;
            answer(set.made, "v4", 200, JSON.stringify({ ip: "198.51.100.24", city: city, country: country }));
            waitForRendering(page);
            const t = placeTexts(page)[0];
            compare(t.text, "Near " + city + ", " + country);
            verify(t.truncated, "cut short");
            compare(t.lineCount, 1);
            compare(block(page).width, width, "the popup keeps its width");
            const b = block(page);
            verify(t.mapToItem(b, Qt.point(0, 0)).x >= -1 && t.mapToItem(b, Qt.point(t.width, 0)).x <= b.width + 1, "inside the block");
            compare(addressLines(page)[1].Accessible.name, "Public address 198.51.100.24, near " + city + ", " + country);
        }

        // ---- Trying a failed check again ----

        function tryAgain(page) {
            const found = all(page, i => i.text === "Try again");
            compare(found.length, 1, "one link");
            return found[0];
        }

        function onScreen(item) {
            for (let p = item; p; p = p.parent) {
                if (!p.visible) {
                    return false;
                }
            }
            return true;
        }

        // A popup whose last check failed, in the same minute as the check
        // before it, which found 198.51.100.24 and 2001:db8::1c. Both
        // families are asked of one host, as short a name as ipify.org's.
        function failedPopup(tag, mirrored, urls) {
            const config = Object.assign({ publicAddressUrl4: "https://" + tag + ".example/ip.txt",
                                           publicAddressUrl6: "https://" + tag + ".example/ip-6.txt" }, urls ?? {});
            const set = shownIn({}, config);
            answer(set.made, "v4", 200, "198.51.100.24");
            answer(set.made, "v6", 200, "2001:db8::1c");
            const page = popup(set.monitor, mirrored);
            root.now += 61000;
            set.checker.open = false;
            set.checker.open = true;
            compare(set.made.length, 4, "asked again");
            answer(set.made, "v4", 503, "");
            answer(set.made, "v6", 503, "");
            compare(set.checker.status, "failed");
            waitForRendering(page);
            return { set: set, page: page, config: config };
        }

        function test_tryAgainOnlyWhenFailed_data() {
            return [
                { tag: "failed", config: {}, fail: ["v4", "v6"], status: "failed" },
                { tag: "checking", config: {}, status: "checking" },
                { tag: "shown", config: {}, ok: ["v4", "v6"], status: "shown" },
                { tag: "one family failed", config: {}, ok: ["v4"], fail: ["v6"], status: "shown" },
                { tag: "offline", props: { egress: route("", "") }, config: {}, status: "offline" },
                { tag: "invalid", config: { publicAddressUrl4: "http://typo.example/ip" }, status: "invalid" },
                { tag: "unrouted", props: { egress: route("", "enp195s0f3u1") },
                  config: { publicAddressUrl4: "https://a.example/", publicAddressUrl6: "" }, status: "unrouted" },
                { tag: "off", config: { publicAddress: false }, status: "off" }
            ];
        }
        function test_tryAgainOnlyWhenFailed(data) {
            const set = shownIn(data.props ?? {}, Object.assign(own("only" + data.tag.replace(/ /g, "")), data.config));
            for (const family of data.ok ?? []) {
                answer(set.made, family, 200, family === "v4" ? "198.51.100.24" : "2001:db8::1c");
            }
            for (const family of data.fail ?? []) {
                answer(set.made, family, 503, "");
            }
            const page = popup(set.monitor);
            compare(set.checker.status, data.status);
            compare(onScreen(tryAgain(page)), data.status === "failed");
        }

        // The link asks at once, within the minute, one request per family;
        // the block says it is asking and keeps its size, and the answer
        // replaces the failure.
        function test_tryAgainAsksAtOnce() {
            const { set, page, config } = failedPopup("tryclick");
            const sent = set.made.length;
            const key = Lookup.service(config.publicAddressUrl4, config.publicAddressUrl6).key;
            const height = block(page).implicitHeight;
            verify(onScreen(tryAgain(page)));
            verify(visibleTexts(page).some(t => t.indexOf("Last seen 198.51.100.24 at ") === 0), visibleTexts(page));

            mouseClick(tryAgain(page));
            compare(set.made.length, sent + 2, "one request per family, within the minute");
            const fresh = set.made.slice(sent);
            compare(fresh.map(r => r.url).sort(), [config.publicAddressUrl4, config.publicAddressUrl6].sort());
            compare(fresh.map(r => r.sent), [true, true]);
            compare(set.checker.status, "checking");
            compare(Lookup.peek(key).attemptAt, root.now, "counts as a check");
            waitForRendering(page);
            compare(onScreen(tryAgain(page)), false);
            const asking = visibleTexts(page);
            verify(asking.includes("Asking tryclick.example…"), asking);
            verify(asking.some(t => t.indexOf("Last seen 198.51.100.24 at ") === 0), asking);
            compare(block(page).implicitHeight, height, "the block keeps its height");

            answer(set.made, "v4", 200, "203.0.113.7");
            answer(set.made, "v6", 200, "2001:db8::1c");
            compare(set.checker.status, "shown");
            compare(Lookup.peek(key).result.v4, "203.0.113.7");
            waitForRendering(page);
            compare(addressLines(page).map(l => l.spoken).slice(1),
                    ["Public address 203.0.113.7", "Public address 2001:db8::1c"]);
            compare(onScreen(tryAgain(page)), false);
            compare(set.made.length, sent + 2, "nothing else was sent");
        }

        // While a check is under way, another click sends nothing, from this
        // checker or from another Ringside widget's.
        function test_tryAgainWhileAsking() {
            const { set, page, config } = failedPopup("tryasking");
            const other = checker({}, config);
            compare(other.made.length, 0);
            const link = tryAgain(page);
            const sent = set.made.length;
            mouseClick(link);
            compare(set.made.length, sent + 2);
            compare(other.checker.status, "checking");

            // A click that was already on its way, and the checkers' own call.
            link.clicked({ button: Qt.LeftButton });
            mouseClick(link);
            set.checker.retry();
            other.checker.retry();
            compare(set.made.length, sent + 2, "asking, so nothing more");
            compare(other.made.length, 0, "another widget's check is waited for");

            answer(set.made, "v4", 200, "203.0.113.7");
            compare(set.checker.status, "checking", "one family still to answer");
            set.checker.retry();
            compare(set.made.length, sent + 2);
            answer(set.made, "v6", 503, "");
            compare(set.checker.status, "shown");
        }

        // A check that fails again leaves the link to try once more.
        function test_tryAgainFailsAgain() {
            const { set, page } = failedPopup("tryagain");
            const sent = set.made.length;
            mouseClick(tryAgain(page));
            answer(set.made, "v4", 0, "");
            answer(set.made, "v6", 0, "");
            compare(set.made.length, sent + 2);
            compare(set.checker.status, "failed");
            waitForRendering(page);
            verify(onScreen(tryAgain(page)), "offered again");
            mouseClick(tryAgain(page));
            compare(set.made.length, sent + 4);
            compare(set.checker.status, "checking");
        }

        // Space, Return and Enter on the focused link do the same as a click.
        function test_tryAgainByKeyboard_data() {
            return [
                { tag: "Space", key: Qt.Key_Space },
                { tag: "Return", key: Qt.Key_Return },
                { tag: "Enter", key: Qt.Key_Enter }
            ];
        }
        function test_tryAgainByKeyboard(data) {
            const { set, page } = failedPopup("trykey" + data.tag);
            const link = tryAgain(page);
            verify(link.activeFocusOnTab, "reached with Tab");
            link.forceActiveFocus(Qt.TabFocusReason);
            verify(link.activeFocus);
            const sent = set.made.length;
            keyClick(data.key);
            compare(set.made.length, sent + 2, "one request per family");
            compare(set.checker.status, "checking");
            keyClick(data.key);
            compare(set.made.length, sent + 2, "and not again while asking");
        }

        // Nothing is asked for a popup that is closed, a setting that is
        // off, no connection or a service that isn't valid.
        function test_tryAgainAsksNothingElse_data() {
            return [
                { tag: "popup closed", change: s => { s.checker.open = false; } },
                { tag: "switched off", change: s => { s.config.publicAddress = false; } },
                { tag: "no connection", change: s => { s.checker.egress = route("", ""); } },
                { tag: "invalid service", change: s => { s.config.publicAddressUrl4 = "http://typo.example/ip"; } }
            ];
        }
        function test_tryAgainAsksNothingElse(data) {
            const { set } = failedPopup("trynone" + data.tag.replace(/ /g, ""));
            const sent = set.made.length;
            data.change(set);
            set.checker.retry();
            compare(set.made.length, sent);
            compare(set.checker.pending, []);
        }

        // The link follows the block's direction: after the message, which
        // starts at the block's edge, with the note under both; named and
        // described for assistive technology.
        function test_tryAgainFollowsTheDirection_data() {
            return [{ tag: "leftToRight", mirrored: false }, { tag: "rightToLeft", mirrored: true }];
        }
        function test_tryAgainFollowsTheDirection(data) {
            const { page } = failedPopup("trydir" + data.mirrored, data.mirrored);
            const link = tryAgain(page);
            const row = link.parent;
            const message = find(row, i => typeof i.text === "string" && i.text.indexOf("Can't reach") === 0);
            verify(message);
            const span = i => ({ start: i.mapToItem(row, Qt.point(0, 0)).x, end: i.mapToItem(row, Qt.point(i.width, 0)).x });
            const m = span(message);
            const l = span(link);
            if (data.mirrored) {
                fuzzyCompare(m.end, row.width, 1, "the message against the right edge");
                verify(l.end <= m.start, "the link to its left: " + [m.start, l.end]);
            } else {
                fuzzyCompare(m.start, 0, 1, "the message against the left edge");
                verify(l.start >= m.end, "the link to its right: " + [m.end, l.start]);
            }
            verify(!message.truncated && !link.truncated);
            verify(Math.min(l.start, l.end) >= -1 && Math.max(l.start, l.end) <= row.width + 1, "inside the row");
            fuzzyCompare(link.mapToItem(row, Qt.point(0, link.baselineOffset)).y,
                         message.mapToItem(row, Qt.point(0, message.baselineOffset)).y, 1, "on the message's baseline");
            const note = find(page, i => typeof i.text === "string" && i.text.indexOf("Last seen") === 0);
            verify(note && onScreen(note));
            verify(note.mapToItem(page, Qt.point(0, 0)).y >= link.mapToItem(page, Qt.point(0, link.height)).y, "the note stays under");

            compare(link.Accessible.role, Accessible.Button);
            compare(link.Accessible.name, "Try again");
            compare(link.Accessible.description,
                    "Ask trydir" + data.mirrored + ".example for the public address again");
            compare(link.font.underline, false);
        }

        // Hosts too long for the line wrap the message, and the link stays
        // whole inside the block, as wide as the popup is.
        function test_tryAgainBesideALongName_data() {
            return [{ tag: "leftToRight", mirrored: false }, { tag: "rightToLeft", mirrored: true }];
        }
        function test_tryAgainBesideALongName(data) {
            const { page } = failedPopup("trylong" + data.mirrored, data.mirrored,
                                         { publicAddressUrl4: "https://lookup.very-long-hostname.example.net/ip",
                                           publicAddressUrl6: "https://lookup-6.another-long-hostname.example.org/ip" });
            const link = tryAgain(page);
            const row = link.parent;
            const message = find(row, i => typeof i.text === "string" && i.text.indexOf("Can't reach") === 0);
            verify(message.lineCount > 1, "wrapped over lines: " + message.lineCount);
            const inside = i => i.mapToItem(row, Qt.point(0, 0)).x >= -1 && i.mapToItem(row, Qt.point(i.width, 0)).x <= row.width + 1;
            verify(inside(message), "the message inside the row");
            verify(inside(link), "the link inside the row");
            verify(!link.truncated && link.width >= link.implicitWidth - 1, "the link in full");
            verify(row.width <= block(page).width, "the row inside the block");
            compare(block(page).width, page.width - 2 * Math.round(Kirigami.Units.largeSpacing * 2), "the popup keeps its width");
        }

        function test_otherStatesInThePopup_data() {
            return [
                { tag: "offline", props: { egress: route("", "") }, config: {}, text: "Waiting for a connection" },
                { tag: "invalid", props: {}, config: { publicAddressUrl4: "http://a.example/" },
                  text: "Check the address service in the settings" },
                { tag: "IPv4 only, without an IPv4 route", props: { egress: route("", "enp195s0f3u1") },
                  config: { publicAddressUrl4: "https://a.example/" }, text: "No IPv4 connection" },
                { tag: "IPv6 only, without an IPv6 route", props: { egress: route("enp195s0f3u1", "") },
                  config: { publicAddressUrl6: "https://b.example/" }, text: "No IPv6 connection" },
                { tag: "checking, two hosts", props: {},
                  config: { publicAddressUrl4: "https://a.example/", publicAddressUrl6: "https://b.example/" },
                  text: "Asking a.example and b.example…" }
            ];
        }
        function test_otherStatesInThePopup(data) {
            const set = shownIn(data.props, data.config);
            const page = popup(set.monitor);
            const shown = visibleTexts(page);
            verify(shown.includes(data.text), shown);
            verify(!shown.includes("Waiting for a connection") || data.tag === "offline", shown);
            compare(header(page).detail, "");
        }

        // Right to left, the block sits on the right and each address still
        // reads left to right, its interface after it.
        function test_mirroredAddressesStayLeftToRight_data() {
            return [{ tag: "leftToRight", mirrored: false }, { tag: "rightToLeft", mirrored: true }];
        }
        function test_mirroredAddressesStayLeftToRight(data) {
            const set = shownIn({ egress: route("wg0-mullvad", "enp195s0f3u1", true, false) }, own("mirror" + data.mirrored));
            answer(set.made, "v4", 200, "198.51.100.24");
            answer(set.made, "v6", 200, "2001:db8::1c");
            const page = popup(set.monitor, data.mirrored);
            for (const line of addressLines(page)) {
                const texts = all(line, i => i instanceof Text && i.visible && i.text !== " · ");
                for (const t of texts) {
                    verify(!t.truncated, t.text + " fits, so it isn't cut short");
                    compare(t.effectiveHorizontalAlignment, Text.AlignLeft, t.text + " starts where its slot does");
                }
                const address = texts.find(t => t.text === line.address);
                const via = texts.find(t => t.text === line.via);
                if (via) {
                    verify(address.mapToItem(line, Qt.point(0, 0)).x < via.mapToItem(line, Qt.point(0, 0)).x, line.spoken);
                }
                const last = via || address;
                const start = address.mapToItem(line, Qt.point(0, 0)).x;
                const end = last.mapToItem(line, Qt.point(last.width, 0)).x;
                if (data.mirrored) {
                    fuzzyCompare(end, line.width, 1, "against the right edge: " + line.spoken);
                } else {
                    fuzzyCompare(start, 0, 1, "against the left edge: " + line.spoken);
                }
            }
        }

        // An interface that won't fit beside a long address goes under it,
        // whole, rather than being cut to nothing.
        function test_longAddressPutsTheInterfaceUnder_data() {
            return [{ tag: "leftToRight", mirrored: false }, { tag: "rightToLeft", mirrored: true }];
        }
        function test_longAddressPutsTheInterfaceUnder(data) {
            const set = shownIn({ egress: route("enp195s0f3u1", "wg0-mullvad", false, true) }, own("longvia" + data.mirrored));
            answer(set.made, "v4", 200, "198.51.100.24");
            answer(set.made, "v6", 200, "dddd:dddd:dddd:dddd:dddd:dddd:dddd:dddd");
            const page = popup(set.monitor, data.mirrored);
            const line = addressLines(page).find(l => l.address.indexOf("dddd") === 0);
            compare(line.Accessible.name, "Public address dddd:dddd:dddd:dddd:dddd:dddd:dddd:dddd through VPN wg0-mullvad");
            const visible = i => {
                for (let p = i; p && p !== line; p = p.parent) {
                    if (!p.visible) {
                        return false;
                    }
                }
                return true;
            };
            const texts = all(line, i => i instanceof Text && visible(i));
            const address = texts.find(t => t.text === line.address);
            const via = texts.find(t => t.text === "wg0-mullvad");
            verify(via, "the interface is shown");
            verify(!via.truncated && via.width >= via.implicitWidth - 1, "in full: " + via.width);
            verify(via.mapToItem(line, Qt.point(0, 0)).y > address.mapToItem(line, Qt.point(0, 0)).y, "on the line under the address");
            compare(texts.filter(t => t.text === " · ").length, 0, "no dot leading the second line");
            verify(all(line, i => i.source === "network-vpn-symbolic" && visible(i)).length === 1, "the shield goes with it");
            for (const t of texts) {
                const x = t.mapToItem(line, Qt.point(0, 0)).x;
                verify(x >= -1 && x + t.width <= line.width + 1, t.text + " inside the line");
            }
            const ipv4 = addressLines(page).find(l => l.address === "198.51.100.24");
            compare(ipv4.roomy, true, "a short address keeps its interface beside it");
        }

        // ---- The settings ----

        // A fresh install sends nothing: the switch ships off and the
        // service at ipify.org, as main.xml has them, and a checker built
        // from those, with the popup open on a connection, asks nothing.
        function test_shippedDefaults() {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../package/contents/config/main.xml"), false);
            request.send();
            const xml = request.responseText;
            verify(xml !== "", "main.xml read; set QML_XHR_ALLOW_FILE_READ=1");
            const entryOf = key => {
                const entry = new RegExp('<entry name="' + key + '" type="(\\w+)">([\\s\\S]*?)</entry>').exec(xml);
                verify(entry, key + " in main.xml");
                return { type: entry[1], value: (/<default>([^<]*)<\/default>/.exec(entry[2]) || ["", ""])[1] };
            };
            compare(entryOf("publicAddress"), { type: "Bool", value: "false" });
            compare(entryOf("publicAddressUrl4"), { type: "String", value: "" });
            compare(entryOf("publicAddressUrl6"), { type: "String", value: "" });
            const set = checker({}, { publicAddress: entryOf("publicAddress").value === "true" });
            compare(set.checker.status, "off");
            compare(set.checker.serviceName, "ipify.org");
            wait(50);
            compare(set.made.length, 0);
        }

        // The General page, right to left if asked, as an RTL language lays it out.
        function general(props, mirrored) {
            const page = createTemporaryObject(generalComponent, root, Object.assign({ rightToLeft: mirrored === true }, props));
            verify(page);
            waitForRendering(page);
            return page;
        }

        // The page's public address controls, found as a user meets them.
        function controls(page) {
            const field = name => find(page, i => i instanceof QQC2.TextField && i.Accessible.name === name);
            const c = {
                box: find(page, i => i instanceof QQC2.CheckBox && i.text === "Show in the Network popup"),
                line: find(page, i => i instanceof QQC2.Label && i.text.indexOf("Asks ") === 0),
                service: find(page, i => i instanceof QQC2.ComboBox && i.Accessible.name === "Service"),
                url4: field("IPv4 URL"),
                url6: field("IPv6 URL"),
                json: find(page, i => i instanceof QQC2.Label && i.text === "Each answers with the address, or JSON with ip and city.")
            };
            for (const name in c) {
                verify(c[name], name);
            }
            return c;
        }

        // The red reason under a URL field, or "" while there is none.
        function reason(field) {
            const shown = all(field.parent, i => i instanceof QQC2.Label && i.visible);
            verify(shown.length <= 1);
            verify(shown.every(i => i.text !== ""), "no empty reason takes room");
            return shown.length === 1 ? shown[0].text : "";
        }

        function typeIn(field, text) {
            field.forceActiveFocus();
            field.selectAll();
            keyClick(Qt.Key_Delete);
            for (const c of text) {
                keyClick(c);
            }
            compare(field.text, text);
        }

        // Picks a service from the open list with the keyboard.
        function pick(c, row) {
            c.service.forceActiveFocus();
            keyClick(Qt.Key_Space);
            tryCompare(c.service.popup, "opened", true);
            const steps = row - c.service.currentIndex;
            for (let i = 0; i < Math.abs(steps); i++) {
                keyClick(steps > 0 ? Qt.Key_Down : Qt.Key_Up);
            }
            keyClick(Qt.Key_Return);
            tryCompare(c.service.popup, "visible", false);
            compare(c.service.currentIndex, row);
        }

        // The line sits under the box's text, at the side it starts from.
        function verifyUnderTheBox(page, c) {
            verify(c.line.visible, "the line shows");
            const text = c.box.contentItem;
            const box = c.box.mapToItem(page, Qt.point(0, 0));
            const line = c.line.mapToItem(page, Qt.point(0, 0));
            const start = text.mapToItem(page, Qt.point(0, 0));
            verify(line.y >= box.y + c.box.height - 0.5, "the line is under the box");
            if (c.box.mirrored) {
                fuzzyCompare(line.x + c.line.width - c.line.rightPadding, start.x + text.width - text.rightPadding, 1,
                             "under the box's text, right to left");
                compare(c.line.effectiveHorizontalAlignment, Text.AlignRight);
            } else {
                fuzzyCompare(line.x + c.line.leftPadding, start.x + text.leftPadding, 1, "under the box's text");
                compare(c.line.effectiveHorizontalAlignment, Text.AlignLeft);
            }
        }

        // One line under the box says whom Ringside asks and what they
        // learn, the same with the box off or on, except that "until you
        // enter a URL" waits for the fields to show. The box and the service
        // list carry it for a screen reader.
        function test_settingsLine_data() {
            const sees = who => "Asks " + who + ", which sees your address, when the popup opens.";
            return [
                { tag: "ipify", line: sees("ipify.org") },
                { tag: "one custom host", url4: "https://a.example/ip", line: sees("a.example") },
                { tag: "one host for both", url4: "https://a.example/4", url6: "https://A.example/6", line: sees("a.example") },
                { tag: "IPv6 only", url6: "https://b.example/ip", line: sees("b.example") },
                { tag: "two hosts", url4: "https://a.example/ip", url6: "https://b.example/ip",
                  line: "Asks a.example and b.example, which see your address, when the popup opens." },
                { tag: "custom, both empty", custom: true, line: "Asks ipify.org, which sees your address, until you enter a URL.",
                  off: sees("ipify.org") },
                { tag: "invalid", url4: "http://a.example/ip", url6: "https://b.example/ip", line: "Asks nothing while a URL isn't valid." },
                { tag: "mirrored", url4: "https://a.example/ip", mirrored: true, line: sees("a.example") }
            ];
        }
        function test_settingsLine(data) {
            const page = general({ cfg_publicAddress: false, cfg_publicAddressUrl4: data.url4 ?? "", cfg_publicAddressUrl6: data.url6 ?? "" },
                                 data.mirrored);
            const c = controls(page);
            mouseClick(c.box);
            compare(page.cfg_publicAddress, true);
            if (data.custom) {
                pick(c, root.customRow);
            }
            for (const on of [true, false, true]) {
                if (page.cfg_publicAddress !== on) {
                    mouseClick(c.box);
                }
                compare(c.box.checked, on);
                waitForRendering(page);
                const line = on ? data.line : data.off ?? data.line;
                compare(c.line.text, line, on ? "ticked" : "unticked");
                compare(c.box.Accessible.description, line);
                compare(c.service.Accessible.description, line);
                verifyUnderTheBox(page, c);
            }
        }

        // The line takes the box's padding from the side its text starts at.
        function test_settingsLineFollowsThePadding_data() {
            return [{ tag: "left to right", mirrored: false }, { tag: "right to left", mirrored: true }];
        }
        function test_settingsLineFollowsThePadding(data) {
            const page = general({ cfg_publicAddress: false }, data.mirrored);
            const c = controls(page);
            c.box.leftPadding = 3;
            c.box.rightPadding = 9;
            waitForRendering(page);
            verifyUnderTheBox(page, c);
        }

        // The box shows the stored setting and follows it, as when Defaults
        // resets it after a click.
        function test_settingsBoxFollowsTheSetting() {
            const page = general({ cfg_publicAddress: true });
            const c = controls(page);
            compare(c.box.checked, true);
            compare(c.service.visible, true);
            for (const on of [false, true]) {
                mouseClick(c.box);
                compare(page.cfg_publicAddress, on);
                compare(c.box.checked, on);
            }
            for (const on of [page.cfg_publicAddressDefault, true]) {
                page.cfg_publicAddress = on;
                compare(c.box.checked, on);
                compare(c.service.visible, on);
            }
        }

        // Off, only the box and its line show; on, the service list too, and
        // the URL fields with a custom service.
        function test_settingsServiceRows_data() {
            return [{ tag: "ipify", url: "", custom: false, row: root.ipifyRow },
                    { tag: "mullvad", url: "https://ipv4.am.i.mullvad.net/json", url6: "https://ipv6.am.i.mullvad.net/json",
                      custom: false, row: root.mullvadRow },
                    { tag: "custom", url: "https://a.example/ip", custom: true, row: root.customRow }];
        }
        function test_settingsServiceRows(data) {
            const page = general({ cfg_publicAddress: false, cfg_publicAddressUrl4: data.url,
                                   cfg_publicAddressUrl6: data.url6 ?? "" });
            const c = controls(page);
            const shown = () => [c.service.visible, c.url4.visible, c.url6.visible, c.json.visible];
            compare(shown(), [false, false, false, false]);
            mouseClick(c.box);
            compare(page.cfg_publicAddress, true);
            compare(shown(), [true, data.custom, data.custom, data.custom]);
            compare(c.service.model, ["ipify.org", "am.i.mullvad.net", "Custom"]);
            compare(c.service.currentIndex, data.row);
            mouseClick(c.box);
            compare(page.cfg_publicAddress, false);
            compare(shown(), [false, false, false, false]);
        }

        // Custom opens on empty fields with the first focused; picking
        // ipify.org empties the URLs, and Custom brings them back.
        function test_settingsCustom() {
            const page = general({ cfg_publicAddress: true });
            const c = controls(page);
            pick(c, root.customRow);
            compare([c.url4.visible, c.url6.visible], [true, true]);
            compare([c.url4.text, c.url6.text], ["", ""]);
            compare([c.url4.placeholderText, c.url6.placeholderText], ["", ""]);
            verify(c.url4.activeFocus, "the IPv4 field has the focus");
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], ["", ""]);
            for (const field of [c.url4, c.url6]) {
                compare(field.parent.Kirigami.FormData.buddyFor, field, field.Accessible.name + "'s label names it");
            }

            typeIn(c.url4, "https://a.example/ip");
            typeIn(c.url6, "https://b.example/ip");
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], ["https://a.example/ip", "https://b.example/ip"]);
            compare(c.line.text, "Asks a.example and b.example, which see your address, when the popup opens.");

            pick(c, root.ipifyRow);
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], ["", ""]);
            compare([c.url4.visible, c.url6.visible], [false, false]);
            compare(c.line.text, "Asks ipify.org, which sees your address, when the popup opens.");

            pick(c, root.customRow);
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], ["https://a.example/ip", "https://b.example/ip"]);
            compare([c.url4.text, c.url6.text], ["https://a.example/ip", "https://b.example/ip"]);

            // Emptying both by hand keeps Custom open, asking ipify.org meanwhile.
            typeIn(c.url4, "");
            typeIn(c.url6, "");
            compare(c.service.currentIndex, root.customRow);
            compare([c.url4.visible, c.url6.visible], [true, true]);
            compare(c.line.text, "Asks ipify.org, which sees your address, until you enter a URL.");
        }

        // Picking the service already shown changes nothing: ipify.org twice
        // still keeps the URLs for Custom, and Custom again keeps what was typed.
        function test_settingsPickedAgain() {
            const page = general({ cfg_publicAddress: true, cfg_publicAddressUrl4: "https://a.example/ip",
                                   cfg_publicAddressUrl6: "https://b.example/ip" });
            const c = controls(page);
            pick(c, root.ipifyRow);
            pick(c, root.ipifyRow);
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], ["", ""]);
            pick(c, root.customRow);
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], ["https://a.example/ip", "https://b.example/ip"]);
            typeIn(c.url4, "https://c.example/ip");
            pick(c, root.customRow);
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], ["https://c.example/ip", "https://b.example/ip"]);
            compare(c.url4.text, "https://c.example/ip");
        }

        // Arrow keys on the closed list change the service but leave the
        // focus on it, so the next arrow can step back.
        function test_settingsArrowKeys() {
            const page = general({ cfg_publicAddress: true });
            const c = controls(page);
            c.service.forceActiveFocus();
            const steps = [[Qt.Key_Down, root.mullvadRow, false], [Qt.Key_Down, root.customRow, true],
                           [Qt.Key_Up, root.mullvadRow, false], [Qt.Key_Up, root.ipifyRow, false]];
            for (const [key, row, fields] of steps) {
                keyClick(key);
                compare(c.service.currentIndex, row);
                compare(c.url4.visible, fields, "fields at row " + row);
                verify(c.service.activeFocus, "the list keeps the focus");
            }
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], ["", ""]);
        }

        // Mullvad writes its own pair of URLs and names itself in the line;
        // ipify.org from there empties them, and Custom brings back what
        // Custom held, not Mullvad's.
        function test_settingsMullvad() {
            const mullvad = ["https://ipv4.am.i.mullvad.net/json", "https://ipv6.am.i.mullvad.net/json"];
            const page = general({ cfg_publicAddress: true, cfg_publicAddressUrl4: "https://a.example/ip" });
            const c = controls(page);
            compare(c.service.currentIndex, root.customRow);
            pick(c, root.mullvadRow);
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], mullvad);
            compare([c.url4.visible, c.url6.visible, c.json.visible], [false, false, false]);
            compare(c.line.text, "Asks am.i.mullvad.net, which sees your address, when the popup opens.");
            pick(c, root.customRow);
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], ["https://a.example/ip", ""]);
            pick(c, root.mullvadRow);
            pick(c, root.ipifyRow);
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], ["", ""]);
            compare(c.line.text, "Asks ipify.org, which sees your address, when the popup opens.");
            pick(c, root.mullvadRow);
            pick(c, root.customRow);
            compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], ["https://a.example/ip", ""],
                    "Custom keeps its own URLs through Mullvad and ipify.org");
        }

        // The wheel over the list leaves the service, and the URLs, alone.
        function test_settingsWheel_data() {
            return [{ tag: "ipify", url: "", index: root.ipifyRow }, { tag: "custom", url: "https://a.example/ip", index: root.customRow }];
        }
        function test_settingsWheel(data) {
            const page = general({ cfg_publicAddress: true, cfg_publicAddressUrl4: data.url });
            const c = controls(page);
            verify(!c.service.wheelEnabled);
            for (const delta of [120, -120]) {
                mouseWheel(c.service, c.service.width / 2, c.service.height / 2, 0, delta);
                compare(c.service.currentIndex, data.index);
                compare([page.cfg_publicAddressUrl4, page.cfg_publicAddressUrl6], [data.url, ""]);
            }
        }

        // A stored URL of spaces asks ipify.org, and one pick of Custom opens
        // the fields.
        function test_settingsStoredBlank() {
            const page = general({ cfg_publicAddress: true, cfg_publicAddressUrl4: " " });
            const c = controls(page);
            compare(c.service.currentIndex, root.ipifyRow);
            compare(c.url4.visible, false);
            pick(c, root.customRow);
            compare([c.url4.visible, c.url6.visible], [true, true]);
            verify(c.url4.activeFocus, "the IPv4 field has the focus");
            compare(c.line.text, "Asks ipify.org, which sees your address, until you enter a URL.");
        }

        // A stored URL emptied by hand keeps Custom open, asking ipify.org
        // meanwhile, rather than taking the field away while it is typed in.
        function test_settingsEmptiedByHand() {
            const page = general({ cfg_publicAddress: true, cfg_publicAddressUrl4: "https://a.example/ip" });
            const c = controls(page);
            compare(c.service.currentIndex, root.customRow);
            compare(c.url4.cursorPosition, 0, "a stored URL opens at its start");
            typeIn(c.url4, "");
            compare(page.cfg_publicAddressUrl4, "");
            compare(c.service.currentIndex, root.customRow);
            compare([c.url4.visible, c.url6.visible], [true, true]);
            verify(c.url4.activeFocus, "the field keeps the focus");
            compare(c.line.text, "Asks ipify.org, which sees your address, until you enter a URL.");
        }

        // Defaults empties both URLs, which is ipify.org again, so Custom
        // closes, from stored URLs or ones typed on the page.
        function test_settingsDefaults_data() {
            return [{ tag: "stored", url4: "https://a.example/ip" },
                    { tag: "both stored", url4: "https://a.example/ip", url6: "https://b.example/ip" },
                    { tag: "typed", typed: "url4" },
                    { tag: "typed IPv6 only", typed: "url6" }];
        }
        function test_settingsDefaults(data) {
            const page = general({ cfg_publicAddress: true, cfg_publicAddressUrl4: data.url4 ?? "",
                                   cfg_publicAddressUrl6: data.url6 ?? "" });
            const c = controls(page);
            if (data.typed) {
                pick(c, root.customRow);
                typeIn(c[data.typed], "https://a.example/ip");
            }
            compare(c.service.currentIndex, root.customRow);
            compare(c.url4.visible, true);
            // Clicking Defaults takes the focus from the field, as a button does.
            c.box.forceActiveFocus();
            for (const key of ["publicAddressUrl4", "publicAddressUrl6"]) {
                page["cfg_" + key] = page["cfg_" + key + "Default"];
            }
            compare(c.service.currentIndex, root.ipifyRow);
            compare([c.url4.visible, c.url6.visible], [false, false]);
            compare(c.line.text, "Asks ipify.org, which sees your address, when the popup opens.");
        }

        // A URL that isn't valid says why under its field, and the line says
        // nothing is asked; spaces around a URL are fine.
        function test_settingsUrlReasons_data() {
            const rows = [];
            for (const name of ["IPv4 URL", "IPv6 URL"]) {
                rows.push({ tag: name + " http", name: name, url: "http://a.example/ip", reason: "Only https:// addresses work." },
                          { tag: name + " no scheme", name: name, url: "a.example", reason: "Only https:// addresses work." },
                          { tag: name + " user", name: name, url: "https://me:pw@a.example/", reason: "Leave out the user name and password." },
                          { tag: name + " no host", name: name, url: "https://", reason: "Check the host name." },
                          { tag: name + " bad host", name: name, url: "https://a_b.example/", reason: "Check the host name." },
                          { tag: name + " capitals, bad host", name: name, url: "HTTPS://a_b.example/", reason: "Check the host name." },
                          { tag: name + " capitals, user", name: name, url: "HTTPS://me:pw@a.example/",
                            reason: "Leave out the user name and password." },
                          { tag: name + " spaces", name: name, url: " https://a.example/ip ", reason: "" });
            }
            return rows;
        }
        function test_settingsUrlReasons(data) {
            const page = general({ cfg_publicAddress: true });
            const c = controls(page);
            pick(c, root.customRow);
            const field = data.name === "IPv4 URL" ? c.url4 : c.url6;
            const other = field === c.url4 ? c.url6 : c.url4;
            typeIn(field, data.url);
            compare(reason(field), data.reason);
            compare(field.Accessible.description, data.reason);
            compare(reason(other), "");
            compare(c.line.text, data.reason === "" ? "Asks a.example, which sees your address, when the popup opens."
                                                    : "Asks nothing while a URL isn't valid.");
            if (data.reason !== "") {
                waitForRendering(page);
                const note = all(field.parent, i => i instanceof QQC2.Label && i.visible)[0];
                compare(note.color, Kirigami.Theme.negativeTextColor);
                verify(note.mapToItem(page, Qt.point(0, 0)).y >= field.mapToItem(page, Qt.point(0, 0)).y + field.height - 0.5,
                       "the reason is under its field");
            }
            typeIn(field, "");
            compare(reason(field), "", "an empty field is fine");
        }

        // Right to left, the labels sit right of the fields, and a URL still
        // reads left to right inside its field, even one that starts with
        // Arabic letters. The reason under it follows the page.
        function test_settingsUrlLeftToRight() {
            const page = general({ cfg_publicAddress: true, cfg_publicAddressUrl4: "https://a.example/ip",
                                   cfg_publicAddressUrl6: "مثال" }, true);
            const c = controls(page);
            verify(c.box.mirrored, "the page is right to left");
            compare(c.service.currentIndex, root.customRow);
            for (const field of [c.url4, c.url6]) {
                verify(!field.mirrored, field.Accessible.name + " mirrored");
                compare(field.effectiveHorizontalAlignment, TextInput.AlignLeft, field.Accessible.name);
            }
            typeIn(c.url6, "http://b.example/ip");
            compare(reason(c.url6), "Only https:// addresses work.");
            const note = all(c.url6.parent, i => i instanceof QQC2.Label && i.visible)[0];
            compare(note.effectiveHorizontalAlignment, Text.AlignRight);
            const label = find(page, i => i instanceof QQC2.Label && i.text === "IPv4 URL:");
            verify(label);
            verify(label.mapToItem(page, Qt.point(0, 0)).x >= c.url4.mapToItem(page, Qt.point(0, 0)).x + c.url4.width - 0.5,
                   "the label sits right of its field");
        }

        // ---- Monitor ----

        // The route facts are read only while the network popup shows the
        // public address, and the User-Agent carries the widget's version.
        function test_monitor_data() {
            return [{ tag: "versioned", version: "0.3.0", agent: "ringside/0.3.0" },
                    { tag: "no version", version: "", agent: "ringside" }];
        }
        // A real Monitor on a config of its own, with fake requests.
        function realMonitor(urlHost, version, enabled) {
            const config = createTemporaryObject(realConfigComponent, root);
            config.publicAddressUrl4 = "https://" + urlHost + ".example/ip";
            config.publicAddress = enabled;
            // Not a temporary object: a monitor has to go before its config.
            const monitor = realMonitorComponent.createObject(root, {
                config: config, version: version,
                helperPath: decodeURIComponent(Qt.resolvedUrl("data/fake-info.sh").toString().replace(/^file:\/\//, ""))
            });
            monitors.push(monitor);
            const fake = requests();
            monitor.publicAddress.makeRequest = fake.make;
            monitor.publicAddress.clock = () => root.now;
            // What the monitor's polled helper runs, of which the route facts end in " egress".
            const polled = () => Array.from(monitor.data)
                .filter(o => o && o.engine === "executable" && o.interval === 3000)
                .reduce((list, o) => list.concat(Array.from(o.connectedSources)), []);
            return { config: config, monitor: monitor, fake: fake, polled: polled,
                     egress: () => polled().filter(source => source.endsWith(" egress")) };
        }

        function test_monitor(data) {
            const { config, monitor, fake, polled, egress } = realMonitor("monitor-" + data.tag.replace(" ", ""), data.version, true);
            for (const open of ["", "cpu", "disk"]) {
                monitor.openPopup = open;
                compare(egress().length, 0, "with " + (open || "nothing") + " open");
            }
            // Route facts alone don't send while the network popup is closed.
            monitor.egress = route("eth9", "eth9");
            compare(fake.made.length, 0, "nothing sent with the popup closed");
            monitor.egress = null;
            monitor.openPopup = "network";
            compare(egress().length, 1, JSON.stringify(polled()));
            tryVerify(() => monitor.egress !== null, 10000, "the stub's routes arrive");
            compare(monitor.egress, { known: true, v4: { device: "eth9", tunnel: false }, v6: { device: "", tunnel: false } });
            compare(fake.made.map(r => r.url), [config.publicAddressUrl4], "IPv6 has no route");
            compare(fake.made[0].headers["User-Agent"], data.agent);

            monitor.openPopup = "";
            compare(egress().length, 0);
            compare(monitor.egress, null, "forgotten when the popup closes");
            monitor.openPopup = "network";
            compare(egress().length, 1);
            config.publicAddress = false;
            compare(egress().length, 0, "not read while off");
            compare(monitor.publicAddress.status, "off");
            monitor.openPopup = "";
        }

        // Off, as shipped, nothing is read or asked even with the popup open,
        // nor with the setting missing or not a Bool; switching it on in the
        // settings starts both.
        function test_monitorSwitchedOn_data() {
            return [{ tag: "off", off: false }, { tag: "no setting", off: undefined }, { tag: "not a Bool", off: "on" }];
        }
        function test_monitorSwitchedOn(data) {
            const { config, monitor, fake, egress } = realMonitor("monitor-switchon-" + data.tag.replace(/ /g, ""), "0.3.0", data.off);
            monitor.openPopup = "network";
            wait(100);
            compare(egress().length, 0, "no route facts read");
            compare(monitor.egress, null);
            compare(fake.made.length, 0);
            compare(monitor.publicAddress.status, "off");
            config.publicAddress = true;
            compare(egress().length, 1);
            tryVerify(() => monitor.egress !== null, 10000, "the stub's routes arrive");
            compare(fake.made.map(r => r.url), [config.publicAddressUrl4]);
            monitor.openPopup = "";
        }
    }
}
