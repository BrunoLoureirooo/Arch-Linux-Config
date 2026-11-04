#!/usr/bin/env bash
# Check that QML modules the shell needs import (and a key type instantiates) under
# the private qs, inside the nested compositor. Needs a running nested instance.
#   qs-imports.sh            -> one line per module: OK / FAIL <first error line>
set -euo pipefail
# shellcheck source=tests/rig/rig_env.sh
source "$(dirname "$(realpath "$0")")/rig_env.sh"

work="$RICE_TESTBIN/qs-imports"
rm -rf "$work"
mkdir -p "$work"

# module | object instantiated inside ShellRoot (empty = import only)
checks=(
    "Quickshell.Hyprland|property var x: Hyprland.monitors"
    "Quickshell.Bluetooth|property var x: Bluetooth.adapters"
    "Quickshell.Services.Notifications|"
    "Quickshell.Services.Mpris|property var x: Mpris.players"
    "Quickshell.Services.Pipewire|property var x: Pipewire.ready"
    "Quickshell.Services.UPower|property var x: UPower.displayDevice"
    "Quickshell.Wayland|property Component x: Component { ScreencopyView {} }"
    "QtQuick.Shapes|property Component x: Component { Shape {} }"
    "Qt.labs.folderlistmodel|property Component x: Component { FolderListModel {} }"
)

fail=0
for c in "${checks[@]}"; do
    mod="${c%%|*}"
    body="${c#*|}"
    f="$work/${mod//./_}.qml"
    cat >"$f" <<QML
import QtQuick
import Quickshell
import $mod
ShellRoot {
    $body
    Component.onCompleted: { console.log("IMPORT_OK $mod"); Qt.quit(); }
}
QML
    out=$(timeout 20 qs -p "$f" --no-color 2>&1 || true)
    if grep -q "IMPORT_OK $mod" <<<"$out"; then
        echo "OK   $mod"
    else
        fail=1
        echo "FAIL $mod: $(grep -m1 -E 'ERROR|error|not installed|not a type' <<<"$out" || echo "${out##*$'\n'}")"
    fi
done
exit "$fail"
