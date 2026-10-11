// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.LocalStorage as Sql
import "code/history.js" as History
import "code/log.js" as Log

// The graphs' hour and day buckets, kept across Plasma restarts and reboots
// while "Keep graph history" is on. Monitor loads this file by URL and only
// then, so where Qt's LocalStorage module is missing (Debian and Ubuntu
// package it on its own) the widget still loads and its history stays in
// memory. Qt keeps the database in plasmashell's data folder, under
// QML/OfflineStorage/Databases: one SQLite file that every Ringside widget
// shares, each row a closed bucket of one widget's graphs under its widget
// id. A save also drops every widget's buckets older than its span, a
// removed widget's too, so while any widget keeps its history the file
// holds about a day.
QtObject {
    id: store

    required property string widget
    // The database's name, which Qt hashes into the file's. A test seam.
    property string name: "ringside"

    property var db: null
    // Set by the first failure, a database that can't be read or written
    // say, after which failures go unsaid rather than fill the journal
    // every 10 minutes.
    property bool failed: false

    property LoggingCategory journal: LoggingCategory {
        name: "ringside.setup"
        defaultLogLevel: LoggingCategory.Info
    }

    function open() {
        if (!db) {
            db = Sql.LocalStorage.openDatabaseSync(name, "", "Ringside graph history", 1000000);
            db.transaction(tx => tx.executeSql(
                "CREATE TABLE IF NOT EXISTS buckets (widget TEXT NOT NULL, tier TEXT NOT NULL, at INTEGER NOT NULL, "
                + "data TEXT NOT NULL, PRIMARY KEY (widget, tier, at))"));
        }
        return db;
    }

    // Runs `work` in a transaction, reporting the first failure rather than
    // throwing into the sample timer.
    function run(work, readOnly) {
        try {
            const d = open();
            if (readOnly) {
                d.readTransaction(work);
            } else {
                d.transaction(work);
            }
        } catch (err) {
            if (!failed) {
                Log.write(journal, "warning", "the graphs' saved history can't be used: " + (err.message ?? err));
            }
            failed = true;
        }
    }

    // A saved row's data, each series' [average, highest] by its key, or
    // null where it isn't an object. A series not in that shape is left out.
    function parsed(text) {
        let data = null;
        try {
            data = JSON.parse(text);
        } catch (err) {
            return null;
        }
        if (data === null || typeof data !== "object" || Array.isArray(data)) {
            return null;
        }
        const kept = {};
        for (const key of Object.keys(data)) {
            const v = data[key];
            if (Array.isArray(v) && v.length === 2 && v.every(n => typeof n === "number")) {
                kept[key] = v;
            }
        }
        return kept;
    }

    // This widget's buckets of a tier, oldest first: [{ at, data }] (see
    // parsed()). A row or a series that isn't in that shape is a gap.
    function load(tier) {
        const rows = [];
        run(tx => {
            const r = tx.executeSql("SELECT at, data FROM buckets WHERE widget = ? AND tier = ? ORDER BY at", [widget, tier]);
            for (let i = 0; i < r.rows.length; ++i) {
                const at = r.rows.item(i).at;
                const data = parsed(r.rows.item(i).data);
                if (Number.isInteger(at) && at >= 0 && data !== null) {
                    rows.push({ at: at, data: data });
                }
            }
        }, true);
        return rows;
    }

    // Saves closed buckets, [{ tier, at, data }], and drops whatever has
    // fallen out of its tier's span, or lies ahead of the clock. A row's
    // series go into the bucket beside those already saved there: a series
    // that went unsampled for a while, a GPU off the rings say, closes its
    // bucket after the others have saved theirs. One saved again, after the
    // clock was set back say, takes the new values.
    function save(rows) {
        run(tx => {
            for (const row of rows) {
                const r = tx.executeSql("SELECT data FROM buckets WHERE widget = ? AND tier = ? AND at = ?", [widget, row.tier, row.at]);
                const data = Object.assign(r.rows.length > 0 ? parsed(r.rows.item(0).data) ?? {} : {}, row.data);
                tx.executeSql("INSERT OR REPLACE INTO buckets VALUES (?, ?, ?, ?)", [widget, row.tier, row.at, JSON.stringify(data)]);
            }
            for (const tier of Object.keys(History.TIERS)) {
                const t = History.TIERS[tier];
                const now = Math.floor(Date.now() / 1000 / t.period);
                tx.executeSql("DELETE FROM buckets WHERE tier = ? AND (at < ? OR at > ?)", [tier, now - t.length, now]);
            }
        });
    }

    // Everything this widget saved.
    function clear() {
        run(tx => tx.executeSql("DELETE FROM buckets WHERE widget = ?", [widget]));
    }
}
