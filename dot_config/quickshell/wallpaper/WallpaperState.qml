pragma Singleton
// The chosen wallpaper (spec 5.3): $HOME/.local/state/quickshell/wallpaper.json,
// {"path": "...", "palette": "..."}, watched and re-read when it changes. When the
// file is absent, empty or corrupt, or `path` is missing, not a string, empty or not
// absolute, `path` is the default $HOME/Pictures/berserk-wallpaper.jpg. A bad file
// logs one warning per change; an absent file is the normal first-run state and logs
// nothing. HOME comes from Quickshell.env so a staged HOME works.
// FileView's watch does not notice a file that did not exist when it was set up, so
// while the file is absent a slow timer re-checks it (it stops once the file exists;
// after the first `rice-palette apply` it always does). In-process writers (the
// carousel) call reload() right after writing.
// `ready` turns true once the state file was read (or found absent/unreadable); no
// Wallpaper loads anything before that, so the default image is never decoded (or
// reported missing) at startup only to be replaced by the chosen one.
// Preview (carousel): preview(path) shows another image without writing any file;
// clearPreview() goes back to the state file's choice. The displayed path is
// previewPath || filePath || defaultPath, so a state-file change during a preview is
// recorded and shows after clearPreview().
// Image verdict: the Wallpaper on the main screen loads a new path first and reports
// the result here; the other screens load it only after it decoded. So a path that is
// not an image (missing, a directory, a text file, unreadable) is tried exactly once,
// and the log gets exactly one warning for it (Qt's own `QML Image ... Cannot open` /
// `Error decoding` line), never one per screen, and nothing retries until it changes.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string statePath: home + "/.local/state/quickshell/wallpaper.json"
    readonly property string defaultPath: home + "/Pictures/berserk-wallpaper.jpg"

    property bool ready: false     // the state file has been read (or found absent)
    property string filePath: ""   // valid path from the state file, "" = use the default
    property string palette: ""    // informational; rice-palette owns the colours
    property string previewPath: "" // carousel preview, "" = none
    readonly property string path: previewPath || filePath || defaultPath

    // Verdict for `path` from the main screen's Wallpaper, set as one object so the
    // path and the state always change together: state 0 unknown/loading, 1 decoded,
    // -1 cannot be shown. Only meaningful while result.path === path.
    property var result: ({ path: "", state: 0 })
    readonly property string verdictPath: result.path
    readonly property int verdict: result.state

    property bool stateAbsent: false

    function reload() {
        stateFile.reload();
    }

    function preview(p) {
        if (typeof p !== "string" || !p.startsWith("/")) {
            console.warn("Wallpaper.preview: not an absolute path:", p);
            return;
        }
        previewPath = p;
    }

    function clearPreview() {
        previewPath = "";
    }

    // State file text -> {path, palette}; path "" when unusable. Never throws.
    function parse(text) {
        let obj = null;
        try {
            obj = JSON.parse(text);
        } catch (e) {
            return { path: "", palette: "", error: "cannot parse (" + e + ")" };
        }
        if (obj === null || typeof obj !== "object" || Array.isArray(obj))
            return { path: "", palette: "", error: "not a JSON object" };
        const pal = typeof obj.palette === "string" ? obj.palette : "";
        if (typeof obj.path !== "string" || !obj.path.startsWith("/"))
            return { path: "", palette: pal, error: "no absolute \"path\" string" };
        return { path: obj.path, palette: pal, error: "" };
    }

    function report(p, ok) {
        if (p !== path)
            return;  // a late result for a previous choice
        result = { path: p, state: ok ? 1 : -1 };
        if (!ok)
            console.info("Wallpaper: showing the background colour instead of", p);
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const r = root.parse(text());
            root.stateAbsent = false;
            if (r.error !== "")
                console.warn("Wallpaper:", path, r.error + ", using", root.defaultPath);
            root.filePath = r.path;
            root.palette = r.palette;
            root.ready = true;
        }
        onLoadFailed: error => {
            // Absent (first run) is normal; anything else is worth one line.
            root.stateAbsent = error === FileViewError.FileNotFound;
            if (!root.stateAbsent)
                console.warn("Wallpaper: cannot read", path, "(" + FileViewError.toString(error) + "), using", root.defaultPath);
            root.filePath = "";
            root.palette = "";
            root.ready = true;
        }
    }

    Timer {
        interval: 10000
        repeat: true
        running: root.stateAbsent
        onTriggered: stateFile.reload()
    }
}
