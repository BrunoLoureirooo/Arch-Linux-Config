#!/usr/bin/env bash
# shellcheck disable=SC2015  # pass() only echoes, so `test && pass || fail` is safe here
# End-to-end check of the Quickshell rig helpers and the shell foundation:
#   1. stage.sh builds the deployed tree, is idempotent, keeps create_ files, refuses
#      foreign directories, and leaves the real chezmoi state alone;
#   2. qs-run.sh start/log/shot/stop runs the staged shell.qml in the nested rig;
#   3. Theme: corrupt file fallback, hot reload, per-key defaults, preview/clearPreview
#      (through tests/rig/gallery.qml);
#   4. qs-supervise restarts a killed qs within 3 s and exits cleanly on SIGTERM;
#   5. bar and Stats (through tests/rig/stats.qml): parsers on fixtures, live values
#      against /proc, main screen, per-screen slots and their independence, the click
#      dispatch, nmcli fake/missing, an unreadable GPU file, no nvidia-smi.
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
# Fresh rig so the workspace state is known: DP-1 (focused, an extra pool, starts on a
# free id) and eDP-1 (pool 1, 11-15 persistent).
"$R/nested-hypr.sh" stop >/dev/null
"$R/nested-hypr.sh" start "$R/full.lua" >/dev/null
fakebin="$tmp/fakebin"
emptybin="$tmp/emptybin"
mkdir -p "$fakebin" "$emptybin"
cat >"$fakebin/nmcli" <<'EOF'
#!/bin/sh
printf 'lo:loopback\nHome\\:5G:802-11-wireless\nWired:802-3-ethernet\n'
EOF
chmod +x "$fakebin/nmcli"
"$R/qs-run.sh" start --entry "$R/stats.qml" --path "$fakebin" >/dev/null
sleep 3
sget() { "$R/qs-run.sh" ipc call stats get; }
spy() { python3 -I -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
H() { "$R/run.sh" hyprctl "$@"; }
active_ws() {
    H monitors -j | python3 -I -c 'import json,sys; print(next(m["activeWorkspace"]["id"] for m in json.load(sys.stdin) if m["name"]==sys.argv[1]))' "$1"
}
filled() { sget | spy "d['slots']['$1']['filled']"; }

want='{"stat":{"total":1000,"idle":800},"cpu":50,"cpuNoDelta":null,"statBad":null,"mem":{"gb":11.444091796875,"pct":75},"memBad":null,"gpu":17,"gpuBad":-1,"nm":"Home:5G","nmEmpty":"","slot":[1,5,1,5,1,5,6]}'
got=$("$R/qs-run.sh" ipc call stats parse)
[[ "$got" == "$want" ]] && pass "Stats parsers and the slot rule on fixtures" \
    || { fail "parsers"; echo "  got  $got"; echo "  want $want"; }

snap=$(sget)
used_mb=$(free -m | awk '/^Mem:/{print $3}')
echo "$snap" | python3 -I -c '
import json, sys
d = json.load(sys.stdin); used = float(sys.argv[1]) / 1024
print("  cpu %.1f  memGb %.2f (free -m: %.2f)  memPct %.1f  gpu %s  gpuPath %r"
      % (d["cpu"], d["memGb"], used, d["memPct"], d["gpu"], d["gpuPath"]))
ok = 0 <= d["cpu"] <= 100 and abs(d["memGb"] - used) < max(0.15, used * 0.03) and 0 < d["memPct"] < 100
sys.exit(0 if ok else 1)' "$used_mb" && pass "Stats cpu/mem agree with free -m" || fail "Stats cpu/mem"
amd=""
for v in /sys/class/drm/card*/device/vendor; do
    [[ "$(cat "$v" 2>/dev/null)" == 0x1002 ]] && { amd="${v%/vendor}/gpu_busy_percent"; break; }
done
gpu_ok=$(echo "$snap" | spy "'ok' if d['gpuPath'] == '$amd' and (d['gpu'] >= 0 if '$amd' else d['gpu'] == -1) else 'bad'")
[[ "$gpu_ok" == ok ]] && pass "Stats gpu from the AMD card (${amd:-none})" || fail "Stats gpu/gpuPath"
[[ -z "$(pgrep -x nvidia-smi || true)" ]] && pass "no nvidia-smi while the shell runs" || fail "nvidia-smi running"
net=$(echo "$snap" | spy "d['netConn']")
[[ "$net" == "Home:5G" ]] && pass "netConn from (fake) nmcli, loopback skipped" || fail "netConn: $net"
[[ "$(echo "$snap" | spy "','.join(d['main'])")" == "DP-1" ]] \
    && pass "Screens.isMain: no BenQ, so the first screen is main" || fail "main screen"
ids=$(echo "$snap" | spy "d['slots']['eDP-1']['ids']")
[[ "$ids" == "[11, 12, 13, 14, 15]" ]] && pass "eDP-1 bar lists its own pool (11-15)" || fail "eDP-1 ids: $ids"

edp0=$(active_ws eDP-1)
"$R/keys.sh" -M ctrl -k 3 -m ctrl
sleep 1
[[ "$(active_ws DP-1)" == 23 && "$(active_ws eDP-1)" == "$edp0" && "$(filled DP-1)" == "[3]" \
    && "$(filled eDP-1)" == "[$((edp0 - 10))]" ]] \
    && pass "Ctrl+3 on DP-1: its bar fills slot 3 (ws 23), the eDP-1 bar is unchanged" \
    || fail "Ctrl+3 independence (DP-1 $(active_ws DP-1) $(filled DP-1), eDP-1 $(active_ws eDP-1) $(filled eDP-1))"
"$R/qs-run.sh" shot DP-1 "$SHOTS/qs-bar-DP-1.png" >/dev/null
H dispatch 'hl.dsp.focus({ monitor = "eDP-1" })' >/dev/null
sleep 0.3
"$R/keys.sh" -M ctrl -M alt -k Right -m alt -m ctrl
sleep 1
[[ "$(active_ws eDP-1)" == $((edp0 + 1)) && "$(active_ws DP-1)" == 23 \
    && "$(filled eDP-1)" == "[$((edp0 - 9))]" && "$(filled DP-1)" == "[3]" ]] \
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

unread="$tmp/unreadable"
: >"$unread"
chmod 000 "$unread"
"$R/qs-run.sh" ipc call stats setPaths /proc/stat /proc/meminfo "$unread"
sleep 4
n1=$("$R/qs-run.sh" log | wc -l)
sleep 8
n2=$("$R/qs-run.sh" log | wc -l)
[[ "$(sget | spy "d['gpu']")" == -1 && "$n1" == "$n2" \
    && "$("$R/qs-run.sh" log | grep -c 'Stats: cannot read')" == 1 ]] \
    && pass "unreadable GPU file: gpu -1, one warning, log stable ($n1 lines)" || fail "unreadable GPU file ($n1 -> $n2)"
bad=$("$R/qs-run.sh" log | grep -E 'ERROR|WARN' | grep -v -e 'Failed to register with host portal' -e 'Stats: cannot read' || true)
[[ -z "$bad" ]] && pass "qs log: no other ERROR/WARN" || { fail "qs log"; echo "$bad"; }
"$R/qs-run.sh" stop >/dev/null

"$R/qs-run.sh" start --entry "$R/stats.qml" --path "$emptybin" >/dev/null
sleep 7
n1=$("$R/qs-run.sh" log | wc -l)
sleep 12
n2=$("$R/qs-run.sh" log | wc -l)
[[ "$(sget | spy "d['netConn']")" == "" && "$n1" == "$n2" ]] \
    && pass "nmcli missing: netConn empty, log stable ($n1 lines over 12 s)" || fail "nmcli missing ($n1 -> $n2)"
"$R/qs-run.sh" stop >/dev/null

"$R/nested-hypr.sh" stop >/dev/null
trap - EXIT
rm -rf -- "$tmp"
echo "screenshots: $SHOTS/qs-*.png"
[[ $fails -eq 0 ]] && echo "SELFTEST-QS OK" || { echo "SELFTEST-QS: $fails failure(s)"; exit 1; }
