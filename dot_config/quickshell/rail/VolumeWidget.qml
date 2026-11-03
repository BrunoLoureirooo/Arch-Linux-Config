// Rail VOLUME section, from Quickshell.Services.Pipewire (the default sink, as the bar's
// VOL chip): `// VOLUME ───`, the output device's friendly name (description, else
// nickname, else node name; elided) on its own line, the master `OUT ... NN%` readout
// (StatRow hero: large value over a tall 10-cell bar; dim bar and `MUTED` in the warn
// colour when muted), then up to three application playback streams (nodes that are
// streams and sinks, i.e. Stream/Output/Audio), lowest id first, one rail row each:
// `<application.name>  [5 cells] NN%` (`muted` when muted). A dim `no output` line
// without a default sink, a dim `no streams` line without streams.
// READ ONLY: no volume or mute is ever written. Device and application names are
// untrusted: plain text only.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs
import qs.components

ColumnLayout {
    id: root

    property real px: Theme.px
    property real rowPx: Math.round(px * 1.5)
    // Font size of the device and stream names, the master value, the row height.
    property real subPx: Math.round(px * 1.3)
    property real heroPx: Math.round(px * 2.2)
    readonly property real rowHeight: Math.round(rowPx * 1.85)
    readonly property int maxStreams: 3

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool hasSink: sink !== null && sink.ready && sink.audio !== null
    readonly property string deviceName: sink ? (sink.description || sink.nickname || sink.name || "") : ""
    readonly property var allStreams: Pipewire.nodes.values.filter(n => n && n.isStream && n.isSink)
        .sort((a, b) => a.id - b.id)
    readonly property var streams: allStreams.slice(0, maxStreams)

    function pct(audio) {
        return audio ? Math.max(0, Math.round(audio.volume * 100)) : 0;
    }

    spacing: Math.round(px * 0.6)

    // Volume and mute are only valid on bound nodes.
    PwObjectTracker {
        objects: [root.sink].concat(root.streams)
    }

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.3)
        px: root.px
        text: "volume"
        note: root.allStreams.length > root.maxStreams ? root.allStreams.length + " streams" : ""
    }

    EmptyNote {
        visible: !root.hasSink
        px: root.px
        text: "no output"
    }

    Text {
        visible: root.hasSink
        Layout.fillWidth: true
        text: root.deviceName
        textFormat: Text.PlainText  // a device name: never StyledText
        elide: Text.ElideRight
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: root.subPx
        font.letterSpacing: root.subPx * 0.02
    }

    StatRow {
        id: out
        readonly property bool muted: root.hasSink && root.sink.audio.muted
        visible: root.hasSink
        Layout.topMargin: Math.round(root.px * 0.2)
        Layout.bottomMargin: Math.round(root.px * 0.4)
        hero: true
        px: root.heroPx
        labelPx: Math.round(root.px * 1.1)
        barHeight: Math.round(root.px * 0.9)
        label: "OUT"
        value: root.hasSink ? root.pct(root.sink.audio) : 0
        warn: false
        litColor: muted ? Theme.dim : Theme.a1
        valueColor: muted ? Theme.warn : Theme.fg
        text: muted ? "MUTED" : value + "%"
    }

    EmptyNote {
        visible: root.streams.length === 0
        px: root.px
        text: "no streams"
    }

    Repeater {
        model: root.streams

        RowLayout {
            id: stream
            required property var modelData
            readonly property var audio: modelData?.audio ?? null
            readonly property bool muted: audio !== null && audio.muted
            readonly property int pct: root.pct(audio)

            Layout.fillWidth: true
            Layout.preferredHeight: root.rowHeight
            spacing: Math.round(root.px * 0.8)

            // Stream marker: a thin a1 tick (dim when muted).
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 2
                implicitHeight: Math.round(root.subPx * 0.9)
                color: stream.muted ? Theme.dim : Theme.a1
            }

            Text {
                Layout.fillWidth: true
                text: stream.modelData?.properties?.["application.name"] || stream.modelData?.description || stream.modelData?.name || ""
                textFormat: Text.PlainText  // an application name: never StyledText
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: root.subPx
            }

            Meter {
                Layout.alignment: Qt.AlignVCenter
                px: root.subPx
                cells: 5
                // The rail's segment look: bar-high cells, 2 px apart.
                cellWidth: Math.round(root.px * 1.0)
                cellHeight: Math.round(root.rowPx * 0.5)
                gap: 2
                warnAbove: 100
                value: stream.muted ? 0 : stream.pct
            }

            Text {
                Layout.preferredWidth: Math.round(root.rowPx * 3)
                horizontalAlignment: Text.AlignRight
                text: stream.audio === null ? "--" : stream.muted ? "muted" : stream.pct + "%"
                color: stream.muted || stream.audio === null ? Theme.dim : Theme.fg
                font.family: Theme.font
                font.pixelSize: root.rowPx
                font.weight: Font.Medium
            }
        }
    }
}
