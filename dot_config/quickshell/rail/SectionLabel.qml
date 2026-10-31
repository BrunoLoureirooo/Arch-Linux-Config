// Rail section heading as in the render (.rail .lbl): `// LABEL ─────── note`.
// `//` in a2, the label dim, uppercase and letter-spaced, a 1px line rule filling the
// rest, and an optional dim `note` at the right end (e.g. "2 connected").
import QtQuick
import QtQuick.Layouts
import qs

RowLayout {
    id: root

    property string text
    property string note
    property real px: Theme.px  // the rail's font size; the label is 0.82 of it

    readonly property real size: Math.round(px * 0.82)

    spacing: Math.round(size * 0.6)

    Text {
        text: "//"
        color: Theme.a2
        font.family: Theme.font
        font.pixelSize: root.size
    }

    Text {
        text: root.text.toUpperCase()
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: root.size
        font.letterSpacing: root.size * 0.16
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: 1
        color: Theme.line
    }

    Text {
        visible: root.note !== ""
        text: root.note
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: root.size
        font.letterSpacing: root.size * 0.04
    }
}
