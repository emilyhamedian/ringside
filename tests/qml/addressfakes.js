// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// What the public address checker learns from outside, for tst_publicaddress
// and the gallery's PublicAddressStates: route facts, and requests that
// record what they were asked and answer when told. Nothing is sent.

// Route facts as Lookup.egress() reports them: each family's device, and
// whether it is a tunnel.
function route(v4, v6, tunnel4, tunnel6) {
    return { known: true, v4: { device: v4, tunnel: !!tunnel4 }, v6: { device: v6, tunnel: !!tunnel6 } };
}

// A checker's makeRequest, `make`, and every request it made, `made`. Each
// request answers when a test calls answer(), or at once from `onSend`
// where one is given.
function requests(onSend) {
    const made = [];
    const make = () => {
        const r = {
            readyState: 0, status: 0, responseText: "", responseURL: "", method: "", url: "", headers: {},
            sent: false, aborted: false, onreadystatechange: null,
            open(method, url) { this.method = method; this.url = url; this.readyState = 1; },
            setRequestHeader(name, value) { this.headers[name] = value; },
            send() {
                this.sent = true;
                if (onSend) {
                    onSend(this);
                }
            },
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
