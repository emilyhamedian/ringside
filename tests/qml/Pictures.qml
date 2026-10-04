// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.plasma.core as PlasmaCore
import "../../package/contents/ui"
import "../../package/contents/ui/popups"

// The README's pictures, from fixed sample readings: scripts/pictures.sh
// runs this, which saves each shot and the fold's frames to the folder given
// after --out and quits. In the popups the week resets at 7:00 AM EDT, far
// enough ahead that most of it has been used; the panel and Standalone
// pictures count down a fixed time, so they come out the same on every run.
Rectangle {
    id: pictures

    readonly property string outDir: Qt.application.arguments.indexOf("--out") >= 0
        ? Qt.application.arguments[Qt.application.arguments.indexOf("--out") + 1] : ""

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

    width: shots.implicitWidth
    height: shots.implicitHeight
    color: Kirigami.Theme.backgroundColor

    // Behind the panel pictures, a stand-in for the wallpaper.
    readonly property color desktop: "#3b4a57"

    // The first 11:00 UTC at least two and a half days away, and the week's
    // use until now: working hours in New York, nothing overnight.
    readonly property int week: 7 * 86400
    readonly property real now: Math.floor(Date.now() / 1000)
    readonly property real resetsAt: {
        const earliest = now + 2.5 * 86400;
        const d = new Date(earliest * 1000);
        const at = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 11) / 1000;
        return at >= earliest ? at : at + 86400;
    }

    function history(percent) {
        const start = resetsAt - week;
        const busy = t => {
            const hour = new Date((t - 4 * 3600) * 1000).getUTCHours();
            return hour >= 9 && hour < 19;
        };
        let total = 0;
        for (let t = start; t < now; t += 1800) {
            total += busy(t) ? 1 : 0;
        }
        const points = [[start, 0]];
        let used = 0;
        for (let t = start + 1800; t <= now; t += 1800) {
            used += busy(t - 1800) ? 1 : 0;
            points.push([t, Math.round(percent * used / Math.max(1, total))]);
        }
        return points;
    }

    function window(percent) {
        return { percent: percent, resetsAt: resetsAt, windowSeconds: week,
                 clockZone: { offset: -4 * 3600, abbreviation: "EDT" }, history: history(percent) };
    }

    FakeMonitor {
        id: sample
        memoryUsed: 24.6 * gib
        usage.entries: ({
            claude: { status: "ok", fetchedAt: pictures.now, weekly: pictures.window(62),
                      scoped: [Object.assign({ id: "Opus", label: "Opus" }, pictures.window(78))] },
            codex: { status: "ok", fetchedAt: pictures.now, weekly: pictures.window(34), scoped: [] }
        })
    }

    // The sample for the panel, Standalone and fold pictures, whose countdowns
    // would otherwise change with the time of day they are rendered: the
    // weeks reset 2 days 21 hours and a half from now, which reads "2d 21h".
    FakeMonitor {
        id: shown
        readonly property int left: 2 * 86400 + 21 * 3600 + 30 * 60
        memoryUsed: 24.6 * gib
        usage.entries: ({
            claude: { status: "ok", fetchedAt: shown.usage.createdAt, weekly: shown.usage.window(62, shown.left, []),
                      scoped: [Object.assign({ id: "Opus", label: "Opus" }, shown.usage.window(78, shown.left, []))] },
            codex: { status: "ok", fetchedAt: shown.usage.createdAt, weekly: shown.usage.window(34, shown.left, []), scoped: [] }
        })
    }

    // A popup on the theme's dialog background, as AppletPopup draws it.
    component Dialog: KSvg.FrameSvgItem {
        default property alias page: holder.data

        imagePath: "dialogs/background"
        implicitWidth: holder.childrenRect.width + margins.left + margins.right
        implicitHeight: holder.childrenRect.height + margins.top + margins.bottom

        Item {
            id: holder
            x: parent.margins.left
            y: parent.margins.top
        }
    }

    // One point of the fold on a strip of desktop at the right screen edge:
    // the panel keeps its thickness while the dials shrink toward the tab,
    // then snaps to the 44 px tab.
    component FoldFrame: Rectangle {
        id: frame

        required property real progress
        readonly property real open: strip.minimumThickness + 8

        width: open + 48
        height: fold.implicitHeight + 40
        color: pictures.desktop

        KSvg.FrameSvgItem {
            id: fold
            imagePath: "widgets/panel-background"
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: frame.progress === 0 ? 44 : frame.open
            height: strip.implicitHeight + 8
            implicitHeight: openStrip.implicitHeight + 8

            StandaloneStrip {
                id: strip
                anchors.fill: parent
                anchors.margins: 4
                monitor: shown
                items: ["cpu", "claude", "codex"]
                enabledItems: items
                vertical: true
                location: PlasmaCore.Types.RightEdge
                expandedThickness: minimumThickness
                visibilityMode: frame.progress === 0 ? 2 : 1
                expansionProgress: frame.progress
                handleProgress: 1
            }
        }

        // The open strip's length, so every frame has the same height.
        StandaloneStrip {
            id: openStrip
            visible: false
            monitor: shown
            items: strip.items
            enabledItems: items
            width: strip.minimumThickness
        }
    }

    ColumnLayout {
        id: shots
        spacing: 40

        // A 46 px Breeze panel gives its applets 38 px.
        KSvg.FrameSvgItem {
            objectName: "panel"
            imagePath: "widgets/panel-background"
            implicitWidth: row.implicitWidth + 2 * Kirigami.Units.gridUnit
            implicitHeight: 46

            Strip {
                id: row
                anchors.centerIn: parent
                height: 38
                monitor: shown
                items: ["cpu", "gpu", "memory", "claude", "network"]
                vertical: false
                thickness: 38
                ringsOnly: []
            }
        }

        RowLayout {
            objectName: "popups"
            spacing: 24

            Dialog {
                Layout.alignment: Qt.AlignTop
                CpuPopup { monitor: sample }
            }
            Dialog {
                Layout.alignment: Qt.AlignTop
                GpuPopup { monitor: sample }
            }
            Dialog {
                Layout.alignment: Qt.AlignTop
                MemoryPopup { monitor: sample }
            }
            Dialog {
                Layout.alignment: Qt.AlignTop
                NetworkPopup { monitor: sample }
            }
        }

        Dialog {
            objectName: "usage"
            UsagePopup {
                monitor: sample
                item: "claude"
            }
        }

        Rectangle {
            objectName: "standalone"
            implicitWidth: side.implicitWidth + 48
            implicitHeight: side.implicitHeight + 40
            color: pictures.desktop

            KSvg.FrameSvgItem {
                id: side
                imagePath: "widgets/panel-background"
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: dials.minimumThickness + 8
                implicitHeight: dials.implicitHeight + 8

                StandaloneStrip {
                    id: dials
                    anchors.fill: parent
                    anchors.margins: 4
                    monitor: shown
                    items: ["cpu", "gpu", "claude", "codex"]
                    enabledItems: items
                    vertical: true
                    location: PlasmaCore.Types.RightEdge
                    visibilityMode: 1
                }
            }
        }

        // Folding, eased as the strip eases it, then the tab held.
        Row {
            id: frames
            spacing: 8
            Repeater {
                model: [1, 0.97, 0.9, 0.78, 0.62, 0.45, 0.28, 0.14, 0.05, 0]
                delegate: FoldFrame {
                    required property real modelData
                    required property int index
                    objectName: "fold-" + index
                    progress: modelData
                }
            }
        }
    }

    function save(names, done) {
        if (names.length === 0) {
            done();
            return;
        }
        const item = find(shots, names[0]);
        item.grabToImage(result => {
            result.saveToFile(outDir + "/" + names[0] + ".png");
            save(names.slice(1), done);
        });
    }

    function find(item, name) {
        if (item.objectName === name) {
            return item;
        }
        for (const child of item.children) {
            const found = find(child, name);
            if (found) {
                return found;
            }
        }
        return null;
    }

    // Long enough for the process lists' first scan.
    Timer {
        interval: 5000
        running: pictures.outDir !== ""
        onTriggered: pictures.save(["panel", "popups", "usage", "standalone"]
                                   .concat(Array.from({ length: 10 }, (_, i) => "fold-" + i)), Qt.quit)
    }
}
