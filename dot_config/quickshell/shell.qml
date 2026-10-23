// Quickshell root (spec 5.3). Started by qs-supervise; one process, one QML tree.
//
// Imports: the shell root is the module `qs` (Quickshell >= 0.2 module imports,
// relative to this file's directory), so every file anywhere in the tree uses
//   import qs             -> Theme (singleton, registered in ./qmldir)
//   import qs.components  -> Chamfer, Meter, Chip
//   import qs.bar / qs.rail / ...   -> the per-area directories added by later units
// Never use relative ("../") or "root:/" imports; they break singletons and the LSP.
//
// Each area adds one line or one Variants block below.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

ShellRoot {
    // Minimal verification surface: a small tag on each screen showing the shell is
    // up and Theme resolves. Removed once the bar exists.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; left: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "rice-skeleton"
            implicitWidth: tag.implicitWidth + 16
            implicitHeight: tag.implicitHeight + 8
            color: Theme.panel

            Text {
                id: tag
                anchors.centerIn: parent
                color: Theme.a1
                font.family: Theme.font
                font.pixelSize: Theme.px
                text: "QS // " + modelData.name
            }
        }
    }
}
