// Rig smoke test: one PanelWindow per screen with a line of text, plus what the
// Hyprland module sees, and an IpcHandler to exercise `qs ipc`.
// Run: tests/rig/run.sh qs -p tests/rig/qs-smoke.qml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true }
            implicitHeight: 64
            color: "#101010"

            Text {
                anchors.centerIn: parent
                color: "#33ff66"
                font.family: "monospace"
                font.pixelSize: 28
                text: "RIG SMOKE " + modelData.name
                      + " | hypr monitors=" + Hyprland.monitors.values.length
                      + " workspaces=" + Hyprland.workspaces.values.length
                      + " focused=" + (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "none")
            }
        }
    }

    IpcHandler {
        target: "rig"
        function ping(): string { return "pong"; }
        function monitors(): string {
            return Hyprland.monitors.values.map(m => m.name).join(",");
        }
    }
}
