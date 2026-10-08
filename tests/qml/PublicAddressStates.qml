// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import "../../package/contents/ui"
import "../../package/contents/ui/code/publicaddress.js" as Lookup

// The public address lookup in each state the network popup shows, for the
// gallery: the real checker runs through canned replies and route facts,
// and what it ends up showing is kept, frozen, for FakeMonitor.publicAddress.
// Its requests are stand-ins that answer from the replies given; nothing is
// sent anywhere. Checks share their records by service, so each state starts
// from a clean slate and they are worked out one after another.
QtObject {
    id: states

    // The interface the popup's monitor names as local, and the moment of
    // the last check: a fixed time, so the notes read the same every run.
    property string localInterface: "enp195s0f3u1"
    property real at: new Date(2026, 9, 7, 14, 2).getTime()
    // name -> a lookup frozen in that state, filled in when this is created.
    property var all: ({})

    property Component checkerComponent: Component {
        PublicAddress {}
    }
    property Component configComponent: Component {
        QtObject {
            property bool publicAddress: true
            property string publicAddressUrl4: ""
            property string publicAddressUrl6: ""
        }
    }

    function route(v4, v6, tunnel4, tunnel6) {
        return { known: true, v4: { device: v4, tunnel: !!tunnel4 }, v6: { device: v6, tunnel: !!tunnel6 } };
    }

    // Runs `steps`, each { egress, v4, v6 } with the replies as [status,
    // body] (none: never answered), a minute apart, the step `last` one at
    // `at`, and keeps what the checker shows after the last step.
    function run(steps, config, last) {
        Lookup.forget();
        let now = states.at - 61000 * (last ?? steps.length - 1);
        let replies = {};
        const make = () => ({
            readyState: 0, status: 0, responseText: "", url: "", responseURL: "", onreadystatechange: null,
            open(method, url) { this.url = url; },
            setRequestHeader() {},
            abort() {},
            send() {
                const reply = replies[this.url];
                if (reply) {
                    this.status = reply[0];
                    this.responseURL = this.url;
                    this.responseText = reply[1];
                    this.readyState = XMLHttpRequest.DONE;
                    this.onreadystatechange();
                }
            }
        });
        const c = configComponent.createObject(states, config || {});
        const checker = checkerComponent.createObject(null, { config: c, clock: () => now, makeRequest: make, localAddress: "192.0.2.1" });
        steps.forEach((step, n) => {
            const service = Lookup.service(c.publicAddressUrl4, c.publicAddressUrl6);
            replies = {};
            if (step.v4) {
                replies[service.v4] = step.v4;
            }
            if (step.v6) {
                replies[service.v6] = step.v6;
            }
            if (n > 0) {
                now += 61000;
                checker.open = false;
            }
            checker.egress = step.egress;
            checker.open = true;
        });
        const frozen = { status: checker.status, service: checker.service, serviceName: checker.serviceName, record: checker.record,
                         clock: () => states.at };
        // Off before it goes: destroy() waits for the event loop, and a checker
        // still on would answer the next state's checks.
        c.publicAddress = false;
        checker.destroy();
        c.destroy();
        return frozen;
    }

    Component.onCompleted: {
        const home = route(localInterface, localInterface);
        const homeV4 = route(localInterface, "");
        const vpn = route("wg0-mullvad", "", true);
        const leak = route("wg0-mullvad", localInterface, true);
        const ok4 = [200, "203.0.113.7\n"];
        const long6 = [200, "2001:db8:85a3:4d1c:9d2e:51f4:c8a3:7e61"];
        all = {
            both: run([{ egress: home, v4: ok4, v6: [200, "2001:db8:4f2a::1c"] }]),
            vpn: run([{ egress: homeV4, v4: ok4 }, { egress: vpn, v4: [200, "198.51.100.24"] }]),
            longvpn: run([{ egress: route("wg0-mullvad", "wg0-mullvad", true, true), v4: [200, "198.51.100.24"], v6: long6 }]),
            longleak: run([{ egress: leak, v4: [200, "198.51.100.24"], v6: long6 }]),
            failed: run([{ egress: homeV4, v4: ok4 }, { egress: homeV4, v4: [503, ""] }], {}, 0)
        };
    }
}
