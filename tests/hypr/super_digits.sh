#!/usr/bin/env bash
# shellcheck disable=SC2015  # echo never fails, so `test && echo || ...` is safe here
# Super+1..5 / Super+Shift+1..5 (same actions as Ctrl+N / Ctrl+Shift+N), checked
# against the NESTED test rig only:
#   tests/rig/nested-hypr.sh start tests/rig/full.lua && tests/hypr/super_digits.sh
#
# Keys go through tests/rig/keys.sh (wtype into the nested compositor). Pools are
# asked from the nested instance (binds.pool_of), never hardcoded.
# Asserts: on each of the two outputs Super+3 jumps to slot 3 of that output's own
# pool, leaves the other output alone and keeps focus; Super+Shift+3 moves a window
# to slot 3 of the focused output's pool. Exit 0 = all passed.
set -euo pipefail
R="$(cd "$(dirname "$(realpath "$0")")/../rig" && pwd)"
# shellcheck source=tests/rig/rig_env.sh
source "$R/rig_env.sh"   # aborts unless the nested instance is up and not the live one

H() { hyprctl -i "$HYPRLAND_INSTANCE_SIGNATURE" "$@"; }
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
expect() { # expect <description> <want> <got>
    if [[ "$2" == "$3" ]]; then pass "$1 ($3)"; else fail "$1: want $2, got $3"; fi
}

active_ws() { # active workspace id of monitor <name>
    H monitors -j | python3 -I -c 'import json,sys; print(next(m["activeWorkspace"]["id"] for m in json.load(sys.stdin) if m["name"]==sys.argv[1]))' "$1"
}
focused_mon() {
    H monitors -j | python3 -I -c 'import json,sys; print(next(m["name"] for m in json.load(sys.stdin) if m["focused"]))'
}
pool_of() { H repl "return require(\"binds\").pool_of(\"$1\")"; }
ws_id() { H repl "return require(\"lib.pools\").ws_id($1, $2)"; }
focus_mon() { H dispatch "hl.dsp.focus({ monitor = \"$1\" })" >/dev/null; sleep 0.2; }
key() { "$R/keys.sh" "$@"; sleep 0.3; }

mapfile -t mons < <(H monitors -j | python3 -I -c 'import json,sys; [print(m["name"]) for m in json.load(sys.stdin)]')
[[ ${#mons[@]} -eq 2 ]] || { echo "super_digits: need exactly 2 monitors in the rig, have: ${mons[*]}" >&2; exit 1; }

for ((m = 0; m < 2; m++)); do
    a=${mons[m]} b=${mons[1 - m]}
    pool=$(pool_of "$a") || { fail "pool_of($a) not available (binds module missing?)"; continue; }
    [[ "$pool" =~ ^[0-9]+$ ]] || { fail "pool_of($a) returned '$pool'"; continue; }
    echo "== $a: pool $pool (other monitor $b)"
    focus_mon "$a"
    key -M ctrl -k 1 -m ctrl   # start from slot 1 so Super+3 is a real move
    expect "start on slot 1 of $a" "$(ws_id "$pool" 1)" "$(active_ws "$a")"

    other_before=$(active_ws "$b")
    key -M logo -k 3 -m logo
    expect "Super+3 on $a" "$(ws_id "$pool" 3)" "$(active_ws "$a")"
    expect "Super+3 leaves $b alone" "$other_before" "$(active_ws "$b")"
    expect "focus stays on $a" "$a" "$(focused_mon)"
    key -M logo -k 5 -m logo
    expect "Super+5 on $a" "$(ws_id "$pool" 5)" "$(active_ws "$a")"
    key -M logo -k 1 -m logo
    expect "Super+1 on $a" "$(ws_id "$pool" 1)" "$(active_ws "$a")"
    expect "Super+N leaves $b alone" "$other_before" "$(active_ws "$b")"
done

# Super+Shift+3 moves the focused window within the focused monitor's pool.
a=${mons[1]} b=${mons[0]}
pool=$(pool_of "$a") || { fail "pool_of($a) not available"; echo "SUPER_DIGITS: $fails failure(s)"; exit 1; }
focus_mon "$a"
key -M logo -k 1 -m logo
other_before=$(active_ws "$b")
H dispatch 'hl.dsp.exec_cmd("kitty")' >/dev/null
win=""
for _ in $(seq 50); do
    win=$(H clients -j | python3 -I -c 'import json,sys; print(next((c["address"] for c in json.load(sys.stdin) if c["class"]=="kitty"), ""))')
    [[ -n "$win" ]] && break
    sleep 0.2
done
if [[ -z "$win" ]]; then
    fail "kitty did not open in the rig"
else
    addr=$win
    sleep 0.5
    key -M logo -M shift -k 3 -m shift -m logo
    got=$(H clients -j | python3 -I -c 'import json,sys; print(next(f"{c["workspace"]["id"]} {c["monitor"]}" for c in json.load(sys.stdin) if c["address"]==sys.argv[1]))' "$addr")
    mon_id=$(H monitors -j | python3 -I -c 'import json,sys; print(next(m["id"] for m in json.load(sys.stdin) if m["name"]==sys.argv[1]))' "$a")
    expect "Super+Shift+3 moves window to slot 3 of $a" "$(ws_id "$pool" 3) $mon_id" "$got"
    expect "Super+Shift+3 leaves $b alone" "$other_before" "$(active_ws "$b")"
    H dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null
fi

[[ $fails -eq 0 ]] && echo "SUPER_DIGITS OK" || { echo "SUPER_DIGITS: $fails failure(s)"; exit 1; }
