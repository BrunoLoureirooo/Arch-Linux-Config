// One rail stat row (render .row3 .sg): `LABEL [10 segments] value`, used by the SYS,
// DISK and VOLUME sections. Segments are 1px apart; lit ones in `litColor` (a1, warn
// colour when `warn`), unlit ones Theme.line. `px` is the row's font size; the bar is
// 0.75 of it high. Children, in this order: label Text, segment Item (lit, cell), value
// Text (the rig's probes read them).
import QtQuick
import QtQuick.Layouts
import qs

RowLayout {
    id: row

    property real px: Theme.px
    property string label
    property real value: 0   // 0-100
    property string text
    property bool warn: value > 75
    property bool known: true
    property color litColor: warn ? Theme.warn : Theme.a1
    property color valueColor: known ? Theme.fg : Theme.dim
    property real labelWidth: Math.round(px * 2.4)
    property real valueWidth: Math.round(px * 2.6)
    property int labelElide: Text.ElideRight

    Layout.fillWidth: true
    spacing: Math.round(px * 0.5)

    Text {
        Layout.preferredWidth: row.labelWidth
        text: row.label
        textFormat: Text.PlainText  // DISK rows put a mount point here
        elide: row.labelElide
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: row.px
        font.letterSpacing: row.px * 0.08
    }

    Item {
        id: segs
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: Math.round(row.px * 0.75)
        readonly property int lit: Math.round(Math.max(0, Math.min(100, row.value)) / 10)
        readonly property real cell: (width - 9) / 10

        Repeater {
            model: 10

            Rectangle {
                required property int index
                x: Math.round(index * (segs.cell + 1))
                width: Math.round((index + 1) * (segs.cell + 1) - 1) - x
                height: segs.height
                color: index < segs.lit ? row.litColor : Theme.line
            }
        }
    }

    Text {
        Layout.preferredWidth: row.valueWidth
        horizontalAlignment: Text.AlignRight
        text: row.text
        color: row.valueColor
        font.family: Theme.font
        font.pixelSize: row.px
    }
}
