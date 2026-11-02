// Rail placement / layout / CPU temperature and empty-workspace HUD probe (test config
// only, never part of production), for tests/rig/selftest-rail.sh. The production
// CentreClock on every screen and the production Rail placed exactly as shell.qml
// places it (Screens.railShown && Screens.isRail), over a background-layer "catcher"
// window per screen that counts left clicks (it stands where the wallpaper is), plus an
// IpcHandler that reads their state by walking the item trees:
//   tests/rig/qs-run.sh start --entry tests/rig/rail-hud.qml
//   qs-run.sh ipc call probe get                 -> JSON (hud, clicks, rail, temp)
//   qs-run.sh ipc call probe setTempPath <file>  -> Stats.tempPath
//   qs-run.sh ipc call probe scanTemp <hwmon-root> <thermal-root>   -> re-run the probe
//   qs-run.sh ipc call probe parseTemp <text>    -> Stats.parseTemp
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.hud
import qs.rail
import qs.services

ShellRoot {
    id: shell

    property var clicks: ({})

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: catcher
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "#07070d"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "rig-catcher"

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    const c = Object.assign({}, shell.clicks);
                    c[catcher.screen.name] = (c[catcher.screen.name] || 0) + 1;
                    shell.clicks = c;
                }
            }
        }
    }

    Variants {
        id: huds
        model: Quickshell.screens

        CentreClock {
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
            active: Screens.railShown && Screens.isRail(modelData)

            Rail {
                screen: railLoader.modelData
            }
        }
    }

    IpcHandler {
        target: "rail"

        function toggle(): void {
            Screens.railShown = !Screens.railShown;
        }
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

    function texts(item) {
        return findAll(item, i => typeof i.text === "string" && i.visible && i.font !== undefined, []).map(t => t.text);
    }

    function rail() {
        for (const l of rails.instances)
            if (l.item)
                return l.item;
        return null;
    }

    IpcHandler {
        target: "probe"

        function get(): string {
            const out = { clicks: shell.clicks, hud: {} };
            for (const h of huds.instances) {
                const win = h.windowLoader.item;
                out.hud[h.screen.name] = { shown: win !== null && win.visible, texts: win ? shell.texts(win.contentItem) : [] };
            }
            const r = shell.rail();
            const c = r ? r.contentItem : null;
            const clip = shell.find(c, i => i.clip === true);
            // Section headings (SectionLabel: text + note), the clock digits, the sparkline.
            const heads = shell.findAll(c, i => i.note !== undefined && typeof i.text === "string" && i.visible, []);
            const spark = shell.find(c, i => i.samples !== undefined && i.peak !== undefined);
            const tmp = shell.find(c, i => i.label === "TMP" && i.value !== undefined);
            const segs = tmp ? shell.find(tmp, i => i.lit !== undefined && i.cell !== undefined) : null;
            const top = i => Math.round(i.mapToItem(clip, 0, 0).y);
            const bottom = i => Math.round(i.mapToItem(clip, 0, i.height).y);
            out.rail = r === null ? null : {
                screen: r.screen.name,
                clipHeight: clip.height,
                columnImplicit: clip.children[0].implicitHeight,
                sections: heads.map(hd => [hd.text, top(hd)]),
                lastBottom: heads.length ? Math.max(...heads.map(hd => bottom(hd.parent))) : -1,
                spark: spark ? [top(spark), Math.round(spark.height)] : null
            };
            out.temp = {
                c: Stats.cpuTempC, path: Stats.tempPath,
                row: tmp ? { text: tmp.text, lit: segs.lit, warn: tmp.warn, known: tmp.known,
                    colors: segs.children.filter(s => s.color !== undefined).map(s => String(s.color)) } : null
            };
            return JSON.stringify(out);
        }

        function setTempPath(path: string): void {
            Stats.tempPath = path;
        }

        function scanTemp(hwmon: string, thermal: string): void {
            Stats.hwmonRoot = hwmon;
            Stats.thermalRoot = thermal;
            Stats.scanTemp();
        }

        function parseTemp(text: string): string {
            return String(Stats.parseTemp(text));
        }
    }
}
