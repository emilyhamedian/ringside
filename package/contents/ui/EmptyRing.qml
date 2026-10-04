// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

// Stands in for the Standalone dials while none has anything to show, so the
// panel keeps its footprint, and says why on hover.
Item {
    id: empty

    property real sizeFactor: 1
    property bool interactive: true
    property int location: PlasmaCore.Types.Floating
    // Why the helper for Claude and Codex gave no report, if it failed.
    property string helperError: ""
    // The items switched on, none of which has anything to show.
    property var enabledItems: []
    // UsageData's last status per provider: a first check that failed says why.
    property var statuses: ({})

    readonly property bool claude: enabledItems.includes("claude")
    readonly property bool codex: enabledItems.includes("codex")
    readonly property string failure: {
        const failed = ["claude", "codex"].filter(id => enabledItems.includes(id)).map(id => statuses[id])
            .find(s => s && (s.status === "error" || s.status === "rate_limited") && s.message);
        return failed ? failed.message : "";
    }
    readonly property string reason: helperError !== "" ? helperError
        : failure !== "" ? failure
        : claude && codex ? i18nc("@info:tooltip", "Run claude or codex in a terminal to sign in.")
        : claude || codex ? i18nc("@info:tooltip %1 is a command, claude or codex", "Run %1 in a terminal to sign in.",
                                  claude ? "claude" : "codex")
        : i18nc("@info:tooltip", "Choose items under Configure Ringside → Panel Items.")

    readonly property real diameter: 52 * sizeFactor
    readonly property color faint: Qt.alpha(Kirigami.Theme.textColor, 0.28)

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    Accessible.role: Accessible.StaticText
    Accessible.name: toolTip.mainText
    Accessible.description: reason

    ReadoutFont {
        id: readingFont
        pointSize: Kirigami.Theme.smallFont.pointSize * empty.sizeFactor
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Math.round(8 * empty.sizeFactor)

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: empty.diameter
            Layout.preferredHeight: empty.diameter

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: empty.faint
                    strokeWidth: 3.5 * empty.sizeFactor
                    capStyle: ShapePath.RoundCap
                    strokeStyle: ShapePath.DashLine
                    // Dash lengths are in stroke widths: a dot every 8.47 units around the ring.
                    dashPattern: [0.29, 2.13]

                    PathAngleArc {
                        centerX: empty.diameter / 2
                        centerY: empty.diameter / 2
                        radiusX: 24.25 * empty.sizeFactor
                        radiusY: 24.25 * empty.sizeFactor
                        startAngle: -90
                        sweepAngle: 360
                    }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(15 * empty.sizeFactor)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1.5 * empty.sizeFactor
                border.color: empty.faint
            }
        }

        // A dial's two lines of readings, the first a dash, so the panel keeps
        // its footprint (see StandaloneDial's readout).
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: Math.round(readingFont.lineHeight + readingFont.plain.ascent)
            Layout.topMargin: -Math.round(readingFont.strong.ascent - readingFont.capHeight)
            verticalAlignment: Text.AlignTop
            text: "–"
            color: Kirigami.Theme.textColor
            font: readingFont.strong.font
            opacity: 0.35
            textFormat: Text.PlainText
        }
    }

    PlasmaCore.ToolTipArea {
        id: toolTip
        anchors.fill: parent
        active: empty.interactive
        mainText: i18nc("@info:tooltip", "Nothing to show")
        subText: empty.reason
        textFormat: Text.PlainText
        location: empty.location
    }
}
