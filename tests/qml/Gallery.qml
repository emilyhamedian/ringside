// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../../package/contents/ui"
import "../../package/contents/ui/popups"

// The panel strip and the four popups with FakeMonitor's readings, then the
// states they have to cope with, then the same under Breeze Light. The
// top-process lists show FakeMonitor's processSample; only the CPU popup's
// frequency, load average and per-thread bars read this machine.
// scripts/gallery.sh renders it to a PNG; qml tests/qml/Gallery.qml shows it
// in a window, and adding -- --snapshot out.png saves a PNG and quits.
TestRoot {
    id: gallery

    readonly property string snapshotPath: Qt.application.arguments.indexOf("--snapshot") >= 0
        ? Qt.application.arguments[Qt.application.arguments.indexOf("--snapshot") + 1] : ""

    width: layout.implicitWidth + 2 * layout.x
    height: layout.implicitHeight + 2 * layout.y
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    FakeMonitor {
        id: normal
    }

    // The public address in the network popup, worked out by the real
    // checker from canned replies.
    PublicAddressStates {
        id: publicStates
        localInterface: normal.networkInterface
    }

    component PublicFake: FakeMonitor {
        property string publicState
        publicAddress: publicStates.all[publicState] ?? null
    }

    PublicFake {
        id: publicBoth
        publicState: "both"
    }

    PublicFake {
        id: publicVpn
        publicState: "vpn"
    }

    PublicFake {
        id: publicLongVpn
        publicState: "longvpn"
    }

    PublicFake {
        id: publicLeak
        publicState: "longleak"
    }

    PublicFake {
        id: publicCity
        publicState: "city"
    }

    PublicFake {
        id: publicFailed
        publicState: "failed"
    }

    // Hot, with its top processes still being read.
    FakeMonitor {
        id: hot
        cpuTemperature: 92
        processSample: []
    }

    FakeMonitor {
        id: asleep
        gpuOuter.phase: "asleep"
    }

    // The last hour and the last day, with a stretch where the machine slept.
    FakeMonitor {
        id: hour
        graphSpan: "hour"
    }

    FakeMonitor {
        id: day
        graphSpan: "day"
    }

    FakeMonitor {
        id: integrated
        gpuOuter.kind: "integrated"
        gpuOuter.name: "AMD Radeon 780M Graphics"
        gpuOuter.usage: 18
        gpuOuter.temperature: 52
        gpuOuter.vramUsed: 0.4 * integrated.gib
        gpuOuter.clock: 1200
        gpuOuter.power: NaN
        gpuOuter.history: integrated.wave(18, 12, 9)
        gpuInner.present: false
    }

    FakeMonitor {
        id: bare
        memoryPressure: NaN
        swapUsed: 0
        swapTotal: 0
        swapLabel: ""
    }

    // The discrete GPU picked for the inner ring, asleep.
    FakeMonitor {
        id: innerAsleep
        gpuOuter.kind: "integrated"
        gpuOuter.name: "AMD Radeon 780M Graphics"
        gpuOuter.usage: 18
        gpuOuter.temperature: 52
        gpuOuter.vramUsed: 0.4 * innerAsleep.gib
        gpuOuter.knownVramTotal: 0.5 * innerAsleep.gib
        gpuOuter.clock: 1200
        gpuOuter.power: NaN
        gpuInner.kind: "discrete"
        gpuInner.name: "AMD Radeon RX 7700S"
        gpuInner.phase: "asleep"
        gpuInner.knownVramTotal: 8 * innerAsleep.gib
    }

    // A hybrid laptop: Intel publishes no GPU temperature.
    FakeMonitor {
        id: intel
        cpuModel: "Intel Core i7-12700H"
        cpuTemperature: 78
        gpuOuter.name: "NVIDIA GeForce RTX 3060 Laptop GPU"
        gpuOuter.temperatureLabel: ""
        gpuOuter.usage: 64
        gpuOuter.temperature: 71
        gpuOuter.vramUsed: 2.2 * intel.gib
        gpuOuter.knownVramTotal: 6 * intel.gib
        gpuOuter.clock: 1650
        gpuOuter.power: 62
        gpuInner.name: "Intel Iris Xe Graphics"
        gpuInner.temperatureLabel: ""
        gpuInner.reportsTemperature: false
        gpuInner.reportsVram: false
        gpuInner.temperature: NaN
        gpuInner.vramUsed: NaN
        gpuInner.knownVramTotal: NaN
        gpuInner.clock: 1100
    }

    // The Codex ring with the OpenAI logo.
    FakeMonitor {
        id: openaiMark
        codexMark: "openai"
    }

    // Every ring past a threshold: hot, warm, full, nearly out.
    FakeMonitor {
        id: alert
        cpuUsage: 95
        cpuTemperature: 92
        memoryUsed: 29.4 * alert.gib
        gpuOuter.usage: 77
        gpuOuter.temperature: 78
        usage.entries: ({
            claude: { status: "ok", weekly: alert.usage.window(95, 4 * 3600 + 12 * 60, []) },
            codex: { status: "ok", weekly: alert.usage.window(81, 5 * alert.usage.day, []) }
        })
    }

    // Claude's last day, which it lasts at this pace.
    FakeMonitor {
        id: lastDay
        usage.entries: ({
            claude: { status: "ok", weekly: lastDay.usage.window(70, 23 * 3600 + 5 * 60, []), scoped: [] }
        })
    }

    // A drive that reports no temperature, warm or hot ones, and every disk.
    FakeMonitor {
        id: diskUnheated
        diskTemperature: NaN
    }

    FakeMonitor {
        id: diskHot
        diskTemperature: 78
        diskDevice: "all"
    }

    // Temperatures climbing through the warm and hot thresholds as a load
    // starts 15 s in, and the same with the highlighting off.
    component Heating: FakeMonitor {
        id: fake

        function climb(from, to) {
            return Array.from({ length: fake.historyLength }, (_, i) =>
                from + (to - from) * (1 - Math.pow(1 - Math.max(0, (i - 15) / (fake.historyLength - 16)), 2.2)) + 0.4 * Math.sin(i * 1.7));
        }

        cpuUsage: 97
        cpuHistory: fake.climb(6, 97)
        cpuTemperature: 93
        cpuTemperatureHistory: fake.climb(52, 93)
        gpuOuter.usage: 99
        gpuOuter.history: fake.climb(3, 99)
        gpuOuter.temperature: 91
        gpuOuter.temperatureHistory: fake.climb(44, 91)
        diskTemperature: 92
        diskTemperatureHistory: fake.climb(41, 92)
    }

    Heating {
        id: heating
    }

    Heating {
        id: plainHeat
        highlightTemperatures: false
    }

    // The discrete GPU alone, awake for the last 35 s, in °F. Asleep it had
    // no temperature and, as Monitor records it, no usage.
    FakeMonitor {
        id: woken
        fahrenheit: true
        gpuOuter.history: Array.from({ length: woken.historyLength }, (_, i) => i < 25 ? 0 : 12 + 3 * Math.sin(i))
        gpuOuter.temperatureHistory: Array.from({ length: woken.historyLength }, (_, i) =>
            i < 25 ? NaN : 48 - 6 * Math.exp(-(i - 25) / 6))
        gpuInner.present: false
    }

    // The only GPU, asleep.
    FakeMonitor {
        id: onlyAsleep
        gpuOuter.phase: "asleep"
        gpuInner.present: false
    }

    // The Memory popup with every string about a third longer, as German and
    // the Romance languages often run. Its views find these functions before
    // the root's, as this component's root is the nearer context object.
    component LongMemoryPopup: Item {
        id: stretched

        required property var monitor

        function i18n(text, ...args) {
            return gallery.stretch(gallery.i18n(text, ...args));
        }
        function i18nc(context, text, ...args) {
            return gallery.stretch(gallery.i18nc(context, text, ...args));
        }
        function i18np(singular, plural, n, ...args) {
            return gallery.stretch(gallery.i18np(singular, plural, n, ...args));
        }
        function i18ncp(context, singular, plural, n, ...args) {
            return gallery.stretch(gallery.i18ncp(context, singular, plural, n, ...args));
        }

        implicitWidth: popup.implicitWidth
        implicitHeight: popup.implicitHeight

        MemoryPopup {
            id: popup
            monitor: stretched.monitor
        }
    }

    component Panel: GalleryPanel {
        monitor: normal
        items: ["cpu", "gpu", "memory", "claude", "network", "disk"]
    }

    // A left or right panel. Breeze's panel keeps 4 px of margin either side
    // of an applet, so the strip gets the thickness less 8 px.
    component VerticalPanel: ColumnLayout {
        id: side

        required property string label
        required property real thickness
        property var monitor: normal

        Layout.alignment: Qt.AlignTop
        spacing: Kirigami.Units.smallSpacing

        GalleryNote {
            text: side.label
        }

        Rectangle {
            color: "transparent"
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
            Layout.preferredWidth: side.thickness
            Layout.preferredHeight: column.implicitHeight + 2 * Kirigami.Units.gridUnit

            Strip {
                id: column
                anchors.centerIn: parent
                width: side.thickness - 8
                height: implicitHeight
                monitor: side.monitor
                items: ["cpu", "gpu", "memory", "claude", "codex", "network", "disk"]
                vertical: true
                thickness: width
                ringsOnly: []
            }
        }
    }

    ColumnLayout {
        id: layout

        x: 3 * Kirigami.Units.gridUnit
        y: x
        spacing: 2 * Kirigami.Units.gridUnit

        Panel {
            label: "Panel · 46 px"
            thickness: 46
        }

        Panel {
            label: "Panel · 44 px"
            thickness: 44
        }

        Panel {
            label: "Panel · 38 px"
            thickness: 38
        }

        Panel {
            label: "Panel · 30 px"
            thickness: 30
        }

        Panel {
            label: "Panel · 72 px"
            thickness: 72
        }

        Panel {
            label: "Panel · 46 px · Claude and Codex"
            thickness: 46
            items: ["claude", "codex"]
        }

        Panel {
            label: "Panel · 46 px · Codex with the OpenAI logo"
            thickness: 46
            monitor: openaiMark
            items: ["claude", "codex"]
        }

        Panel {
            label: "Panel · 46 px · alerts"
            thickness: 46
            monitor: alert
        }

        Panel {
            label: "Panel · 46 px · right to left · Claude's last day, 23h 5m left"
            thickness: 46
            monitor: lastDay
            mirrored: true
        }

        Panel {
            label: "Panel · 46 px · the only GPU asleep"
            thickness: 46
            monitor: onlyAsleep
        }

        Panel {
            label: "Panel · 46 px · rings only · CPU 92 °C"
            thickness: 46
            monitor: hot
            ringsOnly: ["cpu", "gpu", "memory"]
        }

        Panel {
            label: "Panel · 46 px · iGPU outer, dGPU inner asleep"
            thickness: 46
            monitor: innerAsleep
        }

        Panel {
            label: "Panel · 46 px · NVIDIA outer, Intel inner (no temperature)"
            thickness: 46
            monitor: intel
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            VerticalPanel {
                label: "Vertical · 36 px"
                thickness: 36
            }

            VerticalPanel {
                label: "Vertical · 46 px"
                thickness: 46
            }

            VerticalPanel {
                label: "Vertical · 46 px · CPU 92 °C"
                thickness: 46
                monitor: hot
            }

            VerticalPanel {
                label: "Vertical · 60 px"
                thickness: 60
            }
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            GalleryFrame {
                label: "CPU"
                CpuPopup { monitor: normal }
            }

            GalleryFrame {
                label: "GPU"
                GpuPopup { monitor: normal }
            }

            GalleryFrame {
                label: "Memory"
                MemoryPopup { monitor: normal }
            }

            GalleryFrame {
                label: "Network"
                NetworkPopup { monitor: normal }
            }

            GalleryFrame {
                label: "Disk"
                DiskPopup { monitor: normal }
            }
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            GalleryFrame {
                label: "CPU · 1 h"
                CpuPopup { monitor: hour }
            }

            GalleryFrame {
                label: "GPU · 1 h"
                GpuPopup { monitor: hour }
            }

            GalleryFrame {
                label: "Memory · 1 h"
                MemoryPopup { monitor: hour }
            }

            GalleryFrame {
                label: "Network · 1 h"
                NetworkPopup { monitor: hour }
            }

            GalleryFrame {
                label: "Disk · 1 h"
                DiskPopup { monitor: hour }
            }
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            GalleryFrame {
                label: "CPU · 1 day"
                CpuPopup { monitor: day }
            }

            GalleryFrame {
                label: "GPU · 1 day"
                GpuPopup { monitor: day }
            }

            GalleryFrame {
                label: "Memory · 1 day"
                MemoryPopup { monitor: day }
            }

            GalleryFrame {
                label: "Network · 1 day"
                NetworkPopup { monitor: day }
            }

            GalleryFrame {
                label: "Disk · 1 day"
                DiskPopup { monitor: day }
            }
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            GalleryFrame {
                label: "CPU · 92 °C · top processes loading"
                CpuPopup { monitor: hot }
            }

            GalleryFrame {
                label: "GPU · discrete asleep"
                GpuPopup { monitor: asleep }
            }

            GalleryFrame {
                label: "GPU · one integrated GPU"
                GpuPopup { monitor: integrated }
            }

            GalleryFrame {
                label: "Memory · no PSI, no swap"
                MemoryPopup { monitor: bare }
            }

            GalleryFrame {
                label: "Memory · every string a third longer"
                LongMemoryPopup { monitor: normal }
            }
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            GalleryFrame {
                label: "GPU · iGPU outer, dGPU inner asleep"
                GpuPopup { monitor: innerAsleep }
            }

            GalleryFrame {
                label: "GPU · NVIDIA and Intel"
                GpuPopup { monitor: intel }
            }

            GalleryFrame {
                label: "GPU · the only GPU asleep"
                GpuPopup { monitor: onlyAsleep }
            }

            GalleryFrame {
                label: "Disk · no temperature"
                DiskPopup { monitor: diskUnheated }
            }

            GalleryFrame {
                label: "Disk · all disks, 78 °C"
                DiskPopup { monitor: diskHot }
            }
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            GalleryFrame {
                label: "CPU · temperature climbing through 75 and 90 °C"
                CpuPopup { monitor: heating }
            }

            GalleryFrame {
                label: "GPU · dGPU climbing through 75 and 90 °C"
                GpuPopup { monitor: heating }
            }

            GalleryFrame {
                label: "GPU · dGPU awake for the last 35 s, °F"
                GpuPopup { monitor: woken }
            }

            GalleryFrame {
                label: "Disk · climbing through 75 and 90 °C"
                DiskPopup { monitor: heating }
            }

            GalleryFrame {
                label: "Disk · climbing, temperature colours off"
                DiskPopup { monitor: plainHeat }
            }
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            GalleryFrame {
                label: "Network · public IPv4 and IPv6"
                NetworkPopup { monitor: publicBoth }
            }

            GalleryFrame {
                label: "Network · through a VPN, just turned on"
                NetworkPopup { monitor: publicVpn }
            }

            GalleryFrame {
                label: "Network · a long IPv6 through the VPN"
                NetworkPopup { monitor: publicLongVpn }
            }

            GalleryFrame {
                label: "Network · a long IPv6 going around the VPN"
                NetworkPopup { monitor: publicLeak }
            }

            GalleryFrame {
                label: "Network · a Custom service that names the city"
                NetworkPopup { monitor: publicCity }
            }

            GalleryFrame {
                label: "Network · public address unreachable"
                NetworkPopup { monitor: publicFailed }
            }
        }

        // Claude and Codex, in the panel and in their popups.
        UsageGallery {
            monitor: normal
        }

        GalleryLight {
            GalleryNote {
                text: "Breeze Light colours are set on this section only; the popup footers keep the system's."
            }

            Panel {
                label: "Breeze Light · panel · 46 px"
                thickness: 46
            }

            Panel {
                label: "Breeze Light · panel · 46 px · alerts"
                thickness: 46
                monitor: alert
            }

            Panel {
                label: "Breeze Light · panel · 46 px · rings only · CPU 92 °C"
                thickness: 46
                monitor: hot
                ringsOnly: ["cpu", "gpu", "memory"]
            }

            RowLayout {
                spacing: 2 * Kirigami.Units.gridUnit

                GalleryFrame {
                    label: "Breeze Light · CPU"
                    flat: true
                    CpuPopup { monitor: normal }
                }

                GalleryFrame {
                    label: "Breeze Light · GPU"
                    flat: true
                    GpuPopup { monitor: normal }
                }

                GalleryFrame {
                    label: "Breeze Light · Memory"
                    flat: true
                    MemoryPopup { monitor: normal }
                }

                GalleryFrame {
                    label: "Breeze Light · Network"
                    flat: true
                    NetworkPopup { monitor: normal }
                }

                GalleryFrame {
                    label: "Breeze Light · Disk"
                    flat: true
                    DiskPopup { monitor: normal }
                }
            }
        }
    }

    // Long enough for the process lists' first scan and the CPU sensors.
    Timer {
        interval: 5000
        running: gallery.snapshotPath.length > 0
        onTriggered: gallery.grabToImage(result => {
            result.saveToFile(gallery.snapshotPath);
            Qt.quit();
        })
    }
}
