// Rail section heading (render .rail .lbl): `// LABEL ━━──────────╴ note`. `//` in a2,
// the label in fg, uppercase and letter-spaced, then a 1px Theme.line rule with a short
// a1 lead-in (as the bar's bottom rule) and a 1px a1 end tick, and an optional dim
// `note` right-aligned at the end (e.g. "2 connected"). Children in this order: `//`,
// label, rule, note (the rig reads the texts in tree order).
import QtQuick
import qs

Item {
    id: root

    property string text
    property string note
    property real px: Theme.px  // the rail's base font size; the label is 1.1 of it

    readonly property real size: Math.round(px * 1.1)
    readonly property real gap: Math.round(size * 0.6)

    implicitHeight: Math.round(size * 1.6)

    Text {
        id: slash
        anchors.verticalCenter: parent.verticalCenter
        text: "//"
        color: Theme.a2
        font.family: Theme.font
        font.pixelSize: root.size
        font.bold: true
    }

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        x: slash.implicitWidth + Math.round(root.gap * 0.6)
        text: root.text.toUpperCase()
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: root.size
        font.weight: Font.DemiBold
        font.letterSpacing: root.size * 0.24
    }

    Item {
        id: rule
        anchors.verticalCenter: parent.verticalCenter
        x: label.x + label.implicitWidth + root.gap
        width: Math.max(0, (noteText.visible ? noteText.x - root.gap : root.width) - x)
        height: 5

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: Theme.line
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width, Math.round(root.size * 2.2))
            height: 1
            color: Theme.a1
        }
        Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: Theme.a1
        }
    }

    Text {
        id: noteText
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        visible: root.note !== ""
        text: root.note
        textFormat: Text.PlainText
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Math.round(root.size * 0.92)
        font.letterSpacing: root.size * 0.06
    }
}
