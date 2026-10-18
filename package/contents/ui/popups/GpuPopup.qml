// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/log.js" as Log
import "../code/processes.js" as Processes
import "../code/style.js" as Style
import ".."

// One section per awake GPU, the integrated one first, so a discrete GPU
// waking up opens below it rather than pushing it down; each under a header as
// in the other popups and the second after a rule. A powered-down GPU is a
// single line at the end; nothing here reads it, so opening the popup can't
// wake it. A GPU that wakes opens its section at once and fades it in; one
// that goes to sleep fades its section out with its last readings, and only
// then gives way to its line, so the popup changes height once each way.
// Each open section ends with the processes using its GPU, in as many rows
// as fit the screen: none on a small screen with two GPUs awake.
PopupPage {
    id: popup

    readonly property var slots: [popup.monitor.gpuOuter, popup.monitor.gpuInner].filter(slot => slot.present)
        .sort((a, b) => (a.kind === "integrated" ? 0 : 1) - (b.kind === "integrated" ? 0 : 1))
    readonly property var awake: slots.filter(slot => slot.phase !== "asleep")
    // The GPUs with a section open: the awake ones, and one that has just
    // gone to sleep while its section fades out. Set rather than bound, so
    // that a GPU going to sleep is still among them when it is noticed.
    property var open: []
    // Off opens and closes sections at once, as at Plasma's Instant speed.
    property bool animated: Style.animated(Kirigami.Units)

    // An AMD or Intel GPU's processes come from the monitor, which reads them
    // from /proc and /sys and wakes nothing. An NVIDIA GPU's come from
    // libksysguard, from Plasma 6.4, through nvidia-smi, which wakes each
    // NVIDIA GPU it asks, so they're read only while every NVIDIA GPU is
    // awake and on show.
    readonly property bool nvidiaReadable: slots.some(slot => slot.vendor === "10de" && slot.phase !== "asleep")
        && (popup.monitor.hardware?.gpus ?? []).every(gpu => gpu.vendor !== "10de"
            || slots.some(slot => slot.info?.id === gpu.id && slot.live))
    // Fixed processes ({ name, usage, memory, gpu }) stand in for both when
    // set; the preview gallery uses them. An NVIDIA GPU's processes name it
    // as ksystemstats does, the others' by its PCI address.
    readonly property var processSample: popup.monitor.gpuProcessSample ?? null
    // Before Plasma 6.4 libksysguard doesn't say which NVIDIA GPU a process
    // uses, and their lists are left out.
    readonly property bool nvidiaListed: nvidiaReadable && (processSample !== null || processScan.columns.length > 0)
    // Two rows each when two sections share the popup, three for one, fewer
    // where the page would outgrow its room, and none where even one row
    // would.
    readonly property int processCountWanted: open.length > 1 ? 2 : 3
    property int processCount: processCountWanted

    // Sets the rows to the most that fit. The page's height less its lists'
    // doesn't depend on the rows, so the count settles on the first layout
    // after a change rather than stepping down a row at a time.
    function fitProcesses() {
        // A Section is an inline component, which a cast can't name on Qt 6.6.
        // qmllint disable missing-property
        const shown = Array.from({ length: sections.count }, (_, i) => sections.itemAt(i))
            .filter(section => section && section.visible && section.processesShown);
        let count = processCountWanted;
        if (shown.length > 0) {
            const rest = implicitHeight - shown.reduce((sum, section) => sum + section.processListHeight, 0);
            while (count > 0 && rest + shown.reduce((sum, section) => sum + section.processListHeightFor(count), 0) > room) {
                --count;
            }
        }
        // qmllint enable missing-property
        if (count !== processCount) {
            if (count < processCountWanted) {
                Log.write(journal, "debug", "GPU popup: " + count + " process rows a GPU, to fit in " + Math.round(room) + " px");
            }
            processCount = count;
        }
    }

    // Change the row count after layout, rather than during its polish pass.
    onImplicitHeightChanged: Qt.callLater(popup.fitProcesses)
    onRoomChanged: fitProcesses()
    onProcessCountWantedChanged: fitProcesses()
    onNvidiaListedChanged: fitProcesses()

    // The NVIDIA process model is made, but says nothing of GPUs.
    readonly property bool processesUnavailable: processScan.model !== null && processScan.columns.length === 0
    onProcessesUnavailableChanged: {
        if (processesUnavailable) {
            Log.write(journal, "debug", "GPU popup: libksysguard says which GPU a process uses from Plasma 6.4, so no NVIDIA GPU's processes are listed");
        }
    }

    property LoggingCategory journal: LoggingCategory {
        name: "ringside.gpu"
        defaultLogLevel: LoggingCategory.Info
    }

    Component.onCompleted: open = awake
    onAwakeChanged: {
        if (animated && open.some(slot => !awake.includes(slot))) {
            open = slots.filter(slot => open.includes(slot) || awake.includes(slot));
            closing.restart();
        } else {
            closing.stop();
            open = awake;
        }
    }

    ProcessScan {
        id: processScan
        active: popup.nvidiaReadable && popup.processSample === null
        attributes: Processes.gpuAttributes
        reading: Processes.gpuReading
    }

    Timer {
        id: closing
        interval: Kirigami.Units.longDuration
        onTriggered: popup.open = popup.awake
    }

    // A section per GPU, kept as it sleeps and wakes.
    Repeater {
        id: sections
        model: popup.slots.length

        delegate: Section {
            required property int index
            readonly property var live: popup.slots[index] ?? popup.monitor.gpuOuter
            readonly property bool opened: popup.open.includes(live)
            // Its readings while it was last awake, a reading that went
            // missing keeping the one before.
            property var last: null
            readonly property var readings: [live.phase, live.usage, live.temperature, live.vramUsed, live.knownVramTotal,
                                             live.clock, live.power, live.history, live.temperatureHistory, live.highs,
                                             live.temperatureHighs, live.temperatureExtent,
                                             live.reportsTemperature, live.reportsVram]

            function keep() {
                if (live.phase === "asleep") {
                    return;
                }
                const was = last ?? {};
                const held = key => Number.isFinite(live[key]) ? live[key] : was[key] ?? NaN;
                last = {
                    present: true, name: live.name, kind: live.kind, reportsVram: live.reportsVram,
                    reportsTemperature: live.reportsTemperature, temperatureLabel: live.temperatureLabel,
                    knownVramTotal: held("knownVramTotal"), usage: held("usage"), temperature: held("temperature"),
                    vramUsed: held("vramUsed"), clock: held("clock"), power: held("power"),
                    history: live.history.length > 0 ? live.history : was.history ?? [],
                    highs: live.history.length > 0 ? live.highs : was.highs ?? [],
                    temperatureHistory: live.temperatureHistory.length > 0 ? live.temperatureHistory : was.temperatureHistory ?? [],
                    temperatureHighs: live.temperatureHistory.length > 0 ? live.temperatureHighs : was.temperatureHighs ?? [],
                    temperatureExtent: live.temperatureExtent.length > 0 ? live.temperatureExtent : was.temperatureExtent ?? []
                };
            }

            Component.onCompleted: keep()
            onReadingsChanged: keep()

            monitor: popup.monitor
            awake: live.phase !== "asleep"
            visible: opened
            slot: !awake && opened && last ? last : live
            temperatureName: words.sensorName(live.temperatureLabel)
            // Not an integrated GPU's beside a discrete one: it shares the
            // CPU's die, whose temperature the CPU popup graphs, and a second
            // graph would make the popup too tall for a small screen.
            temperatureGraphed: live.kind !== "integrated" || !popup.slots.some(slot => slot.kind === "discrete")
            first: popup.open.indexOf(live) === 0
            animated: popup.animated
            readonly property bool nvidia: live.vendor === "10de"
            readonly property var availableProcesses: Processes.topOnGpu(
                popup.processSample ?? (nvidia ? processScan.processes : popup.monitor.gpuProcesses),
                nvidia ? live.systemName : live.bdf, popup.processCountWanted, live.usage)
            processesShown: (!nvidia || popup.nvidiaListed) && availableProcesses.length > 0
            onProcessesShownChanged: Qt.callLater(popup.fitProcesses)
            processes: availableProcesses.slice(0, popup.processCount)
            processCount: popup.processCount
            processesLoading: (!nvidia || popup.nvidiaListed) && availableProcesses.length === 0
                && popup.processSample === null && !(nvidia ? processScan.scanned : popup.monitor.gpuProcessesScanned)
        }
    }

    Words {
        id: words
        monitor: popup.monitor
    }

    Repeater {
        model: popup.slots.filter(slot => !popup.open.includes(slot))

        delegate: ColumnLayout {
            id: sleeper

            required property var modelData
            required property int index

            Layout.fillWidth: true
            spacing: 0

            Divider {
                visible: popup.open.length > 0
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
                Layout.rightMargin: Layout.leftMargin
                // Where it opens the page, as far down as a header would start.
                Layout.topMargin: popup.open.length > 0 || sleeper.index > 0
                    ? Kirigami.Units.largeSpacing : Math.round(Kirigami.Units.largeSpacing * 1.75)
                Layout.bottomMargin: Kirigami.Units.largeSpacing
                text: i18nc("@info a powered-down GPU: its name, then off", "%1 · off", sleeper.modelData.name)
                color: Style.dim(Kirigami.Theme.textColor)
                elide: Text.ElideNone
                wrapMode: Text.Wrap
                leftPadding: popup.LayoutMirroring.enabled ? 1 : 0
                rightPadding: popup.LayoutMirroring.enabled ? 0 : 1
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
            }
        }
    }

    component Section: ColumnLayout {
        id: section

        required property var monitor
        // A GpuReader, or an object with the same properties.
        required property var slot
        // The slot's temperature label in plain words.
        required property string temperatureName
        property bool temperatureGraphed: true
        // Any section after the first is set off from it by a rule.
        property bool first: true
        // Faded in while the GPU is awake and out while it sleeps.
        property bool awake: true
        property bool animated: true
        property bool processesShown: false
        property var processes: []
        property int processCount: 3
        property bool processesLoading: false
        // The list's height on the page, and what it would be with `count` rows.
        readonly property real processListHeight: processList.visible ? processList.heightFor(processList.count) : 0
        function processListHeightFor(count) {
            return processList.heightFor(count);
        }

        readonly property bool temperatureShown: slot.reportsTemperature
        readonly property bool hasPower: Number.isFinite(slot.power)
        // Smaller than other popups' tiles' (Style.tilePointSize()), so a
        // row of three readings fits.
        readonly property real tilePointSize: Kirigami.Theme.defaultFont.pointSize * 1.23

        Layout.fillWidth: true
        opacity: awake ? 1 : 0
        spacing: 0

        Behavior on opacity {
            enabled: section.animated
            NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
        }

        Words {
            id: sectionWords
            monitor: section.monitor
        }

        Divider {
            visible: !section.first
        }

        PopupHeader {
            processesLoading: section.processesLoading
            processesExpected: true
            ringValue: section.slot.usage
            interval: section.monitor.sampleInterval
            title: section.slot.name
            titleWrapped: true
            subtitle: {
                const slot = section.slot;
                if (slot.kind === "integrated") {
                    return i18nc("@info integrated GPU using system memory", "iGPU · shared");
                }
                if (slot.kind !== "discrete") {
                    return "";
                }
                const total = Format.bytes(slot.knownVramTotal, true);
                return total.unit ? i18nc("@info discrete GPU and its memory, e.g. dGPU · 8 GiB",
                                          "dGPU · %1 %2", total.value, total.unit)
                                  : i18nc("@info discrete GPU", "dGPU");
            }
            value: section.temperatureShown ? Format.temperature(section.slot.temperature, section.monitor.fahrenheit) : ""
            degreeUnit: section.monitor.fahrenheit ? "F" : "C"
            valueColor: Style.levelColor(section.monitor.heat(section.slot.temperature), Kirigami.Theme)
            caption: section.temperatureName
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Style.contentEdge(Kirigami.Units.largeSpacing)
            Layout.rightMargin: Layout.leftMargin
            Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 1.5)
            Layout.bottomMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
            columns: (section.slot.reportsVram ? 1 : 0) + 1 + (section.hasPower ? 1 : 0)
            rowSpacing: Kirigami.Units.largeSpacing
            columnSpacing: Kirigami.Units.largeSpacing
            // Equal columns while the VRAM reading fits one; a long one
            // ("11.6 / 16 GiB") takes a wider column rather than overflow.
            uniformCellWidths: vram.implicitWidth * columns + columnSpacing * (columns - 1) <= width

            Tile {
                Layout.columnSpan: parent.columns
                caption: i18nc("@title:group", "Usage")
                spans: section.monitor
                graphTop: sectionWords.percent(100)
                graphReading: usageGraph.reading

                Graph {
                    id: usageGraph
                    Layout.fillWidth: true
                    describe: i => sectionWords.pointText(values, highs, i, v => sectionWords.percent(v))
                    values: section.slot.history
                    highs: section.slot.highs
                    length: section.monitor.historyLength
                }
            }

            // As in the CPU popup: under the usage it follows.
            TemperatureTile {
                graphed: section.temperatureGraphed
                Layout.columnSpan: parent.columns
                monitor: section.monitor
                history: section.slot.temperatureHistory
                highs: section.slot.temperatureHighs
                extent: section.slot.temperatureExtent
            }

            Tile {
                id: vram
                visible: section.slot.reportsVram
                caption: i18nc("@title:group video memory", "VRAM")
                foot: vramReading

                Reading {
                    id: vramReading
                    // An integrated GPU's share of system memory has no meaningful total.
                    // The known size stands in while a resting GPU's readings are held.
                    readonly property bool ofTotal: section.slot.kind === "discrete"
                    readonly property var b: ofTotal ? Format.bytesOf(section.slot.vramUsed, section.slot.knownVramTotal)
                                                     : Format.bytes(section.slot.vramUsed, false)
                    value: b.value
                    unit: ofTotal && b.unit ? "/ " + sectionWords.bytesText({ value: b.total, unit: b.unit }) : b.unit
                    pointSize: section.tilePointSize
                }
            }

            Tile {
                caption: i18nc("@title:group GPU core clock", "Clock")
                foot: clockReading

                Reading {
                    id: clockReading
                    readonly property var f: Format.frequency(section.slot.clock)
                    value: f.value
                    unit: f.unit
                    pointSize: section.tilePointSize
                }
            }

            Tile {
                visible: section.hasPower
                caption: i18nc("@title:group GPU power draw", "Power")
                foot: powerReading

                Reading {
                    id: powerReading
                    readonly property var w: Format.watts(section.slot.power)
                    value: w.value
                    unit: w.unit
                    pointSize: section.tilePointSize
                }
            }
        }

        GpuProcessList {
            id: processList
            visible: section.processesShown && section.processCount > 0
            rows: section.processes
            count: section.processCount
            memoryShown: section.slot.reportsVram
        }
    }
}
