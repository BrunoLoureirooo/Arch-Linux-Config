// Cut-corner panel: top-left and bottom-right corners cut by `cut`, 1px border.
// Drawn like the render's .ch class: the outer polygon is filled with the border
// colour (or the a1 -> a2 45-degree gradient when `hot`), the inner polygon, inset by
// 1px with the same cut corners, is filled with `fill`. (Qt 6.11 ShapePath has no
// stroke gradient, so a stroked single path could not do the hot border.)
import QtQuick
import QtQuick.Shapes
import qs

Item {
    id: root

    property real cut: 10
    property color fill: Theme.bg
    property color stroke: Theme.line
    property bool hot: false
    default property alias content: slot.data

    // Inner cut so the diagonal edge is also 1px thick: the diagonal moves in by
    // sqrt(2) along each axis, the inner box starts 1px in.
    readonly property real innerCut: Math.max(0, cut - (2 - Math.SQRT2))

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.stroke
            fillGradient: root.hot ? hotGradient : null
            startX: root.cut; startY: 0
            PathLine { x: root.width; y: 0 }
            PathLine { x: root.width; y: root.height - root.cut }
            PathLine { x: root.width - root.cut; y: root.height }
            PathLine { x: 0; y: root.height }
            PathLine { x: 0; y: root.cut }
            PathLine { x: root.cut; y: 0 }
        }

        ShapePath {
            strokeWidth: -1
            fillColor: root.fill
            startX: 1 + root.innerCut; startY: 1
            PathLine { x: root.width - 1; y: 1 }
            PathLine { x: root.width - 1; y: root.height - 1 - root.innerCut }
            PathLine { x: root.width - 1 - root.innerCut; y: root.height - 1 }
            PathLine { x: 1; y: root.height - 1 }
            PathLine { x: 1; y: 1 + root.innerCut }
            PathLine { x: 1 + root.innerCut; y: 1 }
        }
    }

    // CSS linear-gradient(45deg, a1, a2): bottom-left a1 to top-right a2.
    LinearGradient {
        id: hotGradient
        x1: 0; y1: root.height
        x2: root.width; y2: 0
        GradientStop { position: 0; color: Theme.a1 }
        GradientStop { position: 1; color: Theme.a2 }
    }

    Item {
        id: slot
        anchors.fill: parent
    }
}
