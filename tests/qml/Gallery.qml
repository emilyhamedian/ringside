pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import "../../package/contents/ui"
import "../../package/contents/ui/popups"

// The panel strip and the four popups with FakeMonitor's readings, then the
// states the popups have to cope with. The top-process lists and the CPU
// popup's frequency, load average and per-thread bars read this machine.
// scripts/gallery.sh renders it to a PNG; qml tests/qml/Gallery.qml shows it
// in a window, and adding -- --snapshot out.png saves a PNG and quits.
Rectangle {
    id: gallery

    readonly property string snapshotPath: Qt.application.arguments.indexOf("--snapshot") >= 0
        ? Qt.application.arguments[Qt.application.arguments.indexOf("--snapshot") + 1] : ""

    // A bare qml runtime has no KI18n; the views find these on the root.
    function substitute(text, args) {
        return text.replace(/%(\d+)/g, (match, n) => n <= args.length ? String(args[n - 1]) : match);
    }
    function i18n(text, ...args) {
        return substitute(text, args);
    }
    function i18nc(context, text, ...args) {
        return substitute(text, args);
    }
    function i18np(singular, plural, n, ...args) {
        return substitute(n === 1 ? singular : plural, [n].concat(args));
    }
    function i18ncp(context, singular, plural, n, ...args) {
        return substitute(n === 1 ? singular : plural, [n].concat(args));
    }

    width: layout.implicitWidth + 2 * layout.x
    height: layout.implicitHeight + 2 * layout.y
    color: Kirigami.Theme.backgroundColor
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    FakeMonitor {
        id: normal
    }

    FakeMonitor {
        id: hot
        cpuTemperature: 92
    }

    FakeMonitor {
        id: asleep
        gpuOuter.phase: "asleep"
    }

    FakeMonitor {
        id: integrated
        gpuOuter.kind: "integrated"
        gpuOuter.name: "AMD Radeon 780M Graphics"
        gpuOuter.usage: 18
        gpuOuter.temperature: 52
        gpuOuter.vramUsed: 0.4 * integrated.gib
        gpuOuter.vramTotal: 0.5 * integrated.gib
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

    component Note: Text {
        color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        textFormat: Text.PlainText
    }

    // The strip centred on a stretch of panel, as main.qml places it. The
    // outline marks the panel's thickness.
    component Panel: ColumnLayout {
        id: panel

        required property string label
        required property real thickness
        property var ringsOnly: []

        spacing: Kirigami.Units.smallSpacing

        Note {
            text: panel.label
        }

        Rectangle {
            color: "transparent"
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
            Layout.preferredWidth: strip.implicitWidth + 4 * Kirigami.Units.gridUnit
            Layout.preferredHeight: panel.thickness

            Strip {
                id: strip
                anchors.centerIn: parent
                monitor: normal
                items: ["cpu", "gpu", "memory", "network", "disk"]
                vertical: false
                thickness: panel.thickness
                ringSize: 30
                ringsOnly: panel.ringsOnly
            }
        }
    }

    // A popup on the theme's dialog background, sized to its implicit size
    // as AppletPopup sizes its main item.
    component PopupFrame: ColumnLayout {
        id: popup

        required property string label
        default property alias page: holder.data

        Layout.alignment: Qt.AlignTop
        spacing: Kirigami.Units.smallSpacing

        Note {
            text: popup.label
        }

        KSvg.FrameSvgItem {
            id: dialog

            imagePath: "dialogs/background"
            Layout.preferredWidth: holder.childrenRect.width + fixedMargins.left + fixedMargins.right
            Layout.preferredHeight: holder.childrenRect.height + fixedMargins.top + fixedMargins.bottom

            Item {
                id: holder
                x: dialog.fixedMargins.left
                y: dialog.fixedMargins.top
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
            label: "Panel · 30 px"
            thickness: 30
        }

        Panel {
            label: "Panel · 46 px · rings only"
            thickness: 46
            ringsOnly: ["cpu", "gpu", "memory"]
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            PopupFrame {
                label: "CPU"
                CpuPopup { monitor: normal }
            }

            PopupFrame {
                label: "GPU"
                GpuPopup { monitor: normal }
            }

            PopupFrame {
                label: "Memory"
                MemoryPopup { monitor: normal }
            }

            PopupFrame {
                label: "Network & Disk"
                NetworkPopup { monitor: normal }
            }
        }

        RowLayout {
            spacing: 2 * Kirigami.Units.gridUnit

            PopupFrame {
                label: "CPU · 92 °C"
                CpuPopup { monitor: hot }
            }

            PopupFrame {
                label: "GPU · discrete asleep"
                GpuPopup { monitor: asleep }
            }

            PopupFrame {
                label: "GPU · one integrated GPU"
                GpuPopup { monitor: integrated }
            }

            PopupFrame {
                label: "Memory · no PSI, no swap"
                MemoryPopup { monitor: bare }
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
