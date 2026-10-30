// Bar/rail chip as in the render: `LABEL [meter] value`. The label is dim, the value
// a1; `meter` < 0 hides the meter, an empty `text` hides the value. `invert` and
// `warnAbove` pass through to the Meter; `px` is the value's font size (the bar uses
// a smaller one), the label and meter scale with it.
import QtQuick
import qs

Row {
    id: root

    property string label
    property string text
    property real meter: -1
    property bool invert: false
    property real warnAbove: 75
    property real px: Theme.px

    spacing: Math.round(px * 0.5)

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Math.round(root.px * 0.88)
        font.letterSpacing: root.px * 0.88 * 0.1
    }

    Meter {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.meter >= 0
        value: Math.max(0, root.meter)
        invert: root.invert
        warnAbove: root.warnAbove
        px: root.px
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.text !== ""
        text: root.text
        textFormat: Text.PlainText  // may carry an interface name
        color: Theme.a1
        font.family: Theme.font
        font.pixelSize: root.px
        font.weight: Font.Medium
    }
}
