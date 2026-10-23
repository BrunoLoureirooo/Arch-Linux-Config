# shellcheck shell=bash
# Sourced by every rig script: puts the private testbin on PATH and points
# WAYLAND_DISPLAY / HYPRLAND_INSTANCE_SIGNATURE at the nested instance started by
# tests/rig/nested-hypr.sh. Exits (non-zero) if that would reach the live session.

RICE_TESTBIN="${RICE_TESTBIN:-$HOME/.cache/rice-testbin}"

rig_die() { echo "rig_env: $*" >&2; exit 1; }

[[ -r "$RICE_TESTBIN/env.sh" ]] || rig_die "$RICE_TESTBIN/env.sh missing; run tests/rig/setup-testbin.sh"
_rig_tb="$RICE_TESTBIN"
# shellcheck source=/dev/null
source "$RICE_TESTBIN/env.sh"
RICE_TESTBIN="$_rig_tb"   # env.sh re-exports its own path; keep the one we were given
unset _rig_tb

# Drop anything inherited from the live session before reading nested.env.
unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DISPLAY
[[ -r "$RICE_TESTBIN/nested.env" ]] \
    || rig_die "no nested instance ($RICE_TESTBIN/nested.env missing); run tests/rig/nested-hypr.sh start <config>"
# shellcheck source=/dev/null
source "$RICE_TESTBIN/nested.env"

[[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || rig_die "HYPRLAND_INSTANCE_SIGNATURE is empty after reading nested.env"
[[ -n "${WAYLAND_DISPLAY:-}" ]] || rig_die "WAYLAND_DISPLAY is empty after reading nested.env"
[[ -s "$RICE_TESTBIN/live.sig" ]] || rig_die "$RICE_TESTBIN/live.sig missing; run tests/rig/setup-testbin.sh"
if grep -qxF -- "$HYPRLAND_INSTANCE_SIGNATURE" "$RICE_TESTBIN/live.sig"; then
    rig_die "REFUSING: HYPRLAND_INSTANCE_SIGNATURE is the live session ($HYPRLAND_INSTANCE_SIGNATURE)"
fi
_rig_lock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.lock"
[[ -f "$_rig_lock" && "$(sed -n 2p "$_rig_lock")" == "$WAYLAND_DISPLAY" ]] \
    || rig_die "nested instance $HYPRLAND_INSTANCE_SIGNATURE is not running or its socket does not match"
kill -0 "$NESTED_PID" 2>/dev/null || rig_die "nested Hyprland (pid $NESTED_PID) is not running"
unset _rig_lock
export QT_QPA_PLATFORM=wayland
