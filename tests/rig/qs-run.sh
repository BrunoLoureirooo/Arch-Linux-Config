#!/usr/bin/env bash
# Run the repo's Quickshell config, staged as a throwaway HOME, inside the nested rig
# compositor (start it first with nested-hypr.sh).
#
#   qs-run.sh start [--restage] [--entry <file.qml>]
#       stage the repo into ~/.cache/rice-testbin/staged/home (stage.sh; the dir is
#       reused, --restage wipes it first so create_ files are reseeded), then start
#       `qs -p <staged>/.config/quickshell` in the background with HOME=<staged>,
#       XDG_{CONFIG,DATA,STATE,CACHE}_HOME inside it, RICE_NO_RELOAD=1 and
#       <staged>/.local/bin first on PATH (QS_RUN_BARE_PATH=1: no ~/.local/bin on PATH
#       at all, staged or real, as in the real session). Prints the staged HOME.
#       --entry runs a test config instead of shell.qml: the file is copied into the
#       staged config dir as rig-<name>.qml, so `import qs` / `import qs.components`
#       resolve against the staged shell exactly as production files do.
#       Any other environment (e.g. XDG_DATA_DIRS) is inherited from the caller.
#       Session bus: qs never runs on the live session bus (the shell's
#       NotificationServer would compete with the live mako for
#       org.freedesktop.Notifications). If the caller passes a private
#       DBUS_SESSION_BUS_ADDRESS, it is used; if the address is unset or the live one
#       ($XDG_RUNTIME_DIR/bus), qs-run.sh starts its own dbus-daemon (private-bus.conf:
#       no service activation), records its PID and stops it with qs.
#   qs-run.sh stop                 stop only the recorded qs (checked by marker env)
#   qs-run.sh status               running/not running, PID, staged HOME, entry
#   qs-run.sh log [qs log args]    qs log for that exact instance (--pid)
#   qs-run.sh ipc <qs ipc args>    e.g. qs-run.sh ipc call launcher toggle
#   qs-run.sh shot <output> <file> settle (QS_SETTLE seconds, default 1.5), then shot.sh
#   qs-run.sh home                 print the staged HOME
set -euo pipefail

R="$(dirname "$(realpath "$0")")"
TB="${RICE_TESTBIN:-$HOME/.cache/rice-testbin}"
STAGED="$TB/staged/home"
STATE="$TB/qs-run.env"
OUT="$TB/qs-run.out"

die() { echo "qs-run: $*" >&2; exit 1; }

# True only if <pid> is our process carrying RICE_QS_RUN_ID=<id> (a recorded PID alone
# proves nothing: the state file survives reboots and PIDs get reused).
pid_is_ours() {
    local pid="$1" id="$2"
    [[ "$pid" =~ ^[0-9]+$ && -n "$id" && -O "/proc/$pid" ]] || return 1
    tr '\0' '\n' 2>/dev/null <"/proc/$pid/environ" | grep -qxF "RICE_QS_RUN_ID=$id"
}

read_state() {
    [[ -s "$STATE" ]] || return 1
    QS_PID=$(sed -n 's/^QS_PID=//p' "$STATE")
    QS_RUN_ID=$(sed -n 's/^QS_RUN_ID=//p' "$STATE")
    QS_HOME=$(sed -n 's/^QS_HOME=//p' "$STATE")
    QS_ENTRY=$(sed -n 's/^QS_ENTRY=//p' "$STATE")
    QS_BUS_PID=$(sed -n 's/^QS_BUS_PID=//p' "$STATE")
    QS_BUS=$(sed -n 's/^QS_BUS=//p' "$STATE")
}

# The live session bus: unset, or the user bus socket under XDG_RUNTIME_DIR.
is_live_bus() {
    local a="$1" run="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    [[ -z "$a" || "$a" == *"path=$run/bus" || "$a" == *"path=$run/bus,"* ]]
}

# Stop the private dbus-daemon this script started (only a dbus-daemon we own).
stop_bus() {
    local pid="$1"
    [[ "$pid" =~ ^[0-9]+$ && -O "/proc/$pid" && "$(cat "/proc/$pid/comm" 2>/dev/null)" == dbus-daemon ]] || return 0
    kill -TERM "$pid" 2>/dev/null || true
}

is_running() { read_state && pid_is_ours "$QS_PID" "$QS_RUN_ID"; }

cmd_start() {
    local restage=0 entry=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --restage) restage=1; shift ;;
            --entry) [[ $# -ge 2 && -f "$2" ]] || die "--entry needs an existing .qml file"; entry=$(realpath "$2"); shift 2 ;;
            *) die "unknown start option: $1" ;;
        esac
    done
    if is_running; then die "already running (pid $QS_PID); run 'qs-run.sh stop' first"; fi
    rm -f "$STATE"
    "$R/nested-hypr.sh" status >/dev/null 2>&1 || die "nested rig is not running; run nested-hypr.sh start <config> first"

    if [[ $restage -eq 1 && -d "$STAGED" ]]; then
        [[ -e "$STAGED/.rice-stage" ]] || die "$STAGED has no .rice-stage marker; not deleting it"
        rm -rf -- "$STAGED"
    fi
    "$R/stage.sh" "$STAGED" >/dev/null

    local cfgdir="$STAGED/.config/quickshell" target
    target="$cfgdir"
    if [[ -n "$entry" ]]; then
        target="$cfgdir/rig-$(basename "$entry" .qml).qml"
        cp -f -- "$entry" "$target"
    fi

    local id bus="${DBUS_SESSION_BUS_ADDRESS:-}" bus_pid=""
    id="qsrun-$$-$(date +%s%N)"
    if is_live_bus "$bus"; then
        { read -r bus; read -r bus_pid; } < <(dbus-daemon --config-file="$R/private-bus.conf" --fork --nopidfile --print-address=1 --print-pid=1)
        [[ -n "$bus" && "$bus_pid" =~ ^[0-9]+$ ]] || die "could not start a private dbus-daemon"
    fi
    (
        # shellcheck source=tests/rig/rig_env.sh
        source "$R/rig_env.sh"
        local qpath="$STAGED/.local/bin:$PATH"
        if [[ -n "${QS_RUN_BARE_PATH:-}" ]]; then
            # Like the real session (greetd -> start-hyprland): no ~/.local/bin on PATH,
            # neither the staged one nor the real one.
            qpath=$(tr ':' '\n' <<<"$PATH" | grep -vxF -e "$STAGED/.local/bin" -e "$HOME/.local/bin" | paste -sd:)
        fi
        export RICE_QS_RUN_ID="$id" RICE_NO_RELOAD=1 HOME="$STAGED" \
            XDG_CONFIG_HOME="$STAGED/.config" XDG_DATA_HOME="$STAGED/.local/share" \
            XDG_STATE_HOME="$STAGED/.local/state" XDG_CACHE_HOME="$STAGED/.cache" \
            PATH="$qpath" DBUS_SESSION_BUS_ADDRESS="$bus"
        cd "$STAGED"
        exec qs -p "$target" --no-color
    ) >"$OUT" 2>&1 </dev/null &
    local pid=$!
    printf 'QS_PID=%s\nQS_RUN_ID=%s\nQS_HOME=%s\nQS_ENTRY=%s\nQS_BUS_PID=%s\nQS_BUS=%s\n' \
        "$pid" "$id" "$STAGED" "$target" "$bus_pid" "$bus" >"$STATE"

    local i
    for ((i = 0; i < 100; i++)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$STATE"
            stop_bus "$bus_pid"
            tail -n 30 "$OUT" >&2
            die "qs exited during startup (output: $OUT)"
        fi
        if "$R/run.sh" qs log --pid "$pid" -t 1 --no-color >/dev/null 2>&1; then
            echo "$STAGED"
            return 0
        fi
        sleep 0.1
    done
    cmd_stop >/dev/null
    die "qs did not become ready within 10 s (output: $OUT)"
}

cmd_stop() {
    if ! read_state; then echo "qs-run: not running"; return 0; fi
    if ! pid_is_ours "$QS_PID" "$QS_RUN_ID"; then
        stop_bus "$QS_BUS_PID"
        rm -f "$STATE"
        echo "qs-run: removed stale $STATE (pid $QS_PID not signalled)"
        return 0
    fi
    kill -TERM "$QS_PID" 2>/dev/null || true
    local i
    # Wait until the process is gone, zombie included (init reaps it), so the caller
    # never sees a half-dead instance.
    for ((i = 0; i < 50; i++)); do
        [[ -e "/proc/$QS_PID" ]] || break
        sleep 0.1
    done
    if pid_is_ours "$QS_PID" "$QS_RUN_ID"; then
        kill -KILL "$QS_PID" 2>/dev/null || true
        for ((i = 0; i < 20; i++)); do [[ -e "/proc/$QS_PID" ]] || break; sleep 0.1; done
    fi
    stop_bus "$QS_BUS_PID"
    rm -f "$STATE"
    echo "qs-run: stopped pid $QS_PID"
}

cmd_status() {
    if is_running; then
        echo "running: pid=$QS_PID home=$QS_HOME entry=$QS_ENTRY bus=$QS_BUS${QS_BUS_PID:+ (own dbus-daemon $QS_BUS_PID)}"
    else
        echo "not running"
        [[ ! -e "$STATE" ]] || echo "(stale $STATE present)"
        return 1
    fi
}

need_running() { is_running || die "not running; run 'qs-run.sh start' first"; }

case "${1:-}" in
    start) shift; cmd_start "$@" ;;
    stop) cmd_stop ;;
    status) cmd_status ;;
    log) shift; need_running; exec "$R/run.sh" qs log --pid "$QS_PID" --no-color "$@" ;;
    ipc) shift; need_running; exec "$R/run.sh" qs ipc --pid "$QS_PID" "$@" ;;
    shot)
        shift
        [[ $# -eq 2 ]] || die "usage: qs-run.sh shot <output> <file.png>"
        need_running
        sleep "${QS_SETTLE:-1.5}"
        exec "$R/shot.sh" "$1" "$2" ;;
    home) need_running; echo "$QS_HOME" ;;
    *) die "usage: qs-run.sh {start [--restage] [--entry file.qml]|stop|status|log|ipc|shot <output> <file>|home}" ;;
esac
