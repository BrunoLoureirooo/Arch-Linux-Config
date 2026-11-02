#!/usr/bin/env bash
# shellcheck disable=SC2015  # pass() only echoes, so `test && pass || fail` is safe here
# End-to-end check of the rail placement, the rail toggle, the full-height rail layout,
# the CPU temperature row and the empty-workspace clock HUD, in the nested rig:
#   1. production shell.qml (staged HOME, private bus): the rail and its reserved zone on
#      eDP-1 (not the main DP-1); `qs ipc call rail toggle|hide|show|status` removes and
#      restores both layer surfaces and the zone; the real `lid close` (eDP-1 disabled)
#      moves the rail to DP-1 and `lid open` moves it back; the rail spans the full height
#      (screenshot: content down to the bottom edge); the bar has no CPU/MEM chips; one
#      HUD per screen, centred in the free area, gone on eDP-1 while a real kitty is open
#      there and back when it closes;
#   2. through tests/rig/rail-hud.qml (production CentreClock and Rail over a click
#      counting background window): the HUD texts (real output name, pool slot, the
#      binds.lua key hints) follow a workspace switch; a click on the HUD reaches the
#      window below it; the rail sections run from the top to the bottom of the rail; the
#      CPU temperature probe and TMP row on fake hwmon/thermal trees (k10temp, coretemp,
#      x86_pkg_temp, none), two readings, the warn colour, unknown and garbage values.
# Uses its own testbin state when RICE_TESTBIN is set (recommended while other rig runs
# are going on). Screenshots land in $RICE_TESTBIN/shots/rail-*.png. Exit 0 = all passed.
set -euo pipefail
unset RICE_NVIDIA RIG_NVIDIA
R="$(dirname "$(realpath "$0")")"
REPO="$(realpath "$R/../..")"
TB="${RICE_TESTBIN:-$HOME/.cache/rice-testbin}"
SHOTS="$TB/shots"
mkdir -p "$SHOTS"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

kitty_pid=""
tmp=""
cleanup() {
    [[ -z "$kitty_pid" ]] || kill -TERM "$kitty_pid" 2>/dev/null || true
    "$R/qs-run.sh" stop >/dev/null 2>&1 || true
    "$R/nested-hypr.sh" stop >/dev/null 2>&1 || true
    [[ -z "$tmp" ]] || rm -rf -- "$tmp"
}
trap cleanup EXIT
tmp=$(mktemp -d "${TMPDIR:-/tmp}/selftest-rail.XXXXXX")

H() { "$R/run.sh" hyprctl "$@"; }
ipc() { "$R/qs-run.sh" ipc call "$@"; }
# All layers as "<monitor> <namespace> <x> <y> <w> <h>" lines (global coordinates).
layers() {
    H layers -j | python3 -I -c '
import json, sys
for mon, v in json.load(sys.stdin).items():
    for lvl in v["levels"].values():
        for l in lvl:
            print(mon, l["namespace"], l["x"], l["y"], l["w"], l["h"])'
}
layer() { layers | awk -v ns="$1" '$2 == ns {print $1, $3, $4, $5, $6}'; }
nlayer() { layers | awk -v ns="$1" '$2 == ns' | grep -c . || true; }
reserved() { H monitors -j | python3 -I -c 'import json,sys; print(" ".join(m["name"] + str(m["reserved"]) for m in json.load(sys.stdin)))'; }
monx() { H monitors -j | python3 -I -c 'import json,sys; print(next(m["x"] for m in json.load(sys.stdin) if m["name"] == sys.argv[1]))' "$1"; }
active_ws() { H monitors -j | python3 -I -c 'import json,sys; print(next(m["activeWorkspace"]["id"] for m in json.load(sys.stdin) if m["name"] == sys.argv[1]))' "$1"; }
monitors() { H monitors -j | python3 -I -c 'import json,sys; print(" ".join(sorted(m["name"] for m in json.load(sys.stdin))))'; }
# wait_for <tries of 0.2 s> <command...>: until the command succeeds
wait_for() {
    local n="$1" i
    shift
    for ((i = 0; i < n; i++)); do "$@" && return 0; sleep 0.2; done
    return 1
}
rail_on() { [[ "$(layer rice-rail | cut -d' ' -f1)" == "$1" && "$(layer rice-rail-zone | cut -d' ' -f1)" == "$1" ]]; }
no_rail() { [[ "$(nlayer rice-rail)" == 0 && "$(nlayer rice-rail-zone)" == 0 ]]; }
status_is() { [[ "$(ipc rail status)" == "$1" ]]; }

# Lowest and highest rows (screen y) in the rail interior holding text/graph pixels:
# anything clearly brighter than the background, 4 px in from the rail's border.
rail_extent() { # <png> <monitor-x> -> "top bottom"
    local raw="$tmp/shot.rgb"
    magick "$1" -depth 8 "RGB:$raw"
    python3 -I -c '
import sys
raw = open(sys.argv[1], "rb").read()
w, h = 1920, len(raw) // (1920 * 3)
x0, x1 = 1488 + 4, 1920 - 14   # clear of the border and the bottom-right cut corner
rows = [y for y in range(30, h - 4)
        if any(max(raw[(y * w + x) * 3:(y * w + x) * 3 + 3]) > 90 for x in range(x0, x1))]
print(rows[0] if rows else -1, rows[-1] if rows else -1)' "$raw"
}

# --- 1. production shell.qml --------------------------------------------------------
"$R/nested-hypr.sh" start "$R/full.lua" >/dev/null
staged=$("$R/qs-run.sh" start --restage)
wait_for 25 rail_on eDP-1 || true
sleep 1
bad=$("$R/qs-run.sh" log | grep -E 'ERROR|WARN' | grep -v -e 'Failed to register with host portal' \
    -e 'QML Image at @wallpaper/Wallpaper.qml.*Cannot open: .*/Pictures/berserk-wallpaper.jpg$' || true)
[[ -z "$bad" ]] && pass "qs log: no ERROR/WARN besides the portal and missing-wallpaper ones" || { fail "qs log"; echo "$bad"; }

# a. Placement: the built-in panel, not the main screen (DP-1 stands in for the BenQ).
ex=$(monx eDP-1)
rail_geo=$(layer rice-rail)
[[ "$rail_geo" == "eDP-1 $((ex + 1488)) 26 432 1054" && "$(layer rice-rail-zone)" == "eDP-1 $((ex + 1919)) 26 1 1054" \
    && "$(reserved)" == "DP-1[0, 26, 0, 0] eDP-1[0, 26, 432, 0]" && "$(nlayer rice-rail)" == 1 ]] \
    && pass "rail and its 432 px zone on eDP-1 only ($rail_geo); DP-1 keeps its full width" \
    || fail "placement: rail '$rail_geo' zone '$(layer rice-rail-zone)' reserved '$(reserved)'"
status_is "shown eDP-1" && pass "ipc rail status: 'shown eDP-1'" || fail "status: $(ipc rail status)"
[[ "$(nlayer rice-bar)" == 2 ]] && pass "bar still on both screens" || fail "bars: $(nlayer rice-bar)"

"$R/qs-run.sh" shot eDP-1 "$SHOTS/rail-eDP-1.png" >/dev/null
read -r top bot < <(rail_extent "$SHOTS/rail-eDP-1.png" "$ex")
[[ "$top" -le 50 && "$bot" -ge 1040 ]] \
    && pass "screenshot: rail content runs from y $top to y $bot of 1080 (full height)" \
    || fail "rail extent on screen: $top..$bot (content bunched at the top?)"
"$R/qs-run.sh" shot DP-1 "$SHOTS/rail-DP-1.png" >/dev/null

# b. Toggle: hidden = no rail surface, no zone; shown again = as before.
ipc rail toggle
wait_for 25 no_rail && status_is "hidden eDP-1" && [[ "$(reserved)" == "DP-1[0, 26, 0, 0] eDP-1[0, 26, 0, 0]" ]] \
    && pass "toggle: rail hidden, no rice-rail/rice-rail-zone layer left, nothing reserved on eDP-1" \
    || fail "toggle hide: layers $(nlayer rice-rail)/$(nlayer rice-rail-zone), reserved '$(reserved)', $(ipc rail status)"
"$R/qs-run.sh" shot eDP-1 "$SHOTS/rail-hidden-eDP-1.png" >/dev/null
ipc rail hide
sleep 0.5
no_rail && status_is "hidden eDP-1" && pass "hide while hidden: stays hidden" || fail "hide twice"
ipc rail toggle
wait_for 25 rail_on eDP-1 && [[ "$(layer rice-rail)" == "$rail_geo" && "$(reserved)" == "DP-1[0, 26, 0, 0] eDP-1[0, 26, 432, 0]" ]] \
    && status_is "shown eDP-1" && pass "toggle again: rail back on eDP-1 with its zone" || fail "toggle show: $(layers)"
ipc rail hide
wait_for 25 no_rail || true
ipc rail -- show
ipc rail -- show
wait_for 25 rail_on eDP-1 && [[ "$(nlayer rice-rail)" == 1 ]] && pass "hide, show, show: one rail on eDP-1" || fail "hide/show: $(layers)"

# c. Lid closed (the real lid script disables eDP-1): the rail falls back to DP-1, and
#    goes back when the lid opens (hyprctl reload re-applies the monitor line).
"$R/run.sh" bash "$REPO/dot_local/bin/executable_lid" close
wait_for 25 rail_on DP-1 || true
[[ "$(monitors)" == "DP-1" ]] && rail_on DP-1 && [[ "$(layer rice-rail)" == "DP-1 1488 26 432 1054" ]] \
    && [[ "$(reserved)" == "DP-1[0, 26, 432, 0]" ]] && status_is "shown DP-1" \
    && pass "lid closed: eDP-1 gone, rail and zone fall back to DP-1" \
    || fail "fallback: monitors '$(monitors)' $(layer rice-rail) reserved '$(reserved)' $(ipc rail status)"
"$R/qs-run.sh" shot DP-1 "$SHOTS/rail-fallback-DP-1.png" >/dev/null
read -r top bot < <(rail_extent "$SHOTS/rail-fallback-DP-1.png" 0)
[[ "$top" -le 50 && "$bot" -ge 1040 ]] && pass "fallback rail on DP-1 is full height too ($top..$bot)" || fail "fallback extent $top..$bot"
ipc rail toggle
wait_for 25 no_rail && status_is "hidden DP-1" && [[ "$(reserved)" == "DP-1[0, 26, 0, 0]" ]] \
    && pass "toggle on the fallback screen hides it there" || fail "fallback toggle: $(layers)"
ipc rail toggle
wait_for 25 rail_on DP-1 || fail "fallback toggle back"
"$R/run.sh" bash "$REPO/dot_local/bin/executable_lid" open
wait_for 50 rail_on eDP-1 || true
[[ "$(monitors)" == "DP-1 eDP-1" ]] && rail_on eDP-1 && [[ "$(nlayer rice-rail)" == 1 \
    && "$(reserved)" == "DP-1[0, 26, 0, 0] eDP-1[0, 26, 432, 0]" ]] && status_is "shown eDP-1" \
    && pass "lid open: eDP-1 back, the rail moves back to it" \
    || fail "lid open: monitors '$(monitors)' rail '$(layer rice-rail)' reserved '$(reserved)'"

# d. Bar de-duplication: no CPU/MEM chips (VOL, NET, BAT remain): the bar's right
#    group now starts right of where the CPU chip used to be. Checked in the source,
#    the probe below has no bar.
bar="$staged/.config/quickshell/bar/Bar.qml"
! grep -qE 'label: "(CPU|MEM)"' "$bar" && grep -q 'label: "VOL"' "$bar" && grep -q 'label: "NET"' "$bar" \
    && grep -q 'label: "BAT"' "$bar" && pass "bar chips: VOL, NET, BAT only (CPU/MEM only in the rail)" || fail "bar chips"

# e. HUD: one per screen while its workspace is empty, centred in the free area.
hud_center() { layer rice-hud | awk -v m="$1" '$1 == m {print $2 + $4 / 2, $3 + $5 / 2}'; }
two_huds() { [[ "$(nlayer rice-hud)" == 2 ]]; }
wait_for 25 two_huds || true
read -r dcx dcy < <(hud_center DP-1)
read -r ecx ecy < <(hud_center eDP-1)
echo "  HUD centres: DP-1 $dcx,$dcy  eDP-1 $ecx,$ecy (free areas: DP-1 x 0-1920 y 26-1080, eDP-1 x $ex-$((ex + 1488)) y 26-1080)"
python3 -I -c 'import sys; a = list(map(float, sys.argv[1:])); ex = a[4]
sys.exit(not (abs(a[0] - 960) <= 1 and abs(a[1] - 553) <= 1 and abs(a[2] - (ex + 744)) <= 1 and abs(a[3] - 553) <= 1))' \
    "$dcx" "$dcy" "$ecx" "$ecy" "$ex" \
    && pass "one HUD per screen, centred below the bar (DP-1) and left of the rail (eDP-1)" || fail "HUD placement: $(layer rice-hud)"
lvl=$(H layers -j | python3 -I -c '
import json, sys
print(sorted({(m, k) for m, v in json.load(sys.stdin).items() for k, lv in v["levels"].items() for l in lv if l["namespace"] == "rice-hud"}))')
[[ "$lvl" == "[('DP-1', '1'), ('eDP-1', '1')]" ]] && pass "HUD on the bottom layer (level 1: above the wallpaper, below windows)" || fail "HUD level: $lvl"
"$R/qs-run.sh" shot eDP-1 "$SHOTS/rail-hud-eDP-1.png" >/dev/null

# f. A real kitty on eDP-1: that screen's HUD goes away (DP-1 keeps its own), then comes back.
H dispatch 'hl.dsp.focus({ monitor = "eDP-1" })' >/dev/null
"$R/run.sh" env HOME="$staged" XDG_CONFIG_HOME="$staged/.config" XDG_CACHE_HOME="$staged/.cache" \
    XDG_STATE_HOME="$staged/.local/state" XDG_DATA_HOME="$staged/.local/share" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$tmp/no-bus" kitty --config=NONE --title rig-kitty >"$tmp/kitty.out" 2>&1 </dev/null &
kitty_pid=$!
hud_only_dp() { [[ "$(layer rice-hud | cut -d' ' -f1 | tr '\n' ' ')" == "DP-1 " ]]; }
wait_for 50 hud_only_dp && pass "kitty open on eDP-1: its HUD is gone, DP-1 keeps its HUD" || fail "HUD with kitty: $(layer rice-hud)"
kgeo=$(H clients -j | python3 -I -c '
import json, sys
for c in json.load(sys.stdin):
    if c["title"] == "rig-kitty":
        print(c["monitor"], c["at"][0], c["size"][0])')
read -r kmon kx kw <<<"${kgeo:-x 0 0}"
[[ "$kmon" == 1 && $((kx + kw)) -le $((ex + 1488)) && $((kx + kw)) -ge $((ex + 1460)) ]] \
    && pass "kitty on eDP-1 tiles up to the rail ($((kx + kw)) <= $((ex + 1488)))" || fail "kitty geometry: '$kgeo'"
sleep 0.5
"$R/qs-run.sh" shot eDP-1 "$SHOTS/rail-kitty-eDP-1.png" >/dev/null
kill -TERM "$kitty_pid" 2>/dev/null || true
wait "$kitty_pid" 2>/dev/null || true
kitty_pid=""
wait_for 50 two_huds && pass "kitty closed: the eDP-1 HUD is back" || fail "HUD after kitty: $(layer rice-hud)"
"$R/qs-run.sh" stop >/dev/null

# --- 2. probe: rail-hud.qml -------------------------------------------------------------
"$R/qs-run.sh" start --entry "$R/rail-hud.qml" >/dev/null
pj() { ipc probe get | python3 -I -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
sleep 2

# a. HUD texts: real output name and pool slot, the real key hints.
slot() { echo $((($1 - 1) % 10 + 1)); }
keys="['Ctrl', '1', '–', '5', 'workspace ', 'Ctrl', 'Alt', 'W', 'wallpapers ', 'Super', 'Space', 'launcher']"
ews=$(active_ws eDP-1)
[[ "$(pj "d['hud']['eDP-1']['texts'][1]")" == "eDP-1 · workspace $(slot "$ews") · empty" \
    && "$(pj "d['hud']['eDP-1']['texts'][2:]")" == "$keys" \
    && "$(pj "d['hud']['eDP-1']['texts'][0]")" =~ ^[0-2][0-9]:[0-5][0-9]$ ]] \
    && pass "HUD eDP-1: '$(pj "d['hud']['eDP-1']['texts'][0]")', 'eDP-1 · workspace $(slot "$ews") · empty' (ws $ews), key hints Ctrl 1-5 / Ctrl Alt W / Super Space" \
    || fail "HUD texts: $(pj "d['hud']")"
grep -q '"CTRL + " .. n' "$REPO/dot_config/hypr/binds.lua" && grep -q '"CTRL + ALT + W"' "$REPO/dot_config/hypr/binds.lua" \
    && grep -q '"SUPER + SPACE".*launcher toggle' "$REPO/dot_config/hypr/binds.lua" \
    && pass "the hinted binds exist in binds.lua" || fail "hinted binds not found in binds.lua"
H dispatch 'hl.dsp.focus({ workspace = 13 })' >/dev/null
sleep 0.5
[[ "$(active_ws eDP-1)" == 13 && "$(pj "d['hud']['eDP-1']['texts'][1]")" == "eDP-1 · workspace 3 · empty" ]] \
    && pass "workspace 13 on eDP-1: tag follows ('workspace 3')" || fail "after switch: ws $(active_ws eDP-1), $(pj "d['hud']['eDP-1']")"
H dispatch "hl.dsp.focus({ workspace = $ews })" >/dev/null

# b. Click-through: a click on the DP-1 HUD lands on the window under it.
read -r dcx dcy < <(hud_center DP-1)
"$R/run.sh" python3 -I "$R/vpointer.py" "${dcx%.*}" "${dcy%.*}" >/dev/null
sleep 0.5
[[ "$(pj "d['clicks'].get('DP-1', 0)")" == 1 && "$(pj "d['hud']['DP-1']['shown']")" == True ]] \
    && pass "click on the HUD at $dcx,$dcy reaches the background window (input-transparent)" \
    || fail "click-through: clicks $(pj "d['clicks']")"

# c. Full-height layout, measured in the rail's item tree.
echo "  rail: $(pj "d['rail']")"
[[ "$(pj "d['rail']['screen']")" == eDP-1 ]] && python3 -I -c '
import json, sys
r = json.loads(sys.argv[1])
s = r["sections"]
ok = (s[0][0] == "sys" and s[0][1] < 100 and s[-1][0] == "claude"
      and abs(r["lastBottom"] - r["clipHeight"]) <= 2 and r["spark"][1] >= 100
      and r["columnImplicit"] <= r["clipHeight"])
sys.exit(not ok)' "$(pj "json.dumps(d['rail'])")" \
    && pass "rail layout: SYS at the top, CLAUDE ends at the bottom edge ($(pj "d['rail']['lastBottom']") of $(pj "d['rail']['clipHeight']") px), the graph grew to $(pj "d['rail']['spark'][1]") px" \
    || fail "rail layout: $(pj "d['rail']")"

# d. CPU temperature: probe order, two readings, warn, unknown and garbage values.
WARN_C="#ffd23f"
A1_C="#00f0ff"
fake="$tmp/sys"
mkdir -p "$fake/hw/hwmon0" "$fake/hw/hwmon1" "$fake/hw/hwmon2" "$fake/th/thermal_zone0"
echo acpitz >"$fake/hw/hwmon0/name"
echo nvme >"$fake/hw/hwmon1/name"
echo k10temp >"$fake/hw/hwmon2/name"
echo 54000 >"$fake/hw/hwmon2/temp1_input"
echo 40000 >"$fake/hw/hwmon0/temp1_input"
echo acpitz >"$fake/th/thermal_zone0/type"
echo 30000 >"$fake/th/thermal_zone0/temp"
tj() { pj "d['temp']$1"; }
temp_is() { [[ "$(pj "float(d['temp']['c']) == float('$1')")" == True ]]; }
row3() { pj "(d['temp']['row']['text'], d['temp']['row']['lit'], d['temp']['row']['$1'])"; }
ipc probe scanTemp "$fake/hw" "$fake/th"
wait_for 25 temp_is 54.0 || true
[[ "$(tj "['path']")" == "$fake/hw/hwmon2/temp1_input" \
    && "$(row3 warn)" == "('54C', 3, False)" \
    && "$(tj "['row']['colors'][:4]")" == "['$A1_C', '$A1_C', '$A1_C', '#1b1d30']" ]] \
    && pass "k10temp picked (hwmon2, not acpitz), 54000 -> 54C, 3 of 10 lit (30-100 C), a1" || fail "k10temp: $(tj "")"
echo 91500 >"$fake/hw/hwmon2/temp1_input"
wait_for 25 temp_is 91.5 || true
[[ "$(row3 warn)" == "('92C', 9, True)" \
    && "$(tj "['row']['colors'][0]")" == "$WARN_C" ]] \
    && pass "second reading on the shared tick: 91500 -> 92C, 9 lit, warn colour (>= 85 C)" || fail "reading 2: $(tj "")"
echo 85000 >"$fake/hw/hwmon2/temp1_input"
wait_for 25 temp_is 85.0 && [[ "$(tj "['row']['warn']")" == True ]] && pass "85C is already warn" || fail "85C: $(tj "")"
echo garbage >"$fake/hw/hwmon2/temp1_input"
wait_for 25 temp_is -1 && [[ "$(row3 known)" == "('--', 0, False)" ]] \
    && pass "unparsable sensor text: unknown, '--' and an unlit bar" || fail "garbage: $(tj "")"
echo k10temp-not >"$fake/hw/hwmon2/name"
echo coretemp >"$fake/hw/hwmon1/name"
echo 47000 >"$fake/hw/hwmon1/temp1_input"
ipc probe scanTemp "$fake/hw" "$fake/th"
wait_for 25 temp_is 47.0 && [[ "$(tj "['path']")" == "$fake/hw/hwmon1/temp1_input" ]] \
    && pass "no k10temp: coretemp (hwmon1) picked, 47C" || fail "coretemp: $(tj "")"
echo nvme >"$fake/hw/hwmon1/name"
mkdir -p "$fake/th/thermal_zone1"
echo x86_pkg_temp >"$fake/th/thermal_zone1/type"
echo 61000 >"$fake/th/thermal_zone1/temp"
ipc probe scanTemp "$fake/hw" "$fake/th"
wait_for 25 temp_is 61.0 && [[ "$(tj "['path']")" == "$fake/th/thermal_zone1/temp" ]] \
    && pass "no CPU hwmon: thermal x86_pkg_temp (zone1) picked over zone0, 61C" || fail "x86_pkg_temp: $(tj "")"
rm -rf "$fake/th/thermal_zone1"
ipc probe scanTemp "$fake/hw" "$fake/th"
wait_for 25 temp_is 30.0 && [[ "$(tj "['path']")" == "$fake/th/thermal_zone0/temp" && "$(tj "['row']['lit']")" == 0 ]] \
    && pass "else thermal zone0 (30C, bottom of the scale, 0 lit)" || fail "zone0: $(tj "")"
ipc probe scanTemp "$tmp/none" "$tmp/none"
wait_for 25 temp_is -1 && [[ "$(tj "['path']")" == "" && "$(tj "['row']['text']")" == "--" ]] \
    && pass "no sensor at all: cpuTempC -1, TMP row '--'" || fail "no sensor: $(tj "")"
[[ "$(ipc probe parseTemp 48875) $(ipc probe parseTemp ' 100000') $(ipc probe parseTemp '') $(ipc probe parseTemp 4x)" == "48.875 100 -1 -1" ]] \
    && pass "parseTemp fixtures" || fail "parseTemp"
"$R/qs-run.sh" shot eDP-1 "$SHOTS/rail-probe-eDP-1.png" >/dev/null
temp_warns=$("$R/qs-run.sh" log | grep -c 'WARN qml: Stats: cannot read' || true)
[[ "$temp_warns" -le 1 ]] && pass "temperature failures logged at most once ($temp_warns)" || fail "temp warnings: $temp_warns"
"$R/qs-run.sh" stop >/dev/null

echo
if [[ $fails -eq 0 ]]; then echo "selftest-rail: all checks passed"; else echo "selftest-rail: $fails FAILED"; fi
exit $((fails > 0))
