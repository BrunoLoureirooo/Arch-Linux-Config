// Notification toasts (spec 5.3; render .toast): the shell's notification server,
// replacing mako. Toasts stack at the bottom right of the tiling area on the main
// screen, left of the rail. At most three are shown; later ones wait in the server's
// tracked list and appear as slots free. A toast expires after the notification's
// own timeout (expireTimeout) or 5 s by default; critical ones stay until
// clicked. A click dismisses.
//
// Idle cost: the toast window and its single 250 ms timer exist only while a toast is
// shown (LazyLoader), so nothing renders or ticks when there are no notifications.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs
import qs.components
import qs.services

Scope {
    id: root

    readonly property int maxVisible: 3
    readonly property int defaultTimeoutMs: 5000
    readonly property real px: Theme.px
    readonly property int railWidth: Screens.mainScreen ? Math.round(Screens.mainScreen.width * 0.225) : 0

    // Receive time per notification id, for the HH:mm on the toast.
    property var received: ({})

    // Read-only handles (the rig's test config inspects them; production uses neither).
    readonly property NotificationServer server: notifServer
    readonly property LazyLoader windowLoader: toastLoader

    // The server's tracked notifications arrive in order; the first three are shown.
    NotificationServer {
        id: notifServer
        keepOnReload: true
        actionsSupported: false
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: false
        persistenceSupported: false

        onNotification: n => {
            const id = n.id;
            if (!(id in root.received))
                root.received[id] = new Date();
            n.closed.connect(() => delete root.received[id]);
            n.tracked = true;
        }
    }

    // expireTimeout is the D-Bus value in milliseconds as sent (the 0.3.1 docs say
    // seconds, but 2000 arrives as 2000); -1 (server default) and 0 mean "use ours".
    function timeoutMs(n) {
        return n.expireTimeout > 0 ? n.expireTimeout : defaultTimeoutMs;
    }

    function isCritical(n) {
        return n.urgency === NotificationUrgency.Critical;
    }

    ScriptModel {
        id: shown
        objectProp: "id"
        values: notifServer.trackedNotifications.values.slice(0, root.maxVisible)
    }

    LazyLoader {
        id: toastLoader
        active: Screens.mainScreen !== null && shown.values.length > 0

        PanelWindow {
            id: win

            // Shared clock for the countdown bars and expiry; runs only while this
            // window exists.
            property real now: Date.now()

            screen: Screens.mainScreen
            anchors { bottom: true; right: true }
            margins.right: root.railWidth + Math.round(root.px * 1.4)
            margins.bottom: Math.round(root.px * 0.9)
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "rice-toasts"

            // All toasts share one width: the widest natural content, 19em to 32em.
            readonly property real toastWidth: {
                let w = 0;
                for (const c of column.children)
                    if (c.naturalWidth !== undefined)
                        w = Math.max(w, c.naturalWidth);
                return Math.round(Math.min(Math.max(w, root.px * 19), root.px * 32));
            }
            implicitWidth: toastWidth
            implicitHeight: Math.max(1, column.implicitHeight)

            Timer {
                interval: 250
                repeat: true
                running: true
                triggeredOnStart: true
                onTriggered: win.now = Date.now()
            }

            Column {
                id: column
                width: win.toastWidth
                spacing: Math.round(root.px * 0.45)

                Repeater {
                    model: shown

                    Chamfer {
                        id: toast

                        required property var modelData
                        readonly property var n: modelData
                        readonly property bool critical: root.isCritical(n)
                        readonly property real timeout: root.timeoutMs(n)
                        // The countdown starts when the toast is shown, not when queued.
                        property real shownAt: Date.now()
                        readonly property real remaining: critical ? 1 : Math.max(0, Math.min(1, (shownAt + timeout - win.now) / timeout))
                        readonly property bool due: !critical && win.now >= shownAt + timeout
                        readonly property real padX: root.px
                        readonly property real naturalWidth: 2 * padX + Math.max(head.implicitWidth, summary.implicitWidth, body.implicitWidth)

                        onDueChanged: if (due) n.expire()

                        width: column.width
                        height: content.implicitHeight + Math.round(root.px * 0.4) + Math.round(root.px * 0.5)
                        cut: 8
                        stroke: Theme.a2
                        fill: Theme.bg

                        ColumnLayout {
                            id: content
                            anchors {
                                top: parent.top; left: parent.left; right: parent.right
                                topMargin: Math.round(root.px * 0.4)
                                leftMargin: toast.padX; rightMargin: toast.padX
                            }
                            spacing: 0

                            RowLayout {
                                id: head
                                Layout.fillWidth: true
                                spacing: Math.round(root.px * 1.5)

                                Text {
                                    Layout.fillWidth: true
                                    text: "[!] " + (toast.n.appName || "notification")
                                    color: Theme.a2
                                    font.family: Theme.font
                                    font.pixelSize: Math.round(root.px * 0.85)
                                    font.bold: true
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: root.px * 0.085
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: Qt.formatDateTime(root.received[toast.n.id] ?? new Date(), "HH:mm")
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Math.round(root.px * 0.85)
                                    font.letterSpacing: root.px * 0.085
                                }
                            }

                            Text {
                                id: summary
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: toast.n.summary
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: root.px
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Text {
                                id: body
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: toast.n.body
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: root.px
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            // Remaining time: a2 fill on a line-coloured 2 px track.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.topMargin: Math.round(root.px * 0.35)
                                implicitHeight: 2
                                color: Theme.line

                                Rectangle {
                                    width: Math.round(parent.width * toast.remaining)
                                    height: parent.height
                                    color: Theme.a2
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: toast.n.dismiss()
                        }
                    }
                }
            }
        }
    }
}
