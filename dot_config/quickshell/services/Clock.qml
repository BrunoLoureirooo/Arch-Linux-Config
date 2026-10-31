pragma Singleton
// The shell's one clock (bar and rail). A plain JS Date read on the shared 2 s Stats
// tick: no timer of its own, no extra wakeups, and after a suspend/resume the time is
// right again within 2 s. `date` changes only when the shown minute or the UTC offset
// changes, so the clock texts re-render once a minute. Replaces Quickshell's
// SystemClock, which in 0.3.1 logged ~2,200 warnings/s at ~30% CPU during the
// repeated hour of the autumn DST change (docs/superpowers/notes/2026-10-23-nvidia-notes.md).
// `source` is a plain property so a test config can feed a mocked time; null = now.
import QtQuick
import Quickshell

Singleton {
    id: root

    property var source: null   // function returning a Date, or null for the real time
    property date date: new Date()

    function now() {
        return source ? source() : new Date();
    }

    // Re-read the time; assign only when the minute or the UTC offset moved (a DST
    // change moves the offset while the UTC minute keeps counting forward).
    function refresh() {
        const d = now();
        const minute = Math.floor(d.getTime() / 60000);
        if (minute !== Math.floor(date.getTime() / 60000) || d.getTimezoneOffset() !== date.getTimezoneOffset())
            date = d;
    }

    Connections {
        target: Stats
        function onTick() {
            root.refresh();
        }
    }
}
