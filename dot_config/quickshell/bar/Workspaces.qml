// Slots 1-5 of the workspaces Hyprland reports on this screen's monitor (spec 5.3).
// slot = ((id - 1) % 10) + 1, so pool 0 (1-5), pool 1 (11-15), ... all map to 1-5.
// The pool itself is never computed here (it lives in hypr/lib/pools.lua): a cell's id
// is the reported workspace in that slot, or, for a slot with no workspace yet, the
// same tens as the monitor's other in-pool workspaces. Active: filled a1 with an a2
// underline; occupied (windows > 0): fg text, dim underline; empty: dim text.
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

    function slotOf(id) {
        return ((id - 1) % 10) + 1;
    }

    // Workspace in slot k (1-5) on this monitor, or null.
    function wsAt(k) {
        return workspaces.find(w => slotOf(w.id) === k) ?? null;
    }

    // Workspace id for slot k: the reported one, else derived from any in-pool
    // workspace on this monitor; -1 when there is none to derive from.
    function idFor(k) {
        const w = wsAt(k);
        if (w)
            return w.id;
        const ref = workspaces.find(x => slotOf(x.id) <= 5);
        return ref ? ref.id - slotOf(ref.id) + k : -1;
    }

    function focusSlot(k) {
        const id = idFor(k);
        if (id < 0 || !screen)
            return;
        // Hyprland 0.56 with a Lua config takes Lua dispatcher expressions. A workspace
        // that does not exist yet is created on the focused monitor, so focus this
        // screen's monitor first (pool workspaces are persistent in production, so
        // normally the id exists and only the second dispatch runs).
        const lua = Hyprland.usingLua;
        if (!wsAt(k))
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
            readonly property var ws: root.wsAt(slot)
            readonly property bool active: ws !== null && ws.id === root.activeId
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
