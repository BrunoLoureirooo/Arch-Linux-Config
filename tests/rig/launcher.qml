// Launcher probe (test config only, never part of production). Runs the production
// Launcher plus an IpcHandler that reads its state, so Launcher.qml carries no test
// code. NEVER run it against real desktop entries: start it with XDG_DATA_DIRS and
// XDG_DATA_HOME pointing at directories that hold only fake .desktop files.
//   qs-run.sh ipc call launcher toggle          (the production handler)
//   qs-run.sh ipc call launcherprobe get        -> open, screen, query, rows, selection
//   qs-run.sh ipc call launcherprobe parse      -> filter() and tag() on fixtures
//   qs-run.sh ipc call launcherprobe windows    -> how many launcher windows exist
import QtQuick
import Quickshell
import Quickshell.Io
import qs.launcher

ShellRoot {
    Launcher {
        id: launcher
    }

    function findAll(item, pred, out) {
        if (!item)
            return out;
        if (pred(item))
            out.push(item);
        for (const c of item.children)
            findAll(c, pred, out);
        return out;
    }

    IpcHandler {
        target: "launcherprobe"

        function get(): string {
            const win = launcher.windowLoader.item;
            if (!launcher.opened || !win)
                return JSON.stringify({ open: launcher.opened, window: !!win });
            const input = findAll(win.contentItem, i => i.cursorRectangle !== undefined && i.echoMode !== undefined, [])[0];
            return JSON.stringify({
                open: true,
                screen: win.screen ? win.screen.name : "",
                query: input ? input.text : null,
                inputFocus: input ? input.activeFocus : false,
                windowActive: input ? input.Window.active : null,
                activeItem: input && input.Window.activeFocusItem ? String(input.Window.activeFocusItem) : null,
                count: win.matches.length,
                total: win.apps.length,
                rows: win.rows.map(e => e.name),
                selected: win.selected,
                allNames: win.apps.map(e => e.name).sort()
            });
        }

        function windows(): int {
            return launcher.windowLoader.item ? 1 : 0;
        }

        function parse(): string {
            const e = (name, generic, keywords) => ({ name: name, genericName: generic, keywords: keywords });
            const apps = [e("Zed", "Editor", []), e("Firefox", "Web Browser", ["internet"]),
                          e("Fish", "Shell", []), e("Thunar", "File Manager", ["folder", "FIREFOX-like"]),
                          e("LibreOffice", "", []), e("Alacritty", "Terminal", [])];
            const names = q => launcher.filter(apps, q).map(x => x.name);
            return JSON.stringify({
                fir: names("fir"), FIR: names("FIR"), f: names("f"), all: names(""), none: names("qqq"),
                inter: names("inter"), spaces: names("  fish "),
                tags: [launcher.tag("Firefox"), launcher.tag("Visual Studio Code"), launcher.tag("X"), launcher.tag("")]
            });
        }
    }
}
