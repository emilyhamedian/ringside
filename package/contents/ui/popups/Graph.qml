pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "../code/history.js" as History

// A history graph: a faint grid, a filled area under the main series and an
// optional dashed second series (upload under download).
Item {
    id: graph

    // Oldest first; see Monitor.sample().
    property var values: []
    property var secondValues: []
    property bool second: false
    property int length: 60
    // The top of the scale, in the series' own units.
    property real maximum: 100
    property color color: Kirigami.Theme.textColor
    property real fillOpacity: 0.15

    readonly property var mainPoints: History.points(values, length, width, height, maximum)
        .map(p => Qt.point(p.x, p.y))
    readonly property var secondPoints: second ? History.points(secondValues, length, width, height, maximum)
        .map(p => Qt.point(p.x, p.y)) : []

    implicitHeight: Kirigami.Units.gridUnit * 2.7
    clip: true

    Repeater {
        model: 5
        delegate: Rectangle {
            required property int index
            x: Math.round(graph.width * (index + 1) / 6)
            width: 1
            height: graph.height
            color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
        }
    }

    Repeater {
        id: rules
        // Two rules on a full-height graph, one on the small ones.
        model: graph.height >= Kirigami.Units.gridUnit * 2.2 ? 2 : 1
        delegate: Rectangle {
            required property int index
            y: Math.round(graph.height * (index + 1) / (rules.count + 1))
            width: graph.width
            height: 1
            color: Qt.alpha(Kirigami.Theme.textColor, 0.07)
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: graph.mainPoints.length > 1

        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.alpha(graph.color, graph.fillOpacity * graph.color.a)
            PathPolyline {
                path: graph.mainPoints.length > 1
                      ? [Qt.point(graph.mainPoints[0].x, graph.height)].concat(graph.mainPoints,
                            [Qt.point(graph.mainPoints[graph.mainPoints.length - 1].x, graph.height)])
                      : []
            }
        }

        ShapePath {
            strokeColor: graph.color
            strokeWidth: 1.5
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: graph.mainPoints }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: graph.second && graph.secondPoints.length > 1

        ShapePath {
            strokeColor: Qt.alpha(graph.color, 0.55 * graph.color.a)
            strokeWidth: 1.5
            strokeStyle: ShapePath.DashLine
            dashPattern: [2, 1.33]
            fillColor: "transparent"
            PathPolyline { path: graph.secondPoints }
        }
    }
}
