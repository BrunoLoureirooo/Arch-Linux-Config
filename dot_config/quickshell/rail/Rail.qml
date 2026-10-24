// Right-hand rail on the main screen (spec 5.3; render .rail): 22.5% of the screen
// wide, from below the bar to the bottom, with its width reserved so tiled windows
// stop at its left edge. A hot Chamfer (a1 -> a2 border, cut corners top-left and
// bottom-right) holds the widgets in one column. shell.qml creates it only for the
// main screen.
//
// Exclusive zones and layer order: the compositor arranges layer surfaces one after
// another, each inside the area the earlier ones left. A rail with its own zone on the
// top layer therefore lands 26 px lower when it is arranged after the bar, and cuts
// the bar short (bar 0..1488, rail from y 0) when it is arranged first (both seen in
// the rig). So the visible rail ignores zones (always exactly below the bar, never
// shortens it), and a separate 1 px transparent, input-less surface on the overlay
// layer, which is arranged after the top layer, reserves the width.
// Deploy note: that overlay surface sits above fullscreen windows on the main monitor.
// It is 1 px, transparent and takes no input, but if render:direct_scanout is enabled
// in Hyprland, any overlay-layer surface may keep a fullscreen window on the main
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

    anchors { top: true; bottom: true; right: true }
    margins.top: barHeight
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
        exclusiveZone: rail.implicitWidth
        color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "rice-rail-zone"
    }

    Chamfer {
        anchors.fill: parent
        hot: true
        cut: 10

        Item {
            anchors.fill: parent
            anchors.topMargin: Math.round(rail.px * 0.55)
            anchors.bottomMargin: Math.round(rail.px * 0.55)
            anchors.leftMargin: Math.round(rail.px * 0.8)
            anchors.rightMargin: Math.round(rail.px * 0.8)
            clip: true

            ColumnLayout {
                id: column
                anchors { top: parent.top; left: parent.left; right: parent.right }
                spacing: Math.round(rail.px * 0.5)

                ClockWidget { Layout.fillWidth: true; px: rail.px }
                SysWidget { Layout.fillWidth: true; px: rail.px }
                MediaWidget { Layout.fillWidth: true; px: rail.px }
                // More sections (Bluetooth, Claude limits; unit U12) go here, one line each:
                //   BluetoothWidget { Layout.fillWidth: true; px: rail.px }
            }
        }
    }
}
