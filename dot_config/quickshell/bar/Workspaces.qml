// Slots 1-5 of the workspaces Hyprland reports on this screen's monitor (spec 5.3).
// slot = ((id - 1) % 10) + 1. A monitor can hold workspaces from two pools (after an
// unplug Hyprland moves 21-25 next to 11-15), so the five cells always show ONE pool:
// the active workspace's pool; if the active id is outside slots 1-5 (6-10, 16-20...),
// the pool of the lowest in-slot id on the monitor; else none (no fill, no targets).
// The pool is never computed here from monitor ids (it lives in hypr/lib/pools.lua),
// only from the ids Hyprland reports. Active: filled a1 with an a2 underline;
// occupied (windows > 0): fg text, dim underline; empty: dim text.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs

Row {
    id: root

    property var screen          // ShellScreen
    property real px: Theme.px   // font size

    readonly property var monitor: screen ? Hyprland.monitors.values.find(m => m.name === screen.name) ?? null : null
    readonly property var workspaces: screen
        ? Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor && w.monitor.name === screen.name).sort((a, b) => a.id - b.id)
        : []
    readonly property int activeId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    readonly property var current: layout(workspaces.map(w => w.id), activeId)

    function slotOf(id) {
        return ((id - 1) % 10) + 1;
    }

    // Pure: ids on the monitor + its active id -> {base, targets, filled}. `base` is
    // the pool's tens (-1 = none), `targets` the ids cells 1-5 stand for (-1 = none),
    // `filled` the slot of the active workspace when it is in that pool (0 = none).
    function layout(ids, active) {
        const inSlots = id => id > 0 && slotOf(id) <= 5;
        const ref = inSlots(active) ? active : ids.filter(inSlots).sort((a, b) => a - b)[0];
        const base = ref === undefined ? -1 : ref - slotOf(ref);
        const targets = [1, 2, 3, 4, 5].map(k => base < 0 ? -1 : base + k);
        const filled = base >= 0 && inSlots(active) && active - slotOf(active) === base ? slotOf(active) : 0;
        return { base: base, targets: targets, filled: filled };
    }

    function wsById(id) {
        return id < 0 ? null : workspaces.find(w => w.id === id) ?? null;
    }

    function focusSlot(k) {
        const id = current.targets[k - 1];
        if (id === undefined || id < 0 || !screen)
            return;
        // Hyprland 0.56 with a Lua config takes Lua dispatcher expressions. A workspace
        // that does not exist yet is created on the focused monitor, so focus this
        // screen's monitor first (pool workspaces are persistent in production, so
        // normally the id exists and only the second dispatch runs).
        const lua = Hyprland.usingLua;
        if (!wsById(id))
            Hyprland.dispatch(lua ? "hl.dsp.focus({ monitor = \"" + screen.name + "\" })" : "focusmonitor " + screen.name);
        Hyprland.dispatch(lua ? "hl.dsp.focus({ workspace = " + id + " })" : "workspace " + id);
    }

    spacing: Math.round(px * 0.2)

    Repeater {
        model: 5

        Item {
            id: cell

            required property int index
            readonly property int slot: index + 1
            readonly property var ws: root.wsById(root.current.targets[index])
            readonly property bool active: root.current.filled === slot
            readonly property bool occupied: ws !== null && ws.toplevels.values.length > 0

            implicitWidth: Math.round(root.px * 1.8)
            implicitHeight: label.implicitHeight + 2 + 2

            Rectangle {
                anchors.fill: parent
                visible: cell.active
                color: Theme.a1
            }

            Text {
                id: label
                anchors.horizontalCenter: parent.horizontalCenter
                y: 1
                text: cell.slot
                color: cell.active ? Theme.bg : cell.occupied ? Theme.fg : Theme.dim
                font.family: Theme.font
                font.pixelSize: root.px
                font.bold: cell.active
            }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 2
                visible: cell.active || cell.occupied
                color: cell.active ? Theme.a2 : Theme.dim
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusSlot(cell.slot)
            }
        }
    }
}
