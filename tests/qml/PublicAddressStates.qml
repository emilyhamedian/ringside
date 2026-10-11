// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import "../../package/contents/ui"
import "../../package/contents/ui/code/publicaddress.js" as Lookup
import "addressfakes.js" as Fakes

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
    required property string localInterface
    property real at: new Date(2026, 9, 7, 14, 2).getTime()
    // name -> a lookup frozen in that state, filled in when this is created.
    property var all: ({})

    property Component checkerComponent: Component {
        PublicAddress {}
    }
    property Component configComponent: Component {
        FakeConfig {
            publicAddress: true
        }
    }

    // Runs `steps`, each { egress, v4, v6 } with the replies as [status,
    // body] (none: never answered), a minute apart, the step `last` one at
    // `at`, and keeps what the checker shows after the last step.
    function run(steps, config, last) {
        for (const key of Object.keys(Lookup.records)) {
            delete Lookup.records[key];
        }
        let now = states.at - 61000 * (last ?? steps.length - 1);
        let replies = {};
        const fake = Fakes.requests(r => {
            const reply = replies[r.url];
            if (reply) {
                r.answer(reply[0], reply[1]);
            }
        });
        const c = configComponent.createObject(states, config || {});
        const checker = checkerComponent.createObject(null, { config: c, clock: () => now, makeRequest: fake.make, localAddress: "192.0.2.1" });
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
        const home = Fakes.route(localInterface, localInterface);
        const homeV4 = Fakes.route(localInterface, "");
        const vpn = Fakes.route("wg0-mullvad", "", true);
        const leak = Fakes.route("wg0-mullvad", localInterface, true);
        const ok4 = [200, "203.0.113.7\n"];
        const long6 = [200, "2001:db8:85a3:4d1c:9d2e:51f4:c8a3:7e61"];
        all = {
            both: run([{ egress: home, v4: ok4, v6: [200, "2001:db8:4f2a::1c"] }]),
            vpn: run([{ egress: homeV4, v4: ok4 }, { egress: vpn, v4: [200, "198.51.100.24"] }]),
            longvpn: run([{ egress: Fakes.route("wg0-mullvad", "wg0-mullvad", true, true), v4: [200, "198.51.100.24"], v6: long6 }]),
            longleak: run([{ egress: leak, v4: [200, "198.51.100.24"], v6: long6 }]),
            // A Custom service that answers in JSON with a city.
            city: run([{ egress: vpn, v4: [200, JSON.stringify({ ip: "198.51.100.24", city: "Amsterdam", country: "Netherlands",
                                                                 organization: "Example" })] }],
                      { publicAddressUrl4: "https://ip4.example.net/json", publicAddressUrl6: "https://ip6.example.net/json" }),
            failed: run([{ egress: homeV4, v4: ok4 }, { egress: homeV4, v4: [503, ""] }], {}, 0)
        };
    }
}
