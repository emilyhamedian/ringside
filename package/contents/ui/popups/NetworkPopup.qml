import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../code/format.js" as Format
import "../code/history.js" as History
import ".."

// Opened by both the network and the disk items.
PopupPage {
    id: popup

    readonly property real diskTemperature: popup.monitor.diskTemperature
    readonly property bool diskTemperatureShown: Number.isFinite(diskTemperature)

    // Legend and detail text: caption-sized, set as written.
    component Note: Caption {}

    component RateText: Text {
        font.family: Kirigami.Theme.fixedWidthFont.family
        font.pointSize: Kirigami.Theme.defaultFont.pointSize
        textFormat: Text.PlainText
    }

    // Read or write: the rate over a small line graph of its history.
    component DiskRate: Tile {
        id: tile

        property real rate: NaN
        property var history: []
        property int length: 60

        Reading {
            readonly property var r: Format.rate(tile.rate, false)
            value: r.value
            unit: r.unit
            unitScale: 0.67
            pointSize: Kirigami.Theme.defaultFont.pointSize * 1.38
        }

        Graph {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(Kirigami.Units.gridUnit * 1.35)
            values: tile.history
            length: tile.length
            // Anything under 1 MiB/s stays near the floor rather than filling the graph.
            maximum: History.niceMax(tile.history, 1048576)
            fillOpacity: 0
        }
    }

    PopupHeader {
        ringShown: false
        title: i18nc("@title", "Network & Disk")
        subtitle: [popup.monitor.networkInterface, popup.monitor.networkConnection, popup.monitor.networkAddress]
            .filter(s => s !== "").join(" · ")

        GridLayout {
            id: rates

            readonly property var down: Format.rate(popup.monitor.networkDown, popup.monitor.networkBits)
            readonly property var up: Format.rate(popup.monitor.networkUp, popup.monitor.networkBits)
            readonly property real arrowHeight: Math.round(downValue.implicitHeight * 0.62)
            readonly property color markColor: Qt.alpha(Kirigami.Theme.textColor, 0.75)
            readonly property color unitColor: Qt.alpha(Kirigami.Theme.textColor, 0.6)

            columns: 3
            rowSpacing: Math.round(Kirigami.Units.smallSpacing * 1.25)
            columnSpacing: Math.round(Kirigami.Units.smallSpacing * 1.75)

            Arrow {
                Layout.preferredWidth: Layout.preferredHeight * 0.8
                Layout.preferredHeight: rates.arrowHeight
                color: rates.markColor
            }
            RateText {
                id: downValue
                Layout.alignment: Qt.AlignRight
                text: rates.down.value
                color: Kirigami.Theme.textColor
            }
            RateText {
                text: rates.down.unit
                color: rates.unitColor
            }

            Arrow {
                Layout.preferredWidth: Layout.preferredHeight * 0.8
                Layout.preferredHeight: rates.arrowHeight
                up: true
                color: rates.markColor
            }
            RateText {
                Layout.alignment: Qt.AlignRight
                text: rates.up.value
                color: Kirigami.Theme.textColor
            }
            RateText {
                text: rates.up.unit
                color: rates.unitColor
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Math.round(Kirigami.Units.largeSpacing * 1.5)
        Layout.rightMargin: Layout.leftMargin
        Layout.topMargin: Math.round(Kirigami.Units.smallSpacing * 1.5)
        Layout.bottomMargin: Layout.leftMargin
        columns: 2
        rowSpacing: Kirigami.Units.largeSpacing
        columnSpacing: Kirigami.Units.largeSpacing
        uniformCellWidths: true

        Tile {
            Layout.columnSpan: 2
            caption: i18nc("@title:group", "Throughput")
            detail: "· " + Format.duration(popup.monitor.historySeconds)

            Graph {
                Layout.fillWidth: true
                values: popup.monitor.networkDownHistory
                second: true
                secondValues: popup.monitor.networkUpHistory
                length: popup.monitor.historyLength
                // 1 Mb/s at least, so an idle link doesn't draw its noise at full height.
                maximum: History.niceMax(popup.monitor.networkDownHistory.concat(popup.monitor.networkUpHistory), 125000)
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(Kirigami.Units.smallSpacing / 2)
                spacing: Math.round(Kirigami.Units.largeSpacing * 1.75)

                Note {
                    Layout.minimumWidth: implicitWidth
                    text: i18nc("@label graph legend, the solid line", "— Down")
                }

                Note {
                    Layout.minimumWidth: implicitWidth
                    text: i18nc("@label graph legend, the dashed line", "- - Up")
                }

                Note {
                    readonly property var down: Format.bytes(popup.monitor.networkTotalDown)
                    readonly property var up: Format.bytes(popup.monitor.networkTotalUp)

                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    visible: down.unit !== "" && up.unit !== ""
                    text: i18nc("@info bytes received and sent since boot, e.g. Since boot 3.2 GiB ↓ · 410 MiB ↑",
                                "Since boot %1 %2 ↓ · %3 %4 ↑", down.value, down.unit, up.value, up.unit)
                }
            }
        }

        RowLayout {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.leftMargin: Math.round(Kirigami.Units.smallSpacing / 2)
            Layout.rightMargin: Layout.leftMargin
            spacing: 0

            Caption {
                label: i18nc("@title:group", "Disk")
            }

            Note {
                Layout.fillWidth: true
                // Rounded up: the layout snaps to whole pixels, and a fraction short elides.
                Layout.maximumWidth: Math.ceil(implicitWidth)
                text: {
                    const m = popup.monitor;
                    const size = Format.bytes(m.diskSize, true);
                    const free = Format.bytes(m.volumeFree, true);
                    const parts = [
                        m.diskDevice === "all" ? i18nc("@info disk I/O of every disk", "all disks") : m.diskDevice,
                        size.unit ? size.value + " " + size.unit : "",
                        !free.unit ? ""
                            : m.volumeLabel ? i18nc("@info free space on a volume, e.g. 1.2 TiB free on /", "%1 %2 free on %3",
                                                    free.value, free.unit, m.volumeLabel)
                            : i18nc("@info free space, e.g. 1.2 TiB free", "%1 %2 free", free.value, free.unit)
                    ].filter(s => s !== "");
                    // The separators stay in the details' colour when the temperature is highlighted.
                    return parts.map(s => " · " + s).join("") + (popup.diskTemperatureShown ? " · " : "");
                }
            }

            Note {
                visible: popup.diskTemperatureShown
                text: Format.temperature(popup.diskTemperature, popup.monitor.fahrenheit) + "°"
                color: {
                    const level = popup.monitor.heat(popup.diskTemperature);
                    return level === 2 ? Kirigami.Theme.negativeTextColor
                         : level === 1 ? Kirigami.Theme.neutralTextColor : Qt.alpha(Kirigami.Theme.textColor, 0.6);
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        DiskRate {
            caption: i18nc("@title:group disk reads", "Read")
            rate: popup.monitor.diskRead
            history: popup.monitor.diskReadHistory
            length: popup.monitor.historyLength
        }

        DiskRate {
            caption: i18nc("@title:group disk writes", "Write")
            rate: popup.monitor.diskWrite
            history: popup.monitor.diskWriteHistory
            length: popup.monitor.historyLength
        }
    }
}
