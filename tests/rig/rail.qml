// Wallpaper / rail probe (test config only, never part of production). The same
// pieces as shell.qml (wallpaper on every screen, bars, the rail on the main screen
// only), plus an IpcHandler that reads their state by walking the item trees, so the
// production files carry no test code:
//   tests/rig/qs-run.sh start --entry tests/rig/rail.qml
//   qs-run.sh ipc call rail get            -> wallpaper, rail, media, net state (JSON)
//   qs-run.sh ipc call rail parse          -> pure functions on fixtures
//   qs-run.sh ipc call rail setNetDevPath <path>
//   qs-run.sh ipc call rail setGpuPath <path>
//   qs-run.sh ipc call rail preview <path> / clearPreview   -> WallpaperState preview
//   qs-run.sh ipc call rail setReady <true|false>           -> WallpaperState.ready
import QtQuick
import Quickshell
import Quickshell.Io
import qs.bar
import qs.rail
import qs.services
import qs.wallpaper

ShellRoot {
    Variants {
        id: walls
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

    // Depth-first search of an item tree.
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

    IpcHandler {
        target: "rail"

        function get(): string {
            const images = {};
            for (const w of walls.instances) {
                const img = find(w.contentItem, i => i.fillMode !== undefined && i.sourceSize !== undefined);
                images[w.screen.name] = {
                    status: img.status, source: String(img.source),
                    decoded: [img.implicitWidth, img.implicitHeight],
                    sourceSize: [img.sourceSize.width, img.sourceSize.height],
                    leader: w.leader
                };
            }
            const railScreens = [];
            let media = null, gpuRow = null, spark = null, label = null, clockText = [];
            for (const l of rails.instances) {
                if (!l.item)
                    continue;
                const r = l.item;
                railScreens.push(r.screen.name);
                const m = find(r.contentItem, i => i.player !== undefined && i.hasLength !== undefined);
                media = {
                    visible: m.visible,
                    title: m.player ? m.player.trackTitle : "",
                    artist: m.player ? m.player.trackArtist : "",
                    position: m.player ? m.player.position : -1,
                    length: m.player ? m.player.length : -1,
                    texts: findAll(m, i => i.text !== undefined && typeof i.text === "string" && i.visible, []).map(i => i.text)
                };
                const g = find(r.contentItem, i => i.label === "GPU" && i.value !== undefined);
                gpuRow = g ? g.visible : null;
                const s = find(r.contentItem, i => i.samples !== undefined && i.points !== undefined);
                spark = s ? { n: s.points.length, peak: s.peak } : null;
                const sl = find(r.contentItem, i => i.note !== undefined && i.text === "sys");
                label = sl ? sl.visible : null;
            }
            return JSON.stringify({
                wallpaper: {
                    path: WallpaperState.path, defaultPath: WallpaperState.defaultPath,
                    filePath: WallpaperState.filePath, statePath: WallpaperState.statePath,
                    previewPath: WallpaperState.previewPath, ready: WallpaperState.ready,
                    verdict: WallpaperState.verdict, verdictPath: WallpaperState.verdictPath,
                    images: images
                },
                railScreens: railScreens,
                main: Quickshell.screens.filter(s => Screens.isMain(s)).map(s => s.name),
                media: media, gpuRow: gpuRow, spark: spark, sysLabel: label,
                net: { up: Stats.netUp, down: Stats.netDown, n: Stats.netHistory.length,
                       last: Stats.netHistory.length ? Stats.netHistory[Stats.netHistory.length - 1] : -1,
                       conn: Stats.netConn, gpu: Stats.gpu }
            });
        }

        function parse(): string {
            const dev = "Inter-|   Receive                                                |  Transmit\n"
                + " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n"
                + "    lo: 5000 10 0 0 0 0 0 0 5000 10 0 0 0 0 0 0\n"
                + "  eno1: 1000 1 0 0 0 0 0 0 200 1 0 0 0 0 0 0\n"
                + " wlan0: 3000 1 0 0 0 0 0 0 800 1 0 0 0 0 0 0\n";
            return JSON.stringify({
                netDev: Stats.parseNetDev(dev),                       // lo skipped: {4000, 1000}
                netDevBad: Stats.parseNetDev("garbage\nx: 1 2\n"),    // null
                netDevLoOnly: Stats.parseNetDev("lo: 1 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0\n"),  // {0, 0}
                rates: Stats.netRates({ rx: 1000, tx: 100, t: 0 }, { rx: 5096, tx: 2148, t: 2000 }),  // down 2048 up 1024
                ratesFirst: Stats.netRates(null, { rx: 1, tx: 1, t: 1 }),
                ratesBack: Stats.netRates({ rx: 9000, tx: 100, t: 0 }, { rx: 10, tx: 200, t: 2000 }),
                ratesNoTime: Stats.netRates({ rx: 1, tx: 1, t: 5 }, { rx: 2, tx: 2, t: 5 }),
                compact: [0, 512, 1023, 1024, 8601, 122880, 1258291, 3221225472, -1].map(v => Stats.compactRate(v)),
                state: [
                    WallpaperState.parse('{"path": "/a/b.png", "palette": "neon"}'),
                    WallpaperState.parse('{ not json'),
                    WallpaperState.parse(''),
                    WallpaperState.parse('[1, 2]'),
                    WallpaperState.parse('{"palette": "x"}'),
                    WallpaperState.parse('{"path": 7}'),
                    WallpaperState.parse('{"path": ""}'),
                    WallpaperState.parse('{"path": "relative.png"}')
                ].map(r => [r.path, r.palette, r.error !== ""])
            });
        }

        function setNetDevPath(path: string): void {
            Stats.netDevPath = path;
        }

        function setGpuPath(path: string): void {
            Stats.gpuPath = path;
        }

        function preview(path: string): void {
            WallpaperState.preview(path);
        }

        function clearPreview(): void {
            WallpaperState.clearPreview();
        }

        // Simulates "state file not read yet" (the startup window) for the gate check.
        function setReady(ready: bool): void {
            WallpaperState.ready = ready;
        }
    }
}
