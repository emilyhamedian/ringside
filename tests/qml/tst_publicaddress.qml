// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/config"
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

    Component {
        id: configComponent
        QtObject {
            property bool publicAddress: true
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
        id: realConfigComponent
        QtObject {
            property int updateInterval: 1000
            property int historySeconds: 60
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
            property bool publicAddress: true
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
            failOnWarning(/TypeError|ReferenceError|SyntaxError|is not a function|Unable to assign|Cannot assign|Binding loop/);
            // Well past any check an earlier test made.
            root.now += 1e9;
        }

        property var monitors: []

        function cleanup() {
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
            const r = made.find(m => !m.aborted && m.readyState !== 4 && (family === "v6") === /-6\.|api6\./.test(m.url));
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
            const ipify = { custom: false, valid: true, v4: "https://api.ipify.org", v6: "https://api6.ipify.org",
                            hosts: ["ipify.org"], key: "ipify" };
            compare(Lookup.service("", ""), ipify);
            compare(Lookup.service(undefined, null), ipify);
            compare(Lookup.service("  ", "\t"), ipify, "white space alone is empty");

            const one = Lookup.service(" https://a.example/ip ", "");
            compare(one.valid, true);
            compare([one.v4, one.v6], ["https://a.example/ip", ""], "an empty field leaves its family unchecked");
            compare(one.hosts, ["a.example"]);

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
            compare(vpn.v4, { address: "198.51.100.24", via: "wg0", tunnel: true });
            compare(vpn.v6, { address: "2001:db8::1c", via: "", tunnel: false }, "no via through the local interface");
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
                { tag: "network error", status: 0, body: "" }
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
            r.responseText = "1".repeat(5000);
            r.readyState = 3;
            r.onreadystatechange();
            compare(r.aborted, true);
            compare(set.checker.status, "failed");
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
            set.config.publicAddress = false;
            compare(set.made.map(r => r.aborted), [true, true]);
            compare(set.checker.status, "off");
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

        function general(props) {
            const page = createTemporaryObject(generalComponent, root, props);
            verify(page);
            waitForRendering(page);
            return page;
        }

        function test_settingsCheckbox_data() {
            return [{ tag: "on", stored: true, checked: true }, { tag: "off", stored: false, checked: false }];
        }
        function test_settingsCheckbox(data) {
            const page = general({ cfg_publicAddress: data.stored });
            const box = find(page, i => i instanceof QQC2.CheckBox && i.text === "Ask ipify.org for it");
            verify(box, "the checkbox names ipify.org");
            compare(box.checked, data.checked);
            mouseClick(box);
            compare(page.cfg_publicAddress, !data.checked);
            mouseClick(box);
            compare(page.cfg_publicAddress, data.checked);
            const note = visibleTexts(page).find(t => t.indexOf("Shows the address websites see") === 0);
            verify(note.indexOf("api.ipify.org and api6.ipify.org") >= 0, note);
        }

        function test_settingsFields() {
            const page = general({ cfg_publicAddress: true });
            const field = name => find(page, i => i instanceof QQC2.TextField && i.Accessible.name === name);
            const four = field("IPv4 address URL");
            const six = field("IPv6 address URL");
            compare([four.placeholderText, six.placeholderText], ["https://api.ipify.org", "https://api6.ipify.org"]);
            const errors = () => visibleTexts(page).filter(t => t.indexOf("Use an https:// address") === 0).length;
            compare(errors(), 0);

            four.text = "https://a.example/ip";
            four.textEdited();
            compare(page.cfg_publicAddressUrl4, "https://a.example/ip");
            verify(find(page, i => i instanceof QQC2.CheckBox && i.text === "Ask a.example for it"));
            const note = visibleTexts(page).find(t => t.indexOf("Shows the address websites see") === 0);
            verify(note.indexOf("Ringside asks only a.example, at the addresses below") >= 0, note);

            six.text = "https://b.example/ip";
            six.textEdited();
            compare(page.cfg_publicAddressUrl6, "https://b.example/ip");
            verify(find(page, i => i instanceof QQC2.CheckBox && i.text === "Ask a.example and b.example for it"));

            for (const bad of ["http://a.example/ip", "https://me:pw@a.example/", "https://", "a.example"]) {
                four.text = bad;
                four.textEdited();
                compare(errors(), 1, bad);
                compare(four.Accessible.description.indexOf("Use an https:// address"), 0);
                verify(find(page, i => i instanceof QQC2.CheckBox && i.text === "Ask the address service for it"),
                       "an invalid service isn't named after its other URL");
                verify(visibleTexts(page).some(t => t.indexOf("Ringside asks nothing until the addresses below are fixed.") > 0));
            }
            four.text = "";
            four.textEdited();
            compare(errors(), 0, "an empty field is fine");
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

        // Off, as shipped, nothing is read or asked even with the popup open;
        // switching it on in the settings starts both.
        function test_monitorSwitchedOn() {
            const { config, monitor, fake, egress } = realMonitor("monitor-switchon", "0.3.0", false);
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
