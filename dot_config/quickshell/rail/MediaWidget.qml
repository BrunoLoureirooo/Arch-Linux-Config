// Rail MEDIA section (render .trk .prog .tm): `// MEDIA ─── playing|paused`, the first
// playing MPRIS player (else the first player): title (bold) and artist (dim) on one
// line, a 3px progress bar (a1 fill, a2 head) and `m:ss` / `m:ss`. Hidden when
// there is no player. Read only: no controls, no seeking. MprisPlayer.position does
// not update by itself; a 1 s timer re-reads it (emits positionChanged) only while
// the player is playing and the section is visible.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs

ColumnLayout {
    id: root

    property real px: Theme.px
    property real subPx: Math.round(px * 1.3)
    readonly property real capPx: Math.round(px * 1.0)
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property real position: player ? (player.position || 0) : 0  // NaN-safe
    readonly property real length: player ? (player.length || 0) : 0
    readonly property bool hasLength: player !== null && player.lengthSupported && length > 0

    // seconds -> m:ss
    function clock(s) {
        const t = Math.max(0, Math.floor(s || 0));
        return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0");
    }

    visible: player !== null
    spacing: Math.round(px * 0.6)

    Timer {
        interval: 1000
        repeat: true
        running: root.visible && root.player !== null && root.player.isPlaying && root.player.positionSupported
        onTriggered: root.player.positionChanged()
    }

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.3)
        px: root.px
        text: "media"
        note: root.player ? (root.player.isPlaying ? "playing" : "paused") : ""
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: Math.max(title.implicitHeight, artist.implicitHeight)

        Text {
            id: title
            width: Math.min(implicitWidth, parent.width)
            text: root.player ? (root.player.trackTitle || root.player.identity || "unknown") : ""
            textFormat: Text.PlainText  // MPRIS metadata: never StyledText (no <img> fetches)
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: root.subPx
            font.weight: Font.DemiBold
        }

        Text {
            id: artist
            x: title.width + Math.round(root.px * 0.7)
            anchors.baseline: title.baseline
            width: Math.max(0, parent.width - x)
            visible: width > 0 && text !== ""
            text: root.player ? root.player.trackArtist : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Math.round(root.px * 1.1)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Math.round(root.px * 0.2)
        implicitHeight: 3
        color: Theme.line

        Rectangle {
            id: done
            height: parent.height
            width: root.hasLength ? Math.round(parent.width * Math.max(0, Math.min(1, root.position / root.length))) : 0
            color: Theme.a1
        }
        // Play head: a 2 px a2 mark, 3 px taller than the bar on each side.
        Rectangle {
            visible: root.hasLength
            x: Math.min(parent.width - width, done.width)
            y: -3
            width: 2
            height: parent.height + 6
            color: Theme.a2
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: pos.implicitHeight

        Text {
            id: pos
            text: root.player ? root.clock(root.position) : ""
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: root.capPx
        }

        Text {
            anchors.right: parent.right
            text: root.hasLength ? root.clock(root.length) : "-:--"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: root.capPx
        }
    }
}
