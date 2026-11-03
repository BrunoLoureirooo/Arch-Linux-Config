// Rail SYS section (render .row3 .sg .spw .netl). Two hero readouts side by side in thin
// cut-corner frames: CPU (busy %) and MEM (used GiB, the used % as a small note), each
// a large value over a 20-cell bar. Under them inline rows `LABEL [10 segments] value`:
// GPU (hidden when Stats has no GPU source or no value), VRM (`1.0/4.0G`, only while the
// GPU source is the NVIDIA stream) and TMP (the CPU temperature, bar 30-100 °C, warn from
// 85 °C, `--` when unknown). Then the network sparkline over Stats.netHistory in a
// framed plot (quarter grid lines, a tick every 6 samples, the window's peak rate at the
// top right; one polyline over a faint a1 area, a2 end dot, scaled to that peak) and
// the caption `▲ <up>  <iface>  ▼ <down>`. The plot takes spare rail height between
// graphMin and graphMax (Rail.qml), so the rail fills without a void.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs
import qs.components
import qs.services

ColumnLayout {
    id: root

    property real px: Theme.px
    property string note
    // Font sizes: inline rows, hero values, captions.
    property real rowPx: Math.round(px * 1.5)
    property real heroPx: Math.round(px * 2.9)
    readonly property real capPx: Math.round(px * 1.0)
    readonly property real graphMin: Math.round(rowPx * 4.4)
    readonly property real graphMax: Math.round(rowPx * 14)
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
        font.weight: Font.Medium
        text: "0.0/0.0G"
    }

    spacing: Math.round(px * 0.6)

    // A hero tile: thin cut-corner frame, equal halves of the row.
    component Tile: Chamfer {
        Layout.fillWidth: true
        Layout.preferredWidth: 1  // equal halves
        implicitHeight: Math.round(root.heroPx * 1.35) + 2 * pad
        readonly property real pad: Math.round(root.px * 0.8)
        cut: Math.round(root.px * 0.7)
        stroke: Theme.line
    }

    // Plot labels.
    component Tiny: Text {
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: Math.max(9, Math.round(root.px * 0.9))
        font.letterSpacing: root.px * 0.1
    }


    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.3)
        px: root.px
        text: "sys"
        note: root.note
    }

    // Hero readouts.
    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.3)
        spacing: Math.round(root.px * 1.0)

        Tile {
            id: cpuTile
            StatRow {
                anchors { fill: parent; margins: cpuTile.pad; leftMargin: cpuTile.pad + 2; rightMargin: cpuTile.pad + 2 }
                hero: true
                segments: 20
                px: root.heroPx
                label: "CPU"
                valueColor: warn ? Theme.warn : Theme.a1
                value: Stats.cpu
                text: Math.round(Stats.cpu) + "%"
            }
        }

        Tile {
            id: memTile
            StatRow {
                anchors { fill: parent; margins: memTile.pad; leftMargin: memTile.pad + 2; rightMargin: memTile.pad + 2 }
                hero: true
                segments: 20
                px: root.heroPx
                label: "MEM"
                valueColor: warn ? Theme.warn : Theme.a1
                sub: Math.round(Stats.memPct) + "%"
                value: Stats.memPct
                text: Stats.memGb.toFixed(1) + "G"
            }
        }
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

    // Framed network plot.
    Chamfer {
        id: plotFrame
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: Math.round(root.px * 0.5)
        Layout.minimumHeight: root.graphMin
        Layout.preferredHeight: root.graphMin
        Layout.maximumHeight: root.graphMax
        cut: Math.round(root.px * 0.7)
        stroke: Theme.line

        Item {
            id: plot
            anchors { fill: parent; margins: 1 }

            // Quarter grid lines and a tick every 6 samples (12 s on the 2 s tick).
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    y: Math.round(plot.height * (index + 1) / 4)
                    width: plot.width
                    height: 1
                    color: Theme.line
                    opacity: 0.7
                }
            }
            Repeater {
                model: Math.max(0, Math.floor((Stats.historyLength - 1) / 6))
                Rectangle {
                    required property int index
                    x: Math.round((index + 1) * 6 * plot.width / (Stats.historyLength - 1))
                    y: plot.height - height
                    width: 1
                    height: Math.round(root.px * 0.5)
                    color: Theme.dim
                    opacity: 0.6
                }
            }

            Tiny {
                x: Math.round(root.px * 0.6)
                y: Math.round(root.px * 0.3)
                text: "NET"
            }
            Tiny {
                anchors.right: parent.right
                anchors.rightMargin: Math.round(root.px * 0.8)
                y: Math.round(root.px * 0.3)
                text: "PEAK " + Stats.compactRate(Math.max(0, ...spark.samples))
            }

            // Sparkline. Points are recomputed only when netHistory or the plot size
            // changes (every 2 s).
            Item {
                id: spark
                anchors { fill: parent; topMargin: Math.round(root.px * 1.6) }

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
                    readonly property real size: Math.max(4, Math.round(root.px * 0.45))
                    width: size
                    height: size
                    x: spark.width - size
                    y: (spark.points.length ? spark.points[spark.points.length - 1].y : 0) - size / 2
                    color: Theme.a2
                }
            }
        }
    }

    component Caption: Text {
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: root.capPx
        textFormat: Text.StyledText
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: up.implicitHeight

        Caption {
            id: up
            anchors.left: parent.left
            anchors.leftMargin: 2
            text: "<font color=\"" + Theme.a1 + "\">▲</font> <font color=\"" + Theme.fg + "\">" + Stats.compactRate(Stats.netUp) + "</font>"
        }
        Caption {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, parent.width - 2 * Math.max(up.implicitWidth, down.implicitWidth) - root.px * 2)
            elide: Text.ElideMiddle
            text: Stats.netConn !== "" ? Stats.netConn : "--"
            textFormat: Text.PlainText  // an interface name: not the Caption's StyledText
            font.letterSpacing: root.capPx * 0.06
        }
        Caption {
            id: down
            anchors.right: parent.right
            anchors.rightMargin: 2
            text: "<font color=\"" + Theme.a2 + "\">▼</font> <font color=\"" + Theme.fg + "\">" + Stats.compactRate(Stats.netDown) + "</font>"
        }
    }
}
