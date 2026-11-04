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
#      window below it; the rail sections run from the top to the bottom of the rail with
#      the inner padding (14 px left/right, 12 px top/bottom) and one 18 px gap between
#      sections (the spare height above CLAUDE); the
#      CPU temperature probe and TMP row on fake hwmon/thermal trees (k10temp, coretemp,
#      x86_pkg_temp, none), two readings, the warn colour, unknown and garbage values;
#      DISK (parseDf fixtures, a fake df: rows labelled by the full mount point with the
#      filesystem type, a long mount point ellipsized in the middle, warn from 90%, one df
#      per refresh and none
#      per tick), VOLUME on a private PipeWire (fake-pipewire.sh: default sink name and
#      volume, mute, switch, no sink, streams, markup names as plain text) and the
#      always-visible BLUETOOTH section.
# Bar and rail float Theme.gapOut (6 px = gaps_out) off the screen edges; the geometry
# checks expect exactly that gap between a kitty window and the bar, the rail and the
# screen edges.
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
    [[ -z "$tmp" ]] || "$R/fake-pipewire.sh" stop "$tmp/pw" >/dev/null 2>&1 || true
    [[ -z "$tmp" ]] || rm -rf -- "$tmp"
}
trap cleanup EXIT
tmp=$(mktemp -d "${TMPDIR:-/tmp}/selftest-rail.XXXXXX")
# Every qs here talks to a private PipeWire (two null sinks, no real devices or streams):
# the VOLUME section and the bar's VOL chip never see the owner's audio graph.
"$R/fake-pipewire.sh" start "$tmp/pw" >/dev/null
export PIPEWIRE_RUNTIME_DIR="$tmp/pw"

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
# anything clearly brighter than the background, from 12 px in from the rail's left border
# (clear of the top-left cut corner) to 14 px in from the right one. With the 12 px
# bottom padding and CLAUDE's one-row `no data`, the lowest text ends at about y 1054.
rail_extent() { # <png> <monitor-x> -> "top bottom"
    local raw="$tmp/shot.rgb"
    magick "$1" -depth 8 "RGB:$raw"
    python3 -I -c '
import sys
raw = open(sys.argv[1], "rb").read()
w, h = 1920, len(raw) // (1920 * 3)
x0, x1 = 1482 + 12, 1914 - 14   # clear of the border and both cut corners
rows = [y for y in range(38 + 4, 1074 - 4)
        if any(max(raw[(y * w + x) * 3:(y * w + x) * 3 + 3]) > 90 for x in range(x0, x1))]
print(rows[0] if rows else -1, rows[-1] if rows else -1)' "$raw"
}

# Bright pixels (text, bars, graph) in the rail's inner padding band: 2..11 px inside the
# left and right border, 2..9 px inside the top and bottom border (clear of the cut
# corners). Prints the count per side "left top right bottom": 0 0 0 0 = nothing glued
# to the border. Frames inside the rail are Theme.line (max channel 0x30 < 90).
rail_pad_ink() { # <png> -> "l t r b"
    local raw="$tmp/pad.rgb"
    magick "$1" -depth 8 "RGB:$raw"
    python3 -I -c '
import sys
raw = open(sys.argv[1], "rb").read()
w = 1920
def ink(xs, ys):
    return sum(1 for y in ys for x in xs if max(raw[(y * w + x) * 3:(y * w + x) * 3 + 3]) > 90)
print(ink(range(1484, 1494), range(52, 1060)), ink(range(1496, 1900), range(40, 48)),
      ink(range(1902, 1912), range(52, 1060)), ink(range(1486, 1890), range(1064, 1072)))' "$raw"
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
# Bar and rail float 6 px (Theme.gapOut = gaps_out) off the edges: bar 6..32, rail
# 1482..1914 x 38..1074, reserved = bar 26 + 6 on top, rail 432 + 6 on the right.
[[ "$rail_geo" == "eDP-1 $((ex + 1482)) 38 432 1036" && "$(layer rice-rail-zone)" == "eDP-1 $((ex + 1919)) 32 1 1048" \
    && "$(reserved)" == "DP-1[0, 32, 0, 0] eDP-1[0, 32, 438, 0]" && "$(nlayer rice-rail)" == 1 \
    && "$(layer rice-bar | sort | tr '\n' ' ')" == "DP-1 6 6 1908 26 eDP-1 $((ex + 6)) 6 1908 26 " ]] \
    && pass "bar 6 px off the top/left/right, rail 6 px off the bar/right/bottom with its 438 px zone on eDP-1 only ($rail_geo)" \
    || fail "placement: rail '$rail_geo' zone '$(layer rice-rail-zone)' reserved '$(reserved)'"
status_is "shown eDP-1" && pass "ipc rail status: 'shown eDP-1'" || fail "status: $(ipc rail status)"
[[ "$(nlayer rice-bar)" == 2 ]] && pass "bar still on both screens" || fail "bars: $(nlayer rice-bar)"

"$R/qs-run.sh" shot eDP-1 "$SHOTS/rail-eDP-1.png" >/dev/null
read -r top bot < <(rail_extent "$SHOTS/rail-eDP-1.png" "$ex")
[[ "$top" -le 56 && "$bot" -ge 1045 ]] \
    && pass "screenshot: rail content runs from y $top to y $bot (rail 38..1074: full height)" \
    || fail "rail extent on screen: $top..$bot (content bunched at the top?)"
ink=$(rail_pad_ink "$SHOTS/rail-eDP-1.png")
[[ "$ink" == "0 0 0 0" ]] && pass "screenshot: no text or bars in the rail's inner padding band (nothing glued to the border)" \
    || fail "bright pixels in the padding band (left top right bottom): $ink"
"$R/qs-run.sh" shot DP-1 "$SHOTS/rail-DP-1.png" >/dev/null

# b. Toggle: hidden = no rail surface, no zone; shown again = as before.
ipc rail toggle
wait_for 25 no_rail && status_is "hidden eDP-1" && [[ "$(reserved)" == "DP-1[0, 32, 0, 0] eDP-1[0, 32, 0, 0]" ]] \
    && pass "toggle: rail hidden, no rice-rail/rice-rail-zone layer left, nothing reserved on eDP-1" \
    || fail "toggle hide: layers $(nlayer rice-rail)/$(nlayer rice-rail-zone), reserved '$(reserved)', $(ipc rail status)"
"$R/qs-run.sh" shot eDP-1 "$SHOTS/rail-hidden-eDP-1.png" >/dev/null
ipc rail hide
sleep 0.5
no_rail && status_is "hidden eDP-1" && pass "hide while hidden: stays hidden" || fail "hide twice"
ipc rail toggle
wait_for 25 rail_on eDP-1 && [[ "$(layer rice-rail)" == "$rail_geo" && "$(reserved)" == "DP-1[0, 32, 0, 0] eDP-1[0, 32, 438, 0]" ]] \
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
[[ "$(monitors)" == "DP-1" ]] && rail_on DP-1 && [[ "$(layer rice-rail)" == "DP-1 1482 38 432 1036" ]] \
    && [[ "$(reserved)" == "DP-1[0, 32, 438, 0]" ]] && status_is "shown DP-1" \
    && pass "lid closed: eDP-1 gone, rail and zone fall back to DP-1" \
    || fail "fallback: monitors '$(monitors)' $(layer rice-rail) reserved '$(reserved)' $(ipc rail status)"
"$R/qs-run.sh" shot DP-1 "$SHOTS/rail-fallback-DP-1.png" >/dev/null
read -r top bot < <(rail_extent "$SHOTS/rail-fallback-DP-1.png" 0)
[[ "$top" -le 56 && "$bot" -ge 1045 ]] && pass "fallback rail on DP-1 is full height too ($top..$bot)" || fail "fallback extent $top..$bot"
ipc rail toggle
wait_for 25 no_rail && status_is "hidden DP-1" && [[ "$(reserved)" == "DP-1[0, 32, 0, 0]" ]] \
    && pass "toggle on the fallback screen hides it there" || fail "fallback toggle: $(layers)"
ipc rail toggle
wait_for 25 rail_on DP-1 || fail "fallback toggle back"
"$R/run.sh" bash "$REPO/dot_local/bin/executable_lid" open
wait_for 50 rail_on eDP-1 || true
[[ "$(monitors)" == "DP-1 eDP-1" ]] && rail_on eDP-1 && [[ "$(nlayer rice-rail)" == 1 \
    && "$(reserved)" == "DP-1[0, 32, 0, 0] eDP-1[0, 32, 438, 0]" ]] && status_is "shown eDP-1" \
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
echo "  HUD centres: DP-1 $dcx,$dcy  eDP-1 $ecx,$ecy (free areas: DP-1 x 0-1920 y 32-1080, eDP-1 x $ex-$((ex + 1482)) y 32-1080)"
python3 -I -c 'import sys; a = list(map(float, sys.argv[1:])); ex = a[4]
sys.exit(not (abs(a[0] - 960) <= 1 and abs(a[1] - 556) <= 1 and abs(a[2] - (ex + 741)) <= 1 and abs(a[3] - 556) <= 1))' \
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
        print(c["monitor"], c["at"][0], c["at"][1], c["size"][0], c["size"][1])')
read -r kmon kx ky kw kh <<<"${kgeo:-x 0 0 0 0}"
# The 1 px border is drawn just outside at/size: border box x 6..1476, y 38..1074, so
# 6 px of wallpaper between it and the screen edge (left, bottom), the bar (32) and the
# rail (1482), the same gaps_out everywhere.
[[ "$kmon" == 1 && $((kx - 1)) == $((ex + 6)) && $((ky - 1)) == 38 && $((kx + kw + 1)) == $((ex + 1476)) && $((ky + kh + 1)) == 1074 ]] \
    && pass "kitty on eDP-1: border box 6..1476 x 38..1074, 6 px from the edge, the bar and the rail" || fail "kitty geometry: '$kgeo'"
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
g = r["gaps"]
ok = ([x[0] for x in s] == ["sys", "disk", "volume", "bluetooth", "claude"] and s[0][1] < 10
      and r["pad"] == [14, 12, 14, 12] and all(x == 18 for x in g[:-1]) and g[-1] >= 18
      and abs(r["lastBottom"] - r["clipHeight"]) <= 2 and 48 <= r["spark"][1] <= 200
      and r["columnImplicit"] <= r["clipHeight"] and min(r["rowHeights"]) >= 26)
sys.exit(not ok)' "$(pj "json.dumps(d['rail'])")" \
    && pass "rail layout: SYS, DISK, VOLUME, BLUETOOTH, CLAUDE (no clock, no media without a player); padding $(pj "d['rail']['pad']") px (left top right bottom); section gaps $(pj "d['rail']['gaps']") px (18 px, the spare above CLAUDE); CLAUDE ends at the bottom edge ($(pj "d['rail']['lastBottom']") of $(pj "d['rail']['clipHeight']") px); graph $(pj "d['rail']['spark'][1]") px (grows into spare height, capped); SYS rows $(pj "d['rail']['rowHeights']") px high" \
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

# e. DISK. The real df ran once at start: '/' is the first row.
LINE_C="#1b1d30"
DIM_C="#6a7399"
[[ "$(pj "d['disk']['rows'][0]['label'] if d['disk']['rows'] else None")" == / ]] \
    && pass "real df at start: DISK rows $(pj "[(r['label'], r['text']) for r in d['disk']['rows']]")" || fail "real df: $(pj "d['disk']")"
fixture='Filesystem          Type     1-blocks          Used     Available Capacity Mounted on
/dev/mapper/vg-root ext4   52655943680   42468913152    7679193088      85% /
/dev/nvme0n1p1      vfat    1020702720     581177344     439525376      57% /boot
/dev/sda1           btrfs 2000000000000 1900000000000   40000000000      98% /mnt/big data
/dev/sda1           btrfs 2000000000000 1900000000000   40000000000      98% /mnt/snap
//nas/share         cifs   274877906944    7478444032  267399462912       3% /mnt/nas
/dev/loop0          squashfs       100           100             0     100% /snap/x
tmpfs               tmpfs   8000000000      10000000    7990000000       1% /tmp
garbage line
/dev/sdb1           ext4           abc             1             2       3% /broken
/dev/sdc1           xfs              0             0             0       0% /empty
/dev/sdd1           f2fs  500000000000            10  499999999990       1% relative
/dev/sde1           ext4  400000000000  380000000000   20000000000      95% /data'
[[ "$(ipc probe parseDf "$fixture")" == '[["/","ext4",85,"40/49G"],["/mnt/big data","btrfs",98,"1.7/1.8T"],["/data","ext4",95,"354/373G"]]' ]] \
    && pass "parseDf: '/' first, then by size, max 3, one row per device (subvolume twice), cifs/squashfs/tmpfs/garbage/non-numeric/zero size/relative skipped, a mount point with a space" \
    || fail "parseDf: $(ipc probe parseDf "$fixture")"
[[ "$(ipc probe parseDf '') $(ipc probe parseDf 'Filesystem Type 1-blocks Used Available Capacity Mounted on') $(ipc probe parseDf 'df: no file systems processed')" == "[] [] []" ]] \
    && pass "parseDf: empty, header only and the df error text give no rows" || fail "parseDf empty"
[[ "$(ipc probe diskText)" == '["0.6/1.0G","39/49G","145/786G","1.2/1.8T","512/900M","0.0/0.0M"]' ]] \
    && pass "diskText fixtures (unit of the total, one decimal below 10)" || fail "diskText: $(ipc probe diskText)"
# A fake df that logs each run: one df per refresh, on the shared tick only.
printf '%s\n' "$fixture" >"$tmp/df.out"
printf '#!/bin/sh\necho run >>"%s"\ncat "%s"\n' "$tmp/df.log" "$tmp/df.out" >"$tmp/fake-df"
chmod +x "$tmp/fake-df"
ipc probe setDf "$tmp/fake-df"
ipc probe refreshDisks
dj() { pj "d['disk']$1"; }
disk_rows_are() { [[ "$(dj "['n']")" == "$1" ]]; }
wait_for 25 disk_rows_are 3 || true
[[ "$(pj "[(r['label'], r['text'], r['lit'], r['warn'], r['colors']) for r in d['disk']['rows']]")" \
    == "[('/', '40/49G  85%', 9, False, ['$A1_C', '$LINE_C']), ('/mnt/big data', '1.7/1.8T  98%', 10, True, ['$WARN_C']), ('/data', '354/373G  95%', 10, True, ['$WARN_C'])]" ]] \
    && pass "DISK rows from the fake df: '/ 40/49G 85%' a1, 98% and 95% in the warn colour (>= 90%)" \
    || fail "DISK rows: $(dj "['rows']")"
# The label column shows the whole mount point (df's `Mounted on`; the old rail cut
# '/mnt/big data' to '…g data'), the type after it where it fits (not after the long one).
[[ "$(pj "[(r['label'], r['truncated'], r['elide'], r['sub']) for r in d['disk']['rows']]")" \
    == "[('/', False, 2, 'ext4'), ('/mnt/big data', False, 2, ''), ('/data', False, 2, 'ext4')]" ]] \
    && pass "DISK labels: '/', '/mnt/big data', '/data' shown in full (not truncated), filesystem type 'ext4' beside the short ones" \
    || fail "DISK labels: $(pj "[(r['label'], r['truncated'], r['elide'], r['sub']) for r in d['disk']['rows']]")"
"$R/qs-run.sh" shot eDP-1 "$SHOTS/rail-disk-eDP-1.png" >/dev/null
: >"$tmp/df.log"
sleep 10
runs=$(grep -c . "$tmp/df.log" || true)
[[ "$runs" == 0 ]] && pass "no df within 10 s (5 shared ticks): not one per tick" || fail "df ran $runs times in 10 s"
ipc probe setDiskEvery 2
: >"$tmp/df.log"
sleep 8.2
runs=$(grep -c . "$tmp/df.log" || true)
[[ "$runs" -ge 1 && "$runs" -le 3 ]] && pass "diskEvery 2: $runs df runs in 8 s (every 2nd tick, one short-lived process each)" || fail "diskEvery 2: $runs runs"
ipc probe setDiskEvery 30
long="/run/media/rig/Extreme SSD Backup 2TB"
printf 'Filesystem Type 1-blocks Used Available Capacity Mounted on\n/dev/x ext4 1000 990 10 99%% /\n/dev/y btrfs 2000000000000 1000000000000 1000000000000 50%% %s\n' "$long" >"$tmp/df.out"
ipc probe refreshDisks
disk_long() { [[ "$(pj "[r['label'] for r in d['disk']['rows']]")" == "['/', '$long']" ]]; }
wait_for 25 disk_long && [[ "$(pj "[(r['truncated'], r['elide'], r['sub']) for r in d['disk']['rows']][1]")" == "(True, 2, '')" ]] \
    && pass "a long mount point ('$long') is the row label, ellipsized in the middle (Text.ElideMiddle), no type beside it" \
    || fail "long mount: $(dj "['rows']")"
"$R/qs-run.sh" shot eDP-1 "$SHOTS/rail-disk-long-eDP-1.png" >/dev/null
printf 'Filesystem Type 1-blocks Used Available Capacity Mounted on\n/dev/x ext4 1000 990 10 99%% /\n' >"$tmp/df.out"
ipc probe refreshDisks
disk_one() { [[ "$(pj "[r['text'] for r in d['disk']['rows']]")" == "['0.0/0.0M  99%']" ]]; }
wait_for 25 disk_one && pass "a later df output replaces the rows (one row, 99%)" || fail "disk update: $(dj "")"
: >"$tmp/df.out"
ipc probe refreshDisks
wait_for 25 disk_rows_are 0 && [[ "$(dj "['texts']")" == "['//', 'DISK', 'no data']" ]] \
    && pass "df prints nothing: DISK shows 'no data'" || fail "disk empty: $(dj "")"
printf '%s\n' "$fixture" >"$tmp/df.out"
ipc probe refreshDisks
wait_for 25 disk_rows_are 3 || fail "disk fixture back"

# f. VOLUME on the private PipeWire (fake-pipewire.sh: rig_sink_buds is the default).
PW() { "$R/fake-pipewire.sh" "$1" "$tmp/pw" "${@:2}"; }
vj() { pj "d['volume']$1"; }
vol_is() { [[ "$(pj "$1")" == "$2" ]]; }
out_row="[(r['label'], r['text'], r['lit'], r['colors']) for r in d['volume']['rows']]"
wait_for 25 vol_is "d['volume']['texts']" "['//', 'VOLUME', 'Rig AirPods Pro Wireless Stereo Headphones', 'OUT', '100%', 'no streams']" \
    && [[ "$(pj "$out_row")" == "[('OUT', '100%', 10, ['$A1_C'])]" ]] \
    && pass "default sink: friendly name, OUT 100% (10 lit), 'no streams'" || fail "volume start: $(vj "")"
read -r buds analog < <(PW pw pw-dump | python3 -I -c 'import json, sys
n = {o["info"]["props"].get("node.name"): o["id"] for o in json.load(sys.stdin) if o["type"].endswith(":Node")}
print(n["rig_sink_buds"], n["rig_sink_analog"])')
PW volume "$buds" 0.64
wait_for 25 vol_is "$out_row" "[('OUT', '64%', 6, ['$A1_C', '$LINE_C'])]" \
    && pass "sink volume 0.64 (as wpctl shows it): OUT 64%, 6 of 10 lit" || fail "volume 64: $(pj "$out_row")"
PW mute "$buds" true
wait_for 25 vol_is "$out_row" "[('OUT', 'MUTED', 6, ['$DIM_C', '$LINE_C'])]" \
    && pass "muted: 'MUTED', the bar dimmed" || fail "muted: $(pj "$out_row")"
PW mute "$buds" false
PW default rig_sink_analog
wait_for 25 vol_is "d['volume']['texts'][2:5]" "['Built-in Audio Analog Stereo', 'OUT', '100%']" \
    && pass "default sink switched: 'Built-in Audio Analog Stereo' 100%" || fail "switch: $(vj "")"
PW default --
wait_for 25 vol_is "d['volume']['texts']" "['//', 'VOLUME', 'no output', 'no streams']" \
    && pass "no default sink: 'no output'" || fail "no sink: $(vj "")"
PW default rig_sink_buds
s1=$(PW stream "Firefox" 0.55)
PW stream "Spotify" 0.8 >/dev/null
s3=$(PW stream "<b>mpv</b><img src=\"http://127.0.0.1:9/x.png\">" 0.3)
wait_for 25 vol_is "d['volume']['texts'][5:]" "['Firefox', '55%', 'Spotify', '80%', '<b>mpv</b><img src=\"http://127.0.0.1:9/x.png\">', '30%']" \
    && [[ "$(pj "(d['volume']['meters'], d['volume']['plain'], d['volume']['texts'][1])")" == "([3, 4, 2], 0, 'VOLUME')" ]] \
    && pass "three streams: 'Firefox 55%', 'Spotify 80%' and a markup name shown literally (plain text), 5-cell meters 3/4/2" \
    || fail "streams: $(vj "")"
"$R/qs-run.sh" shot eDP-1 "$SHOTS/rail-volume-eDP-1.png" >/dev/null
s4=$(PW stream "Discord" 1.0)
wait_for 25 vol_is "(d['volume']['streams'], len(d['volume']['meters']), d['volume']['texts'][2])" "(4, 3, '4 streams')" \
    && pass "four streams: three rows, '4 streams' in the heading" || fail "four streams: $(vj "")"
PW volume "$s1" 0.2
PW mute "$s3" true
wait_for 25 vol_is "d['volume']['texts'][6:]" "['Firefox', '20%', 'Spotify', '80%', '<b>mpv</b><img src=\"http://127.0.0.1:9/x.png\">', 'muted']" \
    && pass "stream volume and mute changes show (20%, 'muted')" || fail "stream change: $(vj "")"
PW destroy "$s1"
PW destroy "$s3"
PW destroy "$s4"
wait_for 25 vol_is "d['volume']['texts'][5:]" "['Spotify', '80%']" && pass "streams gone: their rows go" || fail "destroy: $(vj "")"

# g. BLUETOOTH is always shown (the real adapter, read only: one of the three empty
#    texts, or connected rows).
bt=$(pj "(d['bt']['visible'], d['bt']['texts'][:2], d['bt']['texts'][2] if len(d['bt']['texts']) > 2 else '')")
echo "  bluetooth: $bt"
[[ "$bt" =~ ^\(True,\ \[\'//\',\ \'BLUETOOTH\'\],\ \'(no adapter|bluetooth off|no devices connected|[0-9]+ connected)\'\)$ ]] \
    && pass "BLUETOOTH always visible (here: ${BASH_REMATCH[1]})" || fail "bluetooth: $bt"
"$R/qs-run.sh" shot eDP-1 "$SHOTS/rail-final-eDP-1.png" >/dev/null
temp_warns=$("$R/qs-run.sh" log | grep -c 'WARN qml: Stats: cannot read' || true)
[[ "$temp_warns" -le 1 ]] && pass "temperature failures logged at most once ($temp_warns)" || fail "temp warnings: $temp_warns"
"$R/qs-run.sh" stop >/dev/null

echo
if [[ $fails -eq 0 ]]; then echo "selftest-rail: all checks passed"; else echo "selftest-rail: $fails FAILED"; fi
exit $((fails > 0))
