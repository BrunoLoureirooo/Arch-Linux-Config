// Segmented meter: `cells` blocks, lit up to `value` (0-100). Lit cells are a1, or warn
// when value > warnAbove (or, with `invert`, when value <= 20: low is bad, batteries).
// Cells scale with `px` (default Theme.px), the font size of the surrounding text.
import QtQuick
import qs

Item {
    id: root

    property real value: 0
    property int cells: 5
    property real warnAbove: 75
    property bool invert: false
    property real px: Theme.px

    readonly property int lit: Math.round(Math.max(0, Math.min(100, value)) / 100 * cells)
    readonly property bool bad: invert ? value <= 20 : value > warnAbove
    readonly property real cellWidth: Math.round(px * 0.34)
    readonly property real cellHeight: Math.round(px * 0.85)

    implicitWidth: row.implicitWidth
    implicitHeight: cellHeight

    Row {
        id: row
        spacing: 1

        Repeater {
            model: root.cells

            Rectangle {
                required property int index
                width: root.cellWidth
                height: root.cellHeight
                color: index < root.lit ? (root.bad ? Theme.warn : Theme.a1) : Theme.line
            }
        }
    }
}
