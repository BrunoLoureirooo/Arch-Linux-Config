#!/usr/bin/env bash
# Send synthetic keys to the nested compositor via its virtual keyboard:
#   keys.sh <wtype args...>     e.g. keys.sh -M logo -k F12 -m logo
#
# wtype uploads its own keymap (keycode 9 = first key it types). Hyprland resolves
# binds through the configured layout by default, so wtype's F12 would look like
# Escape to hl.bind. Setting input.resolve_binds_by_sym makes binds use the sending
# keyboard's keymap. It is applied at runtime (not in the config under test) before
# every call, so it survives `hyprctl reload`. Only virtual keyboards exist in the rig.
set -euo pipefail
[[ $# -gt 0 ]] || { echo "usage: keys.sh <wtype args...>" >&2; exit 2; }
# shellcheck source=tests/rig/rig_env.sh
source "$(dirname "$(realpath "$0")")/rig_env.sh"
hyprctl -i "$HYPRLAND_INSTANCE_SIGNATURE" eval 'hl.config({ input = { resolve_binds_by_sym = true } })' >/dev/null
exec wtype "$@"
