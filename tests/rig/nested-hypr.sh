#!/usr/bin/env bash
# Headless nested Hyprland for tests. Never touches the live session.
#
#   nested-hypr.sh start <config.lua> [output-name ...]   (default outputs: DP-1 eDP-1)
#   nested-hypr.sh start <xdg-config-dir> [output-name ...]
#       a directory D runs Hyprland with no --config and XDG_CONFIG_HOME=D, so it uses
#       Hyprland's own discovery in D/hypr/ (for testing a rendered config tree)
#   nested-hypr.sh stop
#   nested-hypr.sh env       print the nested.env exports
#   nested-hypr.sh status
#
# How it stays invisible: Aquamarine 0.15 needs a buffer allocator from a DRM or a
# Wayland backend; its headless backend alone cannot start. So Hyprland runs as a
# Wayland client of a private labwc (wlroots) compositor that itself uses only the
# wlroots headless backend (WLR_BACKENDS=headless): nothing is drawn on a real
# screen. labwc is used because Aquamarine binds xdg_wm_base v6 and cage/sway only
# offer v5. Aquamarine's DRM backend is kept off by pointing libseat at a backend
# that does not exist, so it can never open a seat session or a GPU card node.
# Tests use Hyprland headless outputs (`hyprctl output create headless <name>`); the
# WAYLAND-1 output Hyprland makes inside labwc is removed after start.
set -euo pipefail

TB="${RICE_TESTBIN:-$HOME/.cache/rice-testbin}"
NESTED_ENV="$TB/nested.env"
RUNDIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LOG="$TB/nested.log"

die() { echo "nested-hypr: $*" >&2; exit 1; }

[[ -r "$TB/env.sh" ]] || die "$TB/env.sh missing; run tests/rig/setup-testbin.sh first"
# shellcheck source=/dev/null
source "$TB/env.sh"
command -v labwc >/dev/null || die "labwc not found in testbin; rerun setup-testbin.sh"

live_sigs() { cat "$TB/live.sig" 2>/dev/null || true; }

is_running() {
    [[ -s "$NESTED_ENV" ]] || return 1
    local pid
    pid=$(sed -n 's/^export NESTED_PID=//p' "$NESTED_ENV")
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# PIDs of our own processes that carry this rig's marker in their environment.
marked_pids() {
    local id="$1" p
    for p in /proc/[0-9]*; do
        [[ -O "$p" ]] || continue
        [[ "${p#/proc/}" == "$$" ]] && continue
        if tr '\0' '\n' 2>/dev/null <"$p/environ" | grep -qxF "RICE_RIG_ID=$id"; then
            echo "${p#/proc/}"
        fi
    done
}

marked_hyprland() {
    local p
    for p in $(marked_pids "$1"); do
        [[ "$(cat "/proc/$p/comm" 2>/dev/null)" == Hyprland ]] && echo "$p"
    done
    return 0
}

# Kill the rig's Hyprland, its labwc parent, then every straggler carrying the marker.
kill_all() {
    local id="$1" parent="$2" pids i
    pids=$(marked_hyprland "$id")
    # shellcheck disable=SC2086
    [[ -z "$pids" ]] || kill -TERM $pids 2>/dev/null || true
    for ((i = 0; i < 50; i++)); do
        [[ -z "$(marked_hyprland "$id")" ]] && break
        sleep 0.1
    done
    kill -TERM "$parent" 2>/dev/null || true
    sleep 0.3
    pids=$(marked_pids "$id")
    if [[ -n "$pids" ]]; then
        # shellcheck disable=SC2086
        kill -TERM $pids 2>/dev/null || true
        sleep 0.5
        pids=$(marked_pids "$id")
        # shellcheck disable=SC2086
        [[ -z "$pids" ]] || kill -KILL $pids 2>/dev/null || true
    fi
}

cmd_start() {
    local config="${1:-}"
    [[ -n "$config" ]] || die "usage: nested-hypr.sh start <config.lua|xdg-config-dir> [output-name ...]"
    [[ -e "$config" ]] || die "config not found: $config"
    config=$(realpath "$config")
    shift
    local xdg_config="$TB/xdg/config" hypr_cmd="Hyprland --config '$config'"
    if [[ -d "$config" ]]; then
        [[ "$config" != "$(realpath "$HOME/.config")" ]] || die "refusing to use the live ~/.config"
        [[ -d "$config/hypr" ]] || die "$config/hypr does not exist"
        xdg_config="$config"
        hypr_cmd="Hyprland"
    fi
    local outputs=("$@")
    [[ ${#outputs[@]} -gt 0 ]] || outputs=(DP-1 eDP-1)

    if is_running; then
        die "a nested instance is already running (see $NESTED_ENV); run 'nested-hypr.sh stop' first"
    fi
    rm -f "$NESTED_ENV" "$TB/bind-fired"

    local rig_id xdg before
    rig_id="rig-$$-$(date +%s%N)"
    xdg="$TB/xdg"
    mkdir -p "$xdg/config" "$xdg/data" "$xdg/state" "$xdg/cache" "$TB/labwc"
    before=$(find "$RUNDIR/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort || true)

    # Clean environment: nothing may point at the live compositor.
    (
        unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE HYPRLAND_CMD DISPLAY NOTIFY_SOCKET \
            SWAYSOCK XDG_SESSION_ID LABWC_PID
        export RICE_RIG_ID="$rig_id"
        export XDG_CONFIG_HOME="$xdg_config" XDG_DATA_HOME="$xdg/data" \
            XDG_STATE_HOME="$xdg/state" XDG_CACHE_HOME="$xdg/cache"
        export HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_SD_NOTIFY=1 HYPRLAND_NO_CRASHREPORTER=1
        export LIBSEAT_BACKEND=rig-no-seat         # no seat session -> Aquamarine DRM backend off
        export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_HEADLESS_OUTPUTS=1
        export LABWC_UPDATE_ACTIVATION_ENV=false   # never touch the systemd/dbus user env
        # -C: private, empty labwc config dir (no autostart from ~/.config or /etc/xdg).
        exec setsid labwc -C "$TB/labwc" -s "$hypr_cmd"
    ) >"$LOG" 2>&1 </dev/null &
    local parent_pid=$!

    # Find our Hyprland (it carries RICE_RIG_ID) and its new instance directory.
    local hypr_pid="" sig="" i d
    for ((i = 0; i < 150; i++)); do
        if ! kill -0 "$parent_pid" 2>/dev/null; then
            kill_all "$rig_id" "$parent_pid"
            tail -n 30 "$LOG" >&2
            die "labwc exited during startup (log: $LOG)"
        fi
        [[ -n "$hypr_pid" ]] || hypr_pid=$(marked_hyprland "$rig_id" | head -n 1)
        if [[ -n "$hypr_pid" ]]; then
            for d in $(comm -13 <(echo "$before") \
                <(find "$RUNDIR/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)); do
                if [[ -f "$RUNDIR/hypr/$d/hyprland.lock" ]] \
                    && [[ "$(head -n 1 "$RUNDIR/hypr/$d/hyprland.lock")" == "$hypr_pid" ]]; then
                    sig="$d"
                fi
            done
        fi
        [[ -n "$sig" ]] && break
        sleep 0.1
    done
    if [[ -z "$sig" ]]; then
        kill_all "$rig_id" "$parent_pid"
        tail -n 30 "$LOG" >&2
        die "nested Hyprland did not come up (log: $LOG)"
    fi
    if live_sigs | grep -qxF "$sig"; then
        kill_all "$rig_id" "$parent_pid"
        die "refusing: new instance signature equals a recorded live one ($sig)"
    fi

    local wl parent_wl
    wl=$(sed -n 2p "$RUNDIR/hypr/$sig/hyprland.lock")
    parent_wl=$(tr '\0' '\n' <"/proc/$hypr_pid/environ" | sed -n 's/^WAYLAND_DISPLAY=//p')
    [[ -n "$wl" && "$wl" != "$parent_wl" ]] || { kill_all "$rig_id" "$parent_pid"; die "could not read nested WAYLAND_DISPLAY"; }

    cat >"$NESTED_ENV" <<ENV
export NESTED_PID=$hypr_pid
export NESTED_PARENT_PID=$parent_pid
export RICE_RIG_ID=$rig_id
export HYPRLAND_INSTANCE_SIGNATURE=$sig
export WAYLAND_DISPLAY=$wl
export NESTED_PARENT_WAYLAND_DISPLAY=$parent_wl
export NESTED_CONFIG=$(printf %q "$config")
export NESTED_LOG=$RUNDIR/hypr/$sig/hyprland.log
ENV

    for ((i = 0; i < 100; i++)); do
        hyprctl -i "$sig" version >/dev/null 2>&1 && break
        sleep 0.1
    done
    hyprctl -i "$sig" version >/dev/null 2>&1 || { cmd_stop; die "hyprctl -i $sig version never answered"; }

    local o
    for o in "${outputs[@]}"; do
        hyprctl -i "$sig" output create headless "$o" >/dev/null
    done
    # Drop the labwc-hosted output so only the requested headless outputs remain.
    hyprctl -i "$sig" output remove WAYLAND-1 >/dev/null 2>&1 || true
    for ((i = 0; i < 50; i++)); do
        [[ $(hyprctl -i "$sig" monitors -j | python3 -I -c 'import json,sys; print(len(json.load(sys.stdin)))') \
            -eq ${#outputs[@]} ]] && break
        sleep 0.1
    done

    echo "nested Hyprland up: pid=$hypr_pid sig=$sig WAYLAND_DISPLAY=$wl"
    hyprctl -i "$sig" monitors | grep '^Monitor' || true
}

cmd_stop() {
    [[ -s "$NESTED_ENV" ]] || { echo "nested-hypr: not running"; return 0; }
    local pid parent id sig
    pid=$(sed -n 's/^export NESTED_PID=//p' "$NESTED_ENV")
    parent=$(sed -n 's/^export NESTED_PARENT_PID=//p' "$NESTED_ENV")
    id=$(sed -n 's/^export RICE_RIG_ID=//p' "$NESTED_ENV")
    sig=$(sed -n 's/^export HYPRLAND_INSTANCE_SIGNATURE=//p' "$NESTED_ENV")
    [[ -n "$pid" && -n "$parent" && -n "$id" && -n "$sig" ]] || die "malformed $NESTED_ENV"
    kill_all "$id" "$parent"
    # Hyprland removes its lock on exit but leaves the instance dir (log + stale
    # socket). Keep a copy of the log, then remove the dir only if it is ours: not a
    # recorded live signature, our PID is gone, and no lock names another process.
    local dir="$RUNDIR/hypr/$sig" lockpid=""
    [[ -f "$dir/hyprland.lock" ]] && lockpid=$(head -n 1 "$dir/hyprland.lock")
    if [[ -d "$dir" ]] && ! live_sigs | grep -qxF "$sig" && ! kill -0 "$pid" 2>/dev/null \
        && [[ -z "$lockpid" || "$lockpid" == "$pid" ]]; then
        cp -f "$dir/hyprland.log" "$TB/last-nested-hyprland.log" 2>/dev/null || true
        rm -rf -- "$dir"
    fi
    rm -f "$NESTED_ENV"
    echo "nested Hyprland stopped (pid $pid, sig $sig)"
}

cmd_env() {
    is_running || die "not running"
    cat "$NESTED_ENV"
}

cmd_status() {
    if is_running; then
        # shellcheck source=/dev/null
        source "$NESTED_ENV"
        echo "running: pid=$NESTED_PID sig=$HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
        hyprctl -i "$HYPRLAND_INSTANCE_SIGNATURE" monitors | grep '^Monitor' || true
    else
        echo "not running"
        [[ ! -e "$NESTED_ENV" ]] || echo "(stale $NESTED_ENV present)"
        return 1
    fi
}

case "${1:-}" in
    start) shift; cmd_start "$@" ;;
    stop) cmd_stop ;;
    env) cmd_env ;;
    status) cmd_status ;;
    *) die "usage: nested-hypr.sh {start <config> [output...]|stop|env|status}" ;;
esac
