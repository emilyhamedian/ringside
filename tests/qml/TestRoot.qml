// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

// The root of the test files and the galleries. A bare qml runtime has no
// KI18n, and the views look its functions up on the root of the file that
// creates them. The tree walks are here because nearly every test needs one.
Item {
    // Source text to a stand-in translation, for a test that needs a long or
    // foreign string, and source text to the context the views gave
    // translators with it.
    property var translations: ({})
    property var contexts: ({})
    // Every string about a third longer, as German and the Romance
    // languages often run.
    property bool longStrings: false

    function stretch(text) {
        return text + "ß".repeat(Math.round(text.length * 0.35));
    }
    function substitute(text, args) {
        const s = text.replace(/%(\d+)/g, (match, n) => n <= args.length ? String(args[n - 1]) : match);
        return longStrings ? stretch(s) : s;
    }
    function i18n(text, ...args) {
        return substitute(translations[text] ?? text, args);
    }
    function i18nc(context, text, ...args) {
        contexts[text] = context;
        return substitute(translations[text] ?? text, args);
    }
    function i18np(singular, plural, n, ...args) {
        return substitute(n === 1 ? singular : plural, [n].concat(args));
    }
    function i18ncp(context, singular, plural, n, ...args) {
        return substitute(n === 1 ? singular : plural, [n].concat(args));
    }

    // Every item under `item`, itself included, that `test` accepts, in
    // tree order.
    function all(item, test) {
        const found = [];
        const collect = i => {
            if (test(i)) {
                found.push(i);
            }
            Array.from(i.children).forEach(collect);
        };
        collect(item);
        return found;
    }

    // The first item under `item`, itself included, that `test` accepts.
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

    // Every non-empty text under `item` that is visible itself.
    function texts(item) {
        return all(item, i => i.visible && typeof i.text === "string" && i.text !== "").map(i => i.text);
    }
}
