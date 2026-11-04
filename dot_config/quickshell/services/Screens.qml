pragma Singleton
// Which screen is "main" (spec 5.3): the one whose Hyprland monitor description starts
// with "BNQ BenQ"; if no screen matches (the rig's headless outputs have empty
// descriptions), the first screen in Quickshell.screens.
// Which screen holds the rail: the built-in panel (output name starting with "eDP"),
// chosen by name, never by focus. A closed lid disables eDP-1, which removes it from
// Quickshell.screens, so the rail falls back to the main screen and moves back when the
// panel returns. `railShown` is the rail's on/off state (qs ipc call rail toggle); it
// lives in memory only and starts visible.
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property var mainScreen: {
        const screens = Quickshell.screens;
        const benq = Hyprland.monitors.values.find(m => m.description.startsWith("BNQ BenQ"));
        const hit = benq ? screens.find(s => s.name === benq.name) : undefined;
        return hit ?? (screens.length > 0 ? screens[0] : null);
    }

    readonly property var railScreen: Quickshell.screens.find(s => s.name.startsWith("eDP")) ?? mainScreen

    property bool railShown: true

    function isMain(screen) {
        return screen !== null && screen !== undefined && mainScreen !== null && screen.name === mainScreen.name;
    }

    function isRail(screen) {
        return screen !== null && screen !== undefined && railScreen !== null && screen.name === railScreen.name;
    }
}
