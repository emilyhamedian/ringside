// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick

// The widget's settings as Plasma hands them to Monitor: every entry in
// package/contents/config/main.xml, at its default.
QtObject {
    property int updateInterval: 1000
    property string graphSpan: "minute"
    property bool keepGraphHistory: false
    property bool fahrenheit: false
    property bool networkBits: true
    property bool highlightTemperatures: true
    property real warmCelsius: 75
    property real hotCelsius: 90
    // A Bool in main.xml; var here so a test can hand Monitor a value that
    // isn't one.
    property var publicAddress: false
    property string publicAddressUrl4: ""
    property string publicAddressUrl6: ""
    property int usageRefreshMinutes: 5
    property var itemOrder: ["cpu", "gpu", "memory", "network", "disk"]
    property var hiddenItems: ["disk"]
    property var ringsOnly: []
    property string fillPanel: ""
    property string cpuTemperatureSensor: ""
    property string outerGpu: ""
    property string innerGpu: ""
    property string networkInterface: ""
    property string diskDevice: ""
    property string diskVolume: ""
    property string diskTemperatureSensor: ""
    property string claudeInnerLimit: ""
    property string codexInnerLimit: ""
    property bool claudeCredits: false
    property bool codexCredits: false
    property string codexMark: "codex"
    property string claudeProgram: ""
    property string codexProgram: ""
    property string knownLimits: ""
    property string usageStatus: ""
    property string seenResets: ""
    property string detectedHardware: ""
}
