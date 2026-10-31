#!/usr/bin/env bash
# shellcheck disable=SC2015  # echo never fails, so `test && echo || ...` is safe here
# Unplug/replug scenario, NESTED test rig only:
#   tests/rig/nested-hypr.sh start tests/rig/full.lua && tests/hypr/dock_scenario.sh
#
# For each headless output in turn: put a kitty on slot 2 of its pool, remove the
# output, assert the window survives and Ctrl+3 lands on slot 3 of the REMAINING
# monitor's pool, then recreate the output and print where workspaces and the
# window ended up (observed, not asserted). Exit 0 = all assertions passed.
set -euo pipefail
R="$(cd "$(dirname "$(realpath "$0")")/../rig" && pwd)"
# shellcheck source=tests/rig/rig_env.sh
source "$R/rig_env.sh"

H() { hyprctl -i "$HYPRLAND_INSTANCE_SIGNATURE" "$@"; }
fails=0
expect() { if [[ "$2" == "$3" ]]; then echo "PASS $1 ($3)"; else echo "FAIL $1: want $2, got $3"; fails=$((fails + 1)); fi; }
key() { "$R/keys.sh" "$@"; sleep 0.4; }
pool_of() { H repl "return require(\"binds\").pool_of(\"$1\")"; }
ws_id() { H repl "return require(\"lib.pools\").ws_id($1, $2)"; }
active_ws() {
    H monitors -j | python3 -I -c 'import json,sys; print(next(m["activeWorkspace"]["id"] for m in json.load(sys.stdin) if m["name"]==sys.argv[1]))' "$1"
}
client_of() { # "<ws id> <monitor name>" of window <address>, or "gone"
    local mons
    mons=$(H monitors -j)
    H clients -j | python3 -I -c '
import json,sys
mons={m["id"]: m["name"] for m in json.loads(sys.argv[2])}
c=[c for c in json.load(sys.stdin) if c["address"]==sys.argv[1]]
print(f"{c[0]["workspace"]["id"]} {mons.get(c[0]["monitor"], c[0]["monitor"])}" if c else "gone")' "$1" "$mons"
}
show() {
    echo "   monitors:   $(H monitors -j | python3 -I -c 'import json,sys; print(", ".join(f"{m["name"]} on {m["activeWorkspace"]["id"]}" + (" (focused)" if m["focused"] else "") for m in json.load(sys.stdin)))')"
    echo "   workspaces: $(H workspaces -j | python3 -I -c 'import json,sys; print(" ".join(f"{w["id"]}@{w["monitor"]}" for w in sorted(json.load(sys.stdin), key=lambda w: w["id"])))')"
}
spawn_kitty() {
    local before
    before=$(H clients -j | python3 -I -c 'import json,sys; print(" ".join(c["address"] for c in json.load(sys.stdin)))')
    H dispatch 'hl.dsp.exec_cmd("kitty")' >/dev/null
    for _ in $(seq 50); do
        addr=$(H clients -j | python3 -I -c 'import json,sys; print(next((c["address"] for c in json.load(sys.stdin) if c["class"]=="kitty" and c["address"] not in sys.argv[1].split()), ""))' "$before")
        [[ -n "$addr" ]] && break
        sleep 0.2
    done
    sleep 0.5
}

for gone in DP-1 eDP-1; do
    [[ "$gone" == DP-1 ]] && stay=eDP-1 || stay=DP-1
    echo "== scenario: unplug $gone (stays: $stay)"
    gone_pool=$(pool_of "$gone")
    stay_pool=$(pool_of "$stay")
    # Park the remaining monitor on slot 1 so the Ctrl+3 below has to move it.
    H dispatch "hl.dsp.focus({ monitor = \"$stay\" })" >/dev/null; sleep 0.2
    key -M ctrl -k 1 -m ctrl
    expect "$stay parked on slot 1" "$(ws_id "$stay_pool" 1)" "$(active_ws "$stay")"
    H dispatch "hl.dsp.focus({ monitor = \"$gone\" })" >/dev/null; sleep 0.2
    key -M ctrl -k 2 -m ctrl
    addr=""
    spawn_kitty
    [[ -n "$addr" ]] || { echo "FAIL kitty did not open"; exit 1; }
    expect "kitty on slot 2 of $gone" "$(ws_id "$gone_pool" 2) $gone" "$(client_of "$addr")"
    show

    H output remove "$gone" >/dev/null; sleep 1
    echo "-- after output remove $gone"
    show
    where=$(client_of "$addr")
    echo "   window: $where"
    [[ "$where" != gone ]] && echo "PASS window still exists after unplug" || { echo "FAIL window lost"; fails=$((fails + 1)); }
    key -M ctrl -k 3 -m ctrl
    expect "Ctrl+3 lands on slot 3 of $stay" "$(ws_id "$stay_pool" 3)" "$(active_ws "$stay")"

    H output create headless "$gone" >/dev/null; sleep 1.5
    echo "-- after output create headless $gone (observed)"
    show
    echo "   window: $(client_of "$addr")"
    echo "   pool_of($gone) now: $(pool_of "$gone")"
    H dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null; sleep 0.5
done

[[ $fails -eq 0 ]] && echo "DOCK_SCENARIO OK" || { echo "DOCK_SCENARIO: $fails failure(s)"; exit 1; }
