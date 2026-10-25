// Rail BLUETOOTH section (render .bt): `// BLUETOOTH ─── <n> connected`, then one row
// per connected device: a small a1 square, the name (elided), and when BlueZ reports a
// battery level a 5-cell meter (low is bad: invert) and `NN%`; otherwise the name only.
// BlueZ gives one level per device, so there is no sub-line (no left/right/case data
// is invented). The whole section is hidden when nothing is connected.
// READ ONLY: this file never calls a device method and never assigns a device
// property. `devices` can be replaced by a fake model in tests: anything with `values`
// (Quickshell ObjectModel) or `count`/`get(i)` (ListModel) whose entries have
// connected, name, battery (0..1) and batteryAvailable.
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs
import qs.components

ColumnLayout {
    id: root

    property real px: Theme.px
    property var devices: Bluetooth.devices

    // Bumped when a list model reports changed rows: reads through ListModel.get() are
    // not tracked by the binding below (BluetoothDevice properties are).
    property int revision: 0

    // The connected entries as a plain array. Reading `connected` inside the binding
    // makes it re-evaluate when a device connects or disconnects.
    readonly property var connected: {
        revision;
        const m = root.devices;
        if (!m)
            return [];
        let all = [];
        if (m.values !== undefined)
            all = m.values;
        else if (m.count !== undefined)
            for (let i = 0; i < m.count; i++)
                all.push(m.get(i));
        return all.filter(d => d && d.connected === true);
    }

    visible: connected.length > 0
    spacing: Math.round(px * 0.2)

    Connections {
        target: root.devices
        ignoreUnknownSignals: true
        function onDataChanged() {
            root.revision++;
        }
    }

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.15)
        px: root.px
        text: "bluetooth"
        note: root.connected.length + " connected"
    }

    Repeater {
        model: root.connected

        RowLayout {
            id: row
            required property var modelData
            readonly property bool hasBattery: modelData.batteryAvailable === true
            readonly property int pct: Math.max(0, Math.min(100, Math.round((modelData.battery || 0) * 100)))

            Layout.fillWidth: true
            spacing: Math.round(root.px * 0.55)

            // The 0.5em square in a 0.55em column (render .bt .dot).
            Item {
                Layout.preferredWidth: Math.round(root.px * 0.55)
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: Math.round(root.px * 0.5)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(root.px * 0.5)
                    height: width
                    color: Theme.a1
                }
            }

            Text {
                Layout.fillWidth: true
                text: row.modelData.name || ""
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: root.px
            }

            Meter {
                visible: row.hasBattery
                Layout.alignment: Qt.AlignVCenter
                px: root.px
                cells: 5
                invert: true
                value: row.pct
            }

            Text {
                visible: row.hasBattery
                text: row.pct + "%"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: root.px
            }
        }
    }
}
