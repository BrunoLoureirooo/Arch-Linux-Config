#!/usr/bin/env bash
# Static check of a Hyprland Lua config without starting a compositor:
#   verify-config.sh <hyprland.lua>   -> prints Hyprland's parse result, exit 0 = "config ok"
# Runs with a clean environment (no live WAYLAND_DISPLAY / HYPRLAND_INSTANCE_SIGNATURE)
# and scratch XDG dirs, so nothing can touch the live session or ~/.config.
set -euo pipefail
[[ $# -eq 1 && -f "$1" ]] || { echo "usage: verify-config.sh <hyprland.lua>" >&2; exit 2; }
TB="${RICE_TESTBIN:-$HOME/.cache/rice-testbin}"
mkdir -p "$TB/xdg/config" "$TB/xdg/data" "$TB/xdg/state" "$TB/xdg/cache"
out=$(env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY \
    XDG_CONFIG_HOME="$TB/xdg/config" XDG_DATA_HOME="$TB/xdg/data" \
    XDG_STATE_HOME="$TB/xdg/state" XDG_CACHE_HOME="$TB/xdg/cache" \
    Hyprland --verify-config --config "$(realpath "$1")" 2>&1) && rc=0 || rc=$?
# Print only the parse result block (drop Hyprland's startup debug lines).
sed -n '/======== Config parsing result:/,$p' <<<"$out"
exit "$rc"
