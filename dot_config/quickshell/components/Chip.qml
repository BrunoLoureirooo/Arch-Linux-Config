// Bar/rail chip as in the render: `LABEL [meter] value`. The label is dim, the value
// a1; `meter` < 0 hides the meter, an empty `text` hides the value.
import QtQuick
import qs

Row {
    id: root

    property string label
    property string text
    property real meter: -1

    spacing: Math.round(Theme.px * 0.5)

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Math.round(Theme.px * 0.88)
        font.letterSpacing: Theme.px * 0.88 * 0.1
    }

    Meter {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.meter >= 0
        value: Math.max(0, root.meter)
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.text !== ""
        text: root.text
        color: Theme.a1
        font.family: Theme.font
        font.pixelSize: Theme.px
        font.weight: Font.Medium
    }
}
