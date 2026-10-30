pragma Singleton
// System stats for the bar and rail (spec 5.3). One shared 2 s timer re-reads
// /proc/stat, /proc/meminfo, /proc/net/route, /proc/net/dev and the AMD GPU's
// gpu_busy_percent through FileViews. netConn is the interface of the default route
// (the render shows `wlan0`): this machine runs iwd + systemd-networkd, not
// NetworkManager. A file that fails keeps the last good value (gpu: -1) and logs one
// warning, not one per tick.
// Throughput (rail sparkline): bytes/s summed over every interface but `lo`, from the
// /proc/net/dev counter deltas between two ticks; netHistory keeps the last
// historyLength (up + down) samples, oldest first.
//
// GPU row source (gpuSource): by default the AMD iGPU's sysfs file (the chip that drives
// the display), else "none". The NVIDIA dGPU is OPT-IN with RICE_NVIDIA=1 in the
// environment: the session leaves the dGPU runtime-suspended most of the time, and the
// stream below keeps it awake while the shell runs. The cards are found once at start by
// reading only the `vendor` file of each /sys/class/drm/card<N>/device (0x10de NVIDIA,
// 0x1002 AMD). With RICE_NVIDIA=1, NVIDIA is used only if that card's
// power/runtime_status reads exactly "active"
// (reading it never wakes the card): then ONE long-lived `nvidia-smi -l 2
// --query-gpu=...` stream runs (no process per tick) and each line updates gpu and the
// VRAM values. It runs under `setpriv --pdeathsig TERM` so it dies with the shell
// (Quickshell 0.3.1 leaves running children behind when it exits). Fallback to AMD when
// the card is not active, nvidia-smi is missing or exits before a valid line, or no
// valid line comes within nvStartTimeout. A stream that dies after valid lines falls
// back to AMD and is retried after nvBackoff (30, 60, 120, then every 300 s; back to
// 30 s only after a stream that lasted 300 s), each time only if the card is still
// active. All timing runs on the shared 2 s timer.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property real cpu: 0       // 0-100, busy share between the last two samples
    property real memGb: 0     // used = MemTotal - MemAvailable, GiB
    property real memPct: 0    // 0-100
    property real gpu: -1      // 0-100, -1 when no source has a value
    // "nvidia" (after the stream's first valid line) | "amd" | "none"
    readonly property string gpuSource: nvLive ? "nvidia" : (gpuPath !== "" ? "amd" : "none")
    property real vramUsedMb: -1   // NVIDIA only, MiB, -1 when unknown
    property real vramTotalMb: -1
    property real vramPct: -1      // 0-100, -1 when unknown
    property string netConn: "" // default-route interface, "" when there is none
    property real netUp: 0     // bytes/s sent, all non-loopback interfaces
    property real netDown: 0   // bytes/s received
    property list<real> netHistory: []  // up + down bytes/s, oldest first
    readonly property int historyLength: 24

    // Emitted on every shared 2 s tick (the Clock service follows it: no timer of its own).
    signal tick()

    // Sources. Plain properties so a test config can point them elsewhere.
    property string statPath: "/proc/stat"
    property string memPath: "/proc/meminfo"
    property string routePath: "/proc/net/route"
    property string netDevPath: "/proc/net/dev"
    property string gpuPath: ""  // set by the vendor probe below
    property string drmRoot: "/sys/class/drm"   // where the vendor probe looks for cards
    // NVIDIA: the card's runtime_status (set by the probe, only with the opt-in, unless
    // already set), the
    // command, the start timeout and the retry back-off (a test config may change them).
    property string nvStatusPath: ""
    property string nvSmiCommand: "nvidia-smi"
    property int nvStartTimeout: 6000
    property list<int> nvBackoff: [30000, 60000, 120000, 300000]
    readonly property bool nvAllowed: Quickshell.env("RICE_NVIDIA") === "1"

    property var lastCpu: null   // {total, idle} of the previous sample
    property var lastNet: null   // {rx, tx, t} of the previous sample (t in ms)
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

    // One nvidia-smi line "util, used, total" (csv, noheader, nounits; MiB) ->
    // {gpu, used, total, pct}, each -1 when unknown ("[N/A]", "[Not Supported]", ...),
    // or null when the line has fewer than three fields or no number at all. Extra
    // columns are ignored; a decimal comma ("1024,5") is accepted when the fields are
    // separated by ", " as nvidia-smi prints them.
    function parseNvLine(text) {
        const line = String(text).trim();
        let f = line.split(/,\s+/);
        if (f.length < 3)
            f = line.split(",");
        if (f.length < 3)
            return null;
        const num = s => {
            const t = s.trim().replace(",", ".");
            return /^\d+(\.\d+)?$/.test(t) ? Number(t) : -1;
        };
        const gpu = num(f[0]), used = num(f[1]), total = num(f[2]);
        if (gpu < 0 && used < 0 && total < 0)
            return null;
        return {
            gpu: gpu < 0 ? -1 : Math.min(100, gpu),
            used: used,
            total: total,
            pct: used >= 0 && total > 0 ? Math.min(100, 100 * used / total) : -1
        };
    }

    // /proc/net/route -> interface of the default route: Destination 00000000 with
    // RTF_UP (0x1) in Flags; the lowest Metric wins. "" when there is none. Lines
    // that do not have the expected fields are skipped.
    function parseRoute(text) {
        let best = null;
        for (const line of String(text).split("\n").slice(1)) {
            const f = line.trim().split(/\s+/);
            if (f.length < 8 || f[1] !== "00000000")
                continue;
            const flags = parseInt(f[3], 16);
            const metric = Number(f[6]);
            if (isNaN(flags) || !(flags & 1) || isNaN(metric))
                continue;
            if (best === null || metric < best.metric)
                best = { iface: f[0], metric: metric };
        }
        return best ? best.iface : "";
    }

    // /proc/net/dev -> {rx, tx} byte counters summed over every interface except lo,
    // or null when no interface line parses.
    function parseNetDev(text) {
        let rx = 0, tx = 0, n = 0;
        for (const line of String(text).split("\n")) {
            const colon = line.indexOf(":");
            if (colon < 0)
                continue;
            const name = line.slice(0, colon).trim();
            const f = line.slice(colon + 1).trim().split(/\s+/).map(Number);
            if (name === "" || name.includes("|") || f.length < 16 || isNaN(f[0]) || isNaN(f[8]))
                continue;
            n++;
            if (name === "lo")
                continue;
            rx += f[0];
            tx += f[8];
        }
        return n > 0 ? { rx: rx, tx: tx } : null;
    }

    // Two parseNetDev samples {rx, tx, t(ms)} -> {up, down} bytes/s, or null when there
    // is no usable delta (first sample, no time passed, or a counter went backwards
    // because an interface vanished or was reset).
    function netRates(prev, cur) {
        if (!prev || !cur)
            return null;
        const dt = (cur.t - prev.t) / 1000;
        const drx = cur.rx - prev.rx, dtx = cur.tx - prev.tx;
        if (!(dt > 0) || drx < 0 || dtx < 0)
            return null;
        return { up: dtx / dt, down: drx / dt };
    }

    // bytes/s -> compact "512B" / "8.4K" / "120K" / "1.2M" / "3.0G" (1024 steps).
    function compactRate(v) {
        if (!(v >= 0))
            return "0B";
        const units = ["B", "K", "M", "G"];
        let i = 0;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        if (i === 0)
            return Math.round(v) + "B";
        return (v < 10 ? v.toFixed(1) : Math.round(v)) + units[i];
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
            routeFile.reload();
            netDevFile.reload();
            if (root.gpuPath !== "" && !root.nvLive)
                gpuFile.reload();
            root.nvTick(Date.now());
            root.tick();
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
        id: routeFile
        path: root.routePath
        printErrors: false
        onLoaded: root.netConn = root.parseRoute(text())
        onLoadFailed: error => root.warnOnce("route", "cannot read " + path + " (" + FileViewError.toString(error) + ")")
    }

    FileView {
        id: netDevFile
        path: root.netDevPath
        printErrors: false
        onLoaded: {
            const c = root.parseNetDev(text());
            if (!c) {
                root.warnOnce("netdev", "cannot parse " + path);
                return;
            }
            const cur = { rx: c.rx, tx: c.tx, t: Date.now() };
            const r = root.netRates(root.lastNet, cur);
            root.lastNet = cur;
            if (r === null)
                return;
            root.netUp = r.up;
            root.netDown = r.down;
            const h = root.netHistory.slice(-(root.historyLength - 1));
            h.push(r.up + r.down);
            root.netHistory = h;
        }
        onLoadFailed: error => root.warnOnce("netdev", "cannot read " + path + " (" + FileViewError.toString(error) + ")")
    }

    FileView {
        id: gpuFile
        path: root.gpuPath
        printErrors: false
        onLoaded: if (!root.nvLive) root.gpu = root.parseGpu(text())
        onLoadFailed: error => {
            if (!root.nvLive)
                root.gpu = -1;
            root.warnOnce("gpu", "cannot read " + path + " (" + FileViewError.toString(error) + ")");
        }
    }
    onGpuPathChanged: if (gpuPath === "" && !nvLive) gpu = -1

    // One-time card lookup: card0 .. card15 under drmRoot; the first vendor 0x1002 (AMD)
    // and the first 0x10de (NVIDIA) win. Only the `vendor` file of each card is read here;
    // the NVIDIA card's runtime_status path is kept only with the opt-in (RICE_NVIDIA=1).
    property int probeCard: 0
    readonly property int probeLimit: 16
    property string probeAmd: ""
    property string probeNv: ""
    FileView {
        id: vendorProbe
        path: root.probeCard < root.probeLimit ? root.drmRoot + "/card" + root.probeCard + "/device/vendor" : ""
        printErrors: false
        onLoaded: {
            // Path changes are deferred: changing it inside its own handler drops
            // the operation that is finishing (quickshell.io.fileview warning).
            const card = root.probeCard;
            const dev = root.drmRoot + "/card" + card + "/device/";
            const vendor = text().trim();
            if (vendor === "0x1002" && root.probeAmd === "")
                root.probeAmd = dev + "gpu_busy_percent";
            else if (vendor === "0x10de" && root.probeNv === "")
                root.probeNv = dev + "power/runtime_status";
            Qt.callLater(() => root.probeCard = card + 1);
        }
        onLoadFailed: {
            const card = root.probeCard;
            Qt.callLater(() => root.probeCard = card + 1);
        }
    }
    onProbeCardChanged: {
        if (probeCard !== probeLimit)
            return;
        if (probeAmd !== "" && gpuPath === "")
            gpuPath = probeAmd;
        if (!nvAllowed)
            return;   // default: no NVIDIA status path, nothing of the card read
        if (probeNv !== "" && nvStatusPath === "")
            nvStatusPath = probeNv;
        if (nvStatusPath !== "")
            nvCheck();
    }

    // --- NVIDIA stream -----------------------------------------------------------------
    // nvState: "off" (not used, or given up), "checking" (reading runtime_status),
    // "starting" (stream up, no valid line yet), "live", "waiting" (back-off).
    property string nvState: "off"
    readonly property bool nvLive: nvState === "live"
    property bool nvRetrying: false   // the current attempt is a back-off retry
    property int nvRetries: 0         // back-off step of the next retry
    property real nvDeadline: 0       // ms: start timeout, or when the retry is due
    property real nvLiveSince: 0      // ms: first valid line of the current stream
    property int nvExitCode: -1

    function nvCheck() {
        nvState = "checking";
        nvStatusFile.reload();
    }

    // runtime_status read: start only when it is exactly "active".
    function nvStatusRead(status) {
        if (nvState !== "checking")
            return;
        if (status === "active") {
            nvExitCode = -1;
            nvState = "starting";
            nvDeadline = Date.now() + nvStartTimeout;
            nvProc.running = true;
        } else if (nvRetrying) {
            nvWait();   // asleep now: never wake it; look again at the next step
        } else {
            nvState = "off";
        }
    }

    // Schedule the next retry.
    function nvWait() {
        nvState = "waiting";
        nvDeadline = Date.now() + nvBackoff[Math.min(nvRetries, nvBackoff.length - 1)];
        nvRetries++;
    }

    // Back to AMD (or none): clear the NVIDIA-only values, re-read the AMD file now.
    function nvFallback() {
        vramUsedMb = -1;
        vramTotalMb = -1;
        vramPct = -1;
        gpu = -1;
        if (gpuPath !== "")
            gpuFile.reload();
    }

    function nvLine(data) {
        if (nvState !== "starting" && nvState !== "live")
            return;
        const v = parseNvLine(data);
        if (!v)
            return;
        gpu = v.gpu;
        vramUsedMb = v.used;
        vramTotalMb = v.total;
        vramPct = v.pct;
        if (nvState === "starting") {
            nvState = "live";
            nvRetrying = false;
            nvLiveSince = Date.now();
        }
    }

    // The stream ended: exit, kill, or spawn failure.
    function nvStopped() {
        const was = nvState;
        if (was !== "starting" && was !== "live")
            return;   // stopped on purpose (start timeout)
        if (was === "live") {
            nvFallback();
            // A stream that ran at least the longest step starts the back-off over;
            // one that keeps dying soon after starting backs off further each time.
            if (Date.now() - nvLiveSince >= nvBackoff[nvBackoff.length - 1])
                nvRetries = 0;
            warnOnce("nv-died", "nvidia-smi stream ended (exit " + nvExitCode + "); GPU row on AMD, retrying with back-off");
            nvRetrying = true;
            nvWait();
        } else if (nvExitCode === 127) {
            // setpriv could not find the command: expected without the NVIDIA tools.
            console.info("Stats: " + nvSmiCommand + " not found; GPU row on AMD");
            nvState = "off";
        } else {
            warnOnce("nv-start", "nvidia-smi exited (" + nvExitCode + ") before a valid line; GPU row on AMD");
            if (nvRetrying)
                nvWait();
            else
                nvState = "off";
        }
    }

    // On every shared tick: the start timeout and a due retry.
    function nvTick(now) {
        if (nvState === "starting" && now >= nvDeadline) {
            warnOnce("nv-timeout", "no valid nvidia-smi line within " + nvStartTimeout + " ms; GPU row on AMD");
            const retry = nvRetrying;
            nvState = "off";   // nvStopped ignores the exit this causes
            nvProc.running = false;
            if (retry)
                nvWait();
        } else if (nvState === "waiting" && now >= nvDeadline) {
            nvCheck();
        }
    }

    FileView {
        id: nvStatusFile
        path: root.nvStatusPath
        // Keep the default preload: with preload false, reload() never loads in
        // Quickshell 0.3.1 (seen in the rig: nvState stuck at "checking"). A reload()
        // while the path's preload is in flight still reports once (selftest 11 h/k).
        printErrors: false
        onLoaded: root.nvStatusRead(text().trim())
        onLoadFailed: root.nvStatusRead("")
    }

    Process {
        id: nvProc
        command: ["setpriv", "--pdeathsig", "TERM", "--", root.nvSmiCommand, "-l", "2",
            "--query-gpu=utilization.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"]
        stdout: SplitParser {
            onRead: data => root.nvLine(data)
        }
        onExited: code => root.nvExitCode = code
        // running drops to false on an exit and on a spawn failure (no exited then);
        // deferred so that exited has recorded the code first.
        onRunningChanged: if (!running) Qt.callLater(root.nvStopped)
    }
}
