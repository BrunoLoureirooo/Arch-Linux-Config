pragma Singleton
// Palette, font and size for the whole shell. Every colour comes from here.
// Colours are read from colors.json next to shell.qml (written by rice-palette) and
// hot-reloaded when it changes. A missing, empty or corrupt file, or a missing or
// invalid key, keeps the built-in neon-rain value for that key and logs a warning.
// preview(tokens) overrides the colours in memory (carousel); clearPreview() undoes it.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var keys: ["bg", "panel", "line", "dim", "fg", "a1", "a2", "warn"]
    readonly property var defaults: ({
        bg: "#07070d", panel: "#0c0d16", line: "#1b1d30", dim: "#6a7399",
        fg: "#d7e3f0", a1: "#00f0ff", a2: "#ff2e88", warn: "#ffd23f"
    })

    // Valid tokens from colors.json, and the in-memory preview (null = none).
    property var fileTokens: ({})
    property var previewTokens: null

    readonly property color bg: tok("bg")
    readonly property color panel: tok("panel")
    readonly property color line: tok("line")
    readonly property color dim: tok("dim")
    readonly property color fg: tok("fg")
    readonly property color a1: tok("a1")
    readonly property color a2: tok("a2")
    readonly property color warn: tok("warn")

    readonly property string font: "JetBrainsMono Nerd Font Mono"
    readonly property real px: 12

    function valid(v) {
        return typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v);
    }

    function tok(k) {
        if (previewTokens && valid(previewTokens[k]))
            return previewTokens[k];
        if (valid(fileTokens[k]))
            return fileTokens[k];
        return defaults[k];
    }

    // Keep only valid keys; report the rest. Returns {tokens, bad}.
    function sanitize(obj) {
        const out = {};
        const bad = [];
        for (const k of keys) {
            if (obj && valid(obj[k]))
                out[k] = obj[k];
            else
                bad.push(k);
        }
        return { tokens: out, bad: bad };
    }

    function preview(tokens) {
        const s = sanitize(tokens);
        if (s.bad.length > 0)
            console.warn("Theme.preview: missing or invalid keys", s.bad.join(","), "- keeping current values for them");
        previewTokens = s.tokens;
    }

    function clearPreview() {
        previewTokens = null;
    }

    function load(text) {
        let obj;
        try {
            obj = JSON.parse(text);
        } catch (e) {
            console.warn("Theme: cannot parse", colorsFile.path, "(" + e + "), using default colours");
            fileTokens = ({});
            return;
        }
        if (obj === null || typeof obj !== "object" || Array.isArray(obj)) {
            console.warn("Theme:", colorsFile.path, "is not a JSON object, using default colours");
            fileTokens = ({});
            return;
        }
        const s = sanitize(obj);
        if (s.bad.length > 0)
            console.warn("Theme:", colorsFile.path, "missing or invalid keys", s.bad.join(","), "- using defaults for them");
        fileTokens = s.tokens;
        console.info("Theme: loaded", colorsFile.path);
    }

    FileView {
        id: colorsFile
        path: Quickshell.shellPath("colors.json")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.load(text())
        onLoadFailed: error => {
            console.warn("Theme: cannot read", path, "(" + FileViewError.toString(error) + "), using default colours");
            root.fileTokens = ({});
        }
    }
}
