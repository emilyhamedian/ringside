pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// A progress ring filling clockwise from twelve o'clock, with an optional
// thinner, dimmer ring inside it for a second reading: the integrated GPU
// under the discrete one. NaN draws the track alone.
// Assistive technology sees a progress bar from 0 to 100 with the outer
// reading as its value; the caller gives it a name.
Item {
    id: gauge

    property real value: NaN
    property real innerValue: NaN
    property bool inner: false
    property color color: Kirigami.Theme.textColor
    property real strokeWidth: Math.max(2, Math.round(width / 10))
    // Shown in the middle of a single ring large enough to read it.
    property string text: ""
    property real textScale: 0.33

    readonly property real innerStrokeWidth: Math.max(1.5, Math.round(strokeWidth * 2 / 3 * 2) / 2)
    readonly property real innerRadius: outer.radius - strokeWidth / 2 - innerStrokeWidth / 2
                                        - Math.max(1, strokeWidth / 2)

    // Qt reports these as the progress bar's range.
    readonly property real from: 0
    readonly property real to: 100

    implicitWidth: 30
    implicitHeight: implicitWidth

    Accessible.role: Accessible.ProgressBar
    Accessible.description: Number.isFinite(value) ? i18nc("@info:status a percentage", "%1%", Math.round(value))
                                                   : i18nc("@info:status no reading", "unavailable")

    component Arc: Shape {
        id: arc

        required property real radius
        required property real stroke
        required property real percent
        required property color tone
        required property real trackOpacity

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.alpha(arc.tone, arc.trackOpacity * arc.tone.a)
            strokeWidth: arc.stroke

            PathAngleArc {
                centerX: gauge.width / 2
                centerY: gauge.height / 2
                radiusX: arc.radius
                radiusY: arc.radius
                startAngle: -90
                sweepAngle: 360
            }
        }

        ShapePath {
            fillColor: "transparent"
            // A zero-length arc with round caps would still draw a dot.
            strokeColor: sweep.sweepAngle >= 1 ? arc.tone : "transparent"
            strokeWidth: arc.stroke
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                id: sweep
                centerX: gauge.width / 2
                centerY: gauge.height / 2
                radiusX: arc.radius
                radiusY: arc.radius
                startAngle: -90
                sweepAngle: Number.isFinite(arc.percent) ? 3.6 * Math.max(0, Math.min(100, arc.percent)) : 0

                Behavior on sweepAngle {
                    NumberAnimation {
                        duration: Kirigami.Units.longDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    Arc {
        id: outer
        radius: (Math.min(gauge.width, gauge.height) - gauge.strokeWidth) / 2 - 0.5
        stroke: gauge.strokeWidth
        percent: gauge.value
        tone: gauge.color
        trackOpacity: 0.16
    }

    Arc {
        visible: gauge.inner
        radius: gauge.innerRadius
        stroke: gauge.innerStrokeWidth
        percent: gauge.innerValue
        tone: Qt.alpha(gauge.color, 0.55)
        trackOpacity: 0.22
    }

    Text {
        anchors.centerIn: parent
        visible: gauge.text !== "" && !gauge.inner && gauge.width >= 24
        text: gauge.text
        color: gauge.color
        font.family: Kirigami.Theme.fixedWidthFont.family
        font.pixelSize: Math.round(gauge.width * gauge.textScale)
        textFormat: Text.PlainText
        // The gauge's own description reads it out.
        Accessible.ignored: true
    }
}
