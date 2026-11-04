// One rail stat row (render .row3 .sg), used by SYS, DISK, VOLUME and CLAUDE. Two forms:
// - inline (default): `LABEL  [segments]  value` in three columns, `labelWidth` and
//   `valueWidth` wide, the value right-aligned, all `rowHeight` high;
// - hero: the label small at the left and the value large (`px`) at the right on one
//   baseline, the segmented bar under them over the full width.
// Labels are dim, small and letter-spaced (`labelColor`/`labelPx` override, e.g. DISK
// mount points); values bright. Lit segments in `litColor` (a1, the warn colour when
// `warn`), unlit ones Theme.line. `sub` is an optional small dim text right after the
// label, shown only when it fits in the label column (DISK: the filesystem type).
// Children, in this order: label Text, Segments (lit, cell), value Text, sub Text
// (the rig's probes read them).
import QtQuick
import QtQuick.Layouts
import qs
import qs.components

Item {
    id: row

    property real px: Theme.px   // value font size
    property string label
    property real value: 0       // 0-100
    property string text
    property bool warn: value > 75
    property bool known: true
    property bool hero: false
    property int segments: 10
    property color litColor: warn ? Theme.warn : Theme.a1
    property color valueColor: known ? Theme.fg : Theme.dim
    property color labelColor: Theme.dim
    property real labelPx: hero ? Math.round(px * 0.4) : Math.round(px * 0.74)
    property real labelWidth: Math.round(px * 2.4)
    property real valueWidth: Math.round(px * 2.6)
    property int labelElide: Text.ElideRight
    property real labelSpacing: labelPx * 0.12
    property string sub
    property real gap: Math.round(px * 0.6)
    property real rowHeight: Math.round(px * 1.85)
    property real barHeight: hero ? Math.max(6, Math.round(px * 0.28)) : Math.round(px * 0.5)

    Layout.fillWidth: true
    implicitHeight: hero ? valueText.implicitHeight + Math.round(px * 0.12) + barHeight : rowHeight

    Text {
        id: labelText
        // Inline: the label column. Hero: on the value's baseline.
        anchors.verticalCenter: row.hero ? undefined : parent.verticalCenter
        anchors.baseline: row.hero ? valueText.baseline : undefined
        width: Math.min(implicitWidth, row.hero ? row.width - valueText.implicitWidth - row.gap : row.labelWidth)
        text: row.label
        textFormat: Text.PlainText  // DISK rows put a mount point here
        elide: row.labelElide
        color: row.labelColor
        font.family: Theme.font
        font.pixelSize: row.labelPx
        font.letterSpacing: row.labelSpacing
    }

    Segments {
        id: segs
        x: row.hero ? 0 : row.labelWidth + row.gap
        y: row.hero ? row.height - height : Math.round((row.height - height) / 2)
        width: row.hero ? row.width : Math.max(0, row.width - row.labelWidth - row.valueWidth - 2 * row.gap)
        height: row.barHeight
        segments: row.segments
        value: row.value
        litColor: row.litColor
    }

    Text {
        id: valueText
        anchors.right: parent.right
        anchors.verticalCenter: row.hero ? undefined : parent.verticalCenter
        y: row.hero ? -Math.round(row.px * 0.08) : 0
        width: row.hero ? implicitWidth : row.valueWidth
        horizontalAlignment: Text.AlignRight
        text: row.text
        color: row.valueColor
        font.family: Theme.font
        font.pixelSize: row.px
        font.weight: row.hero ? Font.DemiBold : Font.Medium
    }

    Text {
        anchors.baseline: labelText.baseline
        x: labelText.x + labelText.width + Math.round(row.gap * 0.7)
        visible: row.sub !== "" && !labelText.truncated && x + implicitWidth <= (row.hero ? valueText.x - row.gap : row.labelWidth)
        text: row.sub
        textFormat: Text.PlainText
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Math.max(9, Math.round(row.labelPx * 0.72))
        font.letterSpacing: row.labelPx * 0.04
    }
}
