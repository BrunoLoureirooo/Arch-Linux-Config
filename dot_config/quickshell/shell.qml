// Quickshell root (spec 5.3). Started by qs-supervise; one process, one QML tree.
//
// Imports: the shell root is the module `qs` (Quickshell >= 0.2 module imports,
// relative to this file's directory), so every file anywhere in the tree uses
//   import qs             -> Theme (singleton, registered in ./qmldir)
//   import qs.components  -> Chamfer, Meter, Chip
//   import qs.services    -> Stats, Screens (singletons, registered in services/qmldir)
//   import qs.bar / qs.rail / ...   -> the per-area directories added by later units
// Never use relative ("../") or "root:/" imports; they break singletons and the LSP.
//
// Each area adds one line or one Variants block below.
import QtQuick
import Quickshell
import qs.bar

ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
        }
    }
}
