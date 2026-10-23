// Stats / Screens / Workspaces probe (test config only, never part of production).
// Runs the production bars plus an IpcHandler, against the staged shell:
//   tests/rig/qs-run.sh start --entry tests/rig/stats.qml
//   qs-run.sh ipc call stats get             -> Stats values, main screen, bar slots
//   qs-run.sh ipc call stats parse           -> results of the pure parsers on fixtures
//   qs-run.sh ipc call stats click <screen> <slot>  -> Workspaces.focusSlot(slot) of that bar
//   qs-run.sh ipc call stats setPaths <stat> <mem> <gpu>   -> point Stats elsewhere
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
                    filled: [1, 2, 3, 4, 5].filter(k => w.wsAt(k) !== null && w.wsAt(k).id === w.activeId),
                    targets: [1, 2, 3, 4, 5].map(k => w.idFor(k))
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
            return JSON.stringify({
                stat: s1,
                cpu: Stats.cpuPercent(s1, s2),           // busy 100 of 200 -> 50
                cpuNoDelta: Stats.cpuPercent(s1, s1),     // null
                statBad: Stats.parseStat("garbage"),      // null
                mem: Stats.parseMem("MemTotal:       16000000 kB\nMemFree: 1 kB\nMemAvailable:    4000000 kB\n"),
                memBad: Stats.parseMem("MemTotal: x\n"),  // null
                gpu: Stats.parseGpu("17\n"), gpuBad: Stats.parseGpu(""),
                nm: Stats.parseNmcli("lo:loopback\nHome\\:5G:802-11-wireless\nWired:802-3-ethernet\n"),
                nmEmpty: Stats.parseNmcli(""),
                slot: [1, 5, 11, 15, 21, 25, 6].map(id => probes.instances[0].ws.slotOf(id))
            });
        }

        // What a click on cell <slot> of <screen>'s bar runs (Workspaces.focusSlot).
        function click(screen: string, slot: int): void {
            for (const p of probes.instances)
                if (p.modelData.name === screen)
                    p.ws.focusSlot(slot);
        }

        function setPaths(stat: string, mem: string, gpu: string): void {
            Stats.statPath = stat;
            Stats.memPath = mem;
            Stats.gpuPath = gpu;
        }
    }
}
