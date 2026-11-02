// Empty-workspace HUD (render .empty .hud .big .tag .keys), one per screen: a hot
// Chamfer centred in the screen's free area with the big HH:mm in a1, the tag
// `<OUTPUT> · WORKSPACE <slot> · EMPTY` and the real key hints (binds.lua: Ctrl+1-5,
// Ctrl+Alt+W, Super+Space). It exists only while this screen's active workspace has
// no windows (LazyLoader), so nothing renders when windows are open.
// The window sits on the bottom layer (above the background-layer wallpaper, below
// every normal window), has no anchors (the compositor centres it in the area the bar
// and rail leave), takes no input (empty mask: clicks fall through) and never takes
// keyboard focus. The time is the shared Clock service.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.components
import qs.services

Scope {
    id: root

    required property var screen  // ShellScreen

    readonly property var monitor: screen ? Hyprland.monitors.values.find(m => m.name === screen.name) ?? null : null
    readonly property var workspace: monitor ? monitor.activeWorkspace : null
    readonly property bool empty: workspace !== null && workspace.toplevels.values.length === 0
    // Pool slot 1-5 (lib/pools.lua: id = pool * 10 + slot); a named workspace shows its name.
    readonly property string slot: workspace ? (workspace.id > 0 ? String(((workspace.id - 1) % 10) + 1) : workspace.name) : ""
    readonly property real px: Theme.px

    // Read-only handle (the rig's test config inspects it; production does not use it).
    readonly property LazyLoader windowLoader: loader

    LazyLoader {
        id: loader
        active: root.empty

        PanelWindow {
            id: win

            screen: root.screen
            implicitWidth: hud.width
            implicitHeight: hud.height
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "rice-hud"

            Chamfer {
                id: hud
                width: Math.ceil(Math.max(big.implicitWidth, tag.implicitWidth, keys.implicitWidth) + root.px * 2.2 * 2)
                height: Math.ceil(col.implicitHeight + root.px * (1 + 1.1))
                hot: true
                cut: root.px
                fill: Qt.alpha(Theme.bg, 0.94)

                Column {
                    id: col
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(root.px)
                    spacing: Math.round(root.px * 0.35)

                    // The digits in a box of their cap height plus 0.1em above and below
                    // (the render's line-height .8): no empty ascent/descent bands.
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: big.implicitWidth
                        implicitHeight: Math.round(digitMetrics.tightBoundingRect.height + big.font.pixelSize * 0.2)

                        TextMetrics {
                            id: digitMetrics
                            font: big.font
                            text: "0123456789"
                        }

                        Text {
                            id: big
                            y: parent.height - Math.round(font.pixelSize * 0.1) - baselineOffset
                            text: Qt.formatDateTime(Clock.date, "HH:mm")
                            color: Theme.a1
                            font.family: Theme.font
                            font.pixelSize: Math.round(root.px * 7.2)
                            font.bold: true
                        }
                    }

                    Text {
                        id: tag
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (root.screen ? root.screen.name : "") + " · workspace " + root.slot + " · empty"
                        textFormat: Text.PlainText
                        font.capitalization: Font.AllUppercase
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Math.round(root.px * 0.9)
                        font.letterSpacing: root.px * 0.9 * 0.14
                    }

                    Row {
                        id: keys
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Math.round(root.px * 0.85 * 0.5)

                        component Key: Rectangle {
                            property alias text: label.text
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: label.implicitWidth + Math.round(root.px * 0.85 * 0.7)
                            implicitHeight: label.implicitHeight
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.line

                            Text {
                                id: label
                                anchors.centerIn: parent
                                color: Theme.a1
                                font.family: Theme.font
                                font.pixelSize: Math.round(root.px * 0.85)
                                font.weight: Font.Medium
                            }
                        }

                        component Hint: Text {
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Math.round(root.px * 0.85)
                        }

                        Key { text: "Ctrl" }
                        Key { text: "1" }
                        Hint { text: "–" }
                        Key { text: "5" }
                        Hint { text: "workspace " }
                        Key { text: "Ctrl" }
                        Key { text: "Alt" }
                        Key { text: "W" }
                        Hint { text: "wallpapers " }
                        Key { text: "Super" }
                        Key { text: "Space" }
                        Hint { text: "launcher" }
                    }
                }
            }
        }
    }
}
