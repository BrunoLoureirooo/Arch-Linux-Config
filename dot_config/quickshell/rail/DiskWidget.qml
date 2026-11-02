// Rail DISK section: `// DISK ───`, then one StatRow per filesystem in Stats.disks ("/"
// first, at most three): `<mountpoint> [10 segments] used/total NN%`, warn colour from
// 90%. The data refreshes about once a minute on the shared Stats tick (one df per
// refresh, see Stats.qml); a dim `no data` line until the first df has answered.
import QtQuick
import QtQuick.Layouts
import qs
import qs.services

ColumnLayout {
    id: root

    property real px: Theme.px
    property real rowPx: Math.round(px * 1.7)
    readonly property var mounts: Stats.disks

    spacing: Math.round(rowPx * 0.45)

    // Widest value text, so the bars line up.
    TextMetrics {
        id: valueMetrics
        font.family: Theme.font
        font.pixelSize: root.rowPx
        text: "000/000G 100%"
    }

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.15)
        px: root.px
        text: "disk"
    }

    Text {
        visible: root.mounts.length === 0
        text: "no data"
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: root.px
    }

    Repeater {
        model: root.mounts

        StatRow {
            required property var modelData
            px: root.rowPx
            labelWidth: Math.round(root.rowPx * 5)
            labelElide: Text.ElideLeft  // the last path part says most: `…/big data`
            valueWidth: Math.ceil(valueMetrics.width)
            label: modelData.mount
            value: modelData.pct
            warn: modelData.pct >= 90
            text: Stats.diskText(modelData.used, modelData.size) + " " + String(modelData.pct).padStart(3, " ") + "%"
        }
    }
}
