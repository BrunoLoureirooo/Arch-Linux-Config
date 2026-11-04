// Wallpaper carousel (spec 5.3; render .car): a bottom strip over the focused screen
// with five thumbnails of ~/Pictures/wallpapers (selected one larger, hot frame, index
// and name tags), the selected image's palette and page ticks. Left/Right select
// (wrapping) and preview live: `rice-palette derive` gives the tokens, then Theme and
// every Wallpaper show them in memory only. Enter runs `rice-palette apply` (writes
// colors.json, wallpaper.json, ...; the shell recolours through its file watches) and
// closes; Escape drops the preview and closes. `qs ipc call carousel toggle`
// (Ctrl+Alt+W). Nothing exists while closed (LazyLoader).
// Derivations: at most one `rice-palette derive` runs at a time; while it runs only the
// latest selection is queued, results are kept per path for the session (the CLI's own
// cache makes repeats fast too), and a result only previews if its path is still the
// selection. A failed derivation shows `✗ <error>` and keeps the previous preview;
// Enter does nothing on it. Enter while the selection is still being derived is
// remembered and applies once the palette arrives (a move or a failure drops it).
// After a successful apply the preview stays until Theme and WallpaperState have re-read
// the new files (or 3 s pass), so the shell never flashes the old palette.
// Escape (or the toggle) closes even while an apply runs: the apply finishes in the
// background (never killed half-way), its preview stays until it lands, and a failure
// then drops the preview. An apply with no result within applyTimeout (15 s) is no
// longer waited for: `✗ apply timed out`, the keyboard grab is released, the preview
// stays until the carousel is closed (the process itself is still not killed); if it
// then succeeds while the strip is still open, the timed-out line is cleared.
// The CLI runs by absolute path ($HOME/.local/bin/rice-palette): the session's PATH
// (greetd -> start-hyprland, no login shell) has no ~/.local/bin.
// Only one keyboard-grabbing overlay at a time (Overlays): the launcher opening closes
// the carousel and the other way round.
import QtQuick
import QtQuick.Shapes
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components
import qs.services

Scope {
    id: root

    readonly property real px: Theme.px
    readonly property bool opened: loader.active
    // Read-only handle (the rig's test config inspects the open window).
    readonly property LazyLoader windowLoader: loader
    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string folder: home + "/Pictures/wallpapers"
    readonly property string cli: home + "/.local/bin/rice-palette"
    property int applyTimeout: 15000

    property var targetScreen: null
    property string wanted: ""        // the selected path while open
    property var results: ({})        // path -> {ok, tokens, dims, error}; reset on open
    property string pending: ""       // queued derivation (latest selection only)
    property bool deriving: false     // a `rice-palette derive` is running
    property bool applying: false     // a `rice-palette apply` is running
    property bool applyOwned: false   // ...and the carousel still waits for its result
    property bool grab: true          // the window holds the Exclusive keyboard grab
    property bool applyQueued: false  // Enter came before the selection's palette
    property string applyError: ""
    property var settling: null       // {tokens, path} after an apply, until the files are re-read

    function open() {
        if (loader.active)
            return;
        finishSettle();
        if (applying && applyOwned) {
            // A background apply from the last session: stop waiting for it (its files
            // still arrive through the watches) and drop the preview it kept.
            applyOwned = false;
            applyTimer.stop();
            Theme.clearPreview();
            WallpaperState.clearPreview();
        }
        const mon = Hyprland.focusedMonitor;
        targetScreen = Quickshell.screens.find(s => mon && s.name === mon.name) ?? Screens.mainScreen;
        results = ({});
        wanted = "";
        pending = "";
        applyQueued = false;
        applyError = "";
        grab = true;
        Overlays.claim("carousel");  // closes the launcher if it is open
        loader.active = true;
    }

    // Escape / toggle: drop the preview and close; while an owned apply runs, close only
    // (the apply lands in the background and settles or drops the preview itself).
    function cancel() {
        if (!loader.active)
            return;
        if (!(applying && applyOwned)) {
            Theme.clearPreview();
            WallpaperState.clearPreview();
        }
        close();
    }

    function close() {
        loader.active = false;
        wanted = "";
        pending = "";
        applyQueued = false;
        Overlays.release("carousel");
    }

    // The launcher opened: give way.
    Connections {
        target: Overlays
        function onActiveChanged() {
            if (Overlays.active !== "carousel" && loader.active)
                root.cancel();
        }
    }

    function toggle() {
        if (loader.active)
            cancel();
        else
            open();
    }

    // Select a path: preview it now if its palette is known, else derive it.
    function want(p) {
        wanted = p;
        applyQueued = false;
        applyError = "";
        const r = results[p];
        if (r)
            show(p, r);
        else if (deriving)
            pending = p;
        else
            startDerive(p);
    }

    function show(p, r) {
        if (!r.ok)
            return;  // keep the previous preview
        Theme.preview(r.tokens);
        WallpaperState.preview(p);
    }

    function startDerive(p) {
        pending = "";
        deriving = true;
        derive.target = p;
        derive.done = 0;
        derive.running = true;
    }

    // Last non-empty line of the CLI's stderr, without the "rice-palette: " prefix.
    function oneLine(text) {
        const lines = (text || "").split("\n").map(l => l.trim()).filter(l => l !== "");
        return lines.length > 0 ? lines[lines.length - 1].replace(/^rice-palette: /, "") : "";
    }

    // `file -b` output -> "WxH" (the last "N x M" in it; JPEG lists its density first).
    function dims(desc) {
        const re = /(\d+) ?x ?(\d+)/g;
        let m, last = null;
        while ((m = re.exec(desc)) !== null)
            last = m;
        return last ? last[1] + "×" + last[2] : "";
    }

    function parseDerive(code, out, err) {
        const lines = (out || "").split("\n");
        const desc = lines.length > 0 && lines[0].startsWith("file:") ? lines.shift().slice(5) : "";
        if (code !== 0)
            return { ok: false, error: oneLine(err) || "rice-palette exited " + code };
        let obj;
        try {
            obj = JSON.parse(lines.join("\n"));
        } catch (e) {
            return { ok: false, error: "unusable rice-palette output" };
        }
        const s = Theme.sanitize(obj);
        if (s.bad.length > 0)
            return { ok: false, error: "rice-palette gave no " + s.bad.join(",") };
        return { ok: true, tokens: s.tokens, dims: dims(desc) };
    }

    function derived() {
        const p = derive.target;
        const r = parseDerive(derive.code, derive.stdout.text, derive.stderr.text);
        if (!r.ok)  // the footer has room for the file name, not the whole path
            r.error = r.error.split(p).join(p.slice(p.lastIndexOf("/") + 1));
        const next = Object.assign({}, results);
        next[p] = r;
        results = next;
        if (!r.ok)
            console.info("Carousel: no palette for", p + ":", r.error);
        const q = pending;
        pending = "";
        deriving = false;
        if (!loader.active)
            return;
        if (p === wanted) {
            show(p, r);
            if (applyQueued) {
                applyQueued = false;
                apply();
            }
        }
        // Next turn of the event loop: the finished Process has fully stopped by then.
        if (q !== "" && !results[q])
            Qt.callLater(() => { if (loader.active && !deriving && !results[q]) startDerive(q); });
    }

    function apply() {
        if (applying || wanted === "")
            return;
        const r = results[wanted];
        if (!r) {
            applyQueued = true;  // still deriving: apply when it arrives
            console.info("Carousel: Enter waits for the palette of", wanted);
            return;
        }
        if (!r.ok)
            return;
        applying = true;
        applyOwned = true;
        applyError = "";
        applyProc.target = wanted;
        applyProc.tokens = r.tokens;
        applyProc.done = 0;
        applyProc.running = true;
        applyTimer.restart();
    }

    // No result within applyTimeout: stop waiting (the process keeps running).
    function applyTimedOut() {
        if (!applying || !applyOwned)
            return;
        applyOwned = false;
        console.warn("Carousel: apply of", applyProc.target, "gave no result within", applyTimeout, "ms; no longer waiting");
        if (loader.active) {
            applyError = "timed out";
            grab = false;
        } else {
            Theme.clearPreview();
            WallpaperState.clearPreview();
        }
    }

    function applied() {
        const owned = applyOwned;
        applying = false;
        applyOwned = false;
        applyTimer.stop();
        const p = applyProc.target;
        const ok = applyProc.code === 0;
        if (!owned) {
            // Late (timed out, or the carousel was reopened): the files, if written,
            // reach Theme through its watch; only the wallpaper state is re-read.
            console.info("Carousel: late apply of", p, ok ? "finished" : "failed (exit " + applyProc.code + ")");
            if (ok) {
                WallpaperState.reload();
                // A strip still open after the timeout no longer claims it timed out.
                if (applyError === "timed out")
                    applyError = "";
            }
            return;
        }
        if (!ok) {
            const err = oneLine(applyProc.stderr.text) || "rice-palette exited " + applyProc.code;
            console.warn("Carousel: apply failed for", p + ":", err);
            if (loader.active) {
                applyError = err;
                return;  // stay open with the preview
            }
            Theme.clearPreview();  // closed during the apply: nothing to keep
            WallpaperState.clearPreview();
            return;
        }
        settling = { tokens: applyProc.tokens, path: p };
        WallpaperState.reload();
        close();
        settleTimer.restart();
        settleCheck();
    }

    function sameTokens(a, b) {
        return Theme.keys.every(k => a && b && a[k] === b[k]);
    }

    function settleCheck() {
        if (settling && sameTokens(Theme.fileTokens, settling.tokens) && WallpaperState.filePath === settling.path)
            finishSettle();
    }

    function finishSettle() {
        if (!settling)
            return;
        settling = null;
        settleTimer.stop();
        Theme.clearPreview();
        WallpaperState.clearPreview();
    }

    IpcHandler {
        target: "carousel"

        function toggle(): void {
            root.toggle();
        }
    }

    // `file -b` first (for the size in the header), then the CLI itself (exec, so one
    // process per derivation).
    Process {
        id: derive

        property string target: ""
        property int code: 0
        property int done: 0
        onDoneChanged: if (done === 3) root.derived()

        command: ["sh", "-c", "printf 'file:%s\\n' \"$(file -b -- \"$1\" 2>/dev/null | head -n 1)\"; exec \"$2\" derive \"$1\"", "sh", target, root.cli]
        stdout: StdioCollector { onStreamFinished: derive.done++ }
        stderr: StdioCollector { onStreamFinished: derive.done++ }
        onExited: (exitCode, exitStatus) => {
            code = exitCode;
            done++;
        }
    }

    Process {
        id: applyProc

        property string target: ""
        property var tokens: null
        property int code: 0
        property int done: 0
        onDoneChanged: if (done === 2) root.applied()

        command: [root.cli, "apply", target]
        stderr: StdioCollector { onStreamFinished: applyProc.done++ }
        onExited: (exitCode, exitStatus) => {
            code = exitCode;
            done++;
        }
    }

    Connections {
        target: Theme
        enabled: root.settling !== null
        function onFileTokensChanged() { root.settleCheck(); }
    }
    Connections {
        target: WallpaperState
        enabled: root.settling !== null
        function onFilePathChanged() { root.settleCheck(); }
    }
    Timer {
        id: applyTimer
        interval: root.applyTimeout
        onTriggered: root.applyTimedOut()
    }
    Timer {
        id: settleTimer
        interval: 3000
        onTriggered: root.finishSettle()
    }

    LazyLoader {
        id: loader
        active: false

        PanelWindow {
            id: win

            property var files: []      // [{path, name}] sorted by name
            property int sel: 0
            property bool loaded: false // the folder has been read once
            // Thumbnails that failed to decode: not retried while open, so each bad
            // file logs Qt's one decode warning once, not on every move.
            property var badThumbs: ({})
            readonly property int count: files.length
            readonly property var cur: count > 0 ? files[sel] : null
            readonly property var result: cur ? root.results[cur.path] ?? null : null
            readonly property real e: root.px
            readonly property real dpr: screen ? screen.devicePixelRatio : 1

            // Thumbnail layout of the render: four 9em items and one 16em item, .7em
            // gaps, filling the strip's inner width (sizes never depend on the count).
            readonly property real gap: Math.round(e * 0.7)
            readonly property real innerW: card.width - 2 * Math.round(e * 0.9)
            readonly property int smallW: Math.max(40, Math.floor((innerW - 4 * gap) / (4 + 16 / 9)))
            readonly property int bigW: Math.round(smallW * 16 / 9)
            readonly property int bigH: Math.round((bigW - 2) * 9 / 16) + 2

            // Distinct neighbours only: 5 slots, fewer when there are fewer images.
            readonly property var offsets: {
                const n = Math.min(count, 5);
                const left = Math.floor((n - 1) / 2);
                const out = [];
                for (let d = -left; d < n - left; d++)
                    out.push(d);
                return out;
            }

            function move(d) {
                if (count < 2 || root.applying)
                    return;
                sel = (sel + d + count) % count;
                root.want(files[sel].path);
            }

            function rebuild() {
                const out = [];
                for (let i = 0; i < folderModel.count; i++)
                    out.push({ path: folderModel.get(i, "filePath"), name: folderModel.get(i, "fileName") });
                const keep = loaded ? (cur ? cur.path : "") : WallpaperState.filePath;
                const old = sel;
                loaded = true;
                files = out;
                if (out.length === 0) {
                    sel = 0;
                    root.wanted = "";
                    return;
                }
                let i = out.findIndex(f => f.path === keep);
                if (i < 0)
                    i = Math.min(old, out.length - 1);
                sel = i;
                if (out[i].path !== root.wanted)
                    root.want(out[i].path);
            }

            function toUrl(p) {
                return "file://" + p.split("/").map(encodeURIComponent).join("/");
            }

            FolderListModel {
                id: folderModel
                folder: "file://" + root.folder
                nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
                caseSensitive: false
                showDirs: false
                showDotAndDotDot: false
                sortField: FolderListModel.Name
                sortCaseSensitive: false
                onStatusChanged: if (status === FolderListModel.Ready) win.rebuild()
                onCountChanged: if (status === FolderListModel.Ready) win.rebuild()
            }

            screen: root.targetScreen
            anchors { bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            implicitHeight: card.height + margin
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.grab ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            WlrLayershell.namespace: "rice-carousel"

            readonly property int margin: Math.round(e * 0.45)

            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape)
                        root.cancel();
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        root.apply();
                    else if (event.key === Qt.Key_Left)
                        win.move(-1);
                    else if (event.key === Qt.Key_Right)
                        win.move(1);
                    else
                        return;
                    event.accepted = true;
                }
            }

            Chamfer {
                id: card
                x: win.margin
                width: win.width - 2 * win.margin
                y: 0
                height: body.implicitHeight + Math.round(win.e * 0.5) + Math.round(win.e * 0.8)
                cut: Math.round(win.e)
                stroke: Theme.a1
                fill: Theme.bg

                Column {
                    id: body
                    x: Math.round(win.e * 0.9)
                    y: Math.round(win.e * 0.5)
                    width: win.innerW
                    spacing: 0

                    // Empty folder: the single line.
                    Text {
                        visible: win.loaded && win.count === 0
                        text: "no wallpapers in ~/Pictures/wallpapers"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: win.e
                    }

                    // Header: WALLPAPER // <name>   <WxH · ext · keys>
                    Item {
                        visible: win.count > 0
                        width: parent.width
                        height: visible ? headLeft.implicitHeight + Math.round(win.e * 0.55) : 0

                        Row {
                            id: headLeft
                            width: Math.min(implicitWidth, parent.width - headRight.implicitWidth - win.e)
                            clip: true
                            Text {
                                text: "WALLPAPER // "
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: win.e
                                font.letterSpacing: win.e * 0.06
                            }
                            Text {
                                text: win.cur ? win.cur.name : ""
                                textFormat: Text.PlainText
                                color: Theme.a1
                                font.family: Theme.font
                                font.pixelSize: win.e
                                font.weight: Font.Medium
                                font.letterSpacing: win.e * 0.06
                            }
                        }
                        Text {
                            id: headRight
                            anchors.right: parent.right
                            text: {
                                const parts = [];
                                if (win.result && win.result.ok && win.result.dims)
                                    parts.push(win.result.dims);
                                const name = win.cur ? win.cur.name : "";
                                const dot = name.lastIndexOf(".");
                                if (dot > 0)
                                    parts.push(name.slice(dot + 1).toLowerCase());
                                if (!root.grab) {  // timed out: the keys no longer reach it
                                    parts.push("ctrl+alt+w close");
                                    return parts.join(" · ");
                                }
                                if (win.count > 1)
                                    parts.push("←/→ select");
                                if (!win.result || win.result.ok)
                                    parts.push("⏎ apply");
                                parts.push("esc cancel");
                                return parts.join(" · ");
                            }
                            textFormat: Text.PlainText  // holds the file's extension
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: win.e
                            font.letterSpacing: win.e * 0.06
                        }
                    }

                    // The strip: bottom-aligned, centred.
                    Item {
                        visible: win.count > 0
                        width: parent.width
                        height: visible ? win.bigH : 0

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            spacing: win.gap

                            Repeater {
                                model: win.offsets

                                Item {
                                    id: thumb

                                    required property int modelData
                                    readonly property bool on: modelData === 0
                                    readonly property int idx: win.count > 0 ? ((win.sel + modelData) % win.count + win.count) % win.count : 0
                                    readonly property var file: win.count > 0 ? win.files[idx] : null
                                    readonly property bool bad: file !== null && win.badThumbs[file.path] === true
                                    readonly property real cut: Math.round(win.e * (on ? 0.8 : 0.5))
                                    readonly property real innerCut: Math.max(0, cut - (2 - Math.SQRT2))

                                    anchors.bottom: parent.bottom
                                    width: on ? win.bigW : win.smallW
                                    height: Math.round((width - 2) * 9 / 16) + 2
                                    opacity: on ? 1 : 0.6

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        color: Theme.panel
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: thumb.bad
                                        text: "✗"
                                        color: Theme.dim
                                        font.family: Theme.font
                                        font.pixelSize: win.e * 1.5
                                    }
                                    Image {
                                        id: img
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        // One decode size for every slot, so an image moving
                                        // between slots comes from the pixmap cache.
                                        sourceSize: Qt.size(Math.ceil((win.bigW - 2) * win.dpr), Math.ceil((win.bigH - 2) * win.dpr))
                                        source: thumb.file && !thumb.bad ? win.toUrl(thumb.file.path) : ""
                                        onStatusChanged: {
                                            if (status === Image.Error && thumb.file) {
                                                const next = Object.assign({}, win.badThumbs);
                                                next[thumb.file.path] = true;
                                                win.badThumbs = next;
                                            }
                                        }
                                    }

                                    // Frame: the 1px ring (a1 -> a2 when selected, line
                                    // otherwise) and the cut corners painted in the strip's
                                    // fill, so the image is clipped to the chamfer.
                                    Shape {
                                        anchors.fill: parent
                                        preferredRendererType: Shape.CurveRenderer

                                        ShapePath {
                                            strokeWidth: -1
                                            fillColor: Theme.bg
                                            startX: 0; startY: 0
                                            PathLine { x: thumb.cut; y: 0 }
                                            PathLine { x: 0; y: thumb.cut }
                                            PathLine { x: 0; y: 0 }
                                            PathMove { x: thumb.width; y: thumb.height }
                                            PathLine { x: thumb.width - thumb.cut; y: thumb.height }
                                            PathLine { x: thumb.width; y: thumb.height - thumb.cut }
                                            PathLine { x: thumb.width; y: thumb.height }
                                        }
                                        ShapePath {
                                            strokeWidth: -1
                                            fillRule: ShapePath.OddEvenFill
                                            fillColor: Theme.line
                                            fillGradient: thumb.on ? hot : null
                                            startX: thumb.cut; startY: 0
                                            PathLine { x: thumb.width; y: 0 }
                                            PathLine { x: thumb.width; y: thumb.height - thumb.cut }
                                            PathLine { x: thumb.width - thumb.cut; y: thumb.height }
                                            PathLine { x: 0; y: thumb.height }
                                            PathLine { x: 0; y: thumb.cut }
                                            PathLine { x: thumb.cut; y: 0 }
                                            PathMove { x: 1 + thumb.innerCut; y: 1 }
                                            PathLine { x: thumb.width - 1; y: 1 }
                                            PathLine { x: thumb.width - 1; y: thumb.height - 1 - thumb.innerCut }
                                            PathLine { x: thumb.width - 1 - thumb.innerCut; y: thumb.height - 1 }
                                            PathLine { x: 1; y: thumb.height - 1 }
                                            PathLine { x: 1; y: 1 + thumb.innerCut }
                                            PathLine { x: 1 + thumb.innerCut; y: 1 }
                                        }
                                    }
                                    LinearGradient {
                                        id: hot
                                        x1: 0; y1: thumb.height
                                        x2: thumb.width; y2: 0
                                        GradientStop { position: 0; color: Theme.a1 }
                                        GradientStop { position: 1; color: Theme.a2 }
                                    }

                                    // Index tag (top right) and name (bottom left), selected only.
                                    Rectangle {
                                        visible: thumb.on
                                        anchors { right: parent.right; top: parent.top; margins: 1 }
                                        width: ix.implicitWidth + Math.round(win.e * 0.8 * 0.5) * 2
                                        height: ix.implicitHeight
                                        color: Theme.a1
                                        Text {
                                            id: ix
                                            anchors.centerIn: parent
                                            text: String(thumb.idx + 1).padStart(2, "0")
                                            color: Theme.bg
                                            font.family: Theme.font
                                            font.pixelSize: Math.round(win.e * 0.8)
                                            font.bold: true
                                        }
                                    }
                                    Rectangle {
                                        visible: thumb.on
                                        anchors { left: parent.left; bottom: parent.bottom; margins: 1 }
                                        width: Math.min(nm.implicitWidth, thumb.width * 0.7) + Math.round(win.e * 0.85 * 0.6) * 2
                                        height: nm.implicitHeight
                                        color: Theme.bg
                                        Text {
                                            id: nm
                                            anchors.centerIn: parent
                                            width: Math.min(implicitWidth, thumb.width * 0.7)
                                            text: {
                                                const n = thumb.file ? thumb.file.name : "";
                                                const dot = n.lastIndexOf(".");
                                                return dot > 0 ? n.slice(0, dot) : n;
                                            }
                                            textFormat: Text.PlainText
                                            elide: Text.ElideRight
                                            color: Theme.fg
                                            font.family: Theme.font
                                            font.pixelSize: Math.round(win.e * 0.85)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Footer: palette swatches (or the error) and page ticks.
                    Item {
                        visible: win.count > 0
                        width: parent.width
                        height: visible ? Math.round(win.e * 0.6) + footLeft.implicitHeight : 0

                        Row {
                            id: footLeft
                            anchors.bottom: parent.bottom
                            spacing: Math.round(win.e * 0.3)
                            width: Math.min(implicitWidth, parent.width - ticks.width - win.e)
                            clip: true

                            readonly property string error: root.applyError === "timed out" ? "apply timed out"
                                : root.applyError !== "" ? "apply failed: " + root.applyError
                                : win.result && !win.result.ok ? win.result.error : ""

                            Text {
                                text: footLeft.error !== "" ? "✗ " + footLeft.error
                                    : win.result ? "PALETTE" : "PALETTE  deriving…"
                                textFormat: Text.PlainText
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: win.e
                            }
                            Repeater {
                                model: footLeft.error === "" && win.result && win.result.ok ? ["bg", "a1", "a2", "fg", "dim", "warn"] : []

                                Rectangle {
                                    required property string modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.round(win.e * 1.5) + 2
                                    height: Math.round(win.e * 0.8) + 2
                                    color: win.result && win.result.ok ? win.result.tokens[modelData] : Theme.bg
                                    border.width: 1
                                    border.color: Theme.line
                                }
                            }
                        }

                        Row {
                            id: ticks
                            anchors.right: parent.right
                            anchors.verticalCenter: footLeft.verticalCenter
                            spacing: Math.round(win.e * 0.25)

                            readonly property int maxTicks: 24
                            readonly property int n: Math.min(win.count, maxTicks)
                            readonly property int on: win.count <= maxTicks ? win.sel
                                : Math.round(win.sel * (maxTicks - 1) / (win.count - 1))

                            Repeater {
                                model: ticks.n

                                Rectangle {
                                    required property int index
                                    width: Math.round(win.e * 1.6)
                                    height: 2
                                    color: index === ticks.on ? Theme.a1 : Theme.line
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
