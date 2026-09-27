.pragma library

// Every Ringside widget in plasmashell shares one JavaScript engine, and so
// this module. For each GPU one reader, the leader, holds its ksystemstats
// subscriptions, and readers of the same GPU in other widgets show what it
// reads. ksystemstats counts subscriptions per D-Bus client, and plasmashell
// is a single client: two readers subscribing one GPU would leave it
// subscribed, and awake, for the rest of the session once either let go.

const leaders = {};
const interest = {};

// The reader leading this GPU; `reader` becomes the leader if there is none.
function lead(id, reader) {
    if (!leaders[id]) {
        leaders[id] = reader;
    }
    return leaders[id];
}

function leave(id, reader) {
    if (leaders[id] === reader) {
        delete leaders[id];
    }
    note(id, reader, false, false);
}

// What each widget wants of a GPU: shown on a ring, its popup open.
function note(id, reader, onRing, watched) {
    const others = (interest[id] || []).filter(entry => entry.reader !== reader);
    interest[id] = onRing || watched ? others.concat([{ reader: reader, onRing: onRing, watched: watched }]) : others;
}

function wanted(id) {
    return (interest[id] || []).some(entry => entry.onRing);
}

function watched(id) {
    return (interest[id] || []).some(entry => entry.watched);
}
