// Quickshell root (spec 5.3). Started by qs-supervise; one process, one QML tree.
//
// Imports: the shell root is the module `qs` (Quickshell >= 0.2 module imports,
// relative to this file's directory), so every file anywhere in the tree uses
//   import qs             -> Theme (singleton, registered in ./qmldir)
//   import qs.components  -> Chamfer, Meter, Chip
//   import qs.services    -> Stats, Screens (singletons, registered in services/qmldir)
//   import qs.wallpaper   -> Wallpaper, WallpaperState (singleton, wallpaper/qmldir)
//   import qs.bar / qs.rail / ...   -> the per-area directories added by later units
// Never use relative ("../") or "root:/" imports; they break singletons and the LSP.
//
// Each area adds one line or one Variants block below.
import QtQuick
import Quickshell
import qs.bar
import qs.notifications
import qs.rail
import qs.services
import qs.wallpaper

ShellRoot {
    // Wallpaper on every screen; the chosen path lives in WallpaperState.
    Variants {
        model: Quickshell.screens

        Wallpaper {
            required property var modelData
            screen: modelData
            path: WallpaperState.path
        }
    }

    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
        }
    }

    // The rail exists only on the main screen: one LazyLoader per screen, active
    // only for Screens.isMain, so no rail window or widget exists anywhere else.
    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: railLoader
            required property var modelData
            active: Screens.isMain(modelData)

            Rail {
                screen: railLoader.modelData
            }
        }
    }

    // The notification server (replaces mako) and its toasts on the main screen.
    Toasts {}
}
