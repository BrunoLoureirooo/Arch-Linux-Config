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
//   qs-run.sh ipc call probe setDf <program> | setDiskEvery <ticks> | refreshDisks
//   qs-run.sh ipc call probe parseDf <df output> | diskText   -> Stats disk helpers
// get also reports the DISK, VOLUME and BLUETOOTH sections (texts, StatRows).
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
            // Section headings (SectionLabel: text + note) and the sparkline.
            const heads = shell.findAll(c, i => i.note !== undefined && typeof i.text === "string" && i.visible, []);
            const spark = shell.find(c, i => i.samples !== undefined && i.peak !== undefined);
            const tmp = shell.find(c, i => i.label === "TMP" && i.value !== undefined);
            const segs = tmp ? shell.find(tmp, i => i.lit !== undefined && i.cell !== undefined) : null;
            const top = i => Math.round(i.mapToItem(clip, 0, 0).y);
            const bottom = i => Math.round(i.mapToItem(clip, 0, i.height).y);
            // Sections top to bottom: [top, bottom] of each section (the heading's parent).
            const secs = heads.map(hd => [top(hd.parent), bottom(hd.parent)]);
            out.rail = r === null ? null : {
                screen: r.screen.name,
                clipHeight: clip.height,
                // Inner padding: the content area's inset from the rail's left, top,
                // right and bottom edges.
                pad: [Math.round(clip.mapToItem(c, 0, 0).x), Math.round(clip.mapToItem(c, 0, 0).y),
                    Math.round(c.width - clip.mapToItem(c, clip.width, 0).x),
                    Math.round(c.height - clip.mapToItem(c, 0, clip.height).y)],
                // Gaps between consecutive sections (the last one, above CLAUDE, takes
                // the spare height).
                gaps: secs.slice(1).map((s2, i) => s2[0] - secs[i][1]),
                columnImplicit: clip.children[0].implicitHeight,
                sections: heads.map(hd => [hd.text, top(hd)]),
                lastBottom: heads.length ? Math.max(...heads.map(hd => bottom(hd.parent))) : -1,
                spark: spark ? [top(spark), Math.round(spark.height)] : null,
                // Heights of the visible SYS rows (CPU, MEM, GPU, VRM, TMP).
                rowHeights: shell.findAll(c, i => ["CPU", "MEM", "GPU", "VRM", "TMP"].includes(i.label) && i.litColor !== undefined && i.visible, [])
                    .map(i => Math.round(i.height))
            };
            // DISK and VOLUME sections: visible texts, and per StatRow its label, text,
            // lit count and segment colours.
            const statRows = sec => shell.findAll(sec, i => i.label !== undefined && i.litColor !== undefined && i.visible, []).map(row => {
                const sg = shell.find(row, i => i.lit !== undefined && i.cell !== undefined);
                // The label Text (children[0]): cut short? elide mode; the sub text when shown.
                const lt = row.children[0];
                return { label: row.label, text: row.text, lit: sg.lit, warn: row.warn,
                    truncated: lt.truncated, elide: lt.elide,
                    sub: row.children[3] && row.children[3].visible ? row.children[3].text : "",
                    colors: [...new Set(sg.children.filter(s => s.color !== undefined).map(s => String(s.color)))] };
            });
            const disk = shell.find(c, i => i.mounts !== undefined);
            const vol = shell.find(c, i => i.allStreams !== undefined);
            const bt = shell.find(c, i => i.devices !== undefined && i.emptyText !== undefined);
            out.disk = disk ? { texts: shell.texts(disk), rows: statRows(disk), ticks: Stats.diskTicks,
                every: Stats.diskEvery, n: Stats.disks.length } : null;
            out.volume = vol ? { texts: shell.texts(vol), rows: statRows(vol), streams: vol.allStreams.length,
                hasSink: vol.hasSink,
                plain: shell.findAll(vol, i => typeof i.text === "string" && i.font !== undefined && i.visible, [])
                    .filter(t => t.textFormat !== Text.PlainText && /[<&]/.test(t.text)).length,
                meters: shell.findAll(vol, i => i.cells !== undefined && i.visible, []).map(m => m.lit) } : null;
            out.bt = bt ? { visible: bt.visible, texts: shell.texts(bt) } : null;
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

        // Disk usage: the df command (one program, no arguments: a fake df script),
        // the refresh period in ticks, an immediate refresh, the pure helpers.
        function setDf(program: string): void {
            Stats.dfCommand = [program];
        }

        function setDiskEvery(ticks: int): void {
            Stats.diskEvery = ticks;
        }

        function refreshDisks(): void {
            Stats.refreshDisks();
        }

        function parseDf(text: string): string {
            return JSON.stringify(Stats.parseDf(text).map(d => [d.mount, d.type, d.pct, Stats.diskText(d.used, d.size)]));
        }

        function diskText(): string {
            const G = 1024 ** 3;
            return JSON.stringify([[0.6 * G, 1.0 * G], [39.4 * G, 49 * G], [145 * G, 786 * G], [1.2 * 1024 * G, 1.8 * 1024 * G],
                [512 * 1048576, 900 * 1048576], [0, 0]].map(p => Stats.diskText(p[0], p[1])));
        }
    }
}
