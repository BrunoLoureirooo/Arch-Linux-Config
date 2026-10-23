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
#      unreadable GPU/route files, no nvidia-smi or nmcli.
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
cleanup() {
    [[ -z "$sup_pid" ]] || kill -TERM "$sup_pid" 2>/dev/null || true
    "$R/qs-run.sh" stop >/dev/null 2>&1 || true
    "$R/nested-hypr.sh" stop >/dev/null 2>&1 || true
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
    .config/quickshell/bar/Workspaces.qml \
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
bad=$("$R/qs-run.sh" log | grep -E 'ERROR|WARN' | grep -v 'Failed to register with host portal' || true)
[[ -z "$bad" ]] && pass "qs log: no ERROR/WARN besides the portal warning" || { fail "qs log has errors"; echo "$bad"; }
qs_pid=$("$R/qs-run.sh" status | sed -n 's/^running: pid=\([0-9]*\) .*/\1/p')
[[ "$(tr '\0' '\n' <"/proc/$qs_pid/environ" | grep -E '^(HOME|RICE_NO_RELOAD)=' | sort | tr '\n' ' ')" \
    == "HOME=$staged RICE_NO_RELOAD=1 " ]] && pass "qs runs with HOME=staged and RICE_NO_RELOAD=1" \
    || fail "qs environment"
layers=$("$R/run.sh" hyprctl layers | grep -c 'namespace: rice-bar' || true)
[[ "$layers" -eq 2 ]] && pass "bar on both outputs (2 rice-bar layers)" || fail "rice-bar layers: $layers"
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

"$R/nested-hypr.sh" stop >/dev/null
trap - EXIT
rm -rf -- "$tmp"
echo "screenshots: $SHOTS/qs-*.png"
[[ $fails -eq 0 ]] && echo "SELFTEST-QS OK" || { echo "SELFTEST-QS: $fails failure(s)"; exit 1; }
