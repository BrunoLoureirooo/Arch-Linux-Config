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
#      kitty, media hidden/shown with a fake MPRIS player, net sampling and failures;
#   7. toasts (through tests/rig/toasts.qml, on a private bus with no service
#      activation): one toast and its 5 s expiry, three at once with the rest queued, the
#      sender's own timeout, a critical toast that stays until a real pointer click,
#      long and empty texts, nothing left at idle;
#   8. launcher (through tests/rig/launcher.qml, XDG_DATA_DIRS with fake .desktop files
#      only): open/close, filter, selection keys, Enter runs the entry (a marker file),
#      Escape, clicks, zero matches, rapid toggles, focused screen, keyboard focus back
#      to the previous window;
#   9. wallpaper carousel (through tests/rig/carousel.qml): listing, live palette and
#      wallpaper preview, Escape writes nothing, Enter applies and persists, rapid input
#      keeps one derive running, empty/single/broken folders, keyboard focus.
#  10. Bluetooth and Claude limits widgets (through tests/rig/widgets-test.qml): real
#      devices counted read-only, fake device models, every claude-limits.json state, live
#      edits, the real status line writer, the 30 s timer, all five rail sections fit.
#  11. NVIDIA GPU source (through tests/rig/nvidia-test.qml, a FAKE nvidia-smi): parser
#      fixtures, stream values and the VRM row, [N/A], timeout, immediate exit, back-off
#      restarts, runtime_status not active, missing command, the probe path on a fake drm
#      tree, opt-in off by default and the rig guard, no fake left after qs stops.
#  12. Clock service and untrusted text (through tests/rig/clock-text.qml, TZ=Europe/Lisbon):
#      bar and rail clocks follow a mocked time across the repeated DST hour (01:59 WEST ->
#      01:00 WET) and a big jump within one 2 s tick, the log stays quiet; a window title,
#      MPRIS title/artist and a Bluetooth name holding <b>, <br> and <img src=http://...>
#      render as literal plain text and no HTTP request reaches a local listener.
# Every qs this script starts runs on a private session bus (qs-run.sh starts its own
# when none is given), so the shell's NotificationServer never meets the live mako.
# Needs no running rig (starts and stops its own). Screenshots land in
# ~/.cache/rice-testbin/shots/qs-*.png. Exit 0 = all checks passed.
set -euo pipefail
# The NVIDIA stream is opt-in (RICE_NVIDIA=1). rig_env.sh drops an inherited RICE_NVIDIA
# and passes on only RIG_NVIDIA; only section 11 sets that, with a FAKE nvidia-smi first
# on PATH.
unset RICE_NVIDIA RIG_NVIDIA
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
sup_bus_pid=""
holder_pid=""
lst_pid=""
cleanup() {
    [[ -z "$lst_pid" ]] || kill -TERM "$lst_pid" 2>/dev/null || true
    [[ -z "$holder_pid" ]] || kill -TERM "$holder_pid" 2>/dev/null || true
    [[ -z "$sup_pid" ]] || kill -TERM "$sup_pid" 2>/dev/null || true
    [[ -z "$kitty_pid" ]] || kill -TERM "$kitty_pid" 2>/dev/null || true
    [[ -z "$fake_pid" ]] || kill -TERM "$fake_pid" 2>/dev/null || true
    "$R/qs-run.sh" stop >/dev/null 2>&1 || true
    "$R/nested-hypr.sh" stop >/dev/null 2>&1 || true
    [[ -z "$bus_pid" ]] || kill -TERM "$bus_pid" 2>/dev/null || true
    [[ -z "$sup_bus_pid" ]] || kill -TERM "$sup_bus_pid" 2>/dev/null || true
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
    .config/quickshell/rail/SectionLabel.qml .config/quickshell/notifications/Toasts.qml \
    .config/quickshell/launcher/Launcher.qml \
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
# The shell's NotificationServer: on qs-run.sh's own private bus, never the live one.
qs_bus=$(tr '\0' '\n' <"/proc/$qs_pid/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
owner=$(DBUS_SESSION_BUS_ADDRESS="$qs_bus" busctl --user --no-pager --no-legend list --acquired 2>/dev/null \
    | awk '$1 == "org.freedesktop.Notifications" {print $2}')
[[ -n "$qs_bus" && "$qs_bus" != *"path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"* && "$owner" == "$qs_pid" ]] \
    && pass "shell.qml owns org.freedesktop.Notifications on a private bus only ($qs_bus)" \
    || fail "notification server bus: '$qs_bus', owner '$owner'"
idle=$("$R/run.sh" hyprctl layers | grep -c -e 'namespace: rice-toasts' -e 'namespace: rice-launcher' || true)
[[ "$idle" == 0 ]] && pass "idle: no toast or launcher surface exists" || fail "idle surfaces: $idle"
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
# Start the staged supervisor with the same environment qs-run.sh uses, on a private
# bus (the production shell runs a NotificationServer).
{ read -r sup_bus; read -r sup_bus_pid; } < <(dbus-daemon --config-file="$R/private-bus.conf" --fork --nopidfile --print-address=1 --print-pid=1)
(
    # shellcheck source=tests/rig/rig_env.sh
    source "$R/rig_env.sh"
    export RICE_NO_RELOAD=1 HOME="$staged" XDG_CONFIG_HOME="$staged/.config" \
        XDG_DATA_HOME="$staged/.local/share" XDG_STATE_HOME="$staged/.local/state" \
        XDG_CACHE_HOME="$staged/.cache" PATH="$staged/.local/bin:$PATH" DBUS_SESSION_BUS_ADDRESS="$sup_bus"
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
kill -TERM "$sup_bus_pid" 2>/dev/null || true
sup_bus_pid=""

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
{ read -r bus_addr; read -r bus_pid; } < <(dbus-daemon --config-file="$R/private-bus.conf" --fork --nopidfile --print-address=1 --print-pid=1)
[[ -n "$bus_addr" && "$bus_pid" =~ ^[0-9]+$ ]] || fail "private dbus-daemon"
# rice.wallpaper info lines ("loading <url> on <screen>") are off in production; on
# here so the checks can see which images were ever loaded.
start6() { DBUS_SESSION_BUS_ADDRESS="$bus_addr" QT_LOGGING_RULES='rice.wallpaper.info=true' "$R/qs-run.sh" start "$@"; }
staged=$(start6 --restage --entry "$R/rail.qml")
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

# k. Carousel preview: shown on both screens without writing the state file; a bad
#    preview falls back with exactly one warning and clearPreview recovers; a state-file
#    change during a preview waits until clearPreview.
mkpng() {
    python3 -I - "$1" "$2" "$3" <<'PY'
import struct, sys, zlib
f, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
row = b"\x00" + (b"\xff\x2e\x88" * 16 + b"\x07\x07\x0d" * 16) * (w // 32) + b"\x07\x07\x0d" * (w % 32)
c = zlib.compressobj(1)
data = b"".join(c.compress(row) for _ in range(h)) + c.flush()
ck = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
open(f, "wb").write(b"\x89PNG\r\n\x1a\n" + ck(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                    + ck(b"IDAT", data) + ck(b"IEND", b""))
PY
}
mkpng "$pics/fhd.png" 1920 1080
mkpng "$pics/hd.png" 1280 720
# True once both screens show <file> decoded (status Ready).
both_show() {
    local _
    for _ in $(seq 40); do
        sleep 0.25
        [[ "$(rj "all(i['status'] == 1 and i['source'].endswith('/$1') for i in d['wallpaper']['images'].values())")" == True ]] \
            && return 0
    done
    return 1
}
both_show wall0.png || fail "wall0 not shown before the preview checks"
# Gate: while the state is not ready (the startup window before the state file is
# read), a path change loads nothing; it loads as soon as the state is ready.
"$R/qs-run.sh" ipc call rail setReady false
"$R/qs-run.sh" ipc call rail preview "$pics/hd.png"
sleep 1.5
gated=$(rj "[i['source'].split('/')[-1] for i in d['wallpaper']['images'].values()]")
"$R/qs-run.sh" ipc call rail setReady true
[[ "$gated" == "['wall0.png', 'wall0.png']" ]] && both_show hd.png \
    && pass "nothing loads before the state is ready (still $gated), then both screens load" \
    || { fail "ready gate (while not ready: $gated)"; rget; }
"$R/qs-run.sh" ipc call rail clearPreview
both_show wall0.png || fail "wall0 not back after the gate check"
sum0=$(sha256sum "$state")
"$R/qs-run.sh" ipc call rail preview "$pics/fhd.png"
both_show fhd.png && [[ "$(rj "d['wallpaper']['path']")" == "$pics/fhd.png" \
    && "$(rj "d['wallpaper']['filePath']")" == "$pics/wall0.png" && "$(sha256sum "$state")" == "$sum0" ]] \
    && pass "preview(fhd.png): both screens show it, state file unchanged" || { fail "preview"; rget; }
"$R/qs-run.sh" ipc call rail clearPreview
both_show wall0.png && [[ "$(rj "d['wallpaper']['path']")" == "$pics/wall0.png" ]] \
    && pass "clearPreview: both screens back on the state file's image" || { fail "clearPreview"; rget; }
n0=$(logn)
"$R/qs-run.sh" ipc call rail preview "$pics/notes.txt"
sleep 2
w=$(rget)
echo "$w" | spy "'ok' if d['wallpaper']['verdictPath'] == '$pics/notes.txt' and d['wallpaper']['verdict'] == -1 and d['wallpaper']['images']['DP-1']['status'] == 3 and d['wallpaper']['images']['eDP-1']['source'] == '' else d" | grep -qx ok \
    && [[ "$(warns_since "$n0" | grep -c .)" == 1 ]] \
    && pass "preview of a text file: background colour, exactly one warning" || { fail "bad preview"; echo "  $w"; warns_since "$n0"; }
"$R/qs-run.sh" ipc call rail clearPreview
both_show wall0.png && pass "clearPreview after a bad preview: both screens recover" || { fail "recover after bad preview"; rget; }
"$R/qs-run.sh" ipc call rail preview "$pics/fhd.png"
both_show fhd.png || fail "second preview not shown"
put_state "{\"path\": \"$pics/hd.png\"}"
sleep 2
[[ "$(rj "d['wallpaper']['filePath']")" == "$pics/hd.png" && "$(rj "d['wallpaper']['path']")" == "$pics/fhd.png" ]] && both_show fhd.png \
    && pass "state-file change during a preview: recorded, the preview stays on screen" || { fail "state change during preview"; rget; }
"$R/qs-run.sh" ipc call rail clearPreview
both_show hd.png && pass "clearPreview: the new state-file image (hd.png) appears on both screens" || { fail "state after clearPreview"; rget; }
put_state "{\"path\": \"$pics/wall0.png\"}"
both_show wall0.png || fail "wall0 not restored after the preview checks"

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
last_a=$(rj "d['net']['last']")
sleep 4.2
n_b=$(rj "d['net']['n']")
last_b=$(rj "d['net']['last']")
# The history saturates at 24 samples; then a new sample shows as a changed last value.
{ [[ "$n_b" -gt "$n_a" ]] || [[ "$n_a" == 24 && "$n_b" == 24 && "$last_b" != "$last_a" ]]; } \
    && [[ "$n_b" -le 24 && "$(rj "d['spark']['n']")" == "$n_b" ]] \
    && pass "netHistory grows ($n_a -> $n_b samples, last $last_a -> $last_b), the sparkline draws all of them" \
    || fail "net history $n_a -> $n_b (last $last_a -> $last_b)"
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

# m. Startup with a state file already present: the default image is never touched.
#    Positive control first: with the default present and no state file, the default is
#    loaded (so the "loading" line and the .jpg-named PNG both work).
loads() { "$R/qs-run.sh" log | grep -c "rice.wallpaper: loading .*/Pictures/$1 on" || true; }
"$R/qs-run.sh" stop >/dev/null
rm -f "$pics/berserk-wallpaper.jpg"
put_state "{\"path\": \"$pics/wall0.png\"}"
start6 --entry "$R/rail.qml" >/dev/null
both_show wall0.png && sleep 1 && [[ "$("$R/qs-run.sh" log | grep -c 'QML Image')" == 0 && "$(loads berserk-wallpaper.jpg)" == 0 ]] \
    && pass "start with a valid state file, default missing: no QML Image warning, default never loaded" \
    || { fail "startup race (default missing)"; "$R/qs-run.sh" log | grep -e 'QML Image' -e 'rice.wallpaper' || true; }
"$R/qs-run.sh" stop >/dev/null
cp "$pics/fhd.png" "$pics/berserk-wallpaper.jpg"
rm -f "$state"
start6 --entry "$R/rail.qml" >/dev/null
both_show berserk-wallpaper.jpg && [[ "$(loads berserk-wallpaper.jpg)" -ge 1 ]] \
    && pass "positive control: no state file, default present: the default is loaded ($(loads berserk-wallpaper.jpg) load lines)" \
    || { fail "default positive control"; "$R/qs-run.sh" log | grep 'rice.wallpaper' || true; }
"$R/qs-run.sh" stop >/dev/null
put_state "{\"path\": \"$pics/wall0.png\"}"
start6 --entry "$R/rail.qml" >/dev/null
both_show wall0.png && sleep 1 && [[ "$(loads berserk-wallpaper.jpg)" == 0 && "$(loads wall0.png)" -ge 1 ]] \
    && pass "start with a valid state file, default present: the default is never decoded (0 load lines)" \
    || { fail "startup race (default present)"; "$R/qs-run.sh" log | grep 'rice.wallpaper' || true; }
"$R/qs-run.sh" stop >/dev/null
kill -TERM "$bus_pid" 2>/dev/null || true
bus_pid=""

# --- 7. toasts --------------------------------------------------------------------------
# A fresh rig; qs-run.sh starts qs on its own private bus (no service activation). The
# notifications below go only to that bus; the live session bus is never addressed.
"$R/nested-hypr.sh" stop >/dev/null
"$R/nested-hypr.sh" start "$R/full.lua" >/dev/null
"$R/qs-run.sh" start --entry "$R/toasts.qml" >/dev/null
tbus=$("$R/qs-run.sh" status | sed -n 's/.* bus=\([^ ]*\).*/\1/p')
case "$tbus" in
    "" | *"path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"*) echo "REFUSING: toast tests need a private bus, got '$tbus'"; exit 1 ;;
esac
notify() { # app summary body urgency timeout-ms
    DBUS_SESSION_BUS_ADDRESS="$tbus" busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
        org.freedesktop.Notifications Notify -- 'susssasa{sv}i' "$1" 0 "" "$2" "$3" 0 1 urgency y "$4" "$5" >/dev/null
}
tj() { "$R/qs-run.sh" ipc call toasts get | spy "$1"; }
now() { date +%s.%N; }
# Seconds until the toast window is gone (polled every 0.1 s, up to $1 s), or "never".
gone_after() {
    local t0 _
    t0=$(now)
    for _ in $(seq "$(($1 * 10))"); do
        [[ "$(tj "d['window'] is None")" == True ]] && { echo "$(now) - $t0" | bc; return 0; }
        sleep 0.1
    done
    echo never
}
n0=$(logn)

# a. One toast: bottom right of the tiling area on the main screen, left of the rail
#    (right margin = rail 432 + 1.4em = 449, bottom 0.9em = 11), a countdown bar that
#    moves, gone after the 5 s default.
notify quickshell "shell reloaded in 0.4s" "" 1 -1
t_sent=$(now)
sleep 0.5
geo=$(layer_xywh rice-toasts)
read -r tmon tx ty tw th <<<"${geo:-x 0 0 0 0}"
r1=$(tj "d['shown'][0]['remaining']")
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-toast-DP-1.png" >/dev/null
sleep 1
r2=$(tj "d['shown'][0]['remaining']")
[[ "$(tj "[t['summary'] for t in d['shown']]")" == "['shell reloaded in 0.4s']" && "$(tj "d['shown'][0]['timeout']")" == 5000 \
    && "$tmon" == DP-1 && $((tx + tw)) == 1471 && $((ty + th)) == 1069 && "$tw" == 228 ]] \
    && python3 -I -c "import sys; a, b = float(sys.argv[1]), float(sys.argv[2]); sys.exit(0 if 1 > a > b > 0 else 1)" "$r1" "$r2" \
    && pass "one toast on DP-1 at $tx,$ty ${tw}x$th (right edge 1471 = rail + 1.4em, bottom 1069), bar $r1 -> $r2" \
    || fail "one toast: layer '$geo', remaining $r1 -> $r2, $(tj d)"
dt=$(gone_after 8)
total=$(echo "$(now) - $t_sent" | bc)
[[ "$dt" != never ]] && python3 -I -c "import sys; sys.exit(0 if 4.5 <= float(sys.argv[1]) <= 6.5 else 1)" "$total" \
    && [[ -z "$(layer_xywh rice-toasts)" ]] \
    && pass "the toast expired $(printf '%.1f' "$total") s after it was sent (default 5 s); no toast surface left" \
    || fail "toast expiry: gone after '$dt' (total $total s)"

# b. Five at once: three shown, two queued; the queued ones appear as slots free.
for i in 1 2 3 4 5; do notify "app$i" "n$i" "" 1 -1; done
sleep 0.5
s1=$(tj "[t['summary'] for t in d['shown']]")
q1=$(tj "len(d['tracked'])")
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-toasts-three-DP-1.png" >/dev/null
s2=""
for _ in $(seq 70); do
    sleep 0.1
    s2=$(tj "[t['summary'] for t in d['shown']]")
    [[ "$s2" == "['n4', 'n5']" ]] && break
done
[[ "$s1" == "['n1', 'n2', 'n3']" && "$q1" == 5 && "$s2" == "['n4', 'n5']" ]] \
    && pass "five quick notifications: $s1 shown, $q1 tracked; then $s2 as slots free" \
    || fail "queue: first $s1 ($q1 tracked), then $s2"
[[ "$(gone_after 8)" != never ]] || fail "queued toasts never expired"

# c. The sender's own timeout (expireTimeout, milliseconds) replaces the default.
notify app "two seconds" "" 1 2000
t_sent=$(now)
sleep 0.3
to=$(tj "d['shown'][0]['timeout']")
gone_after 5 >/dev/null
total=$(echo "$(now) - $t_sent" | bc)
[[ "$to" == 2000 ]] && python3 -I -c "import sys; sys.exit(0 if 1.5 <= float(sys.argv[1]) <= 3.2 else 1)" "$total" \
    && pass "expireTimeout 2000 ms: timeout $to, gone after $(printf '%.1f' "$total") s" || fail "own timeout: $to, $total s"

# d. Critical: stays far past its own 1 s timeout; a real pointer click dismisses it.
notify app "stays" "critical one" 2 1000
sleep 6.5
crit=$(tj "[(t['summary'], t['critical'], t['remaining']) for t in d['shown']]")
geo=$(layer_xywh rice-toasts)
read -r tmon tx ty tw th <<<"${geo:-x 0 0 0 0}"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-toast-critical-DP-1.png" >/dev/null
"$R/run.sh" python3 -I "$R/vpointer.py" $((tx + tw / 2)) $((ty + th / 2)) >/dev/null
sleep 0.5
[[ "$crit" == "[('stays', True, 1)]" && "$(tj "d['window'] is None and d['tracked'] == []")" == True ]] \
    && pass "critical toast still shown 6.5 s after a 1 s timeout; a pointer click at $((tx + tw / 2)),$((ty + th / 2)) dismissed it" \
    || fail "critical: $crit, after click $(tj d)"

# e. Empty summary and app name, a very long body; a very long summary and app name:
#    32em wide at most, one summary line, two body lines, elided.
long=$(python3 -I -c "print(' '.join(['lorem ipsum dolor sit amet consectetur'] * 30))")
notify "" "" "$long" 1 30000
notify "a-very-long-application-name-that-goes-on-and-on" "$long" "short body" 1 30000
sleep 0.6
dims=$(tj "[(t['w'], t['h'], t['summary'] == '') for t in d['shown']]")
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-toast-long-DP-1.png" >/dev/null
echo "$dims" | python3 -I -c "
import ast, sys
d = ast.literal_eval(sys.stdin.read())
sys.exit(0 if len(d) == 2 and all(w == 384 and 40 <= h <= 70 for w, h, _ in d) and d[0][2] else 1)" \
    && pass "empty summary + long body, long summary + long app name: 384 px (32em) wide, bounded height $dims" \
    || fail "long/empty texts: $dims"

# f. Markup in the body (bold, an entity, a link) is shown as the literal string: plain
#    text, on one line exactly as wide as the raw string measured as plain text (this
#    also caught the toast width being rounded down, which wrapped the last word).
"$R/qs-run.sh" ipc call toasts dismissAll
sleep 0.3
markup='<b>bold</b> &amp; <a href="x">link</a>'
notify markup "markup" "$markup" 1 30000
sleep 0.6
mbody=$(tj "d['shown'][0]['body']")
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-toast-markup-DP-1.png" >/dev/null
echo "$mbody" | python3 -I -c "
import ast, sys
b = ast.literal_eval(sys.stdin.read())
sys.exit(0 if b and b['text'] == sys.argv[1] and b['plain'] and b['lines'] == 1 and abs(b['width'] - b['literalWidth']) <= 1 else 1)" "$markup" \
    && pass "markup in the body is drawn literally (plain text, $(echo "$mbody" | python3 -I -c "import ast, sys; print(ast.literal_eval(sys.stdin.read())['width'])") px = the raw string's width)" \
    || fail "markup body: $mbody"
"$R/qs-run.sh" ipc call toasts dismissAll
sleep 0.3
[[ "$(tj "d['window'] is None")" == True && -z "$(layer_xywh rice-toasts)" ]] \
    && pass "after the last toast: no toast window or surface" || fail "toasts left: $(tj d)"
[[ -z "$(warns_since "$n0")" ]] && pass "qs log: no ERROR/WARN in section 7" || { fail "qs log section 7"; warns_since "$n0"; }
"$R/qs-run.sh" stop >/dev/null

# --- 8. launcher --------------------------------------------------------------------------
# Only fake desktop entries are visible (XDG_DATA_DIRS = a temp dir; the staged
# XDG_DATA_HOME has no applications dir). Their Exec writes a marker file; no real
# application is ever started. A long-lived virtual keyboard keeps the seat's keyboard
# capability up between keys.sh calls: without any keyboard, each short wtype run makes
# the seat drop and re-add its keyboard, and Qt then ignores the re-created keyboard
# (seen in the rig; a real seat always has its keyboard).
apps="$tmp/apps"
markers="$tmp/markers"
mkdir -p "$apps/applications" "$markers"
mkdesk() { # file name generic keywords marker [extra line]
    printf '[Desktop Entry]\nType=Application\nName=%s\nGenericName=%s\nKeywords=%s\nExec=sh -c "echo %s > %s/%s"\n%s\n' \
        "$2" "$3" "$4" "$5" "$markers" "$5" "${6:-}" >"$apps/applications/$1.desktop"
}
mkdesk rig-alpha "Rig Test Alpha" "Alpha Tool" "alpha;" alpha
mkdesk rig-beta "Rig Test Beta" "Beta Tool" "beta;" beta
mkdesk firefox-fake "Firefox Fake" "Web Browser" "internet;" firefox
mkdesk rig-hidden "Rig Hidden Entry" "Hidden" "" hidden "NoDisplay=true"
for i in 01 02 03 04 05 06 07 08 09 10; do mkdesk "rig-many-$i" "Rig Many $i" "Filler" "" "many$i"; done
# Terminal=true: the launcher must give it a terminal (kitty -e); the marker records
# whether stdin was a tty, then the argument count and arguments. The Exec carries a
# field code like the real entries (nvim: `Exec=nvim %F`): with no file to open it must
# be dropped, not passed on as a literal "%F".
printf '#!/bin/sh\nif test -t 0; then echo tty; else echo notty; fi > %s/term\necho "$# $*" > %s/term-args\n' \
    "$markers" "$markers" >"$tmp/term-fake.sh"
printf '[Desktop Entry]\nType=Application\nName=Term Fake\nTerminal=true\nExec=sh %s %%F\n' \
    "$tmp/term-fake.sh" >"$apps/applications/term-fake.desktop"
"$R/run.sh" wtype -s 900000 >/dev/null 2>&1 &
holder_pid=$!
XDG_DATA_DIRS="$apps" "$R/qs-run.sh" start --entry "$R/launcher.qml" >/dev/null
lbus=$("$R/qs-run.sh" status | sed -n 's/.* bus=\([^ ]*\).*/\1/p')
lj() { "$R/qs-run.sh" ipc call launcherprobe get | spy "$1"; }
K() { "$R/keys.sh" "$@"; sleep 0.3; }
toggle() { "$R/qs-run.sh" ipc call launcher toggle; sleep 0.4; }
aw() { H activewindow -j | spy "d.get('address')"; }
markers_now() { (cd "$markers" && ls) | tr '\n' ' '; }
n0=$(logn)

want='{"fir":["Firefox","Thunar"],"FIR":["Firefox","Thunar"],"f":["Firefox","Fish","LibreOffice","Thunar"],'
want+='"all":["Alacritty","Firefox","Fish","LibreOffice","Thunar","Zed"],"none":[],"inter":["Firefox"],"spaces":["Fish"],'
want+='"tags":["[fi]","[vi]","[x ]","[  ]"]}'
got=$("$R/qs-run.sh" ipc call launcherprobe parse)
[[ "$got" == "$want" ]] && pass "launcher filter (rank, case, keywords, trim) and tags on fixtures" \
    || { fail "launcher fixtures"; echo "  got  $got"; echo "  want $want"; }

# A real kitty on the focused DP-1 holds the keyboard focus before the launcher opens.
# It runs `cat` into a file, so every line typed into it can be checked: a layer surface
# with exclusive keyboard focus does not change Hyprland's active window, so only keys
# that arrive prove where the keyboard focus is.
typed8="$tmp/kitty8-typed"
: >"$typed8"
H dispatch 'hl.dsp.focus({ monitor = "DP-1" })' >/dev/null
"$R/run.sh" env HOME="$staged" XDG_CONFIG_HOME="$staged/.config" XDG_CACHE_HOME="$staged/.cache" \
    XDG_STATE_HOME="$staged/.local/state" XDG_DATA_HOME="$staged/.local/share" \
    DBUS_SESSION_BUS_ADDRESS="$lbus" kitty --config=NONE --title rig-kitty sh -c "cat >>'$typed8'" \
    >"$tmp/kitty8.out" 2>&1 </dev/null &
kitty_pid=$!
typed() { tr '\n' ' ' <"$typed8"; }
for _ in $(seq 30); do sleep 0.3; [[ "$(H activewindow -j | spy "d.get('title')")" == rig-kitty ]] && break; done
aw0=$(aw)

# a. Closed: nothing exists. Open: one full-screen overlay on DP-1, only the fake entries
#    (NoDisplay hidden), 8 rows of 13, the query field focused.
[[ "$(lj "d['open'] or d['window']")" == False && -z "$(layer_xywh rice-launcher)" ]] \
    && pass "launcher closed: no window, no surface" || fail "launcher at start: $(lj d)"
toggle
fakes="['Firefox Fake', 'Rig Many 01', 'Rig Many 02', 'Rig Many 03', 'Rig Many 04', 'Rig Many 05', 'Rig Many 06', 'Rig Many 07', 'Rig Many 08', 'Rig Many 09', 'Rig Many 10', 'Rig Test Alpha', 'Rig Test Beta', 'Term Fake']"
[[ ! -e "$staged/.local/share/applications" && "$(lj "d['allNames']")" == "$fakes" \
    && "$(lj "(d['count'], d['total'], len(d['rows']), d['inputFocus'], d['screen'])")" == "(14, 14, 8, True, 'DP-1')" \
    && "$(layer_xywh rice-launcher)" == "DP-1 0 0 1920 1080" ]] \
    && pass "toggle opens on DP-1 (full-screen overlay); only the 14 fake entries, 8 rows shown, query focused" \
    || fail "launcher open: $(lj d) layer '$(layer_xywh rice-launcher)'"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-launcher-DP-1.png" >/dev/null
[[ "$(lj "d['windowActive']")" == True && "$(aw)" == "$aw0" ]] \
    && pass "while open the launcher window has the keyboard (Window.active); Hyprland's active window is still the kitty" \
    || fail "open: windowActive $(lj "d['windowActive']"), active window $(aw) (kitty $aw0)"

# b. Filtering: by name, by keyword.
K fir
[[ "$(lj "(d['query'], d['rows'], d['count'])")" == "('fir', ['Firefox Fake'], 1)" ]] \
    && pass "typing 'fir' filters to Firefox Fake (1 / 13)" || fail "fir: $(lj d)"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-launcher-fir-DP-1.png" >/dev/null
K -k BackSpace -k BackSpace -k BackSpace
K internet
[[ "$(lj "d['rows']")" == "['Firefox Fake']" ]] && pass "keyword 'internet' finds Firefox Fake" || fail "keyword: $(lj d)"

# c. Selection keys, clamped to the shown rows.
for _ in 1 2 3 4 5 6 7 8; do "$R/keys.sh" -k BackSpace; done
K rig
sel=$(lj "(d['count'], len(d['rows']), d['selected'])")
K -k Down -k Down; s_dd=$(lj "d['selected']")
K -k Up; s_u=$(lj "d['selected']")
K -M ctrl -k n -m ctrl; s_n=$(lj "d['selected']")
K -M ctrl -k p -k p -k p -m ctrl; s_p=$(lj "d['selected']")
for _ in $(seq 12); do "$R/keys.sh" -k Down; done
sleep 0.3
s_end=$(lj "d['selected']")
[[ "$sel" == "(12, 8, 0)" && "$s_dd" == 2 && "$s_u" == 1 && "$s_n" == 2 && "$s_p" == 0 && "$s_end" == 7 ]] \
    && pass "'rig': 12 matches capped at 8 rows; Down Down 2, Up 1, Ctrl+N 2, Ctrl+P x3 0, Down x12 stops at 7" \
    || fail "selection: $sel dd $s_dd u $s_u n $s_n p $s_p end $s_end"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-launcher-sel-DP-1.png" >/dev/null

# d. Escape closes and gives the keyboard back to the kitty; reopening starts clean.
K -k Escape
K aa -k Return
[[ "$(lj "d['open'] or d['window']")" == False && -z "$(layer_xywh rice-launcher)" && "$(typed)" == "aa " ]] \
    && pass "Escape closes; keys typed next reach the kitty ('$(typed)'), none typed while open did" \
    || fail "Escape: $(lj d), kitty got '$(typed)'"
toggle
[[ "$(lj "(d['query'], d['selected'], d['count'])")" == "('', 0, 14)" ]] \
    && pass "reopening clears the query and the selection" || fail "reopen: $(lj d)"

# e. Enter runs the selected entry (its Exec writes a marker) and closes.
K fir
w_active=$(lj "d['windowActive']")
K -k Return
sleep 0.7
K bb -k Return
[[ "$w_active" == True && "$(lj "d['open']")" == False && "$(markers_now)" == "firefox " \
    && "$(cat "$markers/firefox")" == firefox && "$(typed)" == "aa bb " ]] \
    && pass "Enter on Firefox Fake ran its Exec (marker 'firefox') and closed; the next keys reach the kitty" \
    || fail "Enter: active $w_active, open $(lj "d['open']"), markers '$(markers_now)', kitty got '$(typed)'"

# f. Zero matches: empty list; Enter does nothing.
toggle
K zzzq
z1=$(lj "(d['rows'], d['count'])")
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-launcher-zero-DP-1.png" >/dev/null
K -k Return
[[ "$z1" == "([], 0)" && "$(lj "d['open']")" == True && "$(markers_now)" == "firefox " ]] \
    && pass "zero matches: empty list; Enter runs nothing and keeps it open" || fail "zero matches: $z1, open $(lj "d['open']"), markers '$(markers_now)'"

# g. Real pointer clicks: inside the card keeps it open, outside closes.
"$R/run.sh" python3 -I "$R/vpointer.py" 900 230 >/dev/null
sleep 0.4
in_open=$(lj "d['open']")
"$R/run.sh" python3 -I "$R/vpointer.py" 300 800 >/dev/null
sleep 0.4
K cc -k Return
[[ "$in_open" == True && "$(lj "d['open']")" == False && "$(typed)" == "aa bb cc " ]] \
    && pass "click inside the card keeps it open; click outside closes it and the kitty gets the keys again" \
    || fail "clicks: inside $in_open, after outside $(lj "d['open']"), kitty got '$(typed)'"

# h. Three toggles at once end open, with exactly one window.
"$R/qs-run.sh" ipc call launcher toggle &
t1=$!
"$R/qs-run.sh" ipc call launcher toggle &
t2=$!
"$R/qs-run.sh" ipc call launcher toggle &
t3=$!
wait "$t1" "$t2" "$t3" || true
sleep 0.5
[[ "$(lj "d['open']")" == True && "$("$R/qs-run.sh" ipc call launcherprobe windows)" == 1 \
    && "$(H layers | grep -c 'namespace: rice-launcher')" == 1 ]] \
    && pass "three quick toggles: open, one window, one surface" || fail "rapid toggles: $(lj d), $(H layers | grep -c 'namespace: rice-launcher') surfaces"
K -k Escape

# i. The focused screen decides where it opens.
H dispatch 'hl.dsp.focus({ monitor = "eDP-1" })' >/dev/null
sleep 0.3
toggle
[[ "$(lj "d['screen']")" == eDP-1 && "$(layer_xywh rice-launcher)" == "eDP-1 1920 0 1920 1080" ]] \
    && pass "with eDP-1 focused it opens on eDP-1" || fail "focused screen: $(lj "d['screen']"), layer '$(layer_xywh rice-launcher)'"
"$R/qs-run.sh" shot eDP-1 "$SHOTS/qs-launcher-eDP-1.png" >/dev/null
K -k Escape

# j. A Terminal=true entry runs inside a new kitty (Quickshell's execute() ignores
#    Terminal=): its command sees a tty, and the kitty closes when the command ends.
nk0=$(H clients -j | spy "len([c for c in d if c['class'] == 'kitty'])")
toggle
K term -k Return
for _ in $(seq 50); do [[ -s "$markers/term" ]] && break; sleep 0.2; done
sleep 1
nk1=$(H clients -j | spy "len([c for c in d if c['class'] == 'kitty'])")
[[ "$(cat "$markers/term" 2>/dev/null)" == tty && "$(lj "d['open']")" == False && "$nk1" == "$nk0" ]] \
    && pass "Terminal=true entry ran in a kitty with a tty (marker 'tty'); that kitty closed again" \
    || fail "terminal entry: marker '$(cat "$markers/term" 2>/dev/null)', open $(lj "d['open']"), kitty windows $nk0 -> $nk1"
[[ -s "$markers/term-args" && "$(cat "$markers/term-args")" == "0 " ]] \
    && pass "the %F field code was dropped: the command got no arguments ('$(cat "$markers/term-args")')" \
    || fail "field code: the command got '$(cat "$markers/term-args" 2>/dev/null)' (want '0 ')"
H dispatch 'hl.dsp.focus({ monitor = "DP-1" })' >/dev/null
[[ -z "$(warns_since "$n0")" ]] && pass "qs log: no ERROR/WARN in section 8" || { fail "qs log section 8"; warns_since "$n0"; }
kill -TERM "$kitty_pid" 2>/dev/null || true
wait "$kitty_pid" 2>/dev/null || true
kitty_pid=""
kill -TERM "$holder_pid" 2>/dev/null || true
wait "$holder_pid" 2>/dev/null || true
holder_pid=""
"$R/qs-run.sh" stop >/dev/null

# --- 9. wallpaper carousel (U11) -----------------------------------------------------------
# Through tests/rig/carousel.qml (wallpaper, bars, rail and the production Carousel) on a
# re-created staged HOME and qs-run.sh's own private bus. The folder holds three generated
# gradients (one named Tide.PNG, so the filter and the name sort must ignore case), a copy
# of wall0.png, a text file and a 0-byte broken.png; moss.png is applied
# first, so it is the current wallpaper. The private matugen comes from the rig PATH
# (rig_env.sh), RICE_NO_RELOAD=1 from qs-run.sh. Expected palettes are computed by running
# `rice-palette derive` independently in the same staged environment.
staged=$("$R/qs-run.sh" start --restage --entry "$R/carousel.qml")
"$R/qs-run.sh" stop >/dev/null
wp="$staged/Pictures/wallpapers"
mkdir -p "$wp" "$tmp/c9"
mkgrad() { # file w h r,g,b r,g,b : vertical gradient with a bright disc
    python3 -I - "$@" <<'PY'
import struct, sys, zlib
f, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
a = [int(x) for x in sys.argv[4].split(",")]
b = [int(x) for x in sys.argv[5].split(",")]
cx, cy, rr = w * 0.62, h * 0.42, (h * 0.18) ** 2
hi = bytes(min(255, b[i] + 120) for i in range(3))
rows = []
for y in range(h):
    t = y / (h - 1)
    row = bytearray(bytes(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) * w)
    dy = (y - cy) ** 2
    if dy < rr:
        half = int((rr - dy) ** 0.5)
        x0, x1 = max(0, int(cx - half)), min(w, int(cx + half))
        row[x0 * 3:x1 * 3] = hi * (x1 - x0)
    rows.append(b"\x00" + bytes(row))
ck = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
open(f, "wb").write(b"\x89PNG\r\n\x1a\n" + ck(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                    + ck(b"IDAT", zlib.compress(b"".join(rows), 6)) + ck(b"IEND", b""))
PY
}
mkgrad "$wp/ember.png" 640 360 20,2,4 200,40,30
mkgrad "$wp/moss.png" 640 360 2,18,6 30,170,60
mkgrad "$wp/Tide.PNG" 640 360 2,4,24 30,70,210
cp /usr/share/hypr/wall0.png "$wp/"
echo "not a wallpaper" >"$wp/notes.txt"
: >"$wp/broken.png"
senv() { "$R/run.sh" env HOME="$staged" XDG_CONFIG_HOME="$staged/.config" XDG_CACHE_HOME="$staged/.cache" \
    XDG_STATE_HOME="$staged/.local/state" XDG_DATA_HOME="$staged/.local/share" RICE_NO_RELOAD=1 "$@"; }
derive_a1() { senv "$staged/.local/bin/rice-palette" derive "$wp/$1" | spy "d['a1']"; }
senv "$staged/.local/bin/rice-palette" apply "$wp/moss.png" || fail "seed apply moss.png"
a1_moss=$(derive_a1 moss.png); a1_tide=$(derive_a1 Tide.PNG); a1_ember=$(derive_a1 ember.png)
a1_wall0=$(derive_a1 wall0.png)
[[ -n "$a1_moss" && "$a1_moss" != "$a1_tide" && "$a1_tide" != "$a1_ember" && "$a1_wall0" != "$a1_tide" ]] \
    || fail "test images do not give distinct palettes: $a1_moss $a1_tide $a1_ember $a1_wall0"
rm -f "$staged"/.cache/rice/*.json   # every derivation below starts cold
outs=(.config/quickshell/colors.json .config/kitty/colors.conf .config/hypr/colors.lua
      .config/btop/themes/rice.theme .local/state/quickshell/wallpaper.json)
outsums() { (cd "$staged" && sha1sum "${outs[@]}"); }
# Every file in the staged HOME except caches: rice-palette's own derive cache (.cache/rice)
# and Python's bytecode cache (__pycache__, recompiled after re-staging touched the .py files).
tree_sums() { (cd "$staged" && find . -path ./.cache -prune -o -path ./.chezmoi-cache -prune -o -name __pycache__ -prune \
    -o -type f -print0 | sort -z | xargs -0 sha1sum); }

"$R/run.sh" wtype -s 900000 >/dev/null 2>&1 &
holder_pid=$!
# The real session's PATH has no ~/.local/bin (greetd -> start-hyprland, no login shell):
# the carousel must find rice-palette by its absolute path. QS_RUN_BARE_PATH=1 strips the
# staged and the real ~/.local/bin; every derive and apply below runs that way. The fake
# desktop entries of section 8 serve the launcher in carousel.qml (never real apps).
cstart() { QS_RUN_BARE_PATH=1 XDG_DATA_DIRS="$apps" "$R/qs-run.sh" start --entry "$R/carousel.qml" >/dev/null; }
cstart
sleep 1
qpid=$("$R/qs-run.sh" status | sed -n 's/.* pid=\([0-9]*\) .*/\1/p')
qpath=$(tr '\0' '\n' <"/proc/$qpid/environ" | sed -n 's/^PATH=//p')
[[ -n "$qpath" && "$qpath" != *"/.local/bin"* ]] && ! PATH="$qpath" command -v rice-palette >/dev/null \
    && pass "carousel qs runs with no ~/.local/bin on PATH (rice-palette not resolvable by name)" \
    || fail "carousel PATH still finds rice-palette: $qpath"
cbus=$("$R/qs-run.sh" status | sed -n 's/.* bus=\([^ ]*\).*/\1/p')
cj() { "$R/qs-run.sh" ipc call carouselprobe get | spy "$1"; }
K() { "$R/keys.sh" "$@"; sleep 0.3; }
ctoggle() { "$R/qs-run.sh" ipc call carousel toggle; sleep 0.5; }
# Wait (up to 30 s) until no derivation runs or is queued.
settled() { local i; for ((i = 0; i < 150; i++)); do
    [[ "$(cj "d['deriving'] or d['pending'] != '' or d['applying'] or d['settling'] or bool(d['open'] and d.get('files') and d.get('result') is None)")" == False ]] && return 0
    sleep 0.2; done; return 1; }
n0=$(logn)

want='{"dims":["1920×1080","3840×2160","640×480",""],"oneLine":["not an image: /x/broken.png","","matugen failed: boom"],'
want+='"ok":{"ok":true,"tokens":{"bg":"#07070d","panel":"#0c0d16","line":"#1b1d30","dim":"#6a7399","fg":"#d7e3f0","a1":"#00f0ff","a2":"#ff2e88","warn":"#ffd23f"},"dims":"8×4"},'
want+='"fail":{"ok":false,"error":"not an image: /x/b.png"},"garbage":{"ok":false,"error":"unusable rice-palette output"},'
want+='"partial":{"ok":false,"error":"rice-palette gave no panel,line,dim,fg,a1,a2,warn"}}'
got=$("$R/qs-run.sh" ipc call carouselprobe parse)
[[ "$got" == "$want" ]] && pass "carousel helpers (file size, error line, derive output parser) on fixtures" \
    || { fail "carousel fixtures"; echo "  got  $got"; echo "  want $want"; }

# A kitty on the focused DP-1 whose shell records what is typed into it: proof of where
# the keyboard focus is.
H dispatch 'hl.dsp.focus({ monitor = "DP-1" })' >/dev/null
typed="$tmp/c9/typed"
: >"$typed"
"$R/run.sh" env HOME="$staged" XDG_CONFIG_HOME="$staged/.config" XDG_CACHE_HOME="$staged/.cache" \
    XDG_STATE_HOME="$staged/.local/state" XDG_DATA_HOME="$staged/.local/share" \
    DBUS_SESSION_BUS_ADDRESS="$cbus" kitty --config=NONE --title rig-kitty9 sh -c "cat >>'$typed'" \
    >"$tmp/kitty9.out" 2>&1 </dev/null &
kitty_pid=$!
for _ in $(seq 30); do sleep 0.3; [[ "$(H activewindow -j | spy "d.get('title')")" == rig-kitty9 ]] && break; done
aw0=$(aw)
K a -k Return
[[ "$(cat "$typed")" == a ]] && pass "kitty probe has the keyboard before the carousel opens" || fail "kitty probe: '$(cat "$typed")'"

# a. Closed: nothing. Open: a bottom strip on DP-1, keyboard focus, the image files only
#    (notes.txt not listed, broken.png listed), the current wallpaper (moss) selected.
[[ "$(cj "d['open'] or d['window']")" == False && -z "$(layer_xywh rice-carousel)" ]] \
    && pass "carousel closed: no window, no surface" || fail "carousel at start: $(cj d)"
tree0=$(tree_sums)
ctoggle
settled || fail "open: derivation did not finish"
[[ "$(cj "(d['files'], d['selName'], d['screen'], d['focus'])")" \
    == "(['broken.png', 'ember.png', 'moss.png', 'Tide.PNG', 'wall0.png'], 'moss.png', 'DP-1', True)" ]] \
    && pass "open on DP-1: 5 images (notes.txt not listed, broken.png listed), current moss.png selected, keyboard focus" \
    || fail "open: $(cj "(d['files'], d['selName'], d['screen'], d['focus'])")"
geo=$(layer_xywh rice-carousel)
[[ "$geo" =~ ^DP-1\ 0\ ([0-9]+)\ 1920\ ([0-9]+)$ && $((BASH_REMATCH[1] + BASH_REMATCH[2])) == 1080 && ${BASH_REMATCH[2]} -gt 200 ]] \
    && pass "one bottom-anchored full-width overlay surface ($geo)" || fail "carousel surface '$geo'"
[[ "$(cj "d['texts'][:3]")" == "['WALLPAPER // ', 'moss.png', '640×360 · png · ←/→ select · ⏎ apply · esc cancel']" ]] \
    && pass "header: WALLPAPER // moss.png, real size 640×360 and type" || fail "header: $(cj "d['texts']")"
[[ "$(cj "[t['name'] for t in d['thumbs']]")" == "['broken.png', 'ember.png', 'moss.png', 'Tide.PNG', 'wall0.png']" \
    && "$(cj "[t['on'] for t in d['thumbs']]")" == "[False, False, True, False, False]" \
    && "$(cj "d['thumbs'][2]['w'] > 1.7 * d['thumbs'][0]['w'] and d['thumbs'][0]['opacity'] < 1 and d['thumbs'][2]['opacity'] == 1")" == True ]] \
    && pass "five thumbnails, the selected one centred, larger and opaque, neighbours dimmed" || fail "thumbs: $(cj "d['thumbs']")"
[[ "$(cj "(d['previewing'], d['theme']['a1'], 'PALETTE' in d['texts'], '03' in d['texts'])")" == "(True, '$a1_moss', True, True)" ]] \
    && pass "moss palette previewed, swatches and index tag 03 shown" || fail "open palette: $(cj "(d['previewing'], d['theme'], d['texts'])")"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-carousel-DP-1.png" >/dev/null

# b. Right: the whole shell takes tide's palette and both screens show Tide.PNG.
K -k Right
settled || fail "Right: derivation did not finish"
[[ "$(cj "(d['selName'], d['theme']['a1'], d['wallPreview'].endswith('/Tide.PNG'), [w['shown'].endswith('/Tide.PNG') and w['ready'] for w in d['walls']])")" \
    == "('Tide.PNG', '$a1_tide', True, [True, True])" ]] \
    && pass "Right: Tide.PNG previewed (Theme a1 $a1_moss -> $a1_tide), both screens show it" \
    || fail "Right: $(cj "(d['selName'], d['theme']['a1'], d['wallPreview'], d['walls'])")"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-carousel-tide-DP-1.png" >/dev/null
"$R/qs-run.sh" shot eDP-1 "$SHOTS/qs-carousel-tide-eDP-1.png" >/dev/null   # the previewed wallpaper

# c. Right twice (wrapping): broken.png fails; the previous preview (wall0) stays; Enter
#    does nothing.
K -k Right
settled || fail "wall0: derivation did not finish"
K -k Right
settled || fail "broken: derivation did not finish"
[[ "$(cj "(d['selName'], d['sel'], d['theme']['a1'], d['wallPreview'].endswith('/wall0.png'), d['texts'][-1])")" \
    == "('broken.png', 0, '$a1_wall0', True, '✗ not an image: broken.png')" ]] \
    && pass "wrap to broken.png: '✗ not an image: broken.png', wall0 preview kept" \
    || fail "broken: $(cj "(d['selName'], d['sel'], d['theme']['a1'], d['wallPreview'], d['texts'])")"
K -k Return
sleep 0.5
[[ "$(cj "(d['open'], d['applying'])")" == "(True, False)" ]] && pass "Enter on broken.png does nothing" \
    || fail "Enter on broken: $(cj "(d['open'], d['applying'])")"

# d. Escape: preview gone, original colours and wallpaper, nothing written, focus back.
K -k Escape
[[ "$(cj "(d['open'], d['previewing'], d['wallPreview'], d['theme']['a1'], [w['shown'].endswith('/moss.png') for w in d['walls']])")" \
    == "(False, False, '', '$a1_moss', [True, True])" && -z "$(layer_xywh rice-carousel)" ]] \
    && pass "Escape: closed, moss colours and wallpaper back" || fail "Escape: $(cj d)"
[[ "$(tree_sums)" == "$tree0" ]] && pass "Escape wrote nothing (staged HOME identical outside .cache)" \
    || { fail "Escape changed files"; diff <(echo "$tree0") <(tree_sums) || true; }
K b -k Return
[[ "$(H activewindow -j | spy "d.get('address')")" == "$aw0" && "$(tr '\n' ' ' <"$typed")" == "a b " ]] \
    && pass "after Escape the kitty ($aw0) is active and gets the typed keys" || fail "focus after Escape: '$(cat "$typed")'"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-carousel-escape-DP-1.png" >/dev/null

# e. Enter applies (ember): the five files change in the staged HOME, the shell shows the
#    new palette without a restart, the preview is dropped, focus returns. Left and Enter
#    come in one wtype run, so Enter arrives while ember's palette is still being derived
#    (not derived yet in this session): it must wait for the palette and then apply.
sums0=$(outsums)
ctoggle
settled || fail "reopen: derivation did not finish"
nq=$(logn)
t_apply=$(date +%s%N)
K -k Left -k Return
settled || fail "apply did not settle"
t_apply=$(( ($(date +%s%N) - t_apply) / 1000000 ))
queued=$("$R/qs-run.sh" log | tail -n +"$((nq + 1))" | grep -c 'Carousel: Enter waits for the palette of .*/ember\.png$' || true)
[[ "$queued" == 1 ]] && pass "Enter during ember's derivation was queued (one log line), not dropped" \
    || fail "queued Enter: $queued log lines"
# The preview ends when Theme and WallpaperState have re-read the files, not by the 3 s
# fallback timer.
[[ $t_apply -lt 2800 ]] && pass "Left + Enter to a settled shell in $t_apply ms (no 3 s fallback)" \
    || fail "apply took $t_apply ms to settle"
changed=$(diff <(echo "$sums0") <(outsums) | grep -c '^>' || true)
[[ "$changed" == 5 && "$(spy "d['path']" <"$staged/.local/state/quickshell/wallpaper.json")" == "$wp/ember.png" \
    && "$(spy "d['a1']" <"$staged/.config/quickshell/colors.json")" == "$a1_ember" ]] \
    && pass "Enter: colors.json, kitty, hypr, btop and wallpaper.json all rewritten in the staged HOME (ember)" \
    || fail "apply files: $changed changed; $(cat "$staged/.local/state/quickshell/wallpaper.json")"
[[ "$(cj "(d['open'], d['previewing'], d['wallPreview'], d['theme']['a1'], d['wallFile'].endswith('/ember.png'))")" \
    == "(False, False, '', '$a1_ember', True)" ]] \
    && pass "after apply: closed, no preview left, Theme and WallpaperState read ember from the files" \
    || fail "after apply: $(cj d)"
K c -k Return
[[ "$(H activewindow -j | spy "d.get('address')")" == "$aw0" && "$(tr '\n' ' ' <"$typed")" == "a b c " ]] \
    && pass "after Enter the kitty is active again and gets the typed keys" || fail "focus after Enter: '$(cat "$typed")'"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-carousel-applied-DP-1.png" >/dev/null

bad=$(warns_since "$n0" | grep -v -E 'QML Image at @wallpaper/Carousel.qml.*Error decoding: .*/broken\.png: Unsupported image format$' || true)
ndec=$(warns_since "$n0" | grep -c 'Carousel.qml.*Error decoding' || true)
[[ -z "$bad" && "$ndec" == 2 ]] && pass "qs log: only the broken.png decode warning, once per open (2 opens)" \
    || { fail "qs log section 9 before restart ($ndec decode warnings)"; echo "$bad"; }

# f. Restart: the choice persists.
"$R/qs-run.sh" stop >/dev/null
cstart
sleep 2
n0=$(logn)
[[ "$(cj "(d['theme']['a1'], d['wallFile'].endswith('/ember.png'), [w['shown'].endswith('/ember.png') and w['ready'] for w in d['walls']])")" \
    == "('$a1_ember', True, [True, True])" ]] && pass "restart: ember palette and wallpaper persist" \
    || fail "restart: $(cj d)"

# g. Rapid input: 22 Right presses 40 ms apart with a cold derive cache. At most one
#    rice-palette derive (and one matugen) at any sample; the final preview is the final
#    selection (ember + 22 = tide on 5 images).
rm -f "$staged"/.cache/rice/*.json
ctoggle
settled || fail "burst: initial derivation did not finish"
samples="$tmp/c9/samples"
( for _ in $(seq 400); do
      echo "$(pgrep -fc "$staged/.local/bin/rice-palette derive" || true) $(pgrep -xc matugen || true)"
      sleep 0.02
  done ) >"$samples" &
sampler=$!
sleep 0.2
burst=()
for _ in $(seq 22); do burst+=(-k Right); done
"$R/keys.sh" -d 40 "${burst[@]}"
settled || fail "burst did not settle"
kill "$sampler" 2>/dev/null || true
wait "$sampler" 2>/dev/null || true
maxd=$(cut -d' ' -f1 "$samples" | sort -n | tail -1)
maxm=$(cut -d' ' -f2 "$samples" | sort -n | tail -1)
busy=$(awk '$1 > 0' "$samples" | wc -l)
[[ "$maxd" == 1 && "$maxm" -le 1 && "$busy" -gt 0 ]] \
    && pass "22 quick Right presses: at most 1 derive / $maxm matugen running at any of $(wc -l <"$samples") samples ($busy busy)" \
    || fail "burst processes: max derive $maxd, max matugen $maxm, busy samples $busy"
[[ "$(cj "(d['selName'], d['theme']['a1'], d['result']['tokens']['a1'], d['wallPreview'].endswith('/Tide.PNG'), [w['shown'].endswith('/Tide.PNG') for w in d['walls']])")" \
    == "('Tide.PNG', '$a1_tide', '$a1_tide', True, [True, True])" ]] \
    && pass "after the burst: Tide.PNG selected and previewed (palette and wallpaper)" \
    || fail "after burst: $(cj "(d['selName'], d['theme']['a1'], d['result'], d['wallPreview'])")"
K -k Escape

# g2. The focused screen decides where it opens.
H dispatch 'hl.dsp.focus({ monitor = "eDP-1" })' >/dev/null
sleep 0.3
ctoggle
settled || fail "eDP-1: derivation did not finish"
geo=$(layer_xywh rice-carousel)
[[ "$(cj "(d['open'], d['screen'], d['focus'])")" == "(True, 'eDP-1', True)" && "$geo" =~ ^eDP-1\ 1920\  ]] \
    && pass "with eDP-1 focused it opens on eDP-1 ($geo)" || fail "focused screen: $(cj "d['screen']"), layer '$geo'"
"$R/qs-run.sh" shot eDP-1 "$SHOTS/qs-carousel-eDP-1.png" >/dev/null
K -k Escape
[[ "$(cj "d['open']")" == False ]] || fail "eDP-1: Escape did not close"
H dispatch 'hl.dsp.focus({ monitor = "DP-1" })' >/dev/null
sleep 0.3

# h. Empty folder, missing folder, one image, only broken files.
mkdir -p "$staged/Pictures/aside"
mv "$wp"/* "$staged/Pictures/aside/"
ctoggle
[[ "$(cj "(d['files'], d['texts'], d['thumbs'], d['previewing'])")" == "([], ['no wallpapers in ~/Pictures/wallpapers'], [], False)" ]] \
    && pass "empty folder: the single line 'no wallpapers in ~/Pictures/wallpapers'" || fail "empty: $(cj d)"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-carousel-empty-DP-1.png" >/dev/null
sums0=$(outsums)
K -k Right -k Return
[[ "$(cj "d['open']")" == True && "$(outsums)" == "$sums0" ]] && pass "empty folder: Right/Enter do nothing" || fail "empty keys"
K -k Escape
rmdir "$wp"
ctoggle
[[ "$(cj "(d['files'], d['texts'])")" == "([], ['no wallpapers in ~/Pictures/wallpapers'])" ]] \
    && pass "missing folder: the same empty state" || fail "missing folder: $(cj d)"
K -k Escape
mkdir -p "$wp"
cp "$staged/Pictures/aside/moss.png" "$wp/"
ctoggle
settled || fail "single: derivation did not finish"
K -k Right
[[ "$(cj "(d['files'], d['sel'], len(d['thumbs']), d['theme']['a1'], '←/→ select' in d['texts'][2])")" \
    == "(['moss.png'], 0, 1, '$a1_moss', False)" ]] \
    && pass "one image: one thumbnail, no scrolling, its palette previewed" || fail "single: $(cj d)"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-carousel-single-DP-1.png" >/dev/null
K -k Return
settled || fail "single apply did not settle"
[[ "$(cj "d['open']")" == False && "$(spy "d['path']" <"$staged/.local/state/quickshell/wallpaper.json")" == "$wp/moss.png" ]] \
    && pass "one image: Enter applies it" || fail "single apply: $(cat "$staged/.local/state/quickshell/wallpaper.json")"
rm -f "$wp/moss.png"
: >"$wp/broken.png"
echo "not a picture" >"$wp/fake.jpg"
sums0=$(outsums)
ctoggle
settled || fail "broken-only: derivation did not finish"
K -k Right
settled || true
[[ "$(cj "(d['files'], d['selName'], d['previewing'], d['texts'][-1])")" \
    == "(['broken.png', 'fake.jpg'], 'fake.jpg', False, '✗ not an image: fake.jpg')" ]] \
    && pass "only broken files: listed and flagged, no preview" || fail "broken-only: $(cj d)"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-carousel-broken-DP-1.png" >/dev/null
K -k Return
sleep 0.5
[[ "$(cj "d['open']")" == True && "$(outsums)" == "$sums0" ]] && pass "only broken files: Enter applies nothing" \
    || fail "broken-only Enter"
K -k Escape
# Qt's own decode warning, once per broken file shown since the restart (broken.png in the
# burst, eDP-1 and broken-only opens, fake.jpg once), and nothing else.
bad=$(warns_since "$n0" | grep -v -E 'QML Image at @wallpaper/Carousel.qml.*Error decoding: .*/(broken\.png|fake\.jpg): Unsupported image format$' || true)
ndec=$(warns_since "$n0" | grep -c 'Carousel.qml.*Error decoding' || true)
[[ -z "$bad" && "$ndec" == 4 ]] && pass "qs log: only $ndec thumbnail decode warning(s) for the broken files in section 9" \
    || { fail "qs log section 9 ($ndec decode warnings)"; echo "$bad"; }

# i. Escape while an apply runs: a slow rice-palette (a wrapper around the staged CLI that
#    sleeps before `apply`; test only, the production carousel just runs the file). The
#    carousel closes at once, the kitty gets the keys, the apply is not killed: it lands
#    in the background and the shell settles on it.
rm -f "$wp"/*
cp "$staged/Pictures/aside/ember.png" "$staged/Pictures/aside/moss.png" "$staged/Pictures/aside/Tide.PNG" "$wp/"
cli="$staged/.local/bin/rice-palette"
mv -f "$cli" "$cli.real"
printf '%s\n' '#!/bin/sh' \
    "[ \"\$1\" = apply ] && { touch '$tmp/c9/apply-started'; sleep \"\$(cat '$tmp/c9/apply-delay')\"; }" \
    "exec '$cli.real' \"\$@\"" >"$cli"
chmod +x "$cli"
echo 4 >"$tmp/c9/apply-delay"
n0=$(logn)
# A fresh recording kitty: the first one was started on the bus of the qs that f
# restarted (qs-run.sh stopped that bus with it).
kill -TERM "$kitty_pid" 2>/dev/null || true
wait "$kitty_pid" 2>/dev/null || true
cbus=$("$R/qs-run.sh" status | sed -n 's/.* bus=\([^ ]*\).*/\1/p')
H dispatch 'hl.dsp.focus({ monitor = "DP-1" })' >/dev/null
: >"$typed"
"$R/run.sh" env HOME="$staged" XDG_CONFIG_HOME="$staged/.config" XDG_CACHE_HOME="$staged/.cache" \
    XDG_STATE_HOME="$staged/.local/state" XDG_DATA_HOME="$staged/.local/share" \
    DBUS_SESSION_BUS_ADDRESS="$cbus" kitty --config=NONE --title rig-kitty9i sh -c "cat >>'$typed'" \
    >"$tmp/kitty9i.out" 2>&1 </dev/null &
kitty_pid=$!
for _ in $(seq 30); do sleep 0.3; [[ "$(H activewindow -j | spy "d.get('title')")" == rig-kitty9i ]] && break; done
K z -k Return
[[ "$(tr '\n' ' ' <"$typed")" == "z " ]] && pass "before i: the kitty on DP-1 has the keyboard" \
    || fail "before i: kitty got '$(cat "$typed")' (active: $(H activewindow -j | spy "d.get('title')"))"
: >"$typed"
ctoggle
settled || fail "slow apply: derivation did not finish"
K -k Right
settled || fail "slow apply: Right did not settle"
sel_i=$(cj "d['selName']")
rm -f "$tmp/c9/apply-started"
K -k Return
for _ in $(seq 20); do [[ -e "$tmp/c9/apply-started" ]] && break; sleep 0.1; done
K -k Escape
during=$(cj "(d['open'], d['applying'], d['previewing'], d['overlay'])")
K d -k Return
[[ "$sel_i" == Tide.PNG && "$during" == "(False, True, True, '')" && -z "$(layer_xywh rice-carousel)" && "$(tr '\n' ' ' <"$typed")" == "d " ]] \
    && pass "Escape during a running apply: closed at once (no surface), apply still running, the kitty gets the keys" \
    || fail "Escape during apply: sel $sel_i, (open, applying, previewing, overlay) $during, kitty got '$(cat "$typed")'"
settled || fail "background apply did not settle"
[[ "$(spy "d['path']" <"$staged/.local/state/quickshell/wallpaper.json")" == "$wp/Tide.PNG" \
    && "$(cj "(d['open'], d['previewing'], d['theme']['a1'], d['wallFile'].endswith('/Tide.PNG'))")" == "(False, False, '$a1_tide', True)" ]] \
    && pass "the background apply landed: Tide.PNG written, the shell reads it from the files, no preview left" \
    || fail "background apply: $(cat "$staged/.local/state/quickshell/wallpaper.json"); $(cj d)"

# j. An apply with no result within 15 s: the carousel stops waiting, shows
#    '✗ apply timed out' and releases the keyboard grab; the apply is still not killed.
echo 22 >"$tmp/c9/apply-delay"
: >"$typed"
ctoggle
settled || fail "timeout: derivation did not finish"
K -k Right
settled || fail "timeout: Right did not settle"
rm -f "$tmp/c9/apply-started"
t0=$(date +%s)
K -k Return
for _ in $(seq 20); do [[ -e "$tmp/c9/apply-started" ]] && break; sleep 0.1; done
sleep 3
early=$(cj "(d['open'], d['applying'], d['grab'], d['texts'][-1])")
K x -k Return
early_typed=$(tr '\n' ' ' <"$typed")
for _ in $(seq 150); do [[ "$(cj "d['grab']")" == False ]] && break; sleep 0.1; done
t_out=$(( $(date +%s) - t0 ))
late=$(cj "(d['open'], d['applying'], d['applyOwned'], d['grab'], d['texts'][-1], d['texts'][2].endswith(' · ctrl+alt+w close'))")
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-carousel-timeout-DP-1.png" >/dev/null
K y -k Return
[[ "$early" == "(True, True, True, 'PALETTE')" && -z "$early_typed" && $t_out -ge 14 && $t_out -le 17 \
    && "$late" == "(True, True, False, False, '✗ apply timed out', True)" &&"$(tr '\n' ' ' <"$typed")" == "y " ]] \
    && pass "slow apply: grab held at 3 s; after ${t_out} s '✗ apply timed out', header 'ctrl+alt+w close', grab released (the kitty gets the keys), apply still running" \
    || fail "apply timeout: early $early (kitty '$early_typed'), after ${t_out} s $late, kitty got '$(cat "$typed")'"
ctoggle
[[ "$(cj "(d['open'], d['previewing'], d['applying'])")" == "(False, False, True)" ]] \
    && pass "the toggle closes the timed-out carousel and drops its preview; the apply keeps running" \
    || fail "close after timeout: $(cj d)"
for _ in $(seq 150); do [[ "$(cj "d['applying']")" == False ]] && break; sleep 0.2; done
sleep 1
[[ "$(cj "d['applying']")" == False && "$(spy "d['path']" <"$staged/.local/state/quickshell/wallpaper.json")" == "$wp/ember.png" \
    && "$(cj "(d['theme']['a1'], d['wallFile'].endswith('/ember.png'), d['previewing'])")" == "('$a1_ember', True, False)" ]] \
    && pass "the late apply finished (never killed): ember written and read by the shell" \
    || fail "late apply: $(cat "$staged/.local/state/quickshell/wallpaper.json"); $(cj d)"
mv -f "$cli.real" "$cli"
ntimeout=$(warns_since "$n0" | grep -c 'Carousel: apply of .*/ember\.png gave no result within 15000 ms' || true)
bad=$(warns_since "$n0" | grep -v 'Carousel: apply of .*/ember\.png gave no result within 15000 ms' || true)
[[ -z "$bad" && "$ntimeout" == 1 ]] && pass "qs log: one timeout warning, nothing else, for i/j" \
    || { fail "qs log i/j ($ntimeout timeout warnings)"; echo "$bad"; }

# k. One keyboard-grabbing overlay at a time: the launcher opening closes the carousel
#    (dropping its preview) and the other way round.
n0=$(logn)
ctoggle
settled || fail "overlays: derivation did not finish"
K -k Right
settled || true
k1=$(cj "(d['open'], d['launcherOpen'], d['previewing'], d['overlay'])")
"$R/qs-run.sh" ipc call launcher toggle; sleep 0.5
k2=$(cj "(d['open'], d['launcherOpen'], d['previewing'], d['overlay'])")
layers_n() { echo "$(H layers | grep -c 'namespace: rice-carousel' || true) $(H layers | grep -c 'namespace: rice-launcher' || true)"; }
s2=$(layers_n)
ctoggle
k3=$(cj "(d['open'], d['launcherOpen'], d['overlay'])")
s3=$(layers_n)
K -k Escape
k4=$(cj "(d['open'], d['launcherOpen'], d['overlay'])")
[[ "$k1" == "(True, False, True, 'carousel')" && "$k2" == "(False, True, False, 'launcher')" && "$s2" == "0 1" \
    && "$k3" == "(True, False, 'carousel')" && "$s3" == "1 0" && "$k4" == "(False, False, '')" ]] \
    && pass "launcher over the carousel closes it (preview dropped), carousel over the launcher closes that: one surface each time" \
    || fail "overlays: $k1 -> $k2 [$s2] -> $k3 [$s3] -> $k4"
[[ -z "$(warns_since "$n0")" ]] && pass "qs log: no ERROR/WARN in k" || { fail "qs log k"; warns_since "$n0"; }
kill -TERM "$kitty_pid" 2>/dev/null || true
wait "$kitty_pid" 2>/dev/null || true
kitty_pid=""
kill -TERM "$holder_pid" 2>/dev/null || true
wait "$holder_pid" 2>/dev/null || true
holder_pid=""
"$R/qs-run.sh" stop >/dev/null

# --- 10. Bluetooth and Claude limits rail widgets (U12) --------------------------------
# Through tests/rig/widgets-test.qml (bars and the production rail) on a fresh rig and
# qs-run.sh's own private bus. Bluetooth: the real Bluetooth.devices on the system bus is
# only counted (read only, never named), then the rail's BluetoothWidget gets fake models
# (a ListModel and QObjects behind `values`, the shape of Bluetooth.devices). Claude: the
# widget's cachePath points at fixtures in a temp dir, written atomically like limits.py.
# A fake MPRIS player on the private bus shows the media section for the fit check.
"$R/nested-hypr.sh" stop >/dev/null
"$R/nested-hypr.sh" start "$R/full.lua" >/dev/null
staged=$("$R/qs-run.sh" start --restage --entry "$R/widgets-test.qml")
wbus=$("$R/qs-run.sh" status | sed -n 's/.* bus=\([^ ]*\).*/\1/p')
case "$wbus" in
    "" | *"path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"*) echo "REFUSING: widget tests need a private bus, got '$wbus'"; exit 1 ;;
esac
sleep 2
n0=$(logn)
wj() { "$R/qs-run.sh" ipc call widgets get | spy "$1"; }
wc10() { "$R/qs-run.sh" ipc call widgets "$@"; sleep 0.3; }
c10="$tmp/c10"
mkdir -p "$c10"
lim="$c10/limits.json"
put_lim() { printf '%s' "$1" >"$lim.tmp" && mv -f "$lim.tmp" "$lim"; sleep 1; }
# <state> -> fixture JSON relative to now (see the ClaudeWidget header for the shape)
fixture() {
    local n f d
    n=$(date +%s)
    f="{\"pct\": 38.4, \"resets_at\": $((n + 8060))}"
    d="{\"pct\": 19, \"resets_at\": $((n + 3 * 86400))}"
    case "$1" in
        full) echo "{\"five_hour\": $f, \"seven_day\": $d, \"updated_at\": $((n - 120))}" ;;
        five) echo "{\"five_hour\": {\"pct\": 81, \"resets_at\": $((n + 3000))}, \"seven_day\": null, \"updated_at\": $((n - 5))}" ;;
        stale) echo "{\"five_hour\": {\"pct\": 92, \"resets_at\": $((n + 8060))}, \"seven_day\": $d, \"updated_at\": $((n - 2400))}" ;;
        expired) echo "{\"five_hour\": {\"pct\": 38.4, \"resets_at\": $((n - 60))}, \"seven_day\": $d, \"updated_at\": $((n - 600))}" ;;
        clamp) echo "{\"five_hour\": {\"pct\": 130, \"resets_at\": $((n + 8060))}, \"seven_day\": {\"pct\": -5, \"resets_at\": $((n + 3 * 86400))}, \"updated_at\": $((n - 60))}" ;;
        future) echo "{\"five_hour\": $f, \"seven_day\": $d, \"updated_at\": $((n + 10 * 86400))}" ;;
        bothnull) echo "{\"five_hour\": null, \"seven_day\": null, \"updated_at\": $((n - 60))}" ;;
    esac
}
A1=$(spy "d['a1']" <"$staged/.config/quickshell/colors.json")
LINE=$(spy "d['line']" <"$staged/.config/quickshell/colors.json")
WARN=$(spy "d['warn']" <"$staged/.config/quickshell/colors.json")
DIM=$(spy "d['dim']" <"$staged/.config/quickshell/colors.json")
# Claude summary: (noData, stale, note, visible texts below the heading, per-row lit and
# the set of segment colours as palette token names)
csum="(c['noData'], c['stale'], c['note'], c['texts'][3:] if c['note'] else c['texts'][2:], [(r['label'], r['expired'], r['lit'] if r['segs'] else None, sorted(set(tok.get(x, x) for x in r['colors'])) if r['segs'] else None) for r in c['rows']])"
claude_is() { wj "(lambda c, tok: $csum)(d['claude'], {'$A1': 'a1', '$LINE': 'line', '$WARN': 'warn', '$DIM': 'dim'})"; }

# a. Read-only by construction: no device method calls or device property writes.
if grep -nE '\b(connect|disconnect|pair|forget|cancelPair)\(|\.(trusted|blocked|name|connected|wakeAllowed)\s*=[^=]' \
    "$staged/.config/quickshell/rail/BluetoothWidget.qml" "$staged/.config/quickshell/rail/ClaudeWidget.qml"; then
    fail "the new widgets contain a device call or a device property write"
else
    pass "BluetoothWidget/ClaudeWidget: no connect/disconnect/pair/forget calls, no trusted/blocked/name/connected writes"
fi

# b. Real Bluetooth.devices (read only): the section shows exactly when something is connected.
real=$(wj "(d['realCount'], d['realConnected'], d['bt']['visible'], d['bt']['connected'])")
read -r rc rcon rvis rn < <(echo "$real" | tr -d '(),')
echo "  real BlueZ devices: $rc known, $rcon connected; section visible $rvis"
if [[ "$rcon" == 0 ]]; then
    [[ "$rvis" == False && "$rn" == 0 && "$(wj "d['sections']")" == "['sys', 'claude']" ]] \
        && pass "real devices, none connected: BLUETOOTH hidden" || fail "real devices: $real"
else
    [[ "$rvis" == True && "$rn" == "$rcon" ]] && pass "real devices: $rcon connected shown (names not printed)" || fail "real devices: $real"
fi
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-widgets-real-DP-1.png" >/dev/null

# c. Fake ListModel: connected+battery 82%, connected without battery, disconnected.
wc10 fakeBt three
bt3="(d['bt']['visible'], d['bt']['note'], [(r['name'], r['meter'], r['lit'], r['invert'], r['texts']) for r in d['bt']['rows']])"
[[ "$(wj "$bt3")" == "(True, '2 connected', [('Rig Buds Pro', True, 4, True, ['Rig Buds Pro', '82%']), ('Rig Pad', False, 0, True, ['Rig Pad'])])" ]] \
    && pass "fake model: the 2 connected devices only, 82% with a 4/5 inverted meter, the other name only, '2 connected'" \
    || fail "fake three: $(wj "$bt3")"
wc10 setConnected 0 false
[[ "$(wj "(d['bt']['note'], [r['name'] for r in d['bt']['rows']])")" == "('1 connected', ['Rig Pad'])" ]] \
    && pass "ListModel row disconnects: '1 connected', Rig Pad only" || fail "ListModel disconnect: $(wj "d['bt']")"
wc10 setConnected 1 false
[[ "$(wj "(d['bt']['visible'], d['sections'])")" == "(False, ['sys', 'claude'])" ]] \
    && pass "last fake device disconnects: BLUETOOTH hidden" || fail "all disconnected: $(wj "d['bt']")"
wc10 fakeBt objects
[[ "$(wj "(d['bt']['note'], [r['name'] for r in d['bt']['rows']])")" == "('2 connected', ['Rig Buds Pro', 'Rig Pad'])" ]] || fail "objects: $(wj "d['bt']")"
wc10 setConnected 0 false
wc10 setConnected 2 true
[[ "$(wj "(d['bt']['note'], [(r['name'], r['texts']) for r in d['bt']['rows']])")" == "('2 connected', [('Rig Pad', ['Rig Pad']), ('Rig Speaker', ['Rig Speaker', '50%'])])" ]] \
    && pass "QObject devices (Bluetooth.devices shape): connect/disconnect notifications update the rows" \
    || fail "objects change: $(wj "d['bt']")"
wc10 fakeBt empty
[[ "$(wj "(d['bt']['visible'], d['bt']['connected'])")" == "(False, 0)" ]] && pass "empty model: BLUETOOTH hidden" || fail "empty: $(wj "d['bt']")"

# d. ClaudeWidget's pure helpers.
wp10=$("$R/qs-run.sh" ipc call widgets parse)
wd=$(LC_ALL=C date -d @$((1800000000 + 2 * 86400)) '+resets %a %H:%M')
[[ "$(echo "$wp10" | spy "(d['full'], d['garbage'], d['empty'], d['array'], d['nul'], d['number'], d['badWindow'], d['clamp'])")" \
    == "({'five': {'pct': 38.4, 'resets': 1800008040}, 'seven': {'pct': 19, 'resets': 1800400000}, 'updated': 1799999880}, None, None, None, None, None, {'five': None, 'seven': None, 'updated': None}, {'five': {'pct': 100, 'resets': 1}, 'seven': {'pct': 0, 'resets': 1}, 'updated': 1})" ]] \
    && pass "parse: full, garbage/empty/array/null/number -> null, invalid windows -> null, pct clamped" \
    || fail "parse: $wp10"
[[ "$(echo "$wp10" | spy "(d['ages'], d['resets'], d['weekday'])")" \
    == "(['0s', '12s', '59s', '1m', '5m', '59m', '1h', '1h', '23h', '1d', '3d', '0s'], ['resets in <1m', 'resets in 1m', 'resets in 14m', 'resets in 1h 0m', 'resets in 2h 14m', 'resets in 23h 59m'], '$wd')" ]] \
    && pass "age texts (12s/5m/2h/3d), reset texts, '$wd' beyond 24 h" || fail "texts: $wp10"

# e. Claude states. Missing file first (the staged HOME has no cache): one 'no data' line.
[[ "$(wj "(d['claude']['visible'], d['claude']['readable'], d['claude']['texts'])")" == "(True, False, ['//', 'CLAUDE', 'no data'])" ]] \
    && pass "missing cache file: section visible with 'no data'" || fail "missing: $(wj "d['claude']")"
wc10 setCache "$lim"
put_lim "$(fixture full)"
[[ "$(claude_is | sed 's/resets [A-Z][a-z][a-z] [0-9:]*/WD/')" == "(False, False, '2m ago', ['5H', '38%', 'resets in 2h 14m', '7D', '19%', 'WD'], [('5H', False, 4, ['a1', 'line']), ('7D', False, 2, ['a1', 'line'])])" ]] \
    && pass "full data: 5H 38% (4 lit) 'resets in 2h 14m', 7D 19% weekday reset, '2m ago'" || fail "full: $(claude_is)"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-widgets-claude-DP-1.png" >/dev/null
put_lim "$(fixture five)"
[[ "$(claude_is | sed 's/[56]s ago/Ns ago/')" == "(False, False, 'Ns ago', ['5H', '81%', 'resets in 49m'], [('5H', False, 8, ['line', 'warn'])])" ]] \
    && pass "five_hour only: one row, 81% in warn colour" || fail "five only: $(claude_is)"
put_lim "$(fixture stale)"
[[ "$(claude_is | sed 's/resets [A-Z][a-z][a-z] [0-9:]*/WD/')" == "(False, True, '40m ago', ['5H', '92%', 'resets in 2h 14m', '7D', '19%', 'WD'], [('5H', False, 9, ['dim', 'line']), ('7D', False, 2, ['dim', 'line'])])" ]] \
    && pass "40 min old: bars dimmed (92% shows dim, not warn), '40m ago'" || fail "stale: $(claude_is)"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-widgets-claude-stale-DP-1.png" >/dev/null
put_lim "$(fixture expired)"
[[ "$(claude_is | sed 's/resets [A-Z][a-z][a-z] [0-9:]*/WD/')" == "(False, False, '10m ago', ['5H', 'no data', '7D', '19%', 'WD'], [('5H', True, None, None), ('7D', False, 2, ['a1', 'line'])])" ]] \
    && pass "expired 5H window: 'no data' in its row, 7D still shown" || fail "expired: $(claude_is)"
put_lim '{garbage'
[[ "$(wj "(d['claude']['texts'], d['claude']['readable'])")" == "(['//', 'CLAUDE', 'no data'], True)" ]] \
    && pass "'{garbage': 'no data', shell up" || fail "garbage: $(wj "d['claude']")"
put_lim ''
[[ "$(wj "d['claude']['texts']")" == "['//', 'CLAUDE', 'no data']" ]] && pass "empty file: 'no data'" || fail "empty file: $(wj "d['claude']")"
put_lim '[1, 2]'
[[ "$(wj "d['claude']['texts']")" == "['//', 'CLAUDE', 'no data']" ]] && pass "not an object: 'no data'" || fail "array: $(wj "d['claude']")"
put_lim "$(fixture bothnull)"
[[ "$(wj "d['claude']['texts']")" == "['//', 'CLAUDE', 'no data']" ]] && pass "both windows null: 'no data'" || fail "both null: $(wj "d['claude']")"
put_lim "$(fixture clamp)"
[[ "$(claude_is | sed 's/resets [A-Z][a-z][a-z] [0-9:]*/WD/')" == "(False, False, '1m ago', ['5H', '100%', 'resets in 2h 14m', '7D', '0%', 'WD'], [('5H', False, 10, ['warn']), ('7D', False, 0, ['line'])])" ]] \
    && pass "pct 130 and -5 clamped to 100% (10 lit) and 0% (none lit)" || fail "clamp: $(claude_is)"
put_lim "$(fixture future)"
[[ "$(wj "(d['claude']['future'], d['claude']['stale'], d['claude']['note'], [r['colors'][0] for r in d['claude']['rows']])")" == "(True, True, 'future', ['$DIM', '$DIM'])" ]] \
    && pass "updated_at 10 days ahead: note 'future', bars dimmed" || fail "future: $(wj "d['claude']")"
rm -f "$lim"
sleep 1
[[ "$(wj "(d['claude']['texts'], d['claude']['readable'])")" == "(['//', 'CLAUDE', 'no data'], False)" ]] \
    && pass "cache deleted while running: 'no data'" || fail "deleted: $(wj "d['claude']")"
put_lim "$(fixture full)"
[[ "$(wj "(d['claude']['readable'], d['claude']['note'])")" == "(True, '2m ago')" ]] && pass "cache re-created: shown again" \
    || fail "re-created: $(wj "d['claude']")"

# f. Live edit (in place, not atomic) updates the widget without a restart.
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-widgets-edit-before-DP-1.png" >/dev/null
n=$(date +%s)
printf '{"five_hour": {"pct": 62, "resets_at": %s}, "seven_day": {"pct": 44, "resets_at": %s}, "updated_at": %s}\n' \
    $((n + 3660)) $((n + 2 * 86400)) "$n" >"$lim"
sleep 1
[[ "$(wj "[r['texts'][1] for r in d['claude']['rows']]")" == "['62%', '44%']" ]] && pass "in-place edit while running: 62% / 44% without a restart" \
    || fail "edit: $(wj "d['claude']")"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-widgets-edit-after-DP-1.png" >/dev/null

# g. The real writer: claude-limits-statusline feeds the widget through the atomic rename.
n=$(date +%s)
line=$(printf '{"rate_limits":{"five_hour":{"used_percentage":12.6,"resets_at":%s},"seven_day":{"used_percentage":77,"resets_at":%s}}}' \
    $((n + 7260)) $((n + 400000)) | HOME="$staged" CLAUDE_LIMITS_CACHE="$lim" "$staged/.local/bin/claude-limits-statusline")
sleep 1
[[ "$line" == "5h 13% · 7d 77%" && "$(wj "([r['texts'][1] for r in d['claude']['rows']], d['claude']['note'])")" == "(['13%', '77%'], '0s ago')" ]] \
    && pass "claude-limits-statusline output '$line' shows as 13% / 77%" || fail "statusline: '$line' $(wj "d['claude']")"

# h. A path that did not exist when the FileView was set up: the 30 s timer picks it up.
wc10 setCache "$tmp/c10-later/limits.json"
[[ "$(wj "d['claude']['readable']")" == False ]] || fail "later: readable before creation"
mkdir -p "$tmp/c10-later"
fixture five >"$tmp/c10-later/limits.json"
t0=$(date +%s)
for _ in $(seq 34); do [[ "$(wj "d['claude']['readable']")" == True ]] && break; sleep 1; done
dt=$(($(date +%s) - t0))
[[ "$(wj "d['claude']['readable']")" == True && $dt -le 32 ]] && pass "file created after start picked up in $dt s (<= 32 s: the watch or the 30 s re-read)" \
    || fail "later file not picked up within 32 s"

# i. One 30 s timer, only while the section is visible.
[[ "$(wj "d['timer']")" == "{'running': True, 'interval': 30000}" ]] || fail "timer visible: $(wj "d['timer']")"
wc10 setClaudeVisible false
[[ "$(wj "d['timer']")" == "{'running': False, 'interval': 30000}" ]] && pass "Claude timer: 30 s, running while visible, stopped while hidden" \
    || fail "timer hidden: $(wj "d['timer']")"
wc10 setClaudeVisible true

# j. All five sections at 1080p: nothing clipped.
DBUS_SESSION_BUS_ADDRESS="$wbus" python3 -I "$R/fake-mpris.py" "Rig Song" "Rig Artist" 252 >"$tmp/fake10.out" 2>&1 &
fake_pid=$!
wc10 setCache "$lim"
put_lim "$(fixture full)"
wc10 fakeBt three
sleep 1
fit=$(wj "(d['sections'], d['fit']['columnHeight'], d['fit']['claudeBottom'], d['fit']['clipHeight'])")
read -r fcol fbot fclip < <(wj "d['fit']['columnHeight'], d['fit']['claudeBottom'], d['fit']['clipHeight']" | tr -d '(),')
[[ "$(wj "d['sections']")" == "['sys', 'media', 'bluetooth', 'claude']" ]] && python3 -I -c "import sys; c, b, h = map(float, sys.argv[1:]); sys.exit(not (b <= h and c <= h and b > 250))" "$fcol" "$fbot" "$fclip" \
    && pass "all five sections fit the 1080p rail: column $fcol px, CLAUDE ends at $fbot of $fclip px" || fail "fit: $fit"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-widgets-all-DP-1.png" >/dev/null
kill -TERM "$fake_pid" 2>/dev/null || true
wait "$fake_pid" 2>/dev/null || true
fake_pid=""

bad=$(warns_since "$n0")
[[ -z "$bad" ]] && pass "qs log: no ERROR/WARN in section 10" || { fail "qs log section 10"; echo "$bad"; }
"$R/qs-run.sh" stop >/dev/null

# --- 11. NVIDIA GPU source (U15) -------------------------------------------------------
# Through tests/rig/nvidia-test.qml with a FAKE nvidia-smi (tests/rig/fake-nvidia-smi.sh)
# first on PATH; the real nvidia-smi never runs here. Every qs below gets the opt-in
# RICE_NVIDIA=1 through the rig pass-through RIG_NVIDIA=1 (rig_env.sh drops a plain
# inherited RICE_NVIDIA), except in scenario j (the default, and the guard). The fake logs
# each start (PID, time, args) so starts are counted and every fake PID is checked dead
# after its qs stops.
nvbin="$tmp/nvbin"
mkdir -p "$nvbin"
cp "$R/fake-nvidia-smi.sh" "$nvbin/nvidia-smi"
chmod +x "$nvbin/nvidia-smi"
nvst="$tmp/nv-status"
nvlog="$tmp/nv-starts.log"
real_nv_before=$(pgrep -x nvidia-smi || true)
amd11=""
nvcard=""
for v in /sys/class/drm/card*/device/vendor; do
    case "$(cat "$v" 2>/dev/null)" in
        0x1002) [[ -n "$amd11" ]] || amd11="${v%/vendor}/gpu_busy_percent" ;;
        0x10de) [[ -n "$nvcard" ]] || nvcard="${v%/vendor}/power/runtime_status" ;;
    esac
done
want_src_fallback=$([[ -n "$amd11" ]] && echo amd || echo none)
NVCMD="-l 2 --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits"
# nv_start [VAR=value ...]: a fresh qs on the test config, NVIDIA allowed, fake first on PATH.
nvpath="$nvbin:$(printenv PATH)"
nv_start() {
    : >"$nvlog"
    env RIG_NVIDIA=1 FAKE_NV_LOG="$nvlog" PATH="$nvpath" "$@" \
        "$R/qs-run.sh" start --entry "$R/nvidia-test.qml" >/dev/null
}
nvj() { "$R/qs-run.sh" ipc call nv get | spy "$1"; }
# nv_wait <seconds> <python expr over d>: poll every 0.5 s until the expression is True.
nv_wait() {
    local i
    for ((i = 0; i < $1 * 2; i++)); do
        [[ "$(nvj "$2")" == True ]] && return 0
        sleep 0.5
    done
    return 1
}
starts() { grep -c '^start ' "$nvlog" || true; }
# Fake PIDs from the log that still run (the fake's args contain its path .../nvidia-smi).
alive_fakes() {
    local p
    while read -r p; do
        ps -o args= -p "$p" 2>/dev/null | grep -qF "$nvbin/nvidia-smi" && echo "$p"
    done < <(awk '/^start /{print $2}' "$nvlog")
    return 0
}
# nv_stop <label>: stop qs, then every fake it started must be gone within 1 s.
nv_stop() {
    "$R/qs-run.sh" stop >/dev/null
    local left i
    for ((i = 0; i < 10; i++)); do left=$(alive_fakes); [[ -z "$left" ]] && break; sleep 0.1; done
    [[ -z "$left" ]] && pass "$1: qs stopped, no fake nvidia-smi left ($(starts) start(s) checked by PID)" \
        || fail "$1: fake nvidia-smi left: $left"
}
nv_warns() { "$R/qs-run.sh" log | grep -E 'WARN|ERROR' | grep -v 'host portal' || true; }

# a. Pure parser and VRM text fixtures.
want='{"normal":{"gpu":17,"used":1024,"total":4096,"pct":25},"spaces":{"gpu":17,"used":1024,"total":4096,"pct":25},'
want+='"noSpace":{"gpu":17,"used":1024,"total":4096,"pct":25},"na":{"gpu":-1,"used":1024,"total":-1,"pct":-1},'
want+='"allNa":null,"empty":null,"blank":null,"two":null,"extra":{"gpu":5,"used":2048,"total":4096,"pct":50},'
want+='"comma":{"gpu":17,"used":1024.5,"total":4096,"pct":25.01220703125},"over":{"gpu":100,"used":5000,"total":4096,"pct":100},'
want+='"garbage":null,"texts":["1.0/4.0G","1.5/4.0G","0.0/4.0G","--","--","13/16G","4.0/4.0G"]}'
echo active >"$nvst"
nv_start NVT_STATUS="$nvst"
got=$("$R/qs-run.sh" ipc call nv parse)
[[ "$got" == "$want" ]] && pass "parseNvLine (spaces, [N/A], extra columns, decimal comma, garbage) and VRM texts on fixtures" \
    || { fail "nvidia fixtures"; echo "  got  $got"; echo "  want $want"; }

# b. Normal stream: the fake's values reach Stats and the rail, one process.
nv_wait 8 "d['gpuSource'] == 'nvidia'" || fail "normal: gpuSource never became nvidia ($(nvj d))"
rows="[(r['label'], r['visible'], r['text'], r['lit']) for r in d['rows']]"
[[ "$(nvj "(d['gpu'], d['vramUsedMb'], d['vramTotalMb'], d['vramPct'], d['nvState'])")" == "(42, 1536, 4096, 37.5, 'live')" ]] \
    && pass "normal stream: gpuSource nvidia, gpu 42, VRAM 1536/4096 MiB (37.5%) as the fake prints" \
    || fail "normal values: $(nvj d)"
[[ "$(nvj "${rows}[2:]")" == "[('GPU', True, '42%', 4), ('VRM', True, '1.5/4.0G', 4)]" ]] \
    && pass "rail: GPU 42% (4 lit), VRM row '1.5/4.0G' (4 lit)" || fail "normal rows: $(nvj "$rows")"
[[ "$(nvj "len(set(r['valueWidth'] for r in d['rows'])) == 1 and all(r['valueTextWidth'] <= r['valueWidth'] for r in d['rows'])")" == True ]] \
    && pass "value column: one width for all four rows ($(nvj "d['rows'][0]['valueWidth']") px), '1.5/4.0G' fits it" \
    || fail "value widths: $(nvj "[(r['valueWidth'], r['valueTextWidth']) for r in d['rows']]")"
[[ "$(nvj "d['rows'][3]['bottom'] < d['fit']['clipHeight'] and d['fit']['columnHeight'] <= d['fit']['clipHeight']")" == True ]] \
    && pass "rail fits 1080p with the VRM row (column $(nvj "d['fit']['columnHeight']") of $(nvj "d['fit']['clipHeight']") px)" \
    || fail "fit: $(nvj "d['fit']")"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-nvidia-stream-DP-1.png" >/dev/null
sleep 4
[[ "$(starts)" == 1 && "$(sed -n '1s/^start [0-9]* [0-9]* //p' "$nvlog")" == "$NVCMD" ]] \
    && pass "one long-lived stream (1 start after ~10 s), args '$NVCMD'" || fail "starts: $(cat "$nvlog")"
[[ -z "$(nv_warns)" ]] && pass "normal stream: no WARN/ERROR" || { fail "normal warns"; nv_warns; }
nv_stop "normal stream"

# b2. qs killed with SIGKILL (no clean exit at all): the stream still dies (pdeathsig).
nv_start NVT_STATUS="$nvst"
nv_wait 8 "d['gpuSource'] == 'nvidia'" || fail "kill: never live"
qs_pid=$(sed -n 's/^QS_PID=//p' "$TB/qs-run.env")
fpid=$(awk '/^start /{print $2; exit}' "$nvlog")
kill -KILL "$qs_pid"
for _ in $(seq 20); do [[ -z "$(alive_fakes)" ]] && break; sleep 0.1; done
[[ -n "$fpid" && -z "$(alive_fakes)" ]] && pass "qs SIGKILLed: its fake nvidia-smi ($fpid) died with it" \
    || fail "SIGKILL: fake left $(alive_fakes)"
"$R/qs-run.sh" stop >/dev/null   # clears the stale state and the private bus

# c. [N/A] fields: still the NVIDIA source; unknown values stay -1, the rows follow.
nv_start NVT_STATUS="$nvst" FAKE_NV_LINE="[N/A], 1024, [Not Supported]"
nv_wait 8 "d['gpuSource'] == 'nvidia'" || fail "N/A: never live"
[[ "$(nvj "(d['gpu'], d['vramUsedMb'], d['vramTotalMb'], d['vramPct'], ${rows}[2:])")" \
    == "(-1, 1024, -1, -1, [('GPU', False, '-1%', 0), ('VRM', True, '--', 0)])" ]] \
    && pass "'[N/A], 1024, [Not Supported]': gpu -1 (GPU row hidden), VRM row '--'" || fail "N/A: $(nvj d)"
nv_stop "[N/A] fields"

# d. Only invalid lines: no valid line within 6 s -> the fallback source, stream stopped.
nv_start NVT_STATUS="$nvst" FAKE_NV_LINE="[N/A], [N/A], [N/A]"
t0=$(date +%s)
nv_wait 12 "d['nvState'] == 'off'" || fail "timeout: still $(nvj "d['nvState']")"
dt=$(($(date +%s) - t0))
fallback_ok="d['gpuSource'] == '$want_src_fallback' and d['vramPct'] == -1 and (d['gpu'] >= 0) == ('$amd11' != '')"
[[ "$(nvj "$fallback_ok")" == True && $dt -ge 5 && $dt -le 10 && -z "$(alive_fakes)" ]] \
    && pass "no valid line: $want_src_fallback after ${dt} s (6 s timeout on the 2 s tick), the fake was stopped" \
    || fail "timeout: ${dt}s $(nvj d) alive: $(alive_fakes)"
[[ "$(nvj "[(r['label'], r['visible']) for r in d['rows']][2:]")" == "[('GPU', $([[ -n "$amd11" ]] && echo True || echo False)), ('VRM', False)]" ]] \
    && pass "after the timeout: VRM row hidden, GPU row $([[ -n "$amd11" ]] && echo "from AMD" || echo hidden)" \
    || fail "timeout rows: $(nvj "$rows")"
sleep 6
[[ "$(starts)" == 1 && "$(nv_warns | grep -c .)" == 1 && "$(nv_warns | grep -c 'no valid nvidia-smi line')" == 1 ]] \
    && pass "timeout: one start, exactly one warning, no retry" || { fail "timeout warns/starts ($(starts))"; nv_warns; }
nv_stop "timeout"

# e. The fake exits at once (exit 9): the fallback well within the timeout, no spinning.
nv_start NVT_STATUS="$nvst" FAKE_NV_MODE=exit
nv_wait 3 "d['nvState'] == 'off'" && [[ "$(nvj "$fallback_ok")" == True ]] \
    && pass "fake exits 9 at once: $want_src_fallback within 3 s" || fail "exit: $(nvj d)"
sleep 10
[[ "$(starts)" == 1 && "$(nv_warns | grep -c .)" == 1 && "$(nv_warns | grep -c 'exited (9) before a valid line')" == 1 ]] \
    && pass "immediate exit: 1 start in 10 s (no spin), one warning" || { fail "exit starts $(starts)"; nv_warns; }
nv_stop "immediate exit"

# f. The stream dies mid-way: fallback, then back-off retries (shortened to 4/8/12 s by the
# test config). Each fake run prints 4 lines 1 s apart, then exits 1. Finally the card
# "suspends" during a back-off wait: the next retry must not start anything.
nv_start NVT_STATUS="$nvst" FAKE_NV_MODE=die FAKE_NV_COUNT=4 FAKE_NV_LINE="7, 3500, 4096" NVT_BACKOFF=4000,8000,12000
nv_wait 8 "d['gpuSource'] == 'nvidia'" || fail "die: never live"
[[ "$(nvj "(d['gpu'], d['vramPct'] > 85, ${rows}[2:])")" == "(7, True, [('GPU', True, '7%', 1), ('VRM', True, '3.4/4.0G', 9)])" ]] \
    && pass "another fake line: gpu 7, VRM '3.4/4.0G' (9 lit, above 75 -> warn colour)" || fail "die values: $(nvj d)"
QS_SETTLE=0.3 "$R/qs-run.sh" shot DP-1 "$SHOTS/qs-nvidia-vram-high-DP-1.png" >/dev/null
nv_wait 8 "d['nvState'] == 'waiting'" && [[ "$(nvj "$fallback_ok and not d['rows'][3]['visible']")" == True ]] \
    && pass "stream died: back to $want_src_fallback, VRAM cleared, VRM row hidden, retry scheduled" || fail "die fallback: $(nvj d)"
for _ in $(seq 40); do [[ "$(starts)" -ge 3 ]] && break; sleep 1; done
echo suspended >"$nvst"
read -r g1 g2 < <(awk '/^start /{t[++n]=$3} END{print t[2]-t[1], t[3]-t[2]}' "$nvlog")
echo "  start gaps: ${g1} ms, ${g2} ms (stream ~4 s + back-off 4 s / 8 s + up to one 2 s tick)"
[[ "$(starts)" == 3 && $g1 -ge 8000 && $g1 -le 11500 && $g2 -ge 12000 && $g2 -le 15500 ]] \
    && pass "back-off restarts: 3 starts, gaps ${g1} / ${g2} ms grow with the steps" || fail "back-off: $(cat "$nvlog")"
sleep 20
[[ "$(starts)" == 3 && "$(nvj "d['nvState']")" == waiting && "$(nvj "$fallback_ok")" == True ]] \
    && pass "card not active at the next retry: nothing started in 20 s (still waiting, $want_src_fallback)" \
    || fail "suspended retry: $(starts) starts, $(nvj d)"
[[ "$(nv_warns | grep -c 'stream ended')" == 1 && "$(nv_warns | grep -c .)" == 1 ]] \
    && pass "three stream deaths: exactly one warning" || { fail "die warns"; nv_warns; }
nv_stop "stream dies"

# f2. A stream that lasted at least the longest step (12 s here) starts the back-off over:
# every gap is ~14 s of stream + the first step (4 s), never the 8 s step.
echo active >"$nvst"
nv_start NVT_STATUS="$nvst" FAKE_NV_MODE=die FAKE_NV_COUNT=14 NVT_BACKOFF=4000,8000,12000
for _ in $(seq 50); do [[ "$(starts)" -ge 3 ]] && break; sleep 1; done
read -r g1 g2 < <(awk '/^start /{t[++n]=$3} END{print t[2]-t[1], t[3]-t[2]}' "$nvlog")
echo "  start gaps: ${g1} ms, ${g2} ms (stream ~14 s + back-off 4 s + up to one 2 s tick)"
[[ "$(starts)" -ge 3 && $g1 -ge 18000 && $g1 -le 21500 && $g2 -ge 18000 && $g2 -le 21500 ]] \
    && pass "long-lived streams: back-off restarts at the first step each time (${g1} / ${g2} ms)" \
    || fail "back-off reset: $(cat "$nvlog")"
nv_stop "long-lived streams"

# g. runtime_status not active from the start: no process at all.
echo suspended >"$nvst"
nv_start NVT_STATUS="$nvst"
sleep 6
[[ "$(starts)" == 0 && "$(nvj "d['nvState'] == 'off' and $fallback_ok")" == True && -z "$(nv_warns)" ]] \
    && pass "runtime_status 'suspended': no nvidia-smi started at all, $want_src_fallback, no warning" \
    || fail "suspended: $(starts) starts $(nvj d)"
nv_stop "not active"

# h. The real card's runtime_status (read only): the probe finds it; the fake is started
# only if the card is active right now (it usually sleeps on this machine).
# nvState must have left "checking": the status read completed (a dropped load would
# leave it "checking" with 0 starts, which the start count alone cannot tell apart).
# The rig start wakes the card for ~20 s, so its status is sampled right before and 6 s
# after the start; if it changed in between, either consistent outcome is accepted.
real_status() { [[ -n "$nvcard" ]] && cat "$nvcard" || echo none; }
rs0=$(real_status)
nv_start
sleep 6
rs1=$(real_status)
got_h="$(nvj "d['nvStatusPath']") $(nvj "d['nvState']") $(starts)"
ok_h=""
for st in "$rs0" "$rs1"; do
    [[ "$st" == active ]] && w="live 1" || w="off 0"
    [[ "$got_h" == "$nvcard $w" ]] && ok_h=1
done
[[ -n "$ok_h" ]] \
    && pass "real sysfs: probe found ${nvcard:-no NVIDIA card}, status read ($rs0 -> $rs1): nvState/starts '${got_h#* }'" \
    || fail "real sysfs: '$got_h' (status $rs0 -> $rs1)"
nv_stop "real sysfs"

# k. The production probe path end to end: Stats.drmRoot (the test config's only hook
# here) points the card probe at a fake /sys/class/drm tree (card1 NVIDIA, card2 AMD with
# gpu_busy_percent 33). The probe itself assigns both paths and reads runtime_status.
drm="$tmp/drm"
mkdir -p "$drm/card1/device/power" "$drm/card2/device"
echo 0x10de >"$drm/card1/device/vendor"
echo 0x1002 >"$drm/card2/device/vendor"
echo 33 >"$drm/card2/device/gpu_busy_percent"
echo active >"$drm/card1/device/power/runtime_status"
nv_start NVT_DRM="$drm"
nv_wait 8 "d['gpuSource'] == 'nvidia'" || true   # the checks below report what was reached
[[ "$(nvj "(d['nvStatusPath'], d['gpuPath'], d['nvState'], d['gpu'], d['vramUsedMb'])")" \
    == "('$drm/card1/device/power/runtime_status', '$drm/card2/device/gpu_busy_percent', 'live', 42, 1536)" \
    && "$(starts)" == 1 ]] \
    && pass "probe path: fake drm tree -> runtime_status 'active' read by the probe -> one stream, gpu 42 / 1536 MiB" \
    || fail "probe path active: $(starts) starts $(nvj d)"
nv_stop "probe path active"
echo suspended >"$drm/card1/device/power/runtime_status"
nv_start NVT_DRM="$drm"
nv_wait 6 "d['nvState'] == 'off'" || true
[[ "$(nvj "(d['nvStatusPath'], d['nvState'], d['gpuSource'], d['gpu'])")" \
    == "('$drm/card1/device/power/runtime_status', 'off', 'amd', 33)" && "$(starts)" == 0 ]] \
    && pass "probe path: runtime_status 'suspended' read (nvState off), no start, AMD 33% from the tree" \
    || fail "probe path suspended: $(starts) starts $(nvj d)"
nv_stop "probe path suspended"

# i. nvidia-smi missing: the fallback, no warning, one info line.
echo active >"$nvst"
nv_start NVT_STATUS="$nvst" NVT_SMI=rig-no-such-nvidia-smi
nv_wait 4 "d['nvState'] == 'off'" && [[ "$(nvj "$fallback_ok")" == True && "$(starts)" == 0 && -z "$(nv_warns)" \
    && "$("$R/qs-run.sh" log | grep -c 'rig-no-such-nvidia-smi not found')" == 1 ]] \
    && pass "nvidia-smi not on PATH: $want_src_fallback, no WARN/ERROR, one info line" || { fail "missing: $(nvj d)"; nv_warns; }
nv_stop "missing nvidia-smi"

# j. The default: NVIDIA is opt-in. With the fake drm tree saying "active" and the fake
# first on PATH, no fake is ever started and no NVIDIA status path is even assigned:
#   none    no RICE_NVIDIA, no RIG_NVIDIA
#   zero    RIG_NVIDIA=0 (qs sees RICE_NVIDIA=0)
#   guard   RICE_NVIDIA=1 inherited from an opted-in session, without RIG_NVIDIA: the rig
#           (rig_env.sh) must drop it, or any ad-hoc qs-run.sh would run the real one
echo active >"$drm/card1/device/power/runtime_status"
for optin in none zero guard; do
    : >"$nvlog"
    case $optin in
        none) ev=(env -u RICE_NVIDIA -u RIG_NVIDIA) ;;
        zero) ev=(env -u RICE_NVIDIA RIG_NVIDIA=0) ;;
        guard) ev=(env -u RIG_NVIDIA RICE_NVIDIA=1) ;;
    esac
    "${ev[@]}" FAKE_NV_LOG="$nvlog" PATH="$nvpath" NVT_DRM="$drm" \
        "$R/qs-run.sh" start --entry "$R/nvidia-test.qml" >/dev/null
    sleep 8
    [[ "$(starts)" == 0 && "$(nvj "(d['nvAllowed'], d['nvStatusPath'], d['nvState'], d['gpuSource'], d['gpu'], d['rows'][3]['visible'])")" \
        == "(False, '', 'off', 'amd', 33, False)" ]] \
        && pass "default off ($optin): runtime_status active + fake on PATH, still no start, no NVIDIA status path, AMD 33%, no VRM row" \
        || fail "default off ($optin): $(starts) starts $(nvj d)"
    nv_stop "default off ($optin)"
done
[[ "$(pgrep -x nvidia-smi || true)" == "$real_nv_before" ]] && pass "no real nvidia-smi was started by section 11" \
    || fail "nvidia-smi processes changed: '$real_nv_before' -> '$(pgrep -x nvidia-smi || true)'"

# --- 12. Clock service and untrusted text (FIX-B) ---------------------------------------
# Through tests/rig/clock-text.qml (bars and the production rail) with TZ=Europe/Lisbon, on
# a fresh rig and qs-run.sh's own private bus.
"$R/nested-hypr.sh" stop >/dev/null
"$R/nested-hypr.sh" start "$R/full.lua" >/dev/null
staged=$(TZ=Europe/Lisbon "$R/qs-run.sh" start --restage --entry "$R/clock-text.qml")
pbus=$("$R/qs-run.sh" status | sed -n 's/.* bus=\([^ ]*\).*/\1/p')
case "$pbus" in
    "" | *"path=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"*) echo "REFUSING: section 12 needs a private bus, got '$pbus'"; exit 1 ;;
esac
sleep 2
n0=$(logn)
pj() { "$R/qs-run.sh" ipc call probe "$@"; }
ms() { echo $(( $(date -u -d "$1" +%s) * 1000 )); }
clk() { pj clock | spy "(d['bar:DP-1'][8], d['bar:DP-1'][9], d['bar:eDP-1'][8], d['rail'])"; }

# a. No SystemClock anywhere in the shell; one shared clock.
[[ -z "$(grep -rn 'SystemClock *{' "$R/../../dot_config/quickshell" || true)" ]] \
    && pass "no SystemClock left in dot_config/quickshell" || fail "SystemClock still used: $(grep -rn 'SystemClock *{' "$R/../../dot_config/quickshell")"

# b. The repeated hour of the autumn DST change: 01:59 WEST, then 01:00 WET (the clock goes
#    back one hour), each within one 2 s tick, on both bars and the rail.
pj mock "$(ms '2026-10-25 00:59:30')"; sleep 2.5
c1=$(clk)
pj mock "$(ms '2026-10-25 01:00:30')"; sleep 2.5
c2=$(clk)
pj mock "$(ms '2026-10-25 01:59:10')"; sleep 2.5
c3=$(clk)
[[ "$c1" == "('01:59', 'SUN OCT 25', '01:59', ['01:59', 'WEST', 'SUN OCT 25 2026'])" \
    && "$c2" == "('01:00', 'SUN OCT 25', '01:00', ['01:00', 'WET', 'SUN OCT 25 2026'])" \
    && "$c3" == "('01:59', 'SUN OCT 25', '01:59', ['01:59', 'WET', 'SUN OCT 25 2026'])" ]] \
    && pass "DST: 01:59 WEST -> 01:00 WET (back one hour) -> 01:59 WET on both bars and the rail" \
    || fail "DST clock: $c1 | $c2 | $c3"
# Inside the repeated hour the log stays quiet (SystemClock logged ~2,200 warnings/s here).
nq=$(logn)
sleep 6
[[ "$(logn)" == "$nq" ]] && pass "repeated hour: no log growth over 6 s" || { fail "log grew during the repeated hour"; "$R/qs-run.sh" log | tail -n +"$((nq + 1))" | head -5; }

# c. A big jump (as after a suspend/resume) shows within one tick; back to the real time.
pj mock "$(ms '2026-10-25 13:37:00')"; sleep 2.5
c4=$(clk)
pj real; sleep 2.5
c5=$(pj clock | spy "d['bar:DP-1'][8]")
now5=$(TZ=Europe/Lisbon date +%H:%M); prev5=$(TZ=Europe/Lisbon date -d '-1 min' +%H:%M)
[[ "$c4" == "('13:37', 'SUN OCT 25', '13:37', ['13:37', 'WET', 'SUN OCT 25 2026'])" && ( "$c5" == "$now5" || "$c5" == "$prev5" ) ]] \
    && pass "jump to 13:37 shown within one tick; real time again ($c5)" || fail "jump/real: $c4 | $c5 (now $now5)"

# d. Untrusted strings. A local listener records every connection: an <img src> rendered
#    as StyledText would make the QML engine fetch it.
lport=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
lhits="$tmp/c12-hits"
: >"$lhits"
python3 -I - "$lport" "$lhits" <<'PY' &
import socket, sys
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(8)
while True:
    c, a = s.accept()
    open(sys.argv[2], "a").write(f"connection from {a}\n")
    c.close()
PY
lst_pid=$!
sleep 0.5
img() { echo "<img src=\"http://127.0.0.1:$lport/$1.png\">"; }
# Positive control: the listener sees a real request.
python3 -I -c "import urllib.request,sys
try: urllib.request.urlopen(sys.argv[1], timeout=2)
except Exception: pass" "http://127.0.0.1:$lport/control.png"
sleep 0.3
ctl=$(wc -l <"$lhits")
: >"$lhits"
t_title="<b>Bold</b><br>Title $(img title)"
H dispatch 'hl.dsp.focus({ monitor = "DP-1" })' >/dev/null
"$R/run.sh" env HOME="$staged" XDG_CONFIG_HOME="$staged/.config" XDG_CACHE_HOME="$staged/.cache" \
    XDG_STATE_HOME="$staged/.local/state" XDG_DATA_HOME="$staged/.local/share" \
    DBUS_SESSION_BUS_ADDRESS="$pbus" kitty --config=NONE --title "$t_title" sh -c 'sleep 600' \
    >"$tmp/kitty12.out" 2>&1 </dev/null &
kitty_pid=$!
t_media="<b>Song</b><br>$(img media)"
t_artist="<i>Artist</i> $(img artist)"
DBUS_SESSION_BUS_ADDRESS="$pbus" python3 -I "$R/fake-mpris.py" "$t_media" "$t_artist" 200 >"$tmp/fake12.out" 2>&1 &
fake_pid=$!
t_bt="<font color=\"red\">Buds</font><br>$(img bt)"
pj setBt "$t_bt"
for _ in $(seq 40); do
    [[ "$(pj untrusted | spy "len([t for t in d if 'Bold' in t['text'] or 'Song' in t['text'] or 'Artist' in t['text'] or 'Buds' in t['text']])")" -ge 5 ]] && break
    sleep 0.3
done
sleep 2
u=$(pj untrusted)
echo "$u" | python3 -I -c "
import json, sys
d = json.load(sys.stdin)
want = {'title': sys.argv[1], 'media': sys.argv[2], 'artist': sys.argv[3], 'bt': sys.argv[4]}
seen = {k: [t for t in d if t['text'] == v] for k, v in want.items()}
bad = []
for k, ts in seen.items():
    if not ts:
        bad.append(k + ': not shown')
    for t in ts:
        if not t['plain'] or t['lines'] != 1:
            bad.append(f\"{k} on {t['where']}: plain={t['plain']} lines={t['lines']}\")
print('ok' if not bad else '; '.join(bad))
print(' '.join(f'{k}x{len(v)}' for k, v in seen.items()))
" "$t_title" "$t_media" "$t_artist" "$t_bt" >"$tmp/c12-verdict"
[[ "$(head -1 "$tmp/c12-verdict")" == ok ]] \
    && pass "window title, MPRIS title/artist, Bluetooth name: literal plain text on one line ($(sed -n 2p "$tmp/c12-verdict"))" \
    || fail "untrusted text: $(cat "$tmp/c12-verdict")"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-untrusted-DP-1.png" >/dev/null
[[ "$ctl" == 1 && ! -s "$lhits" ]] && pass "no HTTP request from the shell (listener positive control: $ctl connection)" \
    || fail "listener: control $ctl, shell connections: $(cat "$lhits")"
# e. The Bluetooth rows torn down while bound: no TypeError.
pj clearBt; sleep 0.5
kill -TERM "$fake_pid" 2>/dev/null || true; wait "$fake_pid" 2>/dev/null || true; fake_pid=""
kill -TERM "$kitty_pid" 2>/dev/null || true; wait "$kitty_pid" 2>/dev/null || true; kitty_pid=""
kill -TERM "$lst_pid" 2>/dev/null || true; wait "$lst_pid" 2>/dev/null || true; lst_pid=""
sleep 1
[[ -z "$(warns_since "$n0")" ]] && pass "qs log: no ERROR/WARN in section 12" || { fail "qs log section 12"; warns_since "$n0"; }
"$R/qs-run.sh" stop >/dev/null

"$R/nested-hypr.sh" stop >/dev/null
trap - EXIT
rm -rf -- "$tmp"
echo "screenshots: $SHOTS/qs-*.png"
[[ $fails -eq 0 ]] && echo "SELFTEST-QS OK" || { echo "SELFTEST-QS: $fails failure(s)"; exit 1; }
