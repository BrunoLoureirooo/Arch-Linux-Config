// NVIDIA GPU source probe (test config only, never part of production, U15).
// The production bars and rail (main screen only) plus an IpcHandler. Before the card
// probe in Stats finishes, Component.onCompleted applies the test hooks from the
// environment (all optional):
//   NVT_STATUS=<file>        Stats.nvStatusPath (a temp file standing in for runtime_status)
//   NVT_SMI=<command>        Stats.nvSmiCommand (e.g. a name that is not on PATH)
//   NVT_BACKOFF=<ms,ms,...>  Stats.nvBackoff (shortened retry steps)
//   NVT_TIMEOUT=<ms>         Stats.nvStartTimeout
// Run with RICE_NVIDIA=1 (the opt-in) and a FAKE nvidia-smi first on PATH:
//   tests/rig/qs-run.sh start --entry tests/rig/nvidia-test.qml
//   qs-run.sh ipc call nv get     -> Stats GPU state, the SYS rows on screen, rail fit
//   qs-run.sh ipc call nv parse   -> Stats.parseNvLine / SysWidget.vramText on fixtures
import QtQuick
import Quickshell
import Quickshell.Io
import qs.bar
import qs.rail
import qs.services

ShellRoot {
    id: shell

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

    Component.onCompleted: {
        const env = k => Quickshell.env(k) ?? "";
        if (env("NVT_STATUS") !== "")
            Stats.nvStatusPath = env("NVT_STATUS");
        if (env("NVT_SMI") !== "")
            Stats.nvSmiCommand = env("NVT_SMI");
        if (env("NVT_BACKOFF") !== "")
            Stats.nvBackoff = env("NVT_BACKOFF").split(",").map(Number);
        if (env("NVT_TIMEOUT") !== "")
            Stats.nvStartTimeout = Number(env("NVT_TIMEOUT"));
    }

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

    function rail() {
        for (const l of rails.instances)
            if (l.item)
                return l.item;
        return null;
    }

    function sys() {
        return find(rail()?.contentItem, i => i.vramText !== undefined && i.valueWidth !== undefined);
    }

    IpcHandler {
        target: "nv"

        function get(): string {
            const r = shell.rail();
            const s = shell.sys();
            // StatRow: label, value (0-100), text; its children are the label Text,
            // the segment Item (lit) and the value Text.
            const rows = shell.findAll(s, i => i.label !== undefined && i.value !== undefined && typeof i.text === "string", [])
                .map(row => {
                    const segs = shell.find(row, i => i.lit !== undefined && i.cell !== undefined);
                    const val = row.children[2];
                    return {
                        label: row.label, visible: row.visible, text: row.text, lit: segs.lit,
                        valueWidth: val.width, valueTextWidth: val.contentWidth,
                        bottom: row.visible ? row.mapToItem(r.contentItem, 0, row.height).y : -1
                    };
                });
            const clipItem = shell.find(r?.contentItem, i => i.clip === true);
            const col = clipItem ? clipItem.children[0] : null;
            return JSON.stringify({
                gpuSource: Stats.gpuSource, gpu: Stats.gpu, vramUsedMb: Stats.vramUsedMb,
                vramTotalMb: Stats.vramTotalMb, vramPct: Stats.vramPct, nvState: Stats.nvState,
                nvAllowed: Stats.nvAllowed, nvStatusPath: Stats.nvStatusPath, gpuPath: Stats.gpuPath,
                nvSmiCommand: Stats.nvSmiCommand, nvBackoff: Array.from(Stats.nvBackoff),
                nvStartTimeout: Stats.nvStartTimeout,
                rows: rows,
                fit: col ? { clipHeight: clipItem.height, columnHeight: col.implicitHeight } : null
            });
        }

        function parse(): string {
            const p = Stats.parseNvLine;
            const t = shell.sys().vramText;
            return JSON.stringify({
                normal: p("17, 1024, 4096"),
                spaces: p("  17 ,   1024 ,4096  \r"),
                noSpace: p("17,1024,4096"),
                na: p("[N/A], 1024, [Not Supported]"),
                allNa: p("[N/A], [N/A], [N/A]"),
                empty: p(""),
                blank: p("   "),
                two: p("17, 1024"),
                extra: p("5, 2048, 4096, 61, P8"),
                comma: p("17, 1024,5, 4096"),
                over: p("130, 5000, 4096"),
                garbage: p("NVIDIA-SMI has failed, because, reasons"),
                texts: [t(1024, 4096), t(1536, 4096), t(0, 4096), t(-1, 4096), t(1024, -1), t(12800, 16384), t(4095, 4096)]
            });
        }
    }
}
