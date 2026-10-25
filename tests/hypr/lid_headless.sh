#!/usr/bin/env bash
# shellcheck disable=SC2015  # echo never fails, so `test && echo || ...` is safe here
# The repo's lid and headless scripts against the NESTED test rig only:
#   tests/rig/nested-hypr.sh start tests/rig/full.lua   && tests/hypr/lid_headless.sh   (Lua config)
#   tests/rig/nested-hypr.sh start tests/rig/legacy.conf && tests/hypr/lid_headless.sh  (hyprlang rollback)
#
# lid close/open are hyprctl-only. headless also runs `sudo -n headless-peripherals`, so
# it runs with PATH set to a temp dir holding a FAKE sudo (records its arguments) and
# links to hyprctl and the few tools the script needs: the real sudo is unreachable.
# Asserts: close disables eDP-1 and moves its workspaces to DP-1, open restores it;
# headless turns dpms off on every output (peripherals called after), again turns it on
# (peripherals called before). Exit 0 = all passed.
set -euo pipefail
R="$(cd "$(dirname "$(realpath "$0")")/../rig" && pwd)"
BIN="$(cd "$R/../../dot_local/bin" && pwd)"
# shellcheck source=tests/rig/rig_env.sh
source "$R/rig_env.sh"   # aborts unless the nested instance is up and not the live one

fails=0
expect() { if [[ "$2" == "$3" ]]; then echo "PASS $1 ($3)"; else echo "FAIL $1: want $2, got $3"; fails=$((fails + 1)); fi; }
H() { hyprctl -i "$HYPRLAND_INSTANCE_SIGNATURE" "$@"; }
state() { # "name:disabled:dpms ..." for every output, enabled or not
    H monitors all -j | python3 -I -c 'import json,sys; print(" ".join(f"{m["name"]}:{int(m["disabled"])}:{int(m["dpmsStatus"])}" for m in sorted(json.load(sys.stdin), key=lambda m: m["name"])))'
}
ws_on() { # workspace ids on monitor <name>
    H workspaces -j | python3 -I -c 'import json,sys; print(" ".join(str(w["id"]) for w in sorted(json.load(sys.stdin), key=lambda w: w["id"]) if w["monitor"]==sys.argv[1]))' "$1"
}

echo "== config: $NESTED_CONFIG"
# Light every output first (Lua form, then the hyprlang form), whatever a previous test left.
[[ "$(H dispatch 'hl.dsp.dpms({ action = "on" })' 2>&1)" == ok ]] || H dispatch dpms on >/dev/null 2>&1 || true
sleep 0.5
expect "start state" "DP-1:0:1 eDP-1:0:1" "$(state)"

# --- lid ---------------------------------------------------------------------
bash "$BIN/executable_lid" close; sleep 1
expect "lid close disables eDP-1" "DP-1:0:1 eDP-1:1:1" "$(state)"
echo "   workspaces after close: DP-1: $(ws_on DP-1); eDP-1: $(ws_on eDP-1)"
if [[ "$NESTED_CONFIG" != *.lua ]]; then
    # hyprlang rollback config: no pools, no Lua dispatchers; the panel just holds nothing.
    [[ -z "$(ws_on eDP-1)" ]] && echo "PASS (hyprlang) no workspace left on eDP-1" \
        || { echo "FAIL (hyprlang) workspaces on eDP-1: $(ws_on eDP-1)"; fails=$((fails + 1)); }
else
# Lua config: an empty placeholder workspace (1 in the rig) is observed on the disabled
# eDP-1; what matters is that its pool and new windows go to DP-1.
[[ " $(ws_on DP-1) " == *" 11 12 13 14 15 "* ]] && echo "PASS eDP-1's pool 11-15 moved to DP-1" \
    || { echo "FAIL pool 11-15 not on DP-1: $(ws_on DP-1)"; fails=$((fails + 1)); }
H dispatch 'hl.dsp.exec_cmd("kitty")' >/dev/null
win=""
for _ in $(seq 50); do
    win=$(H clients -j | python3 -I -c 'import json,sys; print(next((f"{c["pid"]} {c["monitor"]}" for c in json.load(sys.stdin) if c["class"]=="kitty"), ""))')
    [[ -n "$win" ]] && break
    sleep 0.2
done
dp1_id=$(H monitors -j | python3 -I -c 'import json,sys; print(next(m["id"] for m in json.load(sys.stdin) if m["name"]=="DP-1"))')
expect "a new window opens on DP-1, not the closed panel" "$dp1_id" "${win#* }"
# Stop that kitty by PID (window.close only raises kitty's own close prompt), and only if
# it carries this rig's marker.
kpid=${win% *}
if [[ -n "$kpid" ]] && tr '\0' '\n' <"/proc/$kpid/environ" 2>/dev/null | grep -qxF "RICE_RIG_ID=$RICE_RIG_ID"; then
    kill "$kpid"; sleep 0.5
fi
fi
bash "$BIN/executable_lid" close; sleep 0.5
expect "second close with only DP-1 lit is a no-op" "DP-1:0:1 eDP-1:1:1" "$(state)"
bash "$BIN/executable_lid" open; sleep 1.5
expect "lid open re-enables eDP-1" "DP-1:0:1 eDP-1:0:1" "$(state)"

# --- headless (fake sudo) --------------------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/run"
cat >"$tmp/bin/sudo" <<'FAKE'
#!/bin/bash
echo "sudo $*" >> "$FAKE_LOG"
FAKE
chmod +x "$tmp/bin/sudo"
for t in bash grep date stat touch cat; do ln -s "$(command -v "$t")" "$tmp/bin/$t"; done
# hyprctl finds its socket under XDG_RUNTIME_DIR, which the script sees as a temp dir (so
# its double-tap guard file never lands in the live runtime dir); the wrapper restores it
# for hyprctl alone and pins the nested instance.
cat >"$tmp/bin/hyprctl" <<WRAP
#!/bin/bash
XDG_RUNTIME_DIR=$(printf %q "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}") exec $(printf %q "$(command -v hyprctl)") -i $(printf %q "$HYPRLAND_INSTANCE_SIGNATURE") "\$@"
WRAP
chmod +x "$tmp/bin/hyprctl"
[[ "$(PATH="$tmp/bin" command -v sudo)" == "$tmp/bin/sudo" ]] || { echo "FAIL fake sudo not first"; exit 1; }
run_headless() {
    : >"$tmp/log"
    env -i PATH="$tmp/bin" FAKE_LOG="$tmp/log" XDG_RUNTIME_DIR="$tmp/run" \
        /usr/bin/env bash "$BIN/executable_headless" || echo "   (headless exited $?)"
    rm -f "$tmp/run/headless.guard"   # the 2 s double-tap guard; tested in test_lid_headless.py
    sleep 1
}
run_headless
expect "headless: dpms off on every output" "DP-1:0:0 eDP-1:0:0" "$(state)"
expect "headless: peripherals cut after dpms" "sudo -n /usr/local/bin/headless-peripherals off" "$(cat "$tmp/log")"
run_headless
expect "headless again: dpms on" "DP-1:0:1 eDP-1:0:1" "$(state)"
expect "headless again: peripherals restored" "sudo -n /usr/local/bin/headless-peripherals on" "$(cat "$tmp/log")"

[[ $fails -eq 0 ]] && echo "LID_HEADLESS OK" || { echo "LID_HEADLESS: $fails failure(s)"; exit 1; }
