// Toast probe (test config only, never part of production). Runs the production
// Toasts plus an IpcHandler that reads their state, so Toasts.qml carries no test code.
// MUST run on a private session bus (the NotificationServer claims
// org.freedesktop.Notifications on whatever bus qs is on):
//   DBUS_SESSION_BUS_ADDRESS=<private> tests/rig/qs-run.sh start --entry tests/rig/toasts.qml
//   qs-run.sh ipc call toasts get         -> tracked count, shown toasts, window geometry
//   qs-run.sh ipc call toasts dismissAll  -> clean slate between checks
import QtQuick
import Quickshell
import Quickshell.Io
import qs.notifications

ShellRoot {
    Toasts {
        id: toasts
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

    // The body Text of a toast as drawn: its text, whether it is plain text, its laid-out
    // width, and the advance width of the same string measured as plain text. Styled or
    // rich rendering of markup makes the two widths differ.
    TextMetrics {
        id: metrics
    }

    function bodyOf(t) {
        const body = findAll(t, i => i.textFormat !== undefined && i.text !== "" && i.text === t.n.body, [])[0];
        if (!body)
            return null;
        metrics.font = body.font;
        metrics.text = body.text;
        return { text: body.text, plain: body.textFormat === Text.PlainText,
                 width: Math.round(body.contentWidth), literalWidth: Math.round(metrics.advanceWidth),
                 lines: body.lineCount, implicit: body.implicitWidth, box: body.width };
    }

    IpcHandler {
        target: "toasts"

        function get(): string {
            const win = toasts.windowLoader.item;
            const shown = win ? findAll(win.contentItem, i => i.n !== undefined && i.critical !== undefined, []) : [];
            return JSON.stringify({
                tracked: toasts.server.trackedNotifications.values.map(n => n.summary),
                window: win ? { screen: win.screen.name, w: win.width, h: win.height,
                                right: win.margins.right, bottom: win.margins.bottom } : null,
                shown: shown.map(t => ({
                    summary: t.n.summary, app: t.n.appName, critical: t.critical,
                    timeout: t.timeout, remaining: Math.round(t.remaining * 100) / 100,
                    x: Math.round(t.mapToItem(win.contentItem, 0, 0).x),
                    y: Math.round(t.mapToItem(win.contentItem, 0, 0).y),
                    w: Math.round(t.width), h: Math.round(t.height),
                    body: bodyOf(t)
                }))
            });
        }

        function dismissAll(): void {
            for (const n of toasts.server.trackedNotifications.values.slice())
                n.dismiss();
        }
    }
}
