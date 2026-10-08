// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.LocalStorage as Sql
import "code/history.js" as History

// The graphs' hour and day buckets, kept across Plasma restarts and reboots
// while "Keep graph history" is on. Monitor loads this file by URL and only
// then, so where Qt's LocalStorage module is missing (Debian and Ubuntu
// package it on its own) the widget still loads and its history stays in
// memory. Qt keeps the database in plasmashell's data folder, under
// QML/OfflineStorage/Databases: one SQLite file for every Ringside widget,
// each row a closed bucket of one widget's graphs. A save also drops every
// widget's buckets older than its span, a removed widget's too, so the file
// holds about a day.
QtObject {
    id: store

    required property string widget
    // The database's name, which Qt hashes into the file's; the tests use
    // their own.
    property string name: "ringside"

    property var db: null

    function open() {
        if (!db) {
            db = Sql.LocalStorage.openDatabaseSync(name, "", "Ringside graph history", 1000000);
            db.transaction(tx => tx.executeSql(
                "CREATE TABLE IF NOT EXISTS buckets (widget TEXT NOT NULL, tier TEXT NOT NULL, at INTEGER NOT NULL, "
                + "data TEXT NOT NULL, PRIMARY KEY (widget, tier, at))"));
        }
        return db;
    }

    // Runs `work` in a transaction, reporting a failure rather than throwing
    // into the sample timer.
    function run(work, readOnly) {
        try {
            const d = open();
            if (readOnly) {
                d.readTransaction(work);
            } else {
                d.transaction(work);
            }
            return true;
        } catch (err) {
            console.warn("ringside: graph history store:", err.message ?? err);
            return false;
        }
    }

    // This widget's buckets of a tier, oldest first: [{ at, data }], data
    // each series' [average, highest] by its key.
    function load(tier) {
        const rows = [];
        run(tx => {
            const r = tx.executeSql("SELECT at, data FROM buckets WHERE widget = ? AND tier = ? ORDER BY at", [widget, tier]);
            for (let i = 0; i < r.rows.length; ++i) {
                try {
                    rows.push({ at: r.rows.item(i).at, data: JSON.parse(r.rows.item(i).data) });
                } catch (err) {
                    // A row that doesn't parse is a gap.
                }
            }
        }, true);
        return rows;
    }

    // Saves closed buckets, [{ tier, at, data }], and drops whatever has
    // fallen out of its tier's span, or lies ahead of the clock.
    function save(rows) {
        run(tx => {
            for (const row of rows) {
                tx.executeSql("INSERT OR REPLACE INTO buckets VALUES (?, ?, ?, ?)", [widget, row.tier, row.at, JSON.stringify(row.data)]);
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
