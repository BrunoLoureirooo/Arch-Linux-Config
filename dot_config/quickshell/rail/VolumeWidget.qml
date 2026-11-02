// Rail VOLUME section, from Quickshell.Services.Pipewire (the default sink, as the bar's
// VOL chip): `// VOLUME ───`, the output device's friendly name (description, else
// nickname, else node name; elided), an `OUT [10 segments] NN%` row (dim bar and
// `MUTED` in the warn colour when muted), then up to three application playback
// streams (nodes that are streams and sinks, i.e. Stream/Output/Audio), lowest id
// first: `<application.name>  [5 cells] NN%` (`muted` when muted). A dim `no output`
// line without a default sink, a dim `no streams` line without streams.
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
    property real rowPx: Math.round(px * 1.7)
    // Font size of the stream rows.
    property real subPx: Math.round(px * 1.3)
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

    spacing: Math.round(rowPx * 0.3)

    // Volume and mute are only valid on bound nodes.
    PwObjectTracker {
        objects: [root.sink].concat(root.streams)
    }

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.15)
        px: root.px
        text: "volume"
        note: root.allStreams.length > root.maxStreams ? root.allStreams.length + " streams" : ""
    }

    Text {
        visible: !root.hasSink
        text: "no output"
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: root.px
    }

    Text {
        visible: root.hasSink
        Layout.fillWidth: true
        text: root.deviceName
        textFormat: Text.PlainText  // a device name: never StyledText
        elide: Text.ElideRight
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: root.rowPx
    }

    StatRow {
        id: out
        readonly property bool muted: root.hasSink && root.sink.audio.muted
        visible: root.hasSink
        px: root.rowPx
        label: "OUT"
        value: root.hasSink ? root.pct(root.sink.audio) : 0
        warn: false
        litColor: muted ? Theme.dim : Theme.a1
        valueColor: muted ? Theme.warn : Theme.fg
        valueWidth: Math.round(root.rowPx * 3.4)
        text: muted ? "MUTED" : value + "%"
    }

    Text {
        visible: root.streams.length === 0
        text: "no streams"
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: root.px
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
            spacing: Math.round(root.px * 0.55)

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
                warnAbove: 100
                value: stream.muted ? 0 : stream.pct
            }

            Text {
                Layout.preferredWidth: Math.round(root.subPx * 3.4)
                horizontalAlignment: Text.AlignRight
                text: stream.audio === null ? "--" : stream.muted ? "muted" : stream.pct + "%"
                color: stream.muted || stream.audio === null ? Theme.dim : Theme.fg
                font.family: Theme.font
                font.pixelSize: root.subPx
            }
        }
    }
}
