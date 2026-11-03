// Segmented bar of the rail (render .sg): `segments` hard-edged blocks `gap` px apart, lit
// up to `value` (0-100). Lit cells are `litColor` and step up in opacity towards the
// leading cell (dim tail, bright head); unlit cells are Theme.line. The rig's probes
// read `lit`, `cell` and the cells' colours.
import QtQuick
import qs

Item {
    id: segs

    property real value: 0
    property int segments: 10
    property int gap: 2
    property color litColor: Theme.a1

    // value * segments / 100 (not value / 100 * segments): 85% of 10 is exactly 8.5 -> 9.
    readonly property int lit: Math.round(Math.max(0, Math.min(100, value)) * segments / 100)
    readonly property real cell: (width - gap * (segments - 1)) / segments

    Repeater {
        model: segs.segments

        Rectangle {
            required property int index
            readonly property bool on: index < segs.lit
            x: Math.round(index * (segs.cell + segs.gap))
            width: Math.round(index * (segs.cell + segs.gap) + segs.cell) - x
            height: segs.height
            color: on ? segs.litColor : Theme.line
            opacity: on && segs.lit > 1 ? 0.7 + 0.3 * index / (segs.lit - 1) : 1
        }
    }
}
