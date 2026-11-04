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
import Quickshell.Io
import qs.bar
import qs.fx
import qs.hud
import qs.launcher
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

    // The rail exists only on the rail screen (Screens.railScreen: the built-in eDP
    // panel, else the main screen) and only while Screens.railShown: one LazyLoader per
    // screen, so no rail window, zone or widget exists anywhere else or while hidden.
    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: railLoader
            required property var modelData
            active: Screens.railShown && Screens.isRail(modelData)

            Rail {
                screen: railLoader.modelData
            }
        }
    }

    // qs ipc call rail toggle|show|hide|status (state in memory only, starts shown).
    IpcHandler {
        target: "rail"

        function toggle(): void {
            Screens.railShown = !Screens.railShown;
        }
        function show(): void {
            Screens.railShown = true;
        }
        function hide(): void {
            Screens.railShown = false;
        }
        function status(): string {
            return (Screens.railShown ? "shown" : "hidden") + " " + (Screens.railScreen ? Screens.railScreen.name : "none");
        }
    }

    // The empty-workspace clock HUD, one per screen (only while its workspace is empty).
    Variants {
        model: Quickshell.screens

        CentreClock {
            required property var modelData
            screen: modelData
        }
    }

    // The notification server (replaces mako) and its toasts on the main screen.
    Toasts {}

    // The application launcher overlay (qs ipc call launcher toggle).
    Launcher {}

    // The wallpaper carousel overlay (qs ipc call carousel toggle).
    Carousel {}

    // The workspace-switch tear on the screen whose workspace changed (on by default;
    // qs ipc call glitch disable|enable).
    Glitch {}
}
