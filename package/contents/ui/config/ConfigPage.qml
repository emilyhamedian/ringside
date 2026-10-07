// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

// The root of every settings page. Plasma's dialog creates a page with a
// cfg_ property for each key in Plasmoid.configuration.keys(), which is
// every entry in main.xml and, as KConfigPropertyMap loads it, each entry's
// Default, and it warns about every one the page lacks. On Apply it writes
// each cfg_ property the page has back to the configuration. So every page
// declares all of them here, once, typed as main.xml types them (tst_config
// checks the list against main.xml), and edits only its own. The Default
// copies are never touched: Apply hands each back unchanged, and the map
// keeps no config item under that name, so nothing reaches the file.
//
// Three of the keys are reports the widget writes while the dialog may be
// open: knownLimits, usageStatus and detectedHardware. Their cfg_ copies
// keep the values the page opened with, since Plasma 6.0 to 6.4 enable
// Apply on any cfg_ change signal; latest follows the live configuration
// instead, one event-loop turn behind, because the dialog's own writes on
// Apply arrive through the same signal, and before 6.5 those come first and
// write the page's copies over the reports. saveConfig() then puts the
// reports where the dialog's order of events keeps them.
KCM.SimpleKCM {
    id: base

    property int cfg_updateInterval
    property int cfg_updateIntervalDefault
    property int cfg_historySeconds
    property int cfg_historySecondsDefault
    property bool cfg_fahrenheit
    property bool cfg_fahrenheitDefault
    property bool cfg_networkBits
    property bool cfg_networkBitsDefault
    property bool cfg_highlightTemperatures
    property bool cfg_highlightTemperaturesDefault
    property real cfg_warmCelsius
    property real cfg_warmCelsiusDefault
    property real cfg_hotCelsius
    property real cfg_hotCelsiusDefault
    property int cfg_usageRefreshMinutes
    property int cfg_usageRefreshMinutesDefault
    property var cfg_itemOrder: []
    property var cfg_itemOrderDefault: []
    property var cfg_hiddenItems: []
    property var cfg_hiddenItemsDefault: []
    property var cfg_ringsOnly: []
    property var cfg_ringsOnlyDefault: []
    property string cfg_cpuTemperatureSensor
    property string cfg_cpuTemperatureSensorDefault
    property string cfg_outerGpu
    property string cfg_outerGpuDefault
    property string cfg_innerGpu
    property string cfg_innerGpuDefault
    property string cfg_networkInterface
    property string cfg_networkInterfaceDefault
    property string cfg_diskDevice
    property string cfg_diskDeviceDefault
    property string cfg_diskVolume
    property string cfg_diskVolumeDefault
    property string cfg_diskTemperatureSensor
    property string cfg_diskTemperatureSensorDefault
    property string cfg_claudeInnerLimit
    property string cfg_claudeInnerLimitDefault
    property string cfg_codexInnerLimit
    property string cfg_codexInnerLimitDefault
    property string cfg_knownLimits
    property string cfg_knownLimitsDefault
    property string cfg_usageStatus
    property string cfg_usageStatusDefault
    property string cfg_detectedHardware
    property string cfg_detectedHardwareDefault

    readonly property var reports: ["knownLimits", "usageStatus", "detectedHardware"]
    // The live configuration: undefined outside Plasma, where tests hand
    // over a stand-in.
    property var live: Plasmoid.configuration
    // The reports as last written, starting from what the page opened with.
    property var latest: ({
        knownLimits: cfg_knownLimits,
        usageStatus: cfg_usageStatus,
        detectedHardware: cfg_detectedHardware
    })

    // One of the reports, parsed; {} while it is empty or unreadable.
    function report(key) {
        try {
            const parsed = JSON.parse(latest[key] || "{}");
            return parsed && typeof parsed === "object" ? parsed : {};
        } catch (err) {
            return {};
        }
    }

    function refresh() {
        if (!live) {
            return;
        }
        const now = {};
        for (const key of reports) {
            now[key] = live[key];
        }
        latest = now;
    }

    // Called by the dialog on Apply. From Plasma 6.5 it comes before the
    // dialog writes the cfg_ copies back, so the live value is the newest
    // and the copies take it. Before 6.5 it comes after, and the live value
    // is the page's own stale copy: latest, still a turn behind, is what the
    // widget wrote last, so it goes back and is saved, as the dialog has
    // saved already.
    function saveConfig() {
        let restored = false;
        for (const key of reports) {
            const value = live && live[key] !== base["cfg_" + key] ? live[key] : latest[key];
            base["cfg_" + key] = value;
            if (live && live[key] !== value) {
                live[key] = value;
                restored = true;
            }
        }
        if (restored) {
            live.writeConfig();
        }
    }

    Connections {
        target: base.live ?? null
        function onValueChanged(key, value) {
            if (base.reports.includes(key)) {
                Qt.callLater(base.refresh);
            }
        }
    }
}
