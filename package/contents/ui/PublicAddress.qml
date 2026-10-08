// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import "code/publicaddress.js" as Lookup

// The address websites see, for the network popup. Monitor owns it, so what
// it has learnt outlives the popup; answers stay in memory and are shared
// with the other Ringside widgets (see code/publicaddress.js).
//
// Nothing is sent unless the setting is on, this widget's network popup
// is open, the service in the settings is valid and there is a route for a
// family it asks.
// A check goes out when the popup opens, unless any Ringside widget made one
// in the last minute, and when the route changes while it stays open, but
// never sooner than a minute after the last. Nothing else polls.
Item {
    id: checker

    // Plasmoid.configuration, or an object with the same keys.
    required property var config
    // This widget's network popup is open.
    property bool open: false
    // Monitor.egress: null until the helper has answered since the popup
    // opened, then { known, v4, v6 }.
    property var egress: null
    // Without route facts (no `ip`), a local address stands for a connection.
    property string localAddress: ""
    // The widget's version, for the User-Agent.
    property string version: ""
    readonly property string userAgent: version !== "" ? "ringside/" + version : "ringside"

    // For the tests: how a request is made, the clock, and the two waits.
    property var makeRequest: () => new XMLHttpRequest()
    property var clock: () => Date.now()
    property int floorMs: 60000
    property int timeoutMs: 10000

    readonly property var facts: currentFacts()
    readonly property bool switchedOn: facts.switchedOn
    readonly property var service: facts.service
    readonly property string serviceKey: facts.key
    // The service as the popup names it: its host, or both hosts. An invalid
    // service asks nothing, so it goes unnamed, as on the General page.
    readonly property string serviceName: !service.valid
        ? i18nc("@info a public address service whose URL isn't valid", "the address service")
        : service.hosts.length === 2
        ? i18nc("@info two services' host names", "%1 and %2", service.hosts[0], service.hosts[1])
        : service.hosts[0]
    readonly property bool connected: facts.connected
    readonly property string route: facts.route
    readonly property bool eligible: facts.eligible

    // This service's shared record (see code/publicaddress.js), or null.
    property int revision: 0
    readonly property var record: {
        revision;
        return serviceKey !== "" ? Lookup.peek(serviceKey) : null;
    }

    // off, invalid, offline, unrouted (connected, but not for the
    // one family the service asks), checking, shown or failed. The last
    // addresses found stay shown, with the route they were asked under,
    // while the next check is under way and until it replaces them; a
    // failure gives way to "checking" while the service is asked again.
    readonly property bool addressKnown: record !== null && record.result !== null
        && (record.result.v4 !== "" || record.result.v6 !== "")
    readonly property string status: !switchedOn ? "off"
        : !service.valid ? "invalid"
        : egress !== null && !connected ? "offline"
        : egress !== null && facts.families.length === 0 ? "unrouted"
        : addressKnown ? "shown"
        : record === null || record.busy || record.result === null ? "checking"
        : "failed"

    // Set when a check is due on its own account (the popup opened, the
    // setting or the service changed) rather than for a route change.
    property bool fresh: false
    // This checker's requests under way, { family, request, done, answer },
    // and the service they went to.
    property var pending: []
    property string pendingKey: ""
    property var listener: null

    // Worked out from the inputs on every call: a change handler can run
    // before the bindings above have caught up with the change.
    function currentFacts() {
        const switchedOn = config.publicAddress === true;
        const service = Lookup.service(config.publicAddressUrl4, config.publicAddressUrl6);
        const key = switchedOn && service.valid ? service.key : "";
        const routed = egress !== null && egress.known === true;
        // The families to ask: those with a URL and, where the routes are known, a route.
        const families = ["v4", "v6"].filter(f => service[f] !== "" && (!routed || egress[f].device !== ""));
        const connected = routed ? egress.v4.device !== "" || egress.v6.device !== "" : localAddress !== "";
        return {
            switchedOn: switchedOn,
            service: service,
            key: key,
            families: families,
            connected: connected,
            route: routed ? egress.v4.device + " " + egress.v6.device : "",
            eligible: key !== "" && open && egress !== null && connected && families.length > 0
        };
    }

    function consider() {
        const now = currentFacts();
        if (!now.eligible) {
            wait.stop();
            return;
        }
        const r = Lookup.peek(now.key);
        if (r !== null && r.busy) {
            // Its result is on the way, whichever widget asked.
            return;
        }
        const current = r !== null && r.result !== null && r.route === now.route;
        if (current && !fresh) {
            return;
        }
        // A clock stepped back reads as a long time since.
        const since = r === null || r.attemptAt < 0 ? Infinity : clock() - r.attemptAt;
        if (since >= 0 && since < floorMs) {
            if (current) {
                fresh = false;
            } else {
                wait.interval = floorMs - since;
                wait.restart();
            }
            return;
        }
        start(now);
    }

    function start(now) {
        fresh = false;
        wait.stop();
        pendingKey = now.key;
        // Every request exists before the first is sent, so one that
        // answers at once can't finish the check early.
        const sent = now.families.map(f => ({ family: f, request: makeRequest(), done: false, answer: "" }));
        pending = sent;
        Lookup.begin(now.key, clock(), now.route, egress);
        timeout.restart();
        for (const s of sent) {
            const request = s.request;
            const url = now.service[s.family];
            request.onreadystatechange = () => {
                // A reply running far past an address's length is not one.
                // abort() only stops Ringside listening: Qt keeps reading
                // whatever the service goes on sending.
                if (request.readyState === XMLHttpRequest.LOADING && String(request.responseText).length > 4096) {
                    request.abort();
                } else if (request.readyState === XMLHttpRequest.DONE) {
                    const trusted = request.status === 200 && Lookup.cameFrom(String(request.responseURL), url);
                    checker.settle(s, trusted ? Lookup.address(request.responseText, s.family) : "");
                }
            };
            request.open("GET", url);
            request.setRequestHeader("User-Agent", userAgent);
            // "*" rather than the languages Qt would send from the locale.
            request.setRequestHeader("Accept-Language", "*");
            request.send();
        }
    }

    function settle(s, address) {
        if (s.done) {
            return;
        }
        s.done = true;
        s.answer = address;
        if (pending.includes(s) && pending.every(p => p.done)) {
            const found = {};
            for (const p of pending) {
                found[p.family] = p.answer;
            }
            pending = [];
            timeout.stop();
            Lookup.finish(pendingKey, clock(), found);
        }
    }

    // Stops this checker's check without a result.
    function drop() {
        const sent = pending;
        pending = [];
        timeout.stop();
        if (sent.length > 0) {
            for (const s of sent) {
                s.done = true;
            }
            for (const s of sent) {
                s.request.abort();
            }
            Lookup.abandon(pendingKey);
        }
    }

    onEligibleChanged: {
        if (eligible) {
            fresh = true;
        }
        consider();
    }
    onRouteChanged: consider()
    onServiceKeyChanged: {
        if (pending.length > 0 && pendingKey !== currentFacts().key) {
            drop();
        }
        fresh = true;
        consider();
    }

    Component.onCompleted: {
        listener = () => {
            ++revision;
            consider();
        };
        Lookup.listen(listener);
    }
    Component.onDestruction: {
        Lookup.unlisten(listener);
        drop();
    }

    // A route change within a minute of the last check waits for the minute.
    Timer {
        id: wait
        objectName: "wait"
        onTriggered: checker.consider()
    }

    Timer {
        id: timeout
        objectName: "timeout"
        interval: checker.timeoutMs
        onTriggered: {
            const late = checker.pending.filter(s => !s.done);
            for (const s of late) {
                checker.settle(s, "");
            }
            for (const s of late) {
                s.request.abort();
            }
        }
    }
}
