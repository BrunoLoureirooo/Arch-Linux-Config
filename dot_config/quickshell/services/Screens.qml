pragma Singleton
// Which screen is "main" (spec 5.3): the one whose Hyprland monitor description starts
// with "BNQ BenQ"; if no screen matches (the rig's headless outputs have empty
// descriptions), the first screen in Quickshell.screens.
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

    function isMain(screen) {
        return screen !== null && screen !== undefined && mainScreen !== null && screen.name === mainScreen.name;
    }
}
