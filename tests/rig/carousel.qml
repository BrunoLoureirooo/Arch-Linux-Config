// Carousel probe (test config only, never part of production). The same pieces as
// shell.qml that the carousel recolours (wallpaper on every screen, bars, the rail on
// the main screen) plus the production Carousel and an IpcHandler that reads its
// state, so Carousel.qml carries no test code:
//   tests/rig/qs-run.sh start --entry tests/rig/carousel.qml
//   qs-run.sh ipc call carousel toggle         (the production handler)
//   qs-run.sh ipc call carouselprobe get       -> open, screen, files, selection, palette state
//   qs-run.sh ipc call carouselprobe parse     -> pure helpers on fixtures
//   qs-run.sh ipc call carouselprobe windows   -> how many carousel windows exist
import QtQuick
import Quickshell
import Quickshell.Io
import qs
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

    Carousel {
        id: carousel
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
        target: "carouselprobe"

        function get(): string {
            const theme = {};
            for (const k of Theme.keys)
                theme[k] = String(Theme[k]);
            const base = {
                open: carousel.opened,
                theme: theme,
                previewing: Theme.previewTokens !== null,
                wallPath: WallpaperState.path,
                wallPreview: WallpaperState.previewPath,
                wallFile: WallpaperState.filePath,
                deriving: carousel.deriving,
                pending: carousel.pending,
                applying: carousel.applying,
                applyQueued: carousel.applyQueued,
                settling: carousel.settling !== null,
                // Each screen's Wallpaper: what it shows and whether it decoded.
                walls: walls.instances.map(w => {
                    const img = findAll(w.contentItem, i => i.fillMode !== undefined && i.sourceSize !== undefined, [])[0];
                    return { screen: w.screen ? w.screen.name : "", shown: w.shownPath, ready: img ? img.status === Image.Ready : false };
                })
            };
            const win = carousel.windowLoader.item;
            if (!carousel.opened || !win) {
                base.window = !!win;
                return JSON.stringify(base);
            }
            const texts = findAll(win.contentItem, i => i.text !== undefined && i.font !== undefined && i.visible, []).map(t => t.text);
            const thumbs = findAll(win.contentItem, i => i.file !== undefined && i.on !== undefined, []);
            base.window = true;
            base.screen = win.screen ? win.screen.name : "";
            base.loaded = win.loaded;
            base.files = win.files.map(f => f.name);
            base.sel = win.sel;
            base.selName = win.cur ? win.cur.name : "";
            base.wanted = carousel.wanted;
            base.result = win.result;
            base.applyError = carousel.applyError;
            base.texts = texts;
            base.thumbs = thumbs.map(t => ({ name: t.file ? t.file.name : "", on: t.on, w: t.width, h: t.height, opacity: t.opacity }));
            base.focus = findAll(win.contentItem, i => i.activeFocus === true && i.focus === true, []).length > 0;
            base.height = win.height;
            return JSON.stringify(base);
        }

        function windows(): int {
            return carousel.windowLoader.item ? 1 : 0;
        }

        function parse(): string {
            return JSON.stringify({
                dims: [carousel.dims("PNG image data, 1920 x 1080, 8-bit/color RGB, non-interlaced"),
                       carousel.dims("JPEG image data, JFIF standard 1.01, aspect ratio, density 72x72, segment length 16, baseline, precision 8, 3840x2160, components 3"),
                       carousel.dims("RIFF (little-endian) data, Web/P image, VP8 encoding, 640x480, Scaling: [none]x[none], YUV color, decoders should clamp"),
                       carousel.dims("empty")],
                oneLine: [carousel.oneLine("rice-palette: not an image: /x/broken.png\n"), carousel.oneLine(""),
                          carousel.oneLine("warning\nrice-palette: matugen failed: boom\n")],
                ok: carousel.parseDerive(0, "file:PNG image data, 8 x 4, 8-bit\n" + JSON.stringify(Theme.defaults), ""),
                fail: carousel.parseDerive(1, "file:empty\n", "rice-palette: not an image: /x/b.png\n"),
                garbage: carousel.parseDerive(0, "file:\nnot json", ""),
                partial: carousel.parseDerive(0, "{\"bg\":\"#000000\"}", "")
            });
        }
    }
}
