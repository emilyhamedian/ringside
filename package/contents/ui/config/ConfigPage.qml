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
// open: knownLimits, usageStatus and detectedHardware. Once the dialog has
// set the page's copies, each follows the live value, so Apply writes back
// the newest report whichever order the dialog saves in, and Plasma 6.4 and
// later, which turn Apply on only where a copy differs from the live value,
// never see one differ. Plasma 6.0 to 6.3 turn Apply on at any cfg_ change
// signal, so there a report written while a page is open turns it on; Apply
// then saves what is stored already.
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
    property bool cfg_publicAddress
    property bool cfg_publicAddressDefault
    property string cfg_publicAddressUrl4
    property string cfg_publicAddressUrl4Default
    property string cfg_publicAddressUrl6
    property string cfg_publicAddressUrl6Default
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

    // One of the reports, parsed; {} while it is empty or unreadable.
    function report(key) {
        try {
            const parsed = JSON.parse(base["cfg_" + key] || "{}");
            return parsed && typeof parsed === "object" ? parsed : {};
        } catch (err) {
            return {};
        }
    }

    Component.onCompleted: {
        if (live) {
            for (const key of reports) {
                base["cfg_" + key] = Qt.binding(() => base.live[key]);
            }
        }
    }
}
