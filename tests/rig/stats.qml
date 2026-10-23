// Stats / Screens / Workspaces probe (test config only, never part of production).
// Runs the production bars plus an IpcHandler, against the staged shell:
//   tests/rig/qs-run.sh start --entry tests/rig/stats.qml
//   qs-run.sh ipc call stats get             -> Stats values, main screen, bar slots
//   qs-run.sh ipc call stats parse           -> results of the pure parsers on fixtures
//   qs-run.sh ipc call stats click <screen> <slot>  -> Workspaces.focusSlot(slot) of that bar
//   qs-run.sh ipc call stats setPaths <stat> <mem> <gpu> <route>  -> point Stats elsewhere
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.bar
import qs.services

ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
        }
    }

    // One invisible Workspaces per screen, to read the slot state the bar draws.
    Variants {
        id: probes
        model: Quickshell.screens

        Item {
            required property var modelData
            readonly property alias ws: w
            Workspaces { id: w; screen: parent.modelData }
        }
    }

    IpcHandler {
        target: "stats"

        function get(): string {
            const slots = {};
            for (const p of probes.instances) {
                const w = p.ws;
                slots[p.modelData.name] = {
                    ids: w.workspaces.map(x => x.id),
                    active: w.activeId,
                    filled: w.current.filled,     // slot of the filled cell, 0 = none
                    targets: w.current.targets    // what a click on cells 1-5 focuses
                };
            }
            return JSON.stringify({
                cpu: Stats.cpu, memGb: Stats.memGb, memPct: Stats.memPct, gpu: Stats.gpu,
                netConn: Stats.netConn, gpuPath: Stats.gpuPath,
                main: Quickshell.screens.filter(s => Screens.isMain(s)).map(s => s.name),
                slots: slots
            });
        }

        function parse(): string {
            const s1 = Stats.parseStat("cpu  100 0 100 800 0 0 0 0 0 0\ncpu0 1 2 3 4\n");
            const s2 = Stats.parseStat("cpu  150 0 150 850 50 0 0 0 0 0\n");
            const hdr = "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n";
            const rt = (i, d, f, m) => i + "\t" + d + "\t0101A8C0\t" + f + "\t0\t0\t" + m + "\t00000000\t0\t0\t0\n";
            const w = probes.instances[0].ws;
            return JSON.stringify({
                stat: s1,
                cpu: Stats.cpuPercent(s1, s2),           // busy 100 of 200 -> 50
                cpuNoDelta: Stats.cpuPercent(s1, s1),     // null
                statBad: Stats.parseStat("garbage"),      // null
                mem: Stats.parseMem("MemTotal:       16000000 kB\nMemFree: 1 kB\nMemAvailable:    4000000 kB\n"),
                memBad: Stats.parseMem("MemTotal: x\n"),  // null
                gpu: Stats.parseGpu("17\n"), gpuBad: Stats.parseGpu(""),
                // /proc/net/route: default = Destination 00000000 with RTF_UP, lowest Metric
                route: Stats.parseRoute(hdr + rt("wlan0", "00000000", "0003", 600) + rt("wlan0", "0001A8C0", "0001", 600)),
                route2: Stats.parseRoute(hdr + rt("eth0", "00000000", "0003", 100) + rt("wlan0", "00000000", "0003", 50)
                                         + rt("tun0", "00000000", "0002", 1)),   // tun0 not up
                routeNone: Stats.parseRoute(hdr + rt("eth0", "0001A8C0", "0001", 100)),
                routeBad: Stats.parseRoute("garbage\n\t\t\nwlan0 00000000\n" + hdr + "eth0\t00000000\tzz\tqq\t0\t0\tx\n"),
                routeEmpty: Stats.parseRoute(""),
                slot: [1, 5, 11, 15, 21, 25, 6].map(id => w.slotOf(id)),
                // Workspaces.layout(ids on the monitor, active id) -> {base, targets, filled}
                wsNormal: w.layout([11, 12, 13, 14, 15], 12),
                wsMigrated: w.layout([11, 12, 13, 14, 15, 21, 22, 23, 24, 25], 23),
                wsLeftover: w.layout([3, 13], 13),
                wsLeftoverLow: w.layout([3, 13], 3),
                wsActive8: w.layout([8], 8),
                wsActive8Mixed: w.layout([8, 12], 8),
                wsEmpty: w.layout([], -1)
            });
        }

        // What a click on cell <slot> of <screen>'s bar runs (Workspaces.focusSlot).
        function click(screen: string, slot: int): void {
            for (const p of probes.instances)
                if (p.modelData.name === screen)
                    p.ws.focusSlot(slot);
        }

        function setPaths(stat: string, mem: string, gpu: string, route: string): void {
            Stats.statPath = stat;
            Stats.memPath = mem;
            Stats.gpuPath = gpu;
            Stats.routePath = route;
        }
    }
}
