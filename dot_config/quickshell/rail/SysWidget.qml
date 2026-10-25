// Rail SYS section (render .row3 .sg .spw .netl): CPU, MEM, GPU rows as
// `LABEL [10 segments] value` (GPU hidden when Stats has no GPU source or no value),
// plus a VRM row (`1.0/4.0G`) while the GPU source is the NVIDIA stream; then the
// network sparkline over Stats.netHistory (one polyline over a faint a1 area, a2 end
// dot, scaled to the window's maximum) and the caption `up <rate>  <iface>  down <rate>`.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs
import qs.services

ColumnLayout {
    id: root

    property real px: Theme.px
    readonly property bool vram: Stats.gpuSource === "nvidia"
    // Value column, the same for every row so the bars line up: wide enough for the
    // VRM text while that row is shown.
    readonly property real valueWidth: vram ? Math.ceil(vramMetrics.width) : Math.round(px * 2.6)

    // MiB -> "1.0/4.0G" (one decimal below 10 GiB, whole GiB above), "--" when unknown.
    function vramText(used, total) {
        if (!(used >= 0) || !(total > 0))
            return "--";
        const g = v => v / 1024 < 10 ? (v / 1024).toFixed(1) : String(Math.round(v / 1024));
        return g(used) + "/" + g(total) + "G";
    }

    TextMetrics {
        id: vramMetrics
        font.family: Theme.font
        font.pixelSize: root.px
        text: "0.0/0.0G"
    }

    spacing: Math.round(px * 0.15)

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.15)
        px: root.px
        text: "sys"
    }

    component StatRow: RowLayout {
        id: row
        property string label
        property real value: 0   // 0-100
        property string text
        Layout.fillWidth: true
        spacing: Math.round(root.px * 0.5)

        Text {
            Layout.preferredWidth: Math.round(root.px * 2.4)
            text: row.label
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: root.px
            font.letterSpacing: root.px * 0.08
        }

        // 10 segments, 1px apart; lit a1, warn above 75, unlit line.
        Item {
            id: segs
            Layout.fillWidth: true
            implicitHeight: Math.round(root.px * 0.6)
            readonly property int lit: Math.round(Math.max(0, Math.min(100, row.value)) / 10)
            readonly property real cell: (width - 9) / 10

            Repeater {
                model: 10

                Rectangle {
                    required property int index
                    x: Math.round(index * (segs.cell + 1))
                    width: Math.round((index + 1) * (segs.cell + 1) - 1) - x
                    height: segs.height
                    color: index < segs.lit ? (row.value > 75 ? Theme.warn : Theme.a1) : Theme.line
                }
            }
        }

        Text {
            Layout.preferredWidth: root.valueWidth
            horizontalAlignment: Text.AlignRight
            text: row.text
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: root.px
        }
    }

    StatRow {
        label: "CPU"
        value: Stats.cpu
        text: Math.round(Stats.cpu) + "%"
    }

    StatRow {
        label: "MEM"
        value: Stats.memPct
        text: Stats.memGb.toFixed(1) + "G"
    }

    StatRow {
        visible: Stats.gpuSource !== "none" && Stats.gpu >= 0
        label: "GPU"
        value: Math.max(0, Stats.gpu)
        text: Math.round(Stats.gpu) + "%"
    }

    StatRow {
        visible: root.vram
        label: "VRM"
        value: Math.max(0, Stats.vramPct)
        text: root.vramText(Stats.vramUsedMb, Stats.vramTotalMb)
    }

    // Sparkline. Points are recomputed only when netHistory changes (every 2 s).
    Item {
        id: spark
        Layout.fillWidth: true
        Layout.topMargin: Math.round(root.px * 0.2)
        implicitHeight: Math.round(root.px * 1.5)

        readonly property var samples: Stats.netHistory
        readonly property real peak: Math.max(1, ...samples)
        readonly property var points: {
            const n = samples.length;
            if (n < 2 || width <= 0)
                return [];
            const h = height;
            return samples.map((v, i) => Qt.point(i * width / (n - 1), h - 1 - v / peak * (h - 3)));
        }

        Shape {
            anchors.fill: parent
            visible: spark.points.length >= 2
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: Qt.alpha(Theme.a1, 0.14)
                PathPolyline {
                    path: spark.points.length >= 2
                        ? [Qt.point(0, spark.height)].concat(spark.points, [Qt.point(spark.width, spark.height)])
                        : []
                }
            }

            ShapePath {
                strokeColor: Theme.a1
                strokeWidth: 1.2
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline { path: spark.points }
            }
        }

        Rectangle {
            visible: spark.points.length >= 2
            readonly property real size: Math.max(3, Math.round(root.px * 0.35))
            width: size
            height: size
            x: spark.width - size + 1
            y: (spark.points.length ? spark.points[spark.points.length - 1].y : 0) - size / 2
            color: Theme.a2
        }
    }

    component Caption: Text {
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Math.round(root.px * 0.9)
        textFormat: Text.StyledText
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: up.implicitHeight

        Caption {
            id: up
            anchors.left: parent.left
            text: "up <font color=\"" + Theme.fg + "\">" + Stats.compactRate(Stats.netUp) + "</font>"
        }
        Caption {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Stats.netConn !== "" ? Stats.netConn : "--"
        }
        Caption {
            anchors.right: parent.right
            text: "down <font color=\"" + Theme.fg + "\">" + Stats.compactRate(Stats.netDown) + "</font>"
        }
    }
}
