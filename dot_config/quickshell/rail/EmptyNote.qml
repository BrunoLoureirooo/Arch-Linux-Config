// A rail section's empty state (`no data`, `no streams`, `no devices connected`...):
// a small hollow dim square and the dim text, one rail row high so an empty section
// keeps the rhythm of a filled one.
import QtQuick
import QtQuick.Layouts
import qs

Item {
    id: root

    property real px: Theme.px  // the rail's base font size
    property alias text: label.text

    Layout.fillWidth: true
    implicitHeight: Math.round(Math.round(px * 1.5) * 1.85)  // = an inline StatRow at the rail's row size

    Rectangle {
        id: mark
        anchors.verticalCenter: parent.verticalCenter
        x: 1
        width: Math.round(root.px * 0.55)
        height: width
        color: "transparent"
        border.width: 1
        border.color: Theme.dim
    }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        x: mark.x + mark.width + Math.round(root.px * 0.8)
        width: parent.width - x
        elide: Text.ElideRight
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Math.round(root.px * 1.1)
        font.letterSpacing: root.px * 0.06
    }
}
