// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// The parts of the public address lookup that need no QML: which service
// to ask, whether its reply is an address, which interface each address
// left through, and the last check. Every Ringside widget in plasmashell
// shares one JavaScript engine, and so this module, as code/gpushare.js is
// shared: a check one widget made within the last minute serves them all.
// Nothing here is ever written to disk or to the configuration.

const IPIFY = { name: "ipify.org", v4: "https://api.ipify.org", v6: "https://api6.ipify.org" };

const FAMILIES = ["v4", "v6"];

function isIPv4(text) {
    // Four decimal parts, none with a leading zero, which some parsers read as octal.
    return /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/.test(text);
}

// The eight groups of an IPv6 address written in hex, or null. Dotted
// forms and zone ids (fe80::1%eth0) are not accepted: no public address
// needs either.
function groups6(text) {
    if (!/^[0-9A-Fa-f:]+$/.test(text)) {
        return null;
    }
    const halves = text.split("::");
    if (halves.length > 2) {
        return null;
    }
    const split = half => half === "" ? [] : half.split(":");
    const head = split(halves[0]);
    const tail = halves.length === 2 ? split(halves[1]) : [];
    if (head.concat(tail).some(g => !/^[0-9A-Fa-f]{1,4}$/.test(g))) {
        return null;
    }
    const missing = 8 - head.length - tail.length;
    if (halves.length === 2 ? missing < 1 : missing !== 0) {
        return null;
    }
    return head.concat(Array(halves.length === 2 ? missing : 0).fill("0"), tail).map(g => parseInt(g, 16));
}

// An IPv4-mapped address (::ffff:a.b.c.d, in any spelling) is an IPv4
// reply in IPv6 clothing, so it doesn't count as an IPv6 address.
function isIPv6(text) {
    const g = groups6(text);
    return g !== null && !(g.slice(0, 5).every(x => x === 0) && g[5] === 0xffff);
}

// The unspecified and loopback addresses, and the rest of 0.0.0.0/8 and
// 127.0.0.0/8: no website sees a computer by one of these.
function isNowhere(text, family) {
    if (family === "v4") {
        return /^(0|127)\./.test(text);
    }
    const g = groups6(text);
    return g.slice(0, 7).every(x => x === 0) && g[7] <= 1;
}

// The address in a service's reply for one family ("v4" or "v6"), or ""
// when the reply is anything else: surrounding white space aside, it has
// to be the address alone, so no other text a service sends is ever shown.
// The patterns leave no room for anything longer than an address.
function address(body, family) {
    const text = typeof body === "string" ? body.trim() : "";
    const valid = family === "v4" ? isIPv4(text) : family === "v6" && isIPv6(text);
    if (!valid || isNowhere(text, family)) {
        return "";
    }
    return family === "v6" ? text.toLowerCase() : text;
}

// Whether a reply came over https from the host that was asked. Qt follows
// a redirect before the reply is seen, to another host or to plain http
// alike, so the URL the request ended at is the one to check.
function cameFrom(responseUrl, asked) {
    const h = host(responseUrl);
    return h !== "" && h === host(asked);
}

// The host of an https:// URL, in lower case, or "" for anything else: a
// URL needs a host and may not carry a user name or password, which the
// pattern for the host and port leaves no room for. Host names go in ASCII
// (punycode for others); an IPv6 host goes in brackets.
function host(url) {
    const m = /^https:\/\/([^\/?#\s]*)([\/?#]\S*)?$/i.exec(String(url));
    if (!m) {
        return "";
    }
    const label = "[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?";
    const parts = new RegExp("^(\\[([0-9A-Fa-f:]+)\\]|" + label + "(?:\\." + label + ")*\\.?)(?::(\\d{1,5}))?$").exec(m[1]);
    if (!parts || (parts[2] !== undefined && groups6(parts[2]) === null)
            || (parts[3] !== undefined && (Number(parts[3]) < 1 || Number(parts[3]) > 65535))) {
        return "";
    }
    return parts[1].toLowerCase();
}

// The service the settings name. With both custom URLs empty, ipify.org.
// With either set, only those: an empty one leaves its family unchecked,
// and an invalid one makes the whole service invalid, so nothing is asked
// rather than falling back to ipify.org. `hosts` names the service by the
// hosts of the URLs that are valid; `key` tells services apart in the
// shared record.
function service(url4, url6) {
    const urls = { v4: String(url4 || "").trim(), v6: String(url6 || "").trim() };
    if (urls.v4 === "" && urls.v6 === "") {
        return { custom: false, valid: true, v4: IPIFY.v4, v6: IPIFY.v6, hosts: [IPIFY.name], key: "ipify" };
    }
    const hosts = FAMILIES.map(f => urls[f] === "" ? "" : host(urls[f]));
    const valid = FAMILIES.every((f, i) => urls[f] === "" || hosts[i] !== "");
    return {
        custom: true,
        valid: valid,
        v4: valid ? urls.v4 : "",
        v6: valid ? urls.v6 : "",
        hosts: hosts.filter((h, i) => h !== "" && hosts.indexOf(h) === i),
        key: valid ? urls.v4 + "\n" + urls.v6 : ""
    };
}

// An interface name as Linux allows one: up to 15 characters, no slash,
// colon or white space, and not "." or "..". Empty means no route.
function deviceName(text) {
    return text === "" || (text.length <= 15 && !/[\s\/:]/.test(text) && text !== "." && text !== "..");
}

// The helper's "egress" report, "4 DEV TUNNEL" and "6 DEV TUNNEL", as
// { known, v4, v6 } with { device, tunnel } for each family. Without `ip`
// the helper exits 3, and the routes are unknown ({ known: false }), as
// they are for a report that lacks either line.
function egress(exitCode, stdout) {
    const found = { known: false };
    if (exitCode === 0) {
        for (const line of String(stdout || "").split("\n")) {
            const fields = line.split(" ");
            if (fields.length === 3 && (fields[0] === "4" || fields[0] === "6") && deviceName(fields[1])) {
                found["v" + fields[0]] = { device: fields[1], tunnel: fields[1] !== "" && fields[2] === "1" };
            }
        }
    }
    return found.v4 && found.v6 ? { known: true, v4: found.v4, v6: found.v6 } : { known: false };
}

// The address lines for a check's result, with the interface each family
// left through (from the route facts taken when it was asked) where that
// isn't the local interface, and whether that interface is a tunnel.
// `leak` names the tunnel one family uses while the other goes around it.
function lines(result, egress, localInterface) {
    const known = !!(egress && egress.known);
    const line = f => {
        const address = result ? result[f] || "" : "";
        if (address === "") {
            return null;
        }
        const route = known ? egress[f] : null;
        const via = route && route.device !== localInterface ? route.device : "";
        return { address: address, via: via, tunnel: via !== "" && route.tunnel };
    };
    const v4 = line("v4");
    const v6 = line("v6");
    let leak = null;
    if (known) {
        const r4 = egress.v4;
        const r6 = egress.v6;
        if (r4.tunnel && v6 && r6.device !== "" && r6.device !== r4.device) {
            leak = { family: "v6", through: r4.device };
        } else if (r6.tunnel && v4 && r4.device !== "" && r4.device !== r6.device) {
            leak = { family: "v4", through: r6.device };
        }
    }
    return { v4: v4, v6: v6, leak: leak };
}

// The last check of each service, by key:
//   attemptAt  when a check last began (ms since the epoch), or -1
//   route      the route key the result was asked under; egress, the
//              route facts then, which go with its addresses
//   busy       a check is under way; asking, { route, egress } it began under
//   result     { at, v4, v6 } of the last finished check, "" for a family
//              that failed or wasn't asked; null before any
//   seen       per family, { address, at } of its last good answer
//   changed    per family, { at, was } when the last check's address
//              differed from the one before it
const records = {};
const listeners = [];

function record(key) {
    if (!records[key]) {
        records[key] = { attemptAt: -1, route: "", egress: null, busy: false, asking: null, result: null,
                         seen: { v4: null, v6: null }, changed: { v4: null, v6: null } };
    }
    return records[key];
}

// A copy of a service's record, so a QML binding sees each change as a new value.
function peek(key) {
    const r = records[key];
    return r ? JSON.parse(JSON.stringify(r)) : null;
}

function listen(fn) {
    listeners.push(fn);
}

function unlisten(fn) {
    const i = listeners.indexOf(fn);
    if (i >= 0) {
        listeners.splice(i, 1);
    }
}

function notify() {
    for (const fn of listeners.slice()) {
        fn();
    }
}

function begin(key, now, route, egress) {
    const r = record(key);
    r.attemptAt = now;
    r.asking = { route: route, egress: egress };
    r.busy = true;
    notify();
}

function finish(key, now, found) {
    const r = record(key);
    r.busy = false;
    r.route = r.asking.route;
    r.egress = r.asking.egress;
    r.asking = null;
    r.result = { at: now, v4: found.v4 || "", v6: found.v6 || "" };
    for (const f of FAMILIES) {
        const before = r.seen[f];
        const answer = r.result[f];
        r.changed[f] = answer !== "" && before && before.address !== answer ? { at: now, was: before.address } : null;
        if (answer !== "") {
            r.seen[f] = { address: answer, at: now };
        }
    }
    notify();
}

// A check stopped before its answers came, say because the setting went
// off: the attempt still counts towards the minute, its result doesn't.
function abandon(key) {
    const r = record(key);
    r.busy = false;
    r.asking = null;
    notify();
}

// Forgets every check, so the gallery can show each state from a clean start.
function forget() {
    for (const key of Object.keys(records)) {
        delete records[key];
    }
}
