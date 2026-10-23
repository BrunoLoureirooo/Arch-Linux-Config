// Top bar, one per screen (spec 5.3; render classes .bar .mark .wsl .chip .m).
// Left: λ tile, workspace slots, `//`, window title. Centre: clock and date.
// Right: CPU, MEM, VOL, NET (default-route interface) chips, plus BAT whenever a
// laptop battery exists: the same chips on every screen, so no screen topology (an
// undocked laptop is the only, hence main, screen) can hide the battery.
// Everything is read only (no volume or power changes).
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs
import qs.components
import qs.services

PanelWindow {
    id: bar

    // The render's bar font is 0.84em of the 12px screen font.
    readonly property real px: Math.round(Theme.px * 0.84)
    readonly property real gap: px  // 1em between items
    readonly property var monitor: screen ? Hyprland.monitors.values.find(m => m.name === screen.name) ?? null : null

    // Focused window when it is on this screen, else the first window on this screen's
    // active workspace; "empty" when there is none.
    readonly property string title: {
        const t = Hyprland.activeToplevel;
        if (t && monitor && t.monitor === monitor)
            return t.title;
        const ws = monitor ? monitor.activeWorkspace : null;
        const first = ws && ws.toplevels.values.length > 0 ? ws.toplevels.values[0] : null;
        return first ? first.title : "empty";
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool hasVolume: sink !== null && sink.audio !== null && sink.ready
    readonly property var battery: UPower.displayDevice
    readonly property bool showBattery: battery.ready && battery.isLaptopBattery

    anchors { top: true; left: true; right: true }
    implicitHeight: 26
    exclusiveZone: implicitHeight
    color: Theme.bg
    WlrLayershell.namespace: "rice-bar"

    // Volume is only valid on a bound node.
    PwObjectTracker { objects: [bar.sink] }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Bottom rule: 1px line with a short a1 segment on the left (7em).
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.line
    }
    Rectangle {
        anchors { left: parent.left; bottom: parent.bottom }
        width: Math.round(bar.px * 7)
        height: 1
        color: Theme.a1
    }

    Row {
        id: left
        anchors { left: parent.left; leftMargin: Math.round(bar.px * 0.7); verticalCenter: parent.verticalCenter }
        spacing: bar.gap

        Chamfer {
            anchors.verticalCenter: parent.verticalCenter
            width: mark.implicitWidth + Math.round(bar.px * 1.4)
            height: mark.implicitHeight + Math.round(bar.px * 0.3)
            cut: Math.round(bar.px * 0.5)
            fill: Theme.a1
            stroke: Theme.a1

            Text {
                id: mark
                anchors.centerIn: parent
                text: "λ"
                color: Theme.bg
                font.family: Theme.font
                font.pixelSize: bar.px
                font.bold: true
            }
        }

        Workspaces {
            anchors.verticalCenter: parent.verticalCenter
            screen: bar.screen
            px: bar.px
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "//"
            color: Theme.a2
            font.family: Theme.font
            font.pixelSize: bar.px
        }

        Text {
            id: titleText
            anchors.verticalCenter: parent.verticalCenter
            // Never run into the clock.
            width: Math.max(0, Math.min(implicitWidth, centre.x - bar.gap - left.x - x))
            text: bar.title
            elide: Text.ElideRight
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: bar.px
        }
    }

    Row {
        id: centre
        anchors.centerIn: parent
        spacing: bar.gap

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: bar.px
            font.bold: true
            font.letterSpacing: bar.px * 0.04
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // The render shows "FRI OCT 23"; C locale so names stay English.
            text: Qt.locale("C").toString(clock.date, "ddd MMM dd").toUpperCase()
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: bar.px
        }
    }

    Row {
        anchors { right: parent.right; rightMargin: Math.round(bar.px * 0.7); verticalCenter: parent.verticalCenter }
        spacing: bar.gap

        Chip {
            anchors.verticalCenter: parent.verticalCenter
            px: bar.px
            label: "CPU"
            meter: Stats.cpu
            text: Math.round(Stats.cpu) + "%"
        }

        Chip {
            anchors.verticalCenter: parent.verticalCenter
            px: bar.px
            label: "MEM"
            text: Stats.memGb.toFixed(1) + "G"
        }

        Chip {
            anchors.verticalCenter: parent.verticalCenter
            px: bar.px
            label: "VOL"
            warnAbove: 100 // only a boosted (> 100%) volume is a warning
            meter: bar.hasVolume ? Math.round(bar.sink.audio.volume * 100) : -1
            text: bar.hasVolume ? "" : "-"
        }

        Chip {
            anchors.verticalCenter: parent.verticalCenter
            px: bar.px
            label: "NET"
            text: Stats.netConn !== "" ? Stats.netConn : "--"
        }

        Chip {
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.showBattery
            px: bar.px
            label: "BAT"
            invert: true
            meter: Math.round(bar.battery.percentage * 100)
            text: Math.round(bar.battery.percentage * 100) + "%"
        }
    }
}
