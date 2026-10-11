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

    // A file's text, by its path from tests/qml. Reading a file needs
    // QML_XHR_ALLOW_FILE_READ=1, which scripts/test.sh sets; without it the
    // text is empty and the test fails here.
    function read(path) {
        const request = new XMLHttpRequest();
        request.open("GET", Qt.resolvedUrl(path), false);
        request.send();
        if (request.responseText === "") {
            throw new Error(path + " read as empty; set QML_XHR_ALLOW_FILE_READ=1");
        }
        return request.responseText;
    }

    // Every <entry> in main.xml as { name, type, value }, the value being
    // the default as Plasma hands it over.
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
        if (list.length === 0) {
            throw new Error("main.xml lists no entry");
        }
        return list;
    }

    // Types `text` into `field` over what it held, with the keys of `test`,
    // a TestCase.
    function typeIn(test, field, text) {
        field.forceActiveFocus();
        field.selectAll();
        test.keyClick(Qt.Key_Delete);
        for (const c of text) {
            test.keyClick(c);
        }
        test.compare(field.text, text);
    }

    // Picks `row` of a combo box from its open list, with the keys of
    // `test`, a TestCase.
    function pick(test, box, row) {
        box.forceActiveFocus();
        test.keyClick(Qt.Key_Space);
        test.tryCompare(box.popup, "opened", true);
        const steps = row - box.currentIndex;
        for (let i = 0; i < Math.abs(steps); i++) {
            test.keyClick(steps > 0 ? Qt.Key_Down : Qt.Key_Up);
        }
        test.keyClick(Qt.Key_Return);
        test.tryCompare(box.popup, "visible", false);
        test.compare(box.currentIndex, row);
    }
}
