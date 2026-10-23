pragma Singleton
// System stats for the bar and rail (spec 5.3). One shared 2 s timer re-reads
// /proc/stat, /proc/meminfo and the AMD GPU's gpu_busy_percent through FileViews (no
// process spawns). The AMD card is found once at start by probing
// /sys/class/drm/card<N>/device/vendor for 0x1002; nothing else of any other card is
// ever read, so the NVIDIA chip (0x10de) is never woken and nvidia-smi never runs.
// netConn comes from nmcli every 5 s (failure or no connection: ""; nmcli missing:
// polling stops). A file that fails keeps the last good value (gpu: -1) and logs one
// warning, not one per tick.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property real cpu: 0       // 0-100, busy share between the last two samples
    property real memGb: 0     // used = MemTotal - MemAvailable, GiB
    property real memPct: 0    // 0-100
    property real gpu: -1      // 0-100, -1 when there is no readable AMD sysfs file
    property string netConn: "" // active connection name, "" when none

    // Sources. Plain properties so a test config can point them elsewhere.
    property string statPath: "/proc/stat"
    property string memPath: "/proc/meminfo"
    property string gpuPath: ""  // set by the vendor probe below

    property var lastCpu: null   // {total, idle} of the previous sample
    property var warned: ({})    // one warning per source

    function warnOnce(key, msg) {
        if (warned[key])
            return;
        warned[key] = true;
        console.warn("Stats:", msg);
    }

    // "cpu  user nice system idle iowait irq softirq steal guest guest_nice":
    // returns {total, idle} (guest is already counted in user), or null.
    function parseStat(text) {
        const line = String(text).split("\n").find(l => /^cpu\s/.test(l));
        if (!line)
            return null;
        const f = line.trim().split(/\s+/).slice(1, 9).map(Number);
        if (f.length < 4 || f.some(isNaN))
            return null;
        const total = f.reduce((a, b) => a + b, 0);
        return { total: total, idle: f[3] + (f[4] || 0) };
    }

    // Busy percent between two parseStat samples, or null when there is no delta.
    function cpuPercent(prev, cur) {
        if (!prev || !cur)
            return null;
        const dt = cur.total - prev.total;
        if (dt <= 0)
            return null;
        return Math.max(0, Math.min(100, 100 * (dt - (cur.idle - prev.idle)) / dt));
    }

    // /proc/meminfo -> {gb, pct} from MemTotal and MemAvailable (kB), or null.
    function parseMem(text) {
        const kb = key => {
            const m = String(text).match(new RegExp("^" + key + ":\\s+(\\d+)", "m"));
            return m ? Number(m[1]) : NaN;
        };
        const total = kb("MemTotal");
        const avail = kb("MemAvailable");
        if (!(total > 0) || isNaN(avail))
            return null;
        const used = Math.max(0, total - avail);
        return { gb: used / 1048576, pct: 100 * used / total };
    }

    // gpu_busy_percent content -> 0-100, or -1.
    function parseGpu(text) {
        const v = parseInt(String(text).trim(), 10);
        return isNaN(v) ? -1 : Math.max(0, Math.min(100, v));
    }

    // `nmcli -t -f NAME,TYPE connection show --active` -> first non-loopback name.
    // Terse mode escapes ':' and '\' in values with a backslash.
    function parseNmcli(text) {
        for (const line of String(text).split("\n")) {
            if (line === "")
                continue;
            const fields = [];
            let cur = "";
            for (let i = 0; i < line.length; i++) {
                const c = line[i];
                if (c === "\\" && i + 1 < line.length) {
                    cur += line[++i];
                } else if (c === ":") {
                    fields.push(cur);
                    cur = "";
                } else {
                    cur += c;
                }
            }
            fields.push(cur);
            if (fields[0] !== "" && fields[1] !== "loopback")
                return fields[0];
        }
        return "";
    }

    Timer {
        // No triggeredOnStart: each FileView's preload takes the first sample, and a
        // reload() while that load is in flight would drop it.
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            statFile.reload();
            memFile.reload();
            if (root.gpuPath !== "")
                gpuFile.reload();
        }
    }

    FileView {
        id: statFile
        path: root.statPath
        printErrors: false
        onLoaded: {
            const cur = root.parseStat(text());
            if (!cur) {
                root.warnOnce("stat", "cannot parse " + path);
                return;
            }
            const pct = root.cpuPercent(root.lastCpu, cur);
            if (pct !== null)
                root.cpu = pct;
            root.lastCpu = cur;
        }
        onLoadFailed: error => root.warnOnce("stat", "cannot read " + path + " (" + FileViewError.toString(error) + ")")
    }

    FileView {
        id: memFile
        path: root.memPath
        printErrors: false
        onLoaded: {
            const m = root.parseMem(text());
            if (!m) {
                root.warnOnce("mem", "cannot parse " + path);
                return;
            }
            root.memGb = m.gb;
            root.memPct = m.pct;
        }
        onLoadFailed: error => root.warnOnce("mem", "cannot read " + path + " (" + FileViewError.toString(error) + ")")
    }

    FileView {
        id: gpuFile
        path: root.gpuPath
        printErrors: false
        onLoaded: root.gpu = root.parseGpu(text())
        onLoadFailed: error => {
            root.gpu = -1;
            root.warnOnce("gpu", "cannot read " + path + " (" + FileViewError.toString(error) + ")");
        }
    }
    onGpuPathChanged: if (gpuPath === "") gpu = -1

    // One-time AMD card lookup: card0 .. card15, first vendor 0x1002 wins. Only the
    // `vendor` file of each card is read here.
    property int probeCard: 0
    readonly property int probeLimit: 16
    FileView {
        id: vendorProbe
        path: root.probeCard < root.probeLimit ? "/sys/class/drm/card" + root.probeCard + "/device/vendor" : ""
        printErrors: false
        onLoaded: {
            // Path changes are deferred: changing it inside its own handler drops
            // the operation that is finishing (quickshell.io.fileview warning).
            const card = root.probeCard;
            if (text().trim() === "0x1002")
                Qt.callLater(() => {
                    root.gpuPath = "/sys/class/drm/card" + card + "/device/gpu_busy_percent";
                    root.probeCard = root.probeLimit;
                });
            else
                Qt.callLater(() => root.probeCard = card + 1);
        }
        onLoadFailed: {
            const card = root.probeCard;
            Qt.callLater(() => root.probeCard = card + 1);
        }
    }

    // nmcli poll. If the previous run never started (binary missing; Quickshell logs
    // that once), polling stops instead of warning every 5 s.
    property bool nmPending: false
    Timer {
        id: nmTimer
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.nmPending) {
                running = false;
                root.netConn = "";
                root.warnOnce("nmcli", "nmcli could not be started; NET polling stopped");
                return;
            }
            root.nmPending = true;
            nmcli.running = true;
        }
    }

    Process {
        id: nmcli
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"]
        onStarted: root.nmPending = false
        stdout: StdioCollector {
            // Empty output (failure, no connection) gives "".
            onStreamFinished: root.netConn = root.parseNmcli(text)
        }
        stderr: StdioCollector {} // swallowed: "NetworkManager is not running" etc.
    }
}
