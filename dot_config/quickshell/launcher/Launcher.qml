// Application launcher (spec 5.3; render .run): an overlay on the focused screen with
// a query line and up to 8 matching desktop entries. Typing filters by case-insensitive
// substring on the name (then generic name and keywords); Up/Down or Ctrl+P/Ctrl+N
// move the selection; Enter runs the selected entry and closes; Escape or a click
// outside the card closes. Opened and closed by `qs ipc call launcher toggle`
// (Super+Space). Nothing exists while it is closed (LazyLoader), so it costs nothing
// at idle; every open starts with an empty query and the first row selected.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.components
import qs.services

Scope {
    id: root

    readonly property int maxRows: 8
    readonly property real px: Theme.px
    readonly property bool opened: loader.active
    // Read-only handle (the rig's test config inspects the open window).
    readonly property LazyLoader windowLoader: loader

    property var targetScreen: null

    function open() {
        if (loader.active)
            return;
        const mon = Hyprland.focusedMonitor;
        targetScreen = Quickshell.screens.find(s => mon && s.name === mon.name) ?? Screens.mainScreen;
        loader.active = true;
    }

    function close() {
        loader.active = false;
    }

    function toggle() {
        if (loader.active)
            close();
        else
            open();
    }

    // 0: name starts with the query, 1: name contains it, 2: generic name or a
    // keyword contains it, -1: no match. q is lower case and not empty.
    function rank(entry, q) {
        const i = (entry.name || "").toLowerCase().indexOf(q);
        if (i === 0)
            return 0;
        if (i > 0)
            return 1;
        const other = [entry.genericName || ""].concat(entry.keywords || []).join("\n").toLowerCase();
        return other.indexOf(q) >= 0 ? 2 : -1;
    }

    // All matching entries, best rank first, then by name.
    function filter(apps, query) {
        const q = query.trim().toLowerCase();
        const hits = [];
        for (const e of apps) {
            const r = q === "" ? 0 : rank(e, q);
            if (r >= 0)
                hits.push({ e: e, r: r });
        }
        hits.sort((a, b) => a.r - b.r || (a.e.name || "").localeCompare(b.e.name || ""));
        return hits.map(h => h.e);
    }

    // `[xx]`: the first two letters of the name.
    function tag(name) {
        const t = (name || "").replace(/\s+/g, "").slice(0, 2).toLowerCase();
        return "[" + (t + "  ").slice(0, 2) + "]";
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.toggle();
        }
    }

    LazyLoader {
        id: loader
        active: false

        PanelWindow {
            id: win

            readonly property var apps: DesktopEntries.applications.values
            readonly property var matches: root.filter(apps, input.text)
            readonly property var rows: matches.slice(0, root.maxRows)
            property int selected: 0

            onMatchesChanged: selected = 0

            function move(d) {
                if (rows.length > 0)
                    selected = Math.max(0, Math.min(rows.length - 1, selected + d));
            }

            function run() {
                if (selected < 0 || selected >= rows.length)
                    return;
                const entry = rows[selected];
                root.close();
                entry.execute();
            }

            screen: root.targetScreen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "rice-launcher"

            // A click anywhere outside the card closes.
            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }

            Chamfer {
                id: card
                x: Math.round((win.width - width) / 2)
                y: Math.round(win.height * 0.18)
                width: Math.round(root.px * 36)
                height: Math.round(list.implicitHeight + root.px * 0.2 + root.px * 0.5)
                cut: Math.round(root.px)
                stroke: Theme.a1
                fill: Theme.bg

                // Clicks on the card do not reach the closing area behind it.
                MouseArea {
                    anchors.fill: parent
                }

                ColumnLayout {
                    id: list
                    anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: Math.round(root.px * 0.2) }
                    spacing: 0

                    // Query line: `❯ text█` and `n / total`, with a 1px rule below.
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: query.implicitHeight + 2 * Math.round(root.px * 0.45) + 1

                        RowLayout {
                            id: query
                            anchors {
                                left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                leftMargin: root.px; rightMargin: root.px
                            }
                            spacing: 0

                            Text {
                                text: "❯ "
                                color: Theme.a2
                                font.family: Theme.font
                                font.pixelSize: root.px
                            }
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: input.implicitHeight

                                TextInput {
                                    id: input
                                    anchors.left: parent.left
                                    width: Math.min(implicitWidth, parent.width - cursorBlock.width)
                                    clip: true
                                    focus: true
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: root.px
                                    // The block cursor below replaces the blinking caret.
                                    cursorDelegate: Item {}
                                    Keys.onPressed: event => {
                                        const ctrl = event.modifiers & Qt.ControlModifier;
                                        if (event.key === Qt.Key_Escape) {
                                            root.close();
                                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            win.run();
                                        } else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) {
                                            win.move(1);
                                        } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) {
                                            win.move(-1);
                                        } else {
                                            return;
                                        }
                                        event.accepted = true;
                                    }
                                }
                                Rectangle {
                                    id: cursorBlock
                                    x: input.x + Math.min(input.cursorRectangle.x, input.width)
                                    anchors.verticalCenter: input.verticalCenter
                                    width: Math.round(root.px * 0.6)
                                    height: Math.round(root.px * 1.1)
                                    color: Theme.a1
                                }
                            }
                            Text {
                                text: win.matches.length + " / " + win.apps.length
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: root.px
                            }
                        }

                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 1; rightMargin: 1 }
                            height: 1
                            color: Theme.line
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: root.px
                        Layout.topMargin: Math.round(root.px * 0.35)
                        Layout.bottomMargin: Math.round(root.px * 0.1)
                        text: "applications"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Math.round(root.px * 0.85)
                        font.letterSpacing: root.px * 0.85 * 0.14
                        font.capitalization: Font.AllUppercase
                    }

                    Repeater {
                        model: win.rows

                        Rectangle {
                            id: row

                            required property var modelData
                            required property int index
                            readonly property bool sel: index === win.selected

                            Layout.fillWidth: true
                            Layout.leftMargin: 1
                            Layout.rightMargin: 1
                            implicitHeight: rowLine.implicitHeight + 2 * Math.round(root.px * 0.12)
                            color: sel ? Theme.a1 : "transparent"

                            RowLayout {
                                id: rowLine
                                anchors {
                                    left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                    leftMargin: root.px - 1; rightMargin: root.px - 1
                                }
                                spacing: Math.round(root.px * 0.8)

                                Text {
                                    text: root.tag(row.modelData.name)
                                    color: row.sel ? Theme.bg : Theme.a1
                                    font.family: Theme.font
                                    font.pixelSize: root.px
                                    textFormat: Text.PlainText
                                }
                                Text {
                                    Layout.maximumWidth: Math.round(root.px * 18)
                                    text: row.modelData.name
                                    color: row.sel ? Theme.bg : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: root.px
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                }
                                // The render puts ⏎ at the start of the spacer, right after the name.
                                Text {
                                    Layout.fillWidth: true
                                    text: row.sel ? "⏎" : ""
                                    color: Theme.bg
                                    font.family: Theme.font
                                    font.pixelSize: root.px
                                }
                                Text {
                                    Layout.maximumWidth: Math.round(root.px * 12)
                                    text: row.modelData.genericName || row.modelData.comment || ""
                                    color: row.sel ? Theme.bg : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: root.px
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
