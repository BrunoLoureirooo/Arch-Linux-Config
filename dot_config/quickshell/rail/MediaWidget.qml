// Rail MEDIA section (render .trk .prog .tm): the first MPRIS player's title (bold)
// and artist (dim) on one line, a 2px progress bar and `m:ss` / `m:ss`. Hidden when
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
    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    readonly property bool hasLength: player !== null && player.lengthSupported && player.length > 0

    // seconds -> m:ss
    function clock(s) {
        const t = Math.max(0, Math.floor(s || 0));
        return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0");
    }

    visible: player !== null
    spacing: 0

    Timer {
        interval: 1000
        repeat: true
        running: root.visible && root.player !== null && root.player.isPlaying && root.player.positionSupported
        onTriggered: root.player.positionChanged()
    }

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.15)
        px: root.px
        text: "media"
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: Math.max(title.implicitHeight, artist.implicitHeight)

        Text {
            id: title
            width: Math.min(implicitWidth, parent.width)
            text: root.player ? (root.player.trackTitle || root.player.identity || "unknown") : ""
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: root.px
            font.weight: Font.Medium
        }

        Text {
            id: artist
            x: title.width + Math.round(root.px * 0.7)
            anchors.baseline: title.baseline
            width: Math.max(0, parent.width - x)
            visible: width > 0 && text !== ""
            text: root.player ? root.player.trackArtist : ""
            elide: Text.ElideRight
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: root.px
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Math.round(root.px * 0.4)
        Layout.bottomMargin: Math.round(root.px * 0.2)
        implicitHeight: 2
        color: Theme.line

        Rectangle {
            height: parent.height
            width: root.hasLength ? Math.round(parent.width * Math.max(0, Math.min(1, root.player.position / root.player.length))) : 0
            color: Theme.a1
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: pos.implicitHeight

        Text {
            id: pos
            text: root.player ? root.clock(root.player.position) : ""
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Math.round(root.px * 0.9)
        }

        Text {
            anchors.right: parent.right
            text: root.hasLength ? root.clock(root.player.length) : "-:--"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Math.round(root.px * 0.9)
        }
    }
}
