// Bluetooth / Claude rail widget probe (test config only, never part of production).
// The production bars and rail (main screen only), plus an IpcHandler that swaps the
// rail's BluetoothWidget.devices for a fake ListModel and points ClaudeWidget.cachePath
// at a test file, and reads their state by walking the item trees, so the production
// files carry no test code:
//   tests/rig/qs-run.sh start --entry tests/rig/widgets-test.qml
//   qs-run.sh ipc call widgets get               -> bluetooth, claude and fit state (JSON)
//   qs-run.sh ipc call widgets parse             -> ClaudeWidget's pure helpers on fixtures
//   qs-run.sh ipc call widgets fakeBt <mode>     -> three | empty (ListModel) | objects | real
//   qs-run.sh ipc call widgets setConnected <i> <bool>   (fake model only)
//   qs-run.sh ipc call widgets setCache <path>
//   qs-run.sh ipc call widgets setClaudeVisible <bool>
// Real devices are only counted, never named: with the real model `get` reports no
// names, and nothing here ever calls a device method or writes a device property.
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.bar
import qs.rail
import qs.services

ShellRoot {
    id: shell

    property bool fake: false

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

    // Fake devices: connected with a battery, connected without one, disconnected.
    ListModel {
        id: fakeDevices
    }

    // The same three as QObjects behind `values`, the shape of Bluetooth.devices
    // (ObjectModel of BluetoothDevice): changes arrive as property notifications.
    component FakeDevice: QtObject {
        property string name
        property bool connected
        property real battery
        property bool batteryAvailable
    }

    QtObject {
        id: fakeObjects
        property list<QtObject> values: [
            FakeDevice { name: "Rig Buds Pro"; connected: true; battery: 0.82; batteryAvailable: true },
            FakeDevice { name: "Rig Pad"; connected: true; batteryAvailable: false },
            FakeDevice { name: "Rig Speaker"; connected: false; battery: 0.5; batteryAvailable: true }
        ]
    }

    property string mode: "real"

    function fillThree() {
        fakeDevices.clear();
        fakeDevices.append({ name: "Rig Buds Pro", connected: true, battery: 0.82, batteryAvailable: true });
        fakeDevices.append({ name: "Rig Pad", connected: true, battery: 0, batteryAvailable: false });
        fakeDevices.append({ name: "Rig Speaker", connected: false, battery: 0.5, batteryAvailable: true });
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

    function bt() {
        return find(rail()?.contentItem, i => i.devices !== undefined && i.connected !== undefined);
    }

    function claude() {
        return find(rail()?.contentItem, i => i.cachePath !== undefined && i.rows !== undefined);
    }

    function texts(item) {
        return findAll(item, i => typeof i.text === "string" && i.font !== undefined && i.visible && i.text !== "", []).map(i => i.text);
    }

    // True when the item and all its ancestors up to `top` are visible.
    function shown(item, top) {
        for (let i = item; i && i !== top; i = i.parent)
            if (!i.visible)
                return false;
        return true;
    }

    IpcHandler {
        target: "widgets"

        function get(): string {
            const r = shell.rail();
            const b = shell.bt();
            const c = shell.claude();
            const bRows = shell.findAll(b, i => i.modelData !== undefined && i.hasBattery !== undefined, []).map(row => {
                const m = shell.find(row, i => i.cells !== undefined && i.invert !== undefined);
                return {
                    name: shell.fake ? row.modelData.name : "<device>",
                    meter: m.visible, lit: m.lit, invert: m.invert, bad: m.bad, pct: row.pct,
                    texts: shell.fake ? shell.texts(row) : []
                };
            });
            const cRows = shell.findAll(c, i => i.modelData !== undefined && i.expired !== undefined, []).map(w => {
                const segs = shell.find(w, i => i.lit !== undefined && i.cell !== undefined);
                return {
                    label: w.modelData.label, expired: w.expired, segs: segs.visible,
                    lit: segs.lit,
                    colors: segs.children.filter(x => x.color !== undefined).map(x => String(x.color)),
                    texts: shell.texts(w)
                };
            });
            const clipItem = shell.find(r?.contentItem, i => i.clip === true);
            const col = clipItem ? clipItem.children[0] : null;
            return JSON.stringify({
                fake: shell.fake,
                realCount: Bluetooth.devices.values.length,
                realConnected: Bluetooth.devices.values.filter(d => d.connected).length,
                bt: {
                    visible: b.visible, shown: shell.shown(b, r.contentItem),
                    note: shell.find(b, i => i.note !== undefined && i.text === "bluetooth").note,
                    connected: b.connected.length, rows: bRows
                },
                claude: {
                    visible: c.visible, cachePath: c.cachePath, noData: c.noData, stale: c.stale,
                    future: c.future, note: c.note, readable: c.readable, now: c.now,
                    texts: shell.texts(c), rows: cRows
                },
                fit: col ? {
                    clipHeight: clipItem.height, columnHeight: col.implicitHeight,
                    claudeBottom: c.mapToItem(clipItem, 0, c.height).y,
                    railHeight: r.height
                } : null,
                // headings of the rail sections that are on screen, top to bottom
                sections: shell.findAll(r?.contentItem, i => i.note !== undefined && typeof i.text === "string"
                    && shell.shown(i, r.contentItem), []).map(i => i.text),
                timer: (t => t ? { running: t.running, interval: t.interval } : null)(
                    c.resources.find(o => o.interval !== undefined && o.running !== undefined))
            });
        }

        // Hides / shows the CLAUDE section (its timer must follow).
        function setClaudeVisible(on: bool): void {
            shell.claude().visible = on;
        }

        function parse(): string {
            const c = shell.claude();
            const now = 1800000000;
            return JSON.stringify({
                full: c.parse('{"five_hour": {"pct": 38.4, "resets_at": 1800008040}, "seven_day": {"pct": 19, "resets_at": 1800400000}, "updated_at": 1799999880}'),
                garbage: c.parse("{garbage"),
                empty: c.parse(""),
                array: c.parse("[1, 2]"),
                nul: c.parse("null"),
                number: c.parse("7"),
                badWindow: c.parse('{"five_hour": "x", "seven_day": {"pct": "38", "resets_at": 1}, "updated_at": "now"}'),
                clamp: c.parse('{"five_hour": {"pct": 130, "resets_at": 1}, "seven_day": {"pct": -5, "resets_at": 1}, "updated_at": 1}'),
                ages: [0, 12, 59, 60, 300, 3599, 3600, 7199, 86399, 86400, 259200, -5].map(s => c.ageText(s)),
                resets: [now + 30, now + 60, now + 840, now + 3600, now + 8040, now + 86399].map(t => c.resetText(t, now)),
                weekday: c.resetText(now + 2 * 86400, now),
            });
        }

        function fakeBt(mode: string): void {
            const b = shell.bt();
            if (mode === "real") {
                shell.fake = false;
                shell.mode = "real";
                b.devices = Bluetooth.devices;
                return;
            }
            shell.fake = true;
            shell.mode = mode;
            if (mode === "objects") {
                for (let i = 0; i < 3; i++)
                    fakeObjects.values[i].connected = i < 2;
                b.devices = fakeObjects;
                return;
            }
            if (mode === "three")
                shell.fillThree();
            else
                fakeDevices.clear();
            b.devices = fakeDevices;
        }

        // Fake models only; never reaches a real device.
        function setConnected(i: int, on: bool): void {
            if (shell.mode === "objects")
                fakeObjects.values[i].connected = on;
            else if (shell.fake)
                fakeDevices.setProperty(i, "connected", on);
        }

        function setCache(path: string): void {
            shell.claude().cachePath = path;
        }
    }
}
