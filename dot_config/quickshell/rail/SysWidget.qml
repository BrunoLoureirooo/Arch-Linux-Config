// Rail SYS section (render .row3 .sg .spw .netl): CPU, MEM, GPU, TMP rows as
// `LABEL [10 segments] value` (GPU hidden when Stats has no GPU source or no value;
// TMP is the CPU temperature, bar 30-100 °C, warn from 85 °C, `--` when unknown),
// plus a VRM row (`1.0/4.0G`) while the GPU source is the NVIDIA stream; then the
// network sparkline over Stats.netHistory (one polyline over a faint a1 area, a2 end
// dot, scaled to the window's maximum) and the caption `up <rate>  <iface>  down <rate>`.
// The rows are the rail's thick rows (StatRow at rowPx); the sparkline has a fixed
// height of about two rows, so spare rail height goes to the spacing between sections.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs
import qs.services

ColumnLayout {
    id: root

    property real px: Theme.px
    // Font size of the stat rows (thicker than the rail's base size).
    property real rowPx: Math.round(px * 1.7)
    readonly property bool vram: Stats.gpuSource === "nvidia"
    // Value column, the same for every row so the bars line up: wide enough for the
    // VRM text while that row is shown.
    readonly property real valueWidth: vram ? Math.ceil(vramMetrics.width) : Math.round(rowPx * 2.6)

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
        font.pixelSize: root.rowPx
        text: "0.0/0.0G"
    }

    spacing: Math.round(rowPx * 0.45)

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.15)
        px: root.px
        text: "sys"
    }

    StatRow {
        px: root.rowPx
        valueWidth: root.valueWidth
        label: "CPU"
        value: Stats.cpu
        text: Math.round(Stats.cpu) + "%"
    }

    StatRow {
        px: root.rowPx
        valueWidth: root.valueWidth
        label: "MEM"
        value: Stats.memPct
        text: Stats.memGb.toFixed(1) + "G"
    }

    StatRow {
        visible: Stats.gpuSource !== "none" && Stats.gpu >= 0
        px: root.rowPx
        valueWidth: root.valueWidth
        label: "GPU"
        value: Math.max(0, Stats.gpu)
        text: Math.round(Stats.gpu) + "%"
    }

    StatRow {
        visible: root.vram
        px: root.rowPx
        valueWidth: root.valueWidth
        label: "VRM"
        value: Math.max(0, Stats.vramPct)
        text: root.vramText(Stats.vramUsedMb, Stats.vramTotalMb)
    }

    StatRow {
        readonly property real temp: Stats.cpuTempC
        px: root.rowPx
        valueWidth: root.valueWidth
        label: "TMP"
        known: temp >= 0
        value: known ? (Math.min(100, Math.max(30, temp)) - 30) / 70 * 100 : 0
        warn: temp >= 85
        text: known ? Math.round(temp) + "C" : "--"
    }

    // Sparkline. Points are recomputed only when netHistory changes (every 2 s).
    Item {
        id: spark
        Layout.fillWidth: true
        Layout.topMargin: Math.round(root.px * 0.2)
        // About two stat rows high.
        implicitHeight: Math.round(root.rowPx * 1.33 * 2 + root.spacing)

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
            textFormat: Text.PlainText  // an interface name: not the Caption's StyledText
        }
        Caption {
            anchors.right: parent.right
            text: "down <font color=\"" + Theme.fg + "\">" + Stats.compactRate(Stats.netDown) + "</font>"
        }
    }
}
