// Workspace-switch glitch (spec 8; the render's `tear`). When the active workspace of
// a screen changes (any cause: key binds, the bar, mouse, a moved workspace), that
// screen gets a click-through overlay on the Overlay layer for a few 42 ms steps:
// the screen is captured once (ScreencopyView) and torn by fx/glitch.frag.qsb.
// The capture is taken after the switch (Hyprland reports the change once it is
// done), so this is the spec's fallback: the resolving half of the render's FR table
// (steps 4 to 6) on the new frame.
// Cost: nothing exists between plays. The overlay window, its capture and its timer
// live in a LazyLoader that is active only while playing; no timer runs at rest. A JS
// gc() follows each teardown. What a play leaves behind (a few MB) relies on qs running
// with transparent huge pages off (qs-supervise); with THP on it was ~+20 MB.
// On by default. Off: $HOME/.local/state/quickshell/glitch-disabled exists
// (`qs ipc call glitch disable` creates it, `... enable` removes it). The file is
// checked on every switch, so a hand-made flag works at once.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs

Scope {
    id: root

    // Test hooks (the rig's glitch.qml): a slower step for screenshots, a fixed seed
    // (>= 0) and a log line per step.
    property int stepMs: 42
    property real fixedSeed: -1
    property bool logSteps: false

    readonly property string home: Quickshell.env("HOME") ?? ""
    readonly property string flagDir: home + "/.local/state/quickshell"
    readonly property string flagPath: flagDir + "/glitch-disabled"

    // The render's FR rows: source, amp (em), ghost (em), blocks. Only 'n' rows play.
    readonly property var frames: [["o", 1.2, 0, 0], ["o", 6, 1, 3], ["o", 13, 2.6, 8],
                                   ["n", 10, 3, 10], ["n", 4.5, 1.2, 4], ["n", 1.4, 0.45, 0]]
    readonly property int firstStep: 3
    property bool disabled: false

    // Slots waiting for the flag check (one entry per screen at most).
    property var pending: []

    function request(slot) {
        if (pending.indexOf(slot) < 0)
            pending = pending.concat([slot]);
        flag.reload();
    }

    function flush(enabled) {
        const p = pending;
        pending = [];
        disabled = !enabled;
        if (enabled)
            for (const s of p)
                s.play();
    }

    FileView {
        id: flag
        path: root.flagPath
        printErrors: false
        onLoaded: root.flush(false)
        // Only "no such file" means on; an unreadable flag counts as present.
        onLoadFailed: error => root.flush(error === FileViewError.FileNotFound)
    }

    Process {
        id: flagWriter
    }

    function setEnabled(on) {
        flagWriter.command = on ? ["rm", "-f", "--", flagPath]
                                : ["sh", "-c", "mkdir -p -- \"$1\" && : >\"$2\"", "sh", flagDir, flagPath];
        flagWriter.running = true;
        disabled = !on;
    }

    IpcHandler {
        target: "glitch"

        function enable(): void {
            root.setEnabled(true);
        }

        function disable(): void {
            root.setEnabled(false);
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: slot

            required property var modelData
            readonly property var monitor: Hyprland.monitorFor(modelData)
            // Not a binding: it must still hold the previous id when the change arrives.
            // The first workspace a monitor reports (startup, a new monitor) only sets it.
            property int lastId: -1

            function currentId() {
                return monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1;
            }

            Component.onCompleted: lastId = currentId()
            onMonitorChanged: lastId = currentId()

            property real askedAt: 0

            function play() {
                askedAt = Date.now();
                if (loader.active && loader.item)
                    loader.item.restart();
                else
                    loader.active = true;
            }

            function done() {
                loader.active = false;
                Qt.callLater(gc);
            }

            Connections {
                target: slot.monitor

                function onActiveWorkspaceChanged() {
                    const id = slot.currentId();
                    const prev = slot.lastId;
                    slot.lastId = id;
                    if (prev > 0 && id > 0 && id !== prev)
                        root.request(slot);
                }
            }

            LazyLoader {
                id: loader

                active: false

                PanelWindow {
                    id: win

                    property int step: -1
                    property real seed: 0
                    property var cuts: []
                    property real t0: 0

                    function restart() {
                        timer.stop();
                        step = -1;
                        view.captureSource = null;
                        view.captureSource = slot.modelData;
                    }

                    function begin() {
                        const c = [];
                        for (let i = 0; i < 8; i++)
                            c.push(Math.random());
                        cuts = c.sort((a, b) => a - b);
                        t0 = Date.now();
                        if (root.logSteps)
                            console.info("glitch capture screen", slot.modelData.name, "ms", t0 - slot.askedAt);
                        show(root.firstStep);
                        timer.restart();
                    }

                    function show(k) {
                        step = k;
                        seed = root.fixedSeed >= 0 ? root.fixedSeed + k : Math.random() * 100;
                        if (root.logSteps)
                            console.info("glitch step", k, "screen", slot.modelData.name, "t", Date.now() - t0);
                    }

                    screen: slot.modelData
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    mask: Region {}
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.namespace: "rice-glitch"
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }

                    ScreencopyView {
                        id: view

                        anchors.fill: parent
                        captureSource: slot.modelData
                        live: false
                        onHasContentChanged: {
                            if (hasContent) {
                                tex.scheduleUpdate();
                                win.begin();
                            }
                        }
                    }

                    // A ScreencopyView is not a texture provider of its own (as the
                    // source directly it renders black); a one-shot layer is.
                    ShaderEffectSource {
                        id: tex

                        anchors.fill: parent
                        sourceItem: view
                        hideSource: true
                        live: false
                        visible: false
                    }

                    ShaderEffect {
                        readonly property var row: win.step >= 0 ? root.frames[win.step] : root.frames[root.firstStep]
                        property var source: tex
                        property real amp: row[1]
                        property real ghost: row[2]
                        property real blocks: row[3]
                        property real seed: win.seed
                        property vector4d cutsA: win.cuts.length === 8 ? Qt.vector4d(win.cuts[0], win.cuts[1], win.cuts[2], win.cuts[3]) : Qt.vector4d(0, 0, 0, 0)
                        property vector4d cutsB: win.cuts.length === 8 ? Qt.vector4d(win.cuts[4], win.cuts[5], win.cuts[6], win.cuts[7]) : Qt.vector4d(1, 1, 1, 1)
                        property color a1: Theme.a1
                        property color a2: Theme.a2
                        property color fg: Theme.fg
                        property color bg: Theme.bg

                        anchors.fill: parent
                        visible: win.step >= 0
                        fragmentShader: Qt.resolvedUrl("glitch.frag.qsb")
                    }

                    Timer {
                        id: timer

                        interval: root.stepMs
                        repeat: true
                        onTriggered: {
                            if (win.step + 1 < root.frames.length) {
                                win.show(win.step + 1);
                            } else {
                                stop();
                                if (root.logSteps)
                                    console.info("glitch end screen", slot.modelData.name, "t", Date.now() - win.t0);
                                slot.done();
                            }
                        }
                    }
                }
            }
        }
    }
}
