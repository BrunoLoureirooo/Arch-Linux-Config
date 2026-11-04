pragma Singleton
// Which keyboard-grabbing overlay is open: "launcher", "carousel" or "". Both take
// Exclusive keyboard focus, so only one may exist: opening one claims the slot, and
// the other closes itself when it sees the slot taken.
import QtQuick
import Quickshell

Singleton {
    property string active: ""

    function claim(name) {
        active = name;
    }

    function release(name) {
        if (active === name)
            active = "";
    }
}
