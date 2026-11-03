// Rail DISK section: `// DISK ─── <n> mounts`, then one StatRow per filesystem in
// Stats.disks ("/" first, at most three): the mount point (df's `Mounted on` column) in
// full in the label column, ellipsized in the middle when it is too long, the filesystem
// type small and dim after it when it fits, then [10 segments] and `used/total NN%`,
// warn colour from 90%. The data refreshes about once a minute on the shared Stats tick
// (one df per refresh, see Stats.qml); a dim `no data` line until the first df has
// answered.
import QtQuick
import QtQuick.Layouts
import qs
import qs.services

ColumnLayout {
    id: root

    property real px: Theme.px
    property real rowPx: Math.round(px * 1.5)
    readonly property var mounts: Stats.disks

    spacing: Math.round(px * 0.6)

    // Widest value text, so the bars line up.
    TextMetrics {
        id: valueMetrics
        font.family: Theme.font
        font.pixelSize: root.rowPx
        font.weight: Font.Medium
        text: "000/000G 100%"
    }

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.3)
        px: root.px
        text: "disk"
        note: root.mounts.length > 0 ? root.mounts.length + (root.mounts.length === 1 ? " mount" : " mounts") : ""
    }

    EmptyNote {
        visible: root.mounts.length === 0
        px: root.px
        text: "no data"
    }

    Repeater {
        model: root.mounts

        StatRow {
            required property var modelData
            px: root.rowPx
            // 30% of the row: `/mnt/big data` (or `/home` and its type) fits at 1080p.
            labelWidth: Math.round(width * 0.3)
            labelPx: Math.round(root.px * 1.3)
            labelColor: Theme.fg
            labelSpacing: labelPx * 0.02
            labelElide: Text.ElideMiddle  // `/run/media/…/backup`, never a cut-off start
            valueWidth: Math.ceil(valueMetrics.width)
            label: modelData.mount
            sub: modelData.type || ""
            value: modelData.pct
            warn: modelData.pct >= 90
            text: Stats.diskText(modelData.used, modelData.size) + " " + String(modelData.pct).padStart(3, " ") + "%"
        }
    }
}
