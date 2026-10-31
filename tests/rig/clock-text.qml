// Clock and untrusted-text probe (test config only, never part of production). Bars on
// every screen and the rail on the main screen, as in shell.qml, plus an IpcHandler:
//   tests/rig/qs-run.sh start --entry tests/rig/clock-text.qml
//   qs-run.sh ipc call probe clock         -> every visible text of the bars and the rail clock
//   qs-run.sh ipc call probe mock <ms>     -> Clock.source returns that UTC instant from now on
//   qs-run.sh ipc call probe real          -> Clock.source back to the real time
//   qs-run.sh ipc call probe untrusted     -> every Text in bars and rail whose string holds '<':
//                                             its format, line count and widths
//   qs-run.sh ipc call probe setBt <name>  -> the rail's BluetoothWidget shows one FAKE device
//   qs-run.sh ipc call probe clearBt       -> the fake model emptied (rows torn down)
import QtQuick
import Quickshell
import Quickshell.Io
import qs.bar
import qs.rail
import qs.services

ShellRoot {
    id: shell

    property real mockMs: 0

    Variants {
        id: bars
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
        }
    }

    Variants {
        id: rails
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

    ListModel {
        id: fakeBt
    }

    function find(item, pred) {
        if (!item)
            return null;
        if (pred(item))
            return item;
        for (const c of item.children) {
            const r = find(c, pred);
            if (r)
                return r;
        }
        return null;
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

    function rail() {
        for (const l of rails.instances)
            if (l.item)
                return l.item;
        return null;
    }

    function roots() {
        const out = bars.instances.map(b => ({ name: "bar:" + (b.screen ? b.screen.name : ""), item: b.contentItem }));
        const r = rail();
        if (r)
            out.push({ name: "rail", item: r.contentItem });
        return out;
    }

    function isText(i) {
        return typeof i.text === "string" && i.font !== undefined && i.lineCount !== undefined;
    }

    IpcHandler {
        target: "probe"

        function clock(): string {
            const out = {};
            for (const b of bars.instances)
                out["bar:" + (b.screen ? b.screen.name : "")] = shell.findAll(b.contentItem, i => shell.isText(i) && i.visible, []).map(t => t.text);
            const clk = shell.find(shell.rail()?.contentItem, i => String(i).startsWith("ClockWidget"));
            out.rail = clk ? shell.findAll(clk, i => shell.isText(i), []).map(t => t.text) : null;
            out.clockDate = String(Clock.date);
            return JSON.stringify(out);
        }

        function mock(ms: string): void {
            shell.mockMs = Number(ms);
            Clock.source = () => new Date(shell.mockMs);
        }

        function real(): void {
            Clock.source = null;
        }

        function untrusted(): string {
            const out = [];
            for (const r of shell.roots())
                for (const t of shell.findAll(r.item, i => shell.isText(i) && i.text.indexOf("<") >= 0, []))
                    out.push({ where: r.name, text: t.text, plain: t.textFormat === Text.PlainText, lines: t.lineCount,
                               visible: t.visible, w: t.implicitWidth });
            return JSON.stringify(out);
        }

        function setBt(name: string): void {
            fakeBt.clear();
            fakeBt.append({ name: name, connected: true, battery: 0.5, batteryAvailable: true });
            shell.find(shell.rail()?.contentItem, i => i.devices !== undefined && i.connected !== undefined).devices = fakeBt;
        }

        function clearBt(): void {
            fakeBt.clear();
        }
    }
}
