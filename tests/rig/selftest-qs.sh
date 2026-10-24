#!/usr/bin/env bash
# shellcheck disable=SC2015  # pass() only echoes, so `test && pass || fail` is safe here
# End-to-end check of the Quickshell rig helpers and the shell foundation:
#   1. stage.sh builds the deployed tree, is idempotent, keeps create_ files, refuses
#      foreign directories, and leaves the real chezmoi state alone;
#   2. qs-run.sh start/log/shot/stop runs the staged shell.qml in the nested rig;
#   3. Theme: corrupt file fallback, hot reload, per-key defaults, preview/clearPreview
#      (through tests/rig/gallery.qml);
#   4. qs-supervise restarts a killed qs within 3 s and exits cleanly on SIGTERM;
#   5. bar and Stats (through tests/rig/stats.qml): parsers and Workspaces.layout on
#      fixtures, live values against /proc and free -m, the default-route NET source,
#      main screen, per-screen slots and their independence, the click dispatch,
#      unreadable GPU/route files, no nvidia-smi or nmcli;
#   6. wallpaper and rail (through tests/rig/rail.qml, on a private session bus): state
#      file fallbacks, image errors with exactly one warning, a huge image decoded at
#      screen size, the rail on the main screen only, its exclusive zone against a real
#      kitty, media hidden/shown with a fake MPRIS player, net sampling and failures.
# Needs no running rig (starts and stops its own). Screenshots land in
# ~/.cache/rice-testbin/shots/qs-*.png. Exit 0 = all checks passed.
set -euo pipefail
R="$(dirname "$(realpath "$0")")"
TB="${RICE_TESTBIN:-$HOME/.cache/rice-testbin}"
SHOTS="$TB/shots"
mkdir -p "$SHOTS"
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

sup_pid=""
kitty_pid=""
fake_pid=""
bus_pid=""
cleanup() {
    [[ -z "$sup_pid" ]] || kill -TERM "$sup_pid" 2>/dev/null || true
    [[ -z "$kitty_pid" ]] || kill -TERM "$kitty_pid" 2>/dev/null || true
    [[ -z "$fake_pid" ]] || kill -TERM "$fake_pid" 2>/dev/null || true
    "$R/qs-run.sh" stop >/dev/null 2>&1 || true
    "$R/nested-hypr.sh" stop >/dev/null 2>&1 || true
    [[ -z "$bus_pid" ]] || kill -TERM "$bus_pid" 2>/dev/null || true
    [[ -z "${tmp:-}" ]] || rm -rf -- "$tmp"
}
trap cleanup EXIT

# --- 1. stage.sh -------------------------------------------------------------------
tmp=$(mktemp -d "${TMPDIR:-/tmp}/selftest-qs.XXXXXX")
real_state="$HOME/.config/chezmoi/chezmoistate.boltdb"
state_before=$(stat -c %Y.%s "$real_state" 2>/dev/null || echo absent)
cache_before=$(stat -c %Y "$HOME/.cache/chezmoi" 2>/dev/null || echo absent)

st="$tmp/home"
"$R/stage.sh" "$st" >/dev/null && pass "stage.sh into a fresh dir" || fail "stage.sh failed"
ok=1
for f in .config/quickshell/shell.qml .config/quickshell/Theme.qml .config/quickshell/qmldir \
    .config/quickshell/colors.json .config/quickshell/components/Chamfer.qml \
    .config/quickshell/components/Meter.qml .config/quickshell/components/Chip.qml \
    .config/quickshell/services/Stats.qml .config/quickshell/services/Screens.qml \
    .config/quickshell/services/qmldir .config/quickshell/bar/Bar.qml \
    .config/quickshell/bar/Workspaces.qml .config/quickshell/wallpaper/Wallpaper.qml \
    .config/quickshell/wallpaper/WallpaperState.qml .config/quickshell/wallpaper/qmldir \
    .config/quickshell/rail/Rail.qml .config/quickshell/rail/ClockWidget.qml \
    .config/quickshell/rail/SysWidget.qml .config/quickshell/rail/MediaWidget.qml \
    .config/quickshell/rail/SectionLabel.qml \
    .local/share/rice/palette.py; do
    [[ -s "$st/$f" ]] || { ok=0; echo "  missing $f"; }
done
for b in qs-supervise rice-palette; do
    [[ -x "$st/.local/bin/$b" ]] || { ok=0; echo "  not executable: .local/bin/$b"; }
done
[[ ! -e "$st/.config/quickshell/create_colors.json" && ! -e "$st/dot_config" ]] || { ok=0; echo "  chezmoi names leaked"; }
[[ $ok -eq 1 ]] && pass "staged tree has the deployed layout" || fail "staged tree incomplete"

echo '{"a1":"#123456"}' >"$st/.config/quickshell/colors.json"
echo "// staged edit" >>"$st/.config/quickshell/shell.qml"
"$R/stage.sh" "$st" >/dev/null
[[ "$(cat "$st/.config/quickshell/colors.json")" == '{"a1":"#123456"}' ]] \
    && pass "re-stage keeps an existing create_ file (colors.json)" || fail "re-stage overwrote colors.json"
cmp -s "$st/.config/quickshell/shell.qml" "$R/../../dot_config/quickshell/shell.qml" \
    && pass "re-stage restores managed files (shell.qml)" || fail "re-stage did not restore shell.qml"

mkdir -p "$tmp/foreign" && touch "$tmp/foreign/x"
! "$R/stage.sh" "$tmp/foreign" >/dev/null 2>&1 && pass "stage.sh refuses a foreign non-empty dir" \
    || fail "stage.sh staged into a foreign dir"
! "$R/stage.sh" "$HOME" >/dev/null 2>&1 && pass "stage.sh refuses the real HOME" || fail "stage.sh accepted HOME"

[[ "$(stat -c %Y.%s "$real_state" 2>/dev/null || echo absent)" == "$state_before" \
    && "$(stat -c %Y "$HOME/.cache/chezmoi" 2>/dev/null || echo absent)" == "$cache_before" ]] \
    && pass "real chezmoi state and cache untouched ($state_before / $cache_before)" \
    || fail "real chezmoi state or cache changed"

# --- 2. qs-run.sh with production shell.qml ------------------------------------------
"$R/nested-hypr.sh" start "$R/full.lua" >/dev/null
staged=$("$R/qs-run.sh" start --restage) && pass "qs-run.sh start (staged HOME $staged)" || fail "qs-run.sh start"
sleep 1
# The fresh staged HOME has no wallpaper yet: exactly one warning for the missing
# default image is expected (section 6 covers the wallpaper in detail).
bad=$("$R/qs-run.sh" log | grep -E 'ERROR|WARN' | grep -v -e 'Failed to register with host portal' \
    -e 'QML Image at @wallpaper/Wallpaper.qml.*Cannot open: .*/Pictures/berserk-wallpaper.jpg$' || true)
nimg=$("$R/qs-run.sh" log | grep -c 'QML Image' || true)
[[ -z "$bad" && "$nimg" == 1 ]] && pass "qs log: no ERROR/WARN besides the portal warning and one for the missing default wallpaper" \
    || { fail "qs log has errors ($nimg image warnings)"; echo "$bad"; }
qs_pid=$("$R/qs-run.sh" status | sed -n 's/^running: pid=\([0-9]*\) .*/\1/p')
[[ "$(tr '\0' '\n' <"/proc/$qs_pid/environ" | grep -E '^(HOME|RICE_NO_RELOAD)=' | sort | tr '\n' ' ')" \
    == "HOME=$staged RICE_NO_RELOAD=1 " ]] && pass "qs runs with HOME=staged and RICE_NO_RELOAD=1" \
    || fail "qs environment"
layers=$("$R/run.sh" hyprctl layers | grep -c 'namespace: rice-bar' || true)
[[ "$layers" -eq 2 ]] && pass "bar on both outputs (2 rice-bar layers)" || fail "rice-bar layers: $layers"
walls=$("$R/run.sh" hyprctl layers | grep -c 'namespace: rice-wallpaper' || true)
railn=$("$R/run.sh" hyprctl layers | grep -c 'namespace: rice-rail,' || true)
[[ "$walls" -eq 2 && "$railn" -eq 1 ]] && pass "shell.qml: wallpaper on both outputs, one rail" \
    || fail "rice-wallpaper layers: $walls, rice-rail layers: $railn"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-skeleton-DP-1.png" >/dev/null && pass "qs-run.sh shot" || fail "qs-run.sh shot"
"$R/qs-run.sh" stop >/dev/null
! kill -0 "$qs_pid" 2>/dev/null && ! "$R/qs-run.sh" status >/dev/null && pass "qs-run.sh stop" || fail "qs-run.sh stop"

# --- 3. Theme through the gallery ----------------------------------------------------
"$R/qs-run.sh" start --entry "$R/gallery.qml" >/dev/null
qs_pid=$("$R/qs-run.sh" status | sed -n 's/^running: pid=\([0-9]*\) .*/\1/p')
colors="$staged/.config/quickshell/colors.json"
orig=$(cat "$colors")
a1() { "$R/qs-run.sh" ipc call gallery state | python3 -I -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }
replace() { printf '%s\n' "$1" >"$colors.tmp" && mv -f "$colors.tmp" "$colors"; sleep 1; }

[[ "$(a1 a1)" == "#00f0ff" ]] && pass "Theme reads colors.json (a1 #00f0ff)" || fail "Theme a1 at start: $(a1 a1)"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-gallery.png" >/dev/null
replace '{ not json'
kill -0 "$qs_pid" && [[ "$(a1 a1)" == "#00f0ff" ]] && "$R/qs-run.sh" log -t 5 | grep -q 'WARN qml: Theme: cannot parse' \
    && pass "corrupt colors.json: shell up, defaults, warning logged" || fail "corrupt colors.json handling"
replace "${orig/\"#00f0ff\"/\"#7cff00\"}"
[[ "$(a1 a1)" == "#7cff00" && "$(a1 a2)" == "#ff2e88" ]] && kill -0 "$qs_pid" \
    && pass "hot reload: a1 -> #7cff00 without restarting qs (pid $qs_pid)" || fail "hot reload"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-gallery-a1.png" >/dev/null
replace '{"bg":"#07070d","panel":"#0c0d16","line":"#ffffff","dim":"#6a7399","fg":"#d7e3f0","a1":"#7cff00"}'
[[ "$(a1 line)" == "#ffffff" && "$(a1 a2)" == "#ff2e88" && "$(a1 warn)" == "#ffd23f" ]] \
    && pass "missing keys a2,warn keep defaults, others apply" || fail "missing-key fallback"
replace "$orig"
"$R/qs-run.sh" ipc call gallery preview
[[ "$(a1 a1)" == "#ffb000" && "$(a1 bg)" == "#100814" ]] && pass "Theme.preview overrides colours" || fail "preview"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-gallery-preview.png" >/dev/null
"$R/qs-run.sh" ipc call gallery clear
[[ "$(a1 a1)" == "#00f0ff" && "$(a1 bg)" == "#07070d" ]] && pass "Theme.clearPreview restores file colours" || fail "clearPreview"
[[ "$(cat "$colors")" == "$orig" ]] && pass "preview wrote no files" || fail "colors.json changed by preview"
"$R/qs-run.sh" stop >/dev/null

# A stale qs-run.env (reboot / PID reuse) must never make `stop` signal the recorded PID.
sleep 300 &
decoy=$!
printf 'QS_PID=%s\nQS_RUN_ID=qsrun-stale-%s\nQS_HOME=%s\nQS_ENTRY=x\n' "$decoy" "$$" "$staged" >"$TB/qs-run.env"
stop_out=$("$R/qs-run.sh" stop)
kill -0 "$decoy" 2>/dev/null && [[ "$stop_out" == *stale* && ! -e "$TB/qs-run.env" ]] \
    && pass "qs-run.sh stop ignores a stale record (decoy $decoy alive)" || fail "stale qs-run.env handling"
kill "$decoy" 2>/dev/null || true
wait "$decoy" 2>/dev/null || true

# --- 4. qs-supervise -----------------------------------------------------------------
# Start the staged supervisor with the same environment qs-run.sh uses.
(
    # shellcheck source=tests/rig/rig_env.sh
    source "$R/rig_env.sh"
    export RICE_NO_RELOAD=1 HOME="$staged" XDG_CONFIG_HOME="$staged/.config" \
        XDG_DATA_HOME="$staged/.local/share" XDG_STATE_HOME="$staged/.local/state" \
        XDG_CACHE_HOME="$staged/.cache" PATH="$staged/.local/bin:$PATH"
    exec qs-supervise -p "$staged/.config/quickshell" --no-color
) >"$TB/selftest-qs-supervise.out" 2>&1 </dev/null &
sup_pid=$!
qs_child() { # the supervisor's qs child (comm qs or quickshell), by parent PID only
    local p
    for p in $(pgrep -P "$sup_pid" || true); do
        case "$(cat "/proc/$p/comm" 2>/dev/null)" in qs | quickshell) echo "$p"; return 0 ;; esac
    done
    return 1
}
for _ in $(seq 50); do qs_child >/dev/null && break; sleep 0.1; done
first=$(qs_child || true)
if [[ -z "$first" ]]; then
    fail "qs-supervise started no qs child"
else
    sleep 2
    t0=$(date +%s.%N)
    kill -TERM "$first"
    second=""
    while :; do
        second=$(qs_child || true)
        [[ -n "$second" && "$second" != "$first" ]] && break
        (($(echo "$(date +%s.%N) - $t0 > 5" | bc))) && break
        sleep 0.05
    done
    t1=$(date +%s.%N)
    dt=$(echo "$t1 - $t0" | bc)
    echo "  killed qs $first at $t0, new qs ${second:-none} at $t1 (${dt}s)"
    [[ -n "$second" && "$second" != "$first" ]] && (($(echo "$dt < 3" | bc))) \
        && pass "qs-supervise restarted qs in ${dt}s (< 3 s)" || fail "qs-supervise restart (${dt}s)"
    sleep 2
    kill -TERM "$sup_pid"
    for _ in $(seq 50); do kill -0 "$sup_pid" 2>/dev/null || break; sleep 0.1; done
    sleep 2
    ! kill -0 "$sup_pid" 2>/dev/null && ! kill -0 "$second" 2>/dev/null \
        && [[ -z "$(pgrep -P "$sup_pid" || true)" ]] \
        && [[ -z "$("$R/run.sh" qs list --all 2>/dev/null | grep -F "$staged" || true)" ]] \
        && pass "SIGTERM: supervisor and its qs exited, nothing restarted" || fail "supervisor SIGTERM"
    sup_pid=""
fi

# --- 5. bar and Stats ------------------------------------------------------------------
# Fresh rig so the workspace state is known: DP-1 (focused, an extra pool, starts on the
# free id 6) and eDP-1 (pool 1, 11-15 persistent). Every value check below fails for a
# value stuck at its default (cpu 0, memGb 0, gpu -1, netConn "", no main screen).
"$R/nested-hypr.sh" stop >/dev/null
"$R/nested-hypr.sh" start "$R/full.lua" >/dev/null
"$R/qs-run.sh" start --entry "$R/stats.qml" >/dev/null
sleep 3
sget() { "$R/qs-run.sh" ipc call stats get; }
spy() { python3 -I -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
H() { "$R/run.sh" hyprctl "$@"; }
active_ws() {
    H monitors -j | python3 -I -c 'import json,sys; print(next(m["activeWorkspace"]["id"] for m in json.load(sys.stdin) if m["name"]==sys.argv[1]))' "$1"
}
filled() { sget | spy "d['slots']['$1']['filled']"; }

want='{"stat":{"total":1000,"idle":800},"cpu":50,"cpuNoDelta":null,"statBad":null,"mem":{"gb":11.444091796875,"pct":75},"memBad":null,"gpu":17,"gpuBad":-1,'
want+='"route":"wlan0","route2":"wlan0","routeNone":"","routeBad":"","routeEmpty":"","slot":[1,5,1,5,1,5,6],'
want+='"wsNormal":{"base":10,"targets":[11,12,13,14,15],"filled":2},'
want+='"wsMigrated":{"base":20,"targets":[21,22,23,24,25],"filled":3},'
want+='"wsLeftover":{"base":10,"targets":[11,12,13,14,15],"filled":3},'
want+='"wsLeftoverLow":{"base":0,"targets":[1,2,3,4,5],"filled":3},'
want+='"wsActive8":{"base":-1,"targets":[-1,-1,-1,-1,-1],"filled":0},'
want+='"wsActive8Mixed":{"base":10,"targets":[11,12,13,14,15],"filled":0},'
want+='"wsEmpty":{"base":-1,"targets":[-1,-1,-1,-1,-1],"filled":0}}'
got=$("$R/qs-run.sh" ipc call stats parse)
[[ "$got" == "$want" ]] && pass "Stats parsers, route parser, slot rule and Workspaces.layout on fixtures" \
    || { fail "fixtures"; echo "  got  $got"; echo "  want $want"; }

# Live values. CPU must be > 0 in two snapshots 4 s apart (a stuck sampler stays 0).
snap1=$(sget)
sleep 4
snap=$(sget)
read -r used_mb total_mb < <(free -m | awk '/^Mem:/{print $3, $2}')
python3 -I -c '
import json, sys
a, b = json.loads(sys.argv[1]), json.loads(sys.argv[2])
used, total = float(sys.argv[3]), float(sys.argv[4])
print("  cpu %.2f then %.2f  memGb %.2f (free -m: %.2f)  memPct %.1f (free -m: %.1f)"
      % (a["cpu"], b["cpu"], b["memGb"], used / 1024, b["memPct"], 100 * used / total))
ok = 0 < a["cpu"] <= 100 and 0 < b["cpu"] <= 100
ok = ok and abs(b["memGb"] - used / 1024) < max(0.15, used / 1024 * 0.03)
ok = ok and abs(b["memPct"] - 100 * used / total) < 1.5
sys.exit(0 if ok else 1)' "$snap1" "$snap" "$used_mb" "$total_mb" \
    && pass "Stats cpu > 0 in two samples, mem agrees with free -m" || fail "Stats cpu/mem"
amd=""
for v in /sys/class/drm/card*/device/vendor; do
    [[ "$(cat "$v" 2>/dev/null)" == 0x1002 ]] && { amd="${v%/vendor}/gpu_busy_percent"; break; }
done
gpu_ok=$(echo "$snap" | spy "'ok' if d['gpuPath'] == '$amd' and (d['gpu'] >= 0 if '$amd' else d['gpu'] == -1) else 'bad'")
[[ "$gpu_ok" == ok ]] && pass "Stats gpu from the AMD card (${amd:-none})" || fail "Stats gpu/gpuPath"
[[ -z "$(pgrep -x nvidia-smi || true)" ]] && pass "no nvidia-smi while the shell runs" || fail "nvidia-smi running"
[[ -z "$(pgrep -x nmcli || true)" ]] && pass "no nmcli spawned" || fail "nmcli running"
# Default route computed independently: Destination 00000000, RTF_UP, lowest metric.
want_if=$(python3 -I -c '
best = None
for line in open("/proc/net/route").read().splitlines()[1:]:
    f = line.split()
    if len(f) >= 8 and f[1] == "00000000" and int(f[3], 16) & 1 and (best is None or int(f[6]) < best[0]):
        best = (int(f[6]), f[0])
print(best[1] if best else "")')
net=$(echo "$snap" | spy "d['netConn']")
[[ "$net" == "$want_if" ]] && pass "netConn = default-route interface (${want_if:-none})" || fail "netConn: '$net', want '$want_if'"
route_fx="$tmp/route"
printf 'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n' >"$route_fx"
printf 'fixture0\t00000000\t0101A8C0\t0003\t0\t0\t7\t00000000\t0\t0\t0\n' >>"$route_fx"
"$R/qs-run.sh" ipc call stats setPaths /proc/stat /proc/meminfo "$amd" "$route_fx"
sleep 3
net=$(sget | spy "d['netConn']")
[[ "$net" == fixture0 ]] && pass "netConn follows a route fixture on the shared timer (fixture0)" || fail "route fixture: '$net'"
[[ "$(echo "$snap" | spy "','.join(d['main'])")" == "DP-1" ]] \
    && pass "Screens.isMain: no BenQ, so the first screen is main" || fail "main screen"
ids=$(echo "$snap" | spy "d['slots']['eDP-1']['ids']")
[[ "$ids" == "[11, 12, 13, 14, 15]" ]] && pass "eDP-1 bar lists its own pool (11-15)" || fail "eDP-1 ids: $ids"
dp0=$(echo "$snap" | spy "d['slots']['DP-1']")
[[ "$dp0" == "{'ids': [6], 'active': 6, 'filled': 0, 'targets': [-1, -1, -1, -1, -1]}" ]] \
    && pass "DP-1 on ws 6 (slot outside 1-5): no cell filled, no click targets" || fail "DP-1 at start: $dp0"

edp0=$(active_ws eDP-1)
"$R/keys.sh" -M ctrl -k 3 -m ctrl
sleep 1
[[ "$(active_ws DP-1)" == 23 && "$(active_ws eDP-1)" == "$edp0" && "$(filled DP-1)" == 3 \
    && "$(filled eDP-1)" == "$((edp0 - 10))" ]] \
    && pass "Ctrl+3 on DP-1: its bar fills slot 3 (ws 23), the eDP-1 bar is unchanged" \
    || fail "Ctrl+3 independence (DP-1 $(active_ws DP-1) $(filled DP-1), eDP-1 $(active_ws eDP-1) $(filled eDP-1))"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-bar-DP-1.png" >/dev/null
H dispatch 'hl.dsp.focus({ monitor = "eDP-1" })' >/dev/null
sleep 0.3
"$R/keys.sh" -M ctrl -M alt -k Right -m alt -m ctrl
sleep 1
[[ "$(active_ws eDP-1)" == $((edp0 + 1)) && "$(active_ws DP-1)" == 23 \
    && "$(filled eDP-1)" == "$((edp0 - 9))" && "$(filled DP-1)" == 3 ]] \
    && pass "Ctrl+Alt+Right on eDP-1: only the eDP-1 bar moves" \
    || fail "step independence (eDP-1 $(active_ws eDP-1) $(filled eDP-1), DP-1 $(filled DP-1))"
"$R/qs-run.sh" shot eDP-1 "$SHOTS/qs-bar-eDP-1.png" >/dev/null
targets=$(sget | spy "d['slots']['DP-1']['targets']")
[[ "$targets" == "[21, 22, 23, 24, 25]" ]] && pass "DP-1 bar targets its own pool (21-25)" || fail "DP-1 targets: $targets"
"$R/qs-run.sh" ipc call stats click DP-1 5
sleep 1
[[ "$(active_ws DP-1)" == 25 && "$(active_ws eDP-1)" == $((edp0 + 1)) ]] \
    && pass "cell click (focusSlot) on the DP-1 bar: ws 25 on DP-1, eDP-1 unchanged" \
    || fail "click dispatch (DP-1 $(active_ws DP-1), eDP-1 $(active_ws eDP-1))"

# Unreadable GPU and route files: gpu -1, netConn keeps its last value, one warning
# each, and the log does not grow per tick.
unread="$tmp/unreadable"
: >"$unread"
chmod 000 "$unread"
"$R/qs-run.sh" ipc call stats setPaths /proc/stat /proc/meminfo "$unread" "$unread"
sleep 4
n1=$("$R/qs-run.sh" log | wc -l)
sleep 8
n2=$("$R/qs-run.sh" log | wc -l)
after=$(sget)
[[ "$(echo "$after" | spy "d['gpu']")" == -1 && "$(echo "$after" | spy "d['netConn']")" == fixture0 && "$n1" == "$n2" \
    && "$("$R/qs-run.sh" log | grep -c 'Stats: cannot read')" == 2 ]] \
    && pass "unreadable GPU/route files: gpu -1, netConn kept, one warning each, log stable ($n1 lines)" \
    || fail "unreadable files ($n1 -> $n2, $after)"
bad=$("$R/qs-run.sh" log | grep -E 'ERROR|WARN' | grep -v -e 'Failed to register with host portal' -e 'Stats: cannot read' || true)
[[ -z "$bad" ]] && pass "qs log: no other ERROR/WARN" || { fail "qs log"; echo "$bad"; }
"$R/qs-run.sh" stop >/dev/null

# --- 6. wallpaper and rail --------------------------------------------------------------
# A fresh rig and a private session bus: no live MPRIS player can leak in, and the fake
# player below never touches the real bus. The staged HOME is re-created, so there is no
# state file and no default image at the start.
"$R/nested-hypr.sh" stop >/dev/null
"$R/nested-hypr.sh" start "$R/full.lua" >/dev/null
{ read -r bus_addr; read -r bus_pid; } < <(dbus-daemon --session --fork --nopidfile --print-address=1 --print-pid=1)
[[ -n "$bus_addr" && "$bus_pid" =~ ^[0-9]+$ ]] || fail "private dbus-daemon"
staged=$(DBUS_SESSION_BUS_ADDRESS="$bus_addr" "$R/qs-run.sh" start --restage --entry "$R/rail.qml")
qs_pid=$("$R/qs-run.sh" status | sed -n 's/^running: pid=\([0-9]*\) .*/\1/p')
sleep 3
rget() { "$R/qs-run.sh" ipc call rail get; }
rj() { rget | spy "$1"; }
logn() { "$R/qs-run.sh" log | wc -l; }
# Log lines after line $1 that are WARN or ERROR (the portal warning excluded).
warns_since() { "$R/qs-run.sh" log | tail -n +"$(($1 + 1))" | grep -E 'WARN|ERROR' | grep -v 'host portal' || true; }
state="$staged/.local/state/quickshell/wallpaper.json"
pics="$staged/Pictures"
mkdir -p "$pics" "$(dirname "$state")"
put_state() { printf '%s\n' "$1" >"$state.tmp" && mv -f "$state.tmp" "$state"; }

want='{"netDev":{"rx":4000,"tx":1000},"netDevBad":null,"netDevLoOnly":{"rx":0,"tx":0},'
want+='"rates":{"up":1024,"down":2048},"ratesFirst":null,"ratesBack":null,"ratesNoTime":null,'
want+='"compact":["0B","512B","1023B","1.0K","8.4K","120K","1.2M","3.0G","0B"],'
want+='"state":[["/a/b.png","neon",false],["","",true],["","",true],["","",true],["","x",true],["","",true],["","",true],["","",true]]}'
got=$("$R/qs-run.sh" ipc call rail parse)
[[ "$got" == "$want" ]] && pass "net/dev parser, rates, compact units and wallpaper.json parser on fixtures" \
    || { fail "rail fixtures"; echo "  got  $got"; echo "  want $want"; }

# a. No state file, no default image: Theme.bg, exactly one warning, and the second
#    screen never even tries the path.
w=$(rget)
echo "$w" | spy "'ok' if d['wallpaper']['path'] == d['wallpaper']['defaultPath'] == '$pics/berserk-wallpaper.jpg' and d['wallpaper']['verdict'] == -1 and d['wallpaper']['verdictPath'] == d['wallpaper']['path'] and d['wallpaper']['images']['DP-1']['status'] == 3 and d['wallpaper']['images']['eDP-1']['source'] == '' else d" | grep -qx ok \
    && [[ "$(warns_since 0 | grep -c .)" == 1 && "$(warns_since 0 | grep -c 'QML Image')" == 1 ]] \
    && pass "no state file, default image missing: background colour, one warning, eDP-1 never loads it" \
    || { fail "missing default"; echo "  $w"; warns_since 0; }

# b. The state file appears (FileView cannot watch an absent file: the 10 s re-check
#    must pick it up) and names a 7680x4320 PNG: both screens decode it at 1920x1080.
cp /usr/share/hypr/wall0.png "$pics/wall0.png"
n0=$(logn)
put_state "{\"path\": \"$pics/wall0.png\", \"palette\": \"wall0\"}"
ok=""
for _ in $(seq 30); do
    sleep 0.5
    [[ "$(rj "d['wallpaper']['images']['eDP-1']['status']")" == 1 ]] && { ok=1; break; }
done
w=$(rget)
[[ -n "$ok" ]] && echo "$w" | spy "'ok' if d['wallpaper']['filePath'] == '$pics/wall0.png' and all(i['status'] == 1 and i['decoded'] == [1920, 1080] for i in d['wallpaper']['images'].values()) else d" | grep -qx ok \
    && [[ -z "$(warns_since "$n0")" ]] \
    && pass "state file created later is picked up; both screens show the image decoded at 1920x1080" \
    || { fail "state file pickup / decode"; echo "  $w"; warns_since "$n0"; }
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-rail-DP-1.png" >/dev/null
"$R/qs-run.sh" shot eDP-1 "$SHOTS/qs-wall-eDP-1.png" >/dev/null

# c. Corrupt state file -> the default path, one warning about the file.
n0=$(logn)
put_state '{ not json'
sleep 2
[[ "$(rj "d['wallpaper']['path'] == d['wallpaper']['defaultPath']")" == True ]] && kill -0 "$qs_pid" \
    && [[ "$(warns_since "$n0" | grep -c 'Wallpaper:.*cannot parse')" == 1 ]] \
    && pass "corrupt wallpaper.json: default path, one warning, shell up" || { fail "corrupt state"; warns_since "$n0"; }

# d./e. A text file and a directory: background colour, exactly one warning each, and
#       only the main screen tried it.
echo "not an image" >"$pics/notes.txt"
mkdir -p "$pics/adir"
for target in "$pics/notes.txt" "$pics/adir"; do
    n0=$(logn)
    put_state "{\"path\": \"$target\"}"
    sleep 2
    w=$(rget)
    echo "$w" | spy "'ok' if d['wallpaper']['verdictPath'] == '$target' and d['wallpaper']['verdict'] == -1 and d['wallpaper']['images']['DP-1']['status'] == 3 and d['wallpaper']['images']['eDP-1']['source'] == '' else d" | grep -qx ok \
        && [[ "$(warns_since "$n0" | grep -c .)" == 1 ]] && kill -0 "$qs_pid" \
        && pass "path is ${target##*/}: background colour, exactly one warning: $(warns_since "$n0" | sed 's/.*Wallpaper.qml\[[0-9:]*\]: //' | cut -c1-40)" \
        || { fail "bad image ${target##*/}"; echo "  $w"; warns_since "$n0"; }
done
n1=$(logn)
sleep 4
[[ "$(logn)" == "$n1" ]] && pass "no retry loop: log stable after the failures" || fail "log grows after failures"

# f. An 8000x8000 PNG: decoded at most at screen size (crop-fill 1920x1920), shell up.
python3 -I - "$pics/huge.png" <<'PY'
import struct, sys, zlib
w = h = 8000
c = zlib.compressobj(1)
row = b"\x00" + (b"\x00\xf0\xff" * 40 + b"\x10\x10\x20" * 40) * (w // 80)
data = b"".join(c.compress(row) for _ in range(h)) + c.flush()
ck = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + ck(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                              + ck(b"IDAT", data) + ck(b"IEND", b""))
PY
rss0=$(awk '/^VmRSS/{print $2}' "/proc/$qs_pid/status")
put_state "{\"path\": \"$pics/huge.png\"}"
ok=""
for _ in $(seq 40); do
    sleep 0.5
    [[ "$(rj "d['wallpaper']['images']['eDP-1']['status']")" == 1 ]] && { ok=1; break; }
done
sleep 2
rss1=$(awk '/^VmRSS/{print $2}' "/proc/$qs_pid/status")
w=$(rget)
echo "  RSS before ${rss0} kB, after the 8000x8000 image ${rss1} kB"
[[ -n "$ok" ]] && kill -0 "$qs_pid" && echo "$w" | spy "'ok' if all(i['status'] == 1 and max(i['decoded']) <= 1920 and min(i['decoded']) >= 1080 for i in d['wallpaper']['images'].values()) else d" | grep -qx ok \
    && pass "8000x8000 PNG shown, decoded at $(echo "$w" | spy "d['wallpaper']['images']['DP-1']['decoded']") (not 8000x8000)" \
    || { fail "huge image"; echo "  $w"; }
put_state "{\"path\": \"$pics/wall0.png\"}"

# g. The rail: one instance, on the main screen, below the bar; its width reserved.
[[ "$(rj "d['railScreens']")" == "['DP-1']" && "$(rj "d['main']")" == "['DP-1']" ]] \
    && pass "rail instance only on the main screen (DP-1)" || fail "rail screens: $(rj "d['railScreens']")"
layer_xywh() {
    H layers -j | python3 -I -c '
import json, sys
for mon, v in json.load(sys.stdin).items():
    for lvl in v["levels"].values():
        for l in lvl:
            if l["namespace"] == sys.argv[1]:
                print(mon, l["x"], l["y"], l["w"], l["h"])' "$1"
}
rail_geo=$(layer_xywh rice-rail)
zone_geo=$(layer_xywh rice-rail-zone)
reserved=$(H monitors -j | python3 -I -c 'import json,sys; print(" ".join(m["name"] + str(m["reserved"]) for m in json.load(sys.stdin)))')
[[ "$rail_geo" == "DP-1 1488 26 432 1054" && "$zone_geo" == "DP-1 1919 26 1 1054" \
    && "$reserved" == "DP-1[0, 26, 432, 0] eDP-1[0, 26, 0, 0]" ]] \
    && pass "rail at 1488,26 432x1054 below the bar; 432 px reserved on DP-1 only; no rail on eDP-1" \
    || fail "rail geometry: rail '$rail_geo' zone '$zone_geo' reserved '$reserved'"

# h. A real kitty on DP-1 tiles up to the rail and below the bar (HOME etc. staged, no
#    user config, private bus).
"$R/run.sh" env HOME="$staged" XDG_CONFIG_HOME="$staged/.config" XDG_CACHE_HOME="$staged/.cache" \
    XDG_STATE_HOME="$staged/.local/state" XDG_DATA_HOME="$staged/.local/share" \
    DBUS_SESSION_BUS_ADDRESS="$bus_addr" kitty --config=NONE --title rig-kitty >"$tmp/kitty.out" 2>&1 </dev/null &
kitty_pid=$!
geo=""
for _ in $(seq 30); do
    sleep 0.3
    geo=$(H clients -j | python3 -I -c '
import json, sys
for c in json.load(sys.stdin):
    if c["title"] == "rig-kitty":
        print(c["monitor"], c["at"][0], c["at"][1], c["size"][0], c["size"][1])')
    [[ -n "$geo" ]] && break
done
read -r kmon kx ky kw kh <<<"${geo:-x 0 0 0 0}"
echo "  kitty: monitor $kmon at $kx,$ky size ${kw}x${kh} (right edge $((kx + kw)), rail starts at 1488)"
[[ "$kmon" == 0 && $((kx + kw)) -le 1488 && $((kx + kw)) -ge 1460 && "$ky" -ge 26 ]] \
    && pass "kitty on DP-1 stops at the rail's left edge ($((kx + kw)) <= 1488) and below the bar (y $ky)" \
    || fail "kitty geometry: '$geo'"
sleep 0.5
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-rail-kitty-DP-1.png" >/dev/null
kill -TERM "$kitty_pid" 2>/dev/null || true
wait "$kitty_pid" 2>/dev/null || true
kitty_pid=""

# i. Media: hidden without a player; a fake player shows title, artist, length and a
#    position that advances; hidden again when it goes away.
[[ "$(rj "d['media']['visible']")" == False ]] && pass "no MPRIS player: media section hidden" \
    || fail "media without player: $(rj "d['media']")"
DBUS_SESSION_BUS_ADDRESS="$bus_addr" python3 -I "$R/fake-mpris.py" "Rig Song" "Rig Artist" 252 >"$tmp/fake.out" 2>&1 &
fake_pid=$!
for _ in $(seq 20); do sleep 0.3; [[ "$(rj "d['media']['visible']")" == True ]] && break; done
m1=$(rget)
sleep 2.5
m2=$(rget)
python3 -I -c '
import json, sys
a, b = json.loads(sys.argv[1])["media"], json.loads(sys.argv[2])["media"]
print("  media:", b["texts"], "position %.1f -> %.1f" % (a["position"], b["position"]))
ok = b["visible"] and b["title"] == "Rig Song" and b["artist"] == "Rig Artist" and abs(b["length"] - 252) < 0.01
ok = ok and "4:12" in b["texts"] and b["position"] - a["position"] >= 1.5
sys.exit(0 if ok else 1)' "$m1" "$m2" && pass "fake player: media shows title, artist, 4:12, position advances" \
    || fail "media with fake player"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-rail-media-DP-1.png" >/dev/null
kill -TERM "$fake_pid" 2>/dev/null || true
wait "$fake_pid" 2>/dev/null || true
fake_pid=""
for _ in $(seq 20); do sleep 0.3; [[ "$(rj "d['media']['visible']")" == False ]] && break; done
[[ "$(rj "d['media']['visible']")" == False ]] && pass "player gone: media section hidden again" || fail "media after player exit"

# j. Net sampling: the history grows on the shared timer and the sparkline draws it; an
#    unreadable /proc/net/dev freezes it with one warning and no QML error.
n_a=$(rj "d['net']['n']")
sleep 4.2
n_b=$(rj "d['net']['n']")
[[ "$n_b" -gt "$n_a" && "$n_b" -le 24 && "$(rj "d['spark']['n']")" == "$n_b" ]] \
    && pass "netHistory grows ($n_a -> $n_b samples), the sparkline draws all of them" || fail "net history $n_a -> $n_b"
gpu_vis=$(rj "d['gpuRow']")
n0=$(logn)
"$R/qs-run.sh" ipc call rail setNetDevPath "$unread"
"$R/qs-run.sh" ipc call rail setGpuPath "$unread"
sleep 3
n_c=$(rj "d['net']['n']")
sleep 4.2
w=$(rget)
[[ "$(echo "$w" | spy "d['net']['n']")" == "$n_c" && "$(warns_since "$n0" | grep -c 'Stats: cannot read')" == 2 \
    && "$(warns_since "$n0" | grep -vc 'Stats: cannot read')" == 0 ]] && kill -0 "$qs_pid" \
    && pass "unreadable /proc/net/dev: history frozen at $n_c, one warning, no QML error" || { fail "unreadable net/dev"; warns_since "$n0"; }
[[ -z "$amd" || "$gpu_vis" == True ]] && [[ "$(echo "$w" | spy "d['gpuRow']")" == False ]] \
    && pass "GPU row shown with a GPU ($gpu_vis), hidden when gpu is -1" || fail "GPU row: before $gpu_vis, after $(echo "$w" | spy "d['gpuRow']")"
bad=$("$R/qs-run.sh" log | grep -E 'ERROR|WARN' | grep -v -e 'host portal' -e 'Stats: cannot read' -e 'QML Image' \
    -e 'Wallpaper:.*cannot parse' || true)
[[ -z "$bad" ]] && pass "qs log: no other ERROR/WARN in section 6" || { fail "qs log section 6"; echo "$bad"; }
"$R/qs-run.sh" stop >/dev/null
kill -TERM "$bus_pid" 2>/dev/null || true
bus_pid=""

"$R/nested-hypr.sh" stop >/dev/null
trap - EXIT
rm -rf -- "$tmp"
echo "screenshots: $SHOTS/qs-*.png"
[[ $fails -eq 0 ]] && echo "SELFTEST-QS OK" || { echo "SELFTEST-QS: $fails failure(s)"; exit 1; }
