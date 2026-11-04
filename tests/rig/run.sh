#!/usr/bin/env bash
# Run any command against the nested compositor (testbin PATH, nested WAYLAND_DISPLAY
# and HYPRLAND_INSTANCE_SIGNATURE), e.g. run.sh hyprctl clients -j, run.sh qs -p x.qml
set -euo pipefail
[[ $# -gt 0 ]] || { echo "usage: run.sh <command> [args...]" >&2; exit 2; }
# shellcheck source=tests/rig/rig_env.sh
source "$(dirname "$(realpath "$0")")/rig_env.sh"
exec "$@"
