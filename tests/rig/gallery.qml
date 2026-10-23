// Components gallery (test config only, never part of production shell.qml).
// Run inside the rig against the staged shell, so `import qs` resolves to it:
//   tests/rig/qs-run.sh start --entry tests/rig/gallery.qml
//   tests/rig/qs-run.sh ipc call gallery state      -> current Theme tokens as JSON
//   tests/rig/qs-run.sh ipc call gallery preview    -> Theme.preview(test palette)
//   tests/rig/qs-run.sh ipc call gallery clear      -> Theme.clearPreview()
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components

ShellRoot {
    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "rice-gallery"
        color: Theme.bg

        Column {
            x: 40; y: 40
            spacing: 24

            Text {
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.px
                text: "// gallery  a1=" + Theme.a1 + "  a2=" + Theme.a2 + "  line=" + Theme.line
                      + "  warn=" + Theme.warn
            }

            Row {
                spacing: 24

                Chamfer {
                    width: 240; height: 96
                    Text {
                        anchors.centerIn: parent
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.px
                        text: "CHAMFER cut=10"
                    }
                }

                Chamfer {
                    width: 240; height: 96
                    hot: true
                    fill: Theme.panel
                    Text {
                        anchors.centerIn: parent
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.px
                        text: "CHAMFER hot"
                    }
                }

                Chamfer {
                    width: 240; height: 96
                    cut: 16
                    stroke: Theme.a2
                    Text {
                        anchors.centerIn: parent
                        color: Theme.a2
                        font.family: Theme.font
                        font.pixelSize: Theme.px
                        text: "[!] cut=16 stroke=a2"
                    }
                }
            }

            Row {
                spacing: 24
                Repeater {
                    model: [
                        { v: 20, inv: false }, { v: 50, inv: false }, { v: 90, inv: false },
                        { v: 87, inv: true }, { v: 15, inv: true }
                    ]
                    Row {
                        required property var modelData
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.px
                            text: (modelData.inv ? "inv " : "") + modelData.v
                        }
                        Meter {
                            anchors.verticalCenter: parent.verticalCenter
                            value: modelData.v
                            invert: modelData.inv
                        }
                    }
                }
            }

            Row {
                spacing: 18
                Chip { label: "CPU"; meter: 23 * 2; text: "23%" }
                Chip { label: "MEM"; text: "3.1G" }
                Chip { label: "VOL"; meter: 40 }
                Chip { label: "BAT"; meter: 87; text: "87%" }
                Chip { label: "GPU"; meter: 92; text: "92%" }
            }
        }
    }

    // Test-only trigger for Theme.preview()/clearPreview(); production Theme has none.
    IpcHandler {
        target: "gallery"
        function preview(): void {
            Theme.preview({ bg: "#100814", panel: "#1a0d1f", line: "#3a1f44", dim: "#9a7aa8",
                            fg: "#f0e0f5", a1: "#ffb000", a2: "#00ff9c", warn: "#ff3030" });
        }
        function clear(): void { Theme.clearPreview(); }
        function state(): string {
            return JSON.stringify({ bg: Theme.bg.toString(), panel: Theme.panel.toString(),
                line: Theme.line.toString(), dim: Theme.dim.toString(), fg: Theme.fg.toString(),
                a1: Theme.a1.toString(), a2: Theme.a2.toString(), warn: Theme.warn.toString() });
        }
    }
}
