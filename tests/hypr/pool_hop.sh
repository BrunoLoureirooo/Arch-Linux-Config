#!/usr/bin/env bash
# shellcheck disable=SC2015  # echo never fails, so `test && echo || ...` is safe here
# Pool hop (Ctrl+Alt+Up/Down) after an output goes away, NESTED test rig only:
#   tests/rig/nested-hypr.sh start tests/rig/full.lua && tests/hypr/pool_hop.sh
#
# A. "unplug": a kitty on slot 3 of DP-1's pool, remove DP-1; on eDP-1 the hop reaches
#    the moved pool (same slot, where the kitty is), wraps back, and Ctrl+N still acts on
#    eDP-1's own pool. B. "lid close": remove eDP-1 (its persistent pool moves to DP-1);
#    on DP-1 the hop reaches eDP-1's pool and Ctrl+3 returns to DP-1's own pool.
# Pools are asked from the nested instance (in the rig eDP-1 is pool 1, DP-1 pool 2).
# Exit 0 = all passed.
set -euo pipefail
R="$(cd "$(dirname "$(realpath "$0")")/../rig" && pwd)"
# shellcheck source=tests/rig/rig_env.sh
source "$R/rig_env.sh"

H() { hyprctl -i "$HYPRLAND_INSTANCE_SIGNATURE" "$@"; }
fails=0
expect() { if [[ "$2" == "$3" ]]; then echo "PASS $1 ($3)"; else echo "FAIL $1: want $2, got $3"; fails=$((fails + 1)); fi; }
key() { "$R/keys.sh" "$@"; sleep 0.4; }
up() { key -M ctrl -M alt -k Up -m alt -m ctrl; }
down() { key -M ctrl -M alt -k Down -m alt -m ctrl; }
pool_of() { H repl "return require(\"binds\").pool_of(\"$1\")"; }
ws_id() { H repl "return require(\"lib.pools\").ws_id($1, $2)"; }
active_ws() {
    H monitors -j | python3 -I -c 'import json,sys; print(next(m["activeWorkspace"]["id"] for m in json.load(sys.stdin) if m["name"]==sys.argv[1]))' "$1"
}
focus_mon() { H dispatch "hl.dsp.focus({ monitor = \"$1\" })" >/dev/null; sleep 0.3; }
kpid=""
stop_kitty() { # by PID, only if it carries this rig's marker (window.close raises kitty's prompt)
    if [[ -n "$kpid" ]] && tr '\0' '\n' <"/proc/$kpid/environ" 2>/dev/null | grep -qxF "RICE_RIG_ID=$RICE_RIG_ID"; then
        kill "$kpid" 2>/dev/null || true; sleep 0.5
    fi
    kpid=""
}
restore() {
    stop_kitty
    for o in DP-1 eDP-1; do
        H monitors -j | grep -q "\"name\": \"$o\"" || H output create headless "$o" >/dev/null 2>&1 || true
    done
}
trap restore EXIT

p_dp=$(pool_of DP-1)
p_ed=$(pool_of eDP-1)
echo "== pools: DP-1 $p_dp, eDP-1 $p_ed"

# --- A: DP-1 goes away ----------------------------------------------------------
focus_mon DP-1
key -M ctrl -k 3 -m ctrl
expect "DP-1 on slot 3 of its pool" "$(ws_id "$p_dp" 3)" "$(active_ws DP-1)"
H dispatch 'hl.dsp.exec_cmd("kitty")' >/dev/null
for _ in $(seq 50); do
    kpid=$(H clients -j | python3 -I -c 'import json,sys; print(next((str(c["pid"]) for c in json.load(sys.stdin) if c["class"]=="kitty"), ""))')
    [[ -n "$kpid" ]] && break
    sleep 0.2
done
[[ -n "$kpid" ]] || { echo "FAIL kitty did not open"; exit 1; }
sleep 0.5
H output remove DP-1 >/dev/null; sleep 1
focus_mon eDP-1
key -M ctrl -k 3 -m ctrl
expect "eDP-1 on its own slot 3" "$(ws_id "$p_ed" 3)" "$(active_ws eDP-1)"
up
expect "Ctrl+Alt+Up reaches the moved pool, same slot" "$(ws_id "$p_dp" 3)" "$(active_ws eDP-1)"
win_ws=$(H clients -j | python3 -I -c 'import json,sys; print(next((c["workspace"]["id"] for c in json.load(sys.stdin) if str(c["pid"])==sys.argv[1]), ""))' "$kpid")
expect "the stranded kitty is on that workspace" "$(active_ws eDP-1)" "$win_ws"
up
expect "Ctrl+Alt+Up wraps back to the own pool" "$(ws_id "$p_ed" 3)" "$(active_ws eDP-1)"
down
expect "Ctrl+Alt+Down reaches the moved pool" "$(ws_id "$p_dp" 3)" "$(active_ws eDP-1)"
key -M ctrl -k 2 -m ctrl
expect "Ctrl+2 from the moved pool goes to eDP-1's own slot 2" "$(ws_id "$p_ed" 2)" "$(active_ws eDP-1)"
stop_kitty
H output create headless DP-1 >/dev/null; sleep 1.5

# --- B: eDP-1 goes away (lid close) -----------------------------------------------
focus_mon eDP-1
key -M ctrl -k 3 -m ctrl
H output remove eDP-1 >/dev/null; sleep 1
focus_mon DP-1
key -M ctrl -k 3 -m ctrl
expect "DP-1 on its own slot 3" "$(ws_id "$p_dp" 3)" "$(active_ws DP-1)"
up
expect "Ctrl+Alt+Up reaches eDP-1's moved pool" "$(ws_id "$p_ed" 3)" "$(active_ws DP-1)"
key -M ctrl -k 3 -m ctrl
expect "Ctrl+3 returns to DP-1's own pool" "$(ws_id "$p_dp" 3)" "$(active_ws DP-1)"
H output create headless eDP-1 >/dev/null; sleep 1.5

[[ $fails -eq 0 ]] && echo "POOL_HOP OK" || { echo "POOL_HOP: $fails failure(s)"; exit 1; }
