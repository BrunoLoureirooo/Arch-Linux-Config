#!/usr/bin/env bash
# shellcheck disable=SC2015  # pass() only echoes, so `test && pass || fail` is safe here
# End-to-end check of the rig itself: start nested Hyprland with minimal.lua, take a
# screenshot, prove wtype keys reach a client (wev) and fire an hl.bind, run the
# Quickshell smoke config (render + ipc + kill), check module imports, then stop.
# Screenshots land in ~/.cache/rice-testbin/shots/. Exit 0 = all checks passed.
set -euo pipefail
R="$(dirname "$(realpath "$0")")"
TB="${RICE_TESTBIN:-$HOME/.cache/rice-testbin}"
SHOTS="$TB/shots"
mkdir -p "$SHOTS"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
trap '"$R/nested-hypr.sh" stop >/dev/null 2>&1 || true' EXIT

"$R/nested-hypr.sh" start "$R/minimal.lua"

mons=$("$R/run.sh" hyprctl monitors -j | python3 -I -c 'import json,sys; print(",".join(m["name"] for m in json.load(sys.stdin)))')
[[ "$mons" == "DP-1,eDP-1" ]] && pass "outputs: $mons" || fail "outputs: $mons"
[[ -z "$("$R/run.sh" hyprctl configerrors | tr -d '[:space:]')" ]] && pass "no config errors" || fail "config errors"

"$R/shot.sh" DP-1 "$SHOTS/selftest-empty.png" >/dev/null
[[ $(stat -c %s "$SHOTS/selftest-empty.png") -gt 0 ]] && pass "grim shot of headless DP-1" || fail "grim shot"

# Keys reach a client.
"$R/run.sh" stdbuf -oL wev -f wl_keyboard:key >"$TB/selftest-wev.out" 2>&1 &
sleep 2
"$R/keys.sh" rig
sleep 1
grep -q "sym: r " "$TB/selftest-wev.out" && grep -q "sym: g " "$TB/selftest-wev.out" \
    && pass "wtype keys reached wev" || fail "wtype keys did not reach wev"
wev_pids=$("$R/run.sh" hyprctl clients -j | python3 -I -c 'import json,sys; print(" ".join(str(c["pid"]) for c in json.load(sys.stdin) if c["class"]=="wev"))')
# shellcheck disable=SC2086
[[ -z "$wev_pids" ]] || kill $wev_pids

# Virtual keyboard fires an hl.bind (SUPER+F12 from lib/rigbind.lua).
rm -f "$TB/bind-fired"
"$R/keys.sh" -M logo -k F12 -m logo
sleep 1
[[ -e "$TB/bind-fired" ]] && pass "SUPER+F12 hl.bind fired" || fail "SUPER+F12 hl.bind did not fire"

# Quickshell smoke: renders on both outputs, ipc works, kill works.
"$R/run.sh" qs -p "$R/qs-smoke.qml" --no-color >"$TB/selftest-qs.out" 2>&1 &
sleep 4
[[ "$("$R/run.sh" qs ipc -p "$R/qs-smoke.qml" call rig ping)" == pong ]] && pass "qs ipc call rig ping" || fail "qs ipc"
[[ "$("$R/run.sh" qs ipc -p "$R/qs-smoke.qml" call rig monitors)" == "DP-1,eDP-1" ]] \
    && pass "Quickshell.Hyprland sees nested monitors" || fail "Quickshell.Hyprland monitors"
layers=$("$R/run.sh" hyprctl layers -j | grep -c '"namespace": "quickshell"' || true)
[[ "$layers" -eq 2 ]] && pass "qs PanelWindow on each output ($layers layers)" || fail "qs layers: $layers"
"$R/shot.sh" DP-1 "$SHOTS/selftest-qs-DP-1.png" >/dev/null
"$R/shot.sh" eDP-1 "$SHOTS/selftest-qs-eDP-1.png" >/dev/null
"$R/run.sh" qs kill -p "$R/qs-smoke.qml" >/dev/null && pass "qs kill" || fail "qs kill"

"$R/qs-imports.sh" && pass "qs module imports" || fail "qs module imports"

"$R/nested-hypr.sh" stop
trap - EXIT
echo "screenshots: $SHOTS/selftest-*.png"
[[ $fails -eq 0 ]] && echo "SELFTEST OK" || { echo "SELFTEST: $fails failure(s)"; exit 1; }
