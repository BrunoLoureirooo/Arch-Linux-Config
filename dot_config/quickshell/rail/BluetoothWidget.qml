// Rail BLUETOOTH section (render .bt): `// BLUETOOTH ─── <n> connected`, then one rail
// row per connected device: a small a1 square, the name (elided), and when BlueZ reports a
// battery level a 5-cell meter (low is bad: invert) and `NN%`; otherwise the name only.
// BlueZ gives one level per device, so there is no sub-line (no left/right/case data
// is invented). The section is always shown: with nothing connected it is the heading
// and one dim line, `no adapter` (no BlueZ adapter), `bluetooth off` (adapter powered
// off) or `no devices connected`.
// READ ONLY: this file never calls a device method and never assigns a device or
// adapter property. `devices` can be replaced by a fake model in tests: anything with
// `values` (Quickshell ObjectModel) or `count`/`get(i)` (ListModel) whose entries have
// connected, name, battery (0..1) and batteryAvailable; `adapter` by anything with
// `enabled`, or null.
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs
import qs.components

ColumnLayout {
    id: root

    property real px: Theme.px
    property var devices: Bluetooth.devices
    // Font sizes of the device names and the battery values, the row height.
    property real subPx: Math.round(px * 1.3)
    property real rowPx: Math.round(px * 1.5)
    readonly property real rowHeight: Math.round(rowPx * 1.85)

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

    property var adapter: Bluetooth.defaultAdapter
    readonly property string emptyText: !adapter ? "no adapter" : adapter.enabled !== true ? "bluetooth off" : "no devices connected"

    spacing: Math.round(px * 0.6)

    Connections {
        target: root.devices
        ignoreUnknownSignals: true
        function onDataChanged() {
            root.revision++;
        }
    }

    SectionLabel {
        Layout.fillWidth: true
        Layout.bottomMargin: Math.round(root.px * 0.3)
        px: root.px
        text: "bluetooth"
        note: root.connected.length > 0 ? root.connected.length + " connected" : ""
    }

    EmptyNote {
        visible: root.connected.length === 0
        px: root.px
        text: root.emptyText
    }

    Repeater {
        model: root.connected

        RowLayout {
            id: row
            required property var modelData
            readonly property bool hasBattery: modelData?.batteryAvailable === true
            readonly property int pct: Math.max(0, Math.min(100, Math.round((modelData?.battery || 0) * 100)))

            Layout.fillWidth: true
            Layout.preferredHeight: root.rowHeight
            spacing: Math.round(root.px * 0.8)

            // The 0.5em square in a 0.55em column (render .bt .dot).
            Item {
                Layout.preferredWidth: Math.round(root.px * 0.55) + 1
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: Math.round(root.subPx * 0.5)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 1
                    width: Math.round(root.px * 0.55)
                    height: width
                    color: Theme.a1
                }
            }

            Text {
                Layout.fillWidth: true
                text: row.modelData?.name || ""
                textFormat: Text.PlainText  // a device name: never StyledText
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: root.subPx
            }

            Meter {
                visible: row.hasBattery
                Layout.alignment: Qt.AlignVCenter
                px: root.subPx
                cells: 5
                // The rail's segment look: bar-high cells, 2 px apart.
                cellWidth: Math.round(root.px * 1.0)
                cellHeight: Math.round(root.rowPx * 0.5)
                gap: 2
                invert: true
                value: row.pct
            }

            Text {
                visible: row.hasBattery
                Layout.preferredWidth: Math.round(root.rowPx * 3)
                horizontalAlignment: Text.AlignRight
                text: row.pct + "%"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: root.rowPx
                font.weight: Font.Medium
            }
        }
    }
}
