// Rail CLAUDE section (render .row3 .sg .rst): `// CLAUDE ─── 2m ago`, then `5H` and
// `7D` as inline StatRows `LABEL [10 segments] NN%` (the rail's row size, warn above 75)
// each with a dim `resets in 2h 14m` line under its bar (`resets Mon 09:00`, weekday and
// local time, beyond 24 h).
// Data: ~/.cache/claude-limits.json, written atomically by claude-limits-statusline
// (spec 5.6, limits.py): {"five_hour": {"pct": N, "resets_at": N} | null,
// "seven_day": ... | null, "updated_at": N}, unix seconds.
// - Missing, unreadable, unparsable, not an object, or both windows null/absent:
//   one dim `no data` line (the section stays visible).
// - One window null: only the other row. A window whose resets_at has passed shows
//   `no data` in its own row. Percentages are clamped to 0..100.
// - Older than 30 minutes (or an updated_at that is missing or in the future): the
//   bars and numbers are drawn in Theme.dim.
// One 30 s timer, running only while the section is visible, refreshes the age and
// reset texts and re-reads the file while it is missing (a FileView watch does not see
// a file that is created after it was set up).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

ColumnLayout {
    id: root

    property real px: Theme.px
    property real rowPx: Math.round(px * 1.5)
    property string cachePath: Quickshell.env("HOME") + "/.cache/claude-limits.json"
    readonly property int staleAfter: 30 * 60

    property real now: Date.now() / 1000
    // parse() result of the current file; null while the file cannot be read.
    property var limits: null
    property bool readable: false

    function finite(v) {
        return typeof v === "number" && isFinite(v);
    }

    // Pure: file text -> {five, seven, updated} (windows null when absent or invalid),
    // or null when the text is not a JSON object.
    function parse(text) {
        let obj;
        try {
            obj = JSON.parse(text);
        } catch (e) {
            return null;
        }
        if (obj === null || typeof obj !== "object" || Array.isArray(obj))
            return null;
        const win = w => (w !== null && typeof w === "object" && finite(w.pct) && finite(w.resets_at))
            ? { pct: Math.max(0, Math.min(100, w.pct)), resets: w.resets_at } : null;
        return { five: win(obj.five_hour), seven: win(obj.seven_day), updated: finite(obj.updated_at) ? obj.updated_at : NaN };
    }

    // Seconds -> `12s`, `5m`, `2h`, `3d` (floored).
    function ageText(s) {
        s = Math.max(0, Math.floor(s));
        if (s < 60)
            return s + "s";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        if (s < 86400)
            return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }

    // `resets in 2h 14m` / `resets in 14m` / `resets in <1m`; `resets Mon 09:00` beyond 24 h.
    function resetText(resets, now) {
        const d = resets - now;
        if (d >= 86400)
            return "resets " + Qt.locale("C").toString(new Date(resets * 1000), "ddd HH:mm");
        const h = Math.floor(d / 3600), m = Math.floor((d % 3600) / 60);
        if (h > 0)
            return "resets in " + h + "h " + m + "m";
        return m > 0 ? "resets in " + m + "m" : "resets in <1m";
    }

    readonly property bool noData: limits === null || (limits.five === null && limits.seven === null)
    readonly property real age: limits && root.finite(limits.updated) ? now - limits.updated : NaN
    // A clock skew of up to a minute counts as fresh; beyond that the age is unknown.
    readonly property bool future: age < -60
    readonly property bool stale: !(age <= staleAfter) || future
    readonly property string note: noData || isNaN(age) ? "" : (future ? "future" : ageText(age) + " ago")
    readonly property var rows: noData ? [] : [
        { label: "5H", w: limits.five },
        { label: "7D", w: limits.seven }
    ].filter(r => r.w !== null)

    spacing: Math.round(px * 0.6)

    FileView {
        id: cache
        path: root.cachePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.now = Date.now() / 1000;
            root.readable = true;
            root.limits = root.parse(text());
        }
        onLoadFailed: error => {
            root.readable = false;
            root.limits = null;
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.visible
        onTriggered: {
            root.now = Date.now() / 1000;
            if (!root.readable)
                cache.reload();
        }
    }

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.3)
        px: root.px
        text: "claude"
        note: root.note
    }

    EmptyNote {
        visible: root.noData
        px: root.px
        text: "no data"
    }

    Repeater {
        model: root.rows

        ColumnLayout {
            id: win
            required property var modelData
            readonly property bool expired: modelData.w.resets <= root.now
            readonly property real pct: modelData.w.pct

            Layout.fillWidth: true
            spacing: 0

            StatRow {
                id: bar
                visible: !win.expired
                px: root.rowPx
                label: win.modelData.label
                value: win.pct
                text: Math.round(win.pct) + "%"
                litColor: root.stale ? Theme.dim : win.pct > 75 ? Theme.warn : Theme.a1
                valueColor: root.stale ? Theme.dim : Theme.fg
            }

            // An expired window: its label and `no data` in place of the bar.
            Item {
                visible: win.expired
                Layout.fillWidth: true
                implicitHeight: bar.rowHeight

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.modelData.label
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: bar.labelPx
                    font.letterSpacing: bar.labelPx * 0.12
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: bar.labelWidth + bar.gap
                    text: "no data"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Math.round(root.px * 1.1)
                }
            }

            Text {
                visible: !win.expired
                Layout.leftMargin: bar.labelWidth + bar.gap
                Layout.topMargin: -Math.round(root.px * 0.4)
                text: root.resetText(win.modelData.w.resets, root.now)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: root.px
                font.letterSpacing: root.px * 0.04
            }
        }
    }
}
