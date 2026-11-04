// Right-hand rail (spec 5.3; render .rail): 22.5% of the screen wide, from below the
// bar to the bottom, with its width reserved so tiled windows stop at its left edge.
// Like the bar it floats Theme.gapOut (= hyprland gaps_out) off the screen edges: that
// gap below the bar, right and bottom; the reserved zone is the width plus that gap, so
// gaps_out leaves the same gap between a tiled window and the rail. A
// hot Chamfer (a1 -> a2 border, cut corners top-left and bottom-right) holds the
// widgets in one column over the full height. shell.qml creates it only for
// Screens.railScreen (the built-in eDP panel, else the main screen) and only while
// Screens.railShown, so a hidden rail leaves no surface and no reserved zone.
//
// Exclusive zones and layer order: the compositor arranges layer surfaces one after
// another, each inside the area the earlier ones left. A rail with its own zone on the
// top layer therefore lands 26 px lower when it is arranged after the bar, and cuts
// the bar short (bar 0..1488, rail from y 0) when it is arranged first (both seen in
// the rig). So the visible rail ignores zones (always exactly below the bar, never
// shortens it), and a separate 1 px transparent, input-less surface on the overlay
// layer, which is arranged after the top layer, reserves the width.
// Deploy note: that overlay surface sits above fullscreen windows on the rail's monitor.
// It is 1 px, transparent and takes no input, but if render:direct_scanout is enabled
// in Hyprland, any overlay-layer surface may keep a fullscreen window on that
// monitor from being scanned out directly (the other monitor is unaffected).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.components

PanelWindow {
    id: rail

    // The render's rail font is 0.82em of the 12px screen font (the bar's is 0.84em).
    readonly property real px: Math.round(Theme.px * 0.82)
    readonly property int barHeight: 26
    // Spacing scale: inner padding (x, y) and the gap between sections.
    readonly property int padX: Math.round(Theme.px * 1.2)
    readonly property int padY: Math.round(Theme.px * 1.0)
    readonly property int sectionGap: Math.round(Theme.px * 1.5)

    anchors { top: true; bottom: true; right: true }
    margins { top: Theme.gapOut + barHeight + Theme.gapOut; right: Theme.gapOut; bottom: Theme.gapOut }
    implicitWidth: Math.round((screen ? screen.width : 1920) * 0.225)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "rice-rail"

    // Reserves the rail's width for tiled windows (see the header).
    PanelWindow {
        screen: rail.screen
        visible: rail.visible
        anchors { top: true; bottom: true; right: true }
        implicitWidth: 1
        exclusiveZone: rail.implicitWidth + Theme.gapOut
        color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "rice-rail-zone"
    }

    Chamfer {
        anchors.fill: parent
        hot: true
        cut: 10

        // Inner padding: content 1.2em (screen font) in from the left/right border and
        // 1em from the top/bottom, clear of the cut corners.
        Item {
            anchors.fill: parent
            anchors.topMargin: rail.padY
            anchors.bottomMargin: rail.padY
            anchors.leftMargin: rail.padX
            anchors.rightMargin: rail.padX
            clip: true

            // Full height, packed from the top with one section gap between sections:
            // SYS, DISK, VOLUME, MEDIA (only while a player exists), BLUETOOTH, and
            // CLAUDE on the bottom edge. Spare height goes first to the SYS network
            // plot (up to its maximum, see SysWidget), the rest to one gap above CLAUDE.
            ColumnLayout {
                id: column
                anchors.fill: parent
                spacing: rail.sectionGap

                SysWidget {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    px: rail.px
                    note: rail.screen ? rail.screen.name : ""
                }
                DiskWidget { Layout.fillWidth: true; px: rail.px }
                VolumeWidget { Layout.fillWidth: true; px: rail.px }
                MediaWidget { Layout.fillWidth: true; px: rail.px }
                BluetoothWidget { Layout.fillWidth: true; px: rail.px }
                // CLAUDE sits on the bottom edge of the spare height.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: claude.implicitHeight
                    implicitHeight: claude.implicitHeight

                    ClaudeWidget {
                        id: claude
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        px: rail.px
                    }
                }
            }
        }
    }
}
