#!/usr/bin/env bash
# shellcheck disable=SC2015  # echo never fails, so `test && echo || ...` is safe here
# A palette apply must never re-light a panel the lid script disabled (FIX-B I6).
#   tests/hypr/palette_lid.sh
# Starts its OWN nested instance (stops any running one first) on a temp HOME holding
# the repo's Hyprland config tree (hyprland.lua, binds.lua, lib/, colors.lua from the
# seed; autostart.lua replaced by an empty stub so nothing is autostarted), so
# Hyprland's own autoreload watches exactly the files of the real layout. Then, with
# eDP-1 disabled as `lid close` does:
#   1. rice-palette apply (HOME = that temp HOME; a FAKE pkill first on PATH, so no
#      real kitty is signalled; a logging hyprctl shim that execs the real hyprctl,
#      which reaches only the nested instance) rewrites colors.lua with a new palette
#      and recolours the borders at runtime;
#   2. eDP-1 stays disabled (no `hyprctl reload`, and writing colors.lua does not
#      trigger the autoreload);
#   3. the border options hold the new palette; an explicit reload (what `lid open`
#      does) reads the same colours back from colors.lua and re-enables eDP-1.
# Exit 0 = all passed. Stops the nested instance it started.
set -euo pipefail
R="$(cd "$(dirname "$(realpath "$0")")/../rig" && pwd)"
REPO="$(cd "$R/../.." && pwd)"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/palette-lid.XXXXXX")
cleanup() { "$R/nested-hypr.sh" stop >/dev/null 2>&1 || true; rm -rf -- "$tmp"; }
trap cleanup EXIT

home="$tmp/home"
cfg="$home/.config/hypr"
mkdir -p "$cfg/lib" "$tmp/stubs" "$home/.local/bin" "$home/.local/share"
cp "$REPO/dot_config/hypr/hyprland.lua" "$REPO/dot_config/hypr/binds.lua" "$cfg/"
cp "$REPO/dot_config/hypr/lib/pools.lua" "$cfg/lib/"
cp "$REPO/dot_config/hypr/create_colors.lua" "$cfg/colors.lua"
echo '-- palette_lid.sh stub: nothing is autostarted in the rig' >"$cfg/autostart.lua"
cp "$REPO/dot_local/bin/executable_rice-palette" "$home/.local/bin/rice-palette"
cp -r "$REPO/dot_local/share/rice" "$home/.local/share/rice"
printf '#!/bin/sh\necho "pkill $*" >>%s/pkill.log\nexit 1\n' "$tmp" >"$tmp/stubs/pkill"
real_hyprctl=$(command -v hyprctl)
printf '#!/bin/sh\necho "hyprctl $*" >>%s/hyprctl.log\nexec %s "$@"\n' "$tmp" "$real_hyprctl" >"$tmp/stubs/hyprctl"
chmod +x "$tmp/stubs/pkill" "$tmp/stubs/hyprctl" "$home/.local/bin/rice-palette"

"$R/nested-hypr.sh" stop >/dev/null 2>&1 || true
"$R/nested-hypr.sh" start "$home/.config" >/dev/null
# shellcheck source=tests/rig/rig_env.sh
source "$R/rig_env.sh"   # aborts unless the nested instance is up and not the live one

fails=0
expect() { if [[ "$2" == "$3" ]]; then echo "PASS $1 ($3)"; else echo "FAIL $1: want $2, got $3"; fails=$((fails + 1)); fi; }
H() { hyprctl -i "$HYPRLAND_INSTANCE_SIGNATURE" "$@"; }
state() { H monitors all -j | python3 -I -c 'import json,sys; print(" ".join(f"{m["name"]}:{int(m["disabled"])}" for m in sorted(json.load(sys.stdin), key=lambda m: m["name"])))'; }
border() { echo "$(H getoption general:col.active_border | head -1) / $(H getoption general:col.inactive_border | head -1)"; }

expect "start: both outputs on" "DP-1:0 eDP-1:0" "$(state)"
expect "seed borders" "gradient data: ff00f0ff ffff2e88 45deg / gradient data: ff1b1d30 0deg" "$(border)"
[[ "$(H eval 'hl.monitor({ output = "eDP-1", disabled = true })')" == ok ]]; sleep 1
expect "eDP-1 disabled (as lid close does)" "DP-1:0 eDP-1:1" "$(state)"

img="$tmp/tide.png"
python3 -I - "$img" <<'PY'
import struct, sys, zlib
w, h = 64, 36
raw = b"".join(b"\x00" + b"".join(bytes((10 + x, 40 + y, 200)) for x in range(w)) for y in range(h))
ck = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + ck(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                              + ck(b"IDAT", zlib.compress(raw)) + ck(b"IEND", b""))
PY
lua0=$(sha1sum <"$cfg/colors.lua")
out=$(env -u RICE_NO_RELOAD HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    XDG_STATE_HOME="$home/.local/state" XDG_DATA_HOME="$home/.local/share" PATH="$tmp/stubs:$PATH" \
    "$home/.local/bin/rice-palette" apply "$img" 2>&1) && rc=0 || rc=$?
expect "rice-palette apply exit" 0 "$rc"
[[ -z "$out" ]] || echo "   apply said: $out"
[[ "$(sha1sum <"$cfg/colors.lua")" != "$lua0" ]] && echo "PASS colors.lua rewritten with the new palette" \
    || { echo "FAIL colors.lua unchanged"; fails=$((fails + 1)); }
expect "kitty recolour went to the FAKE pkill" "pkill -USR1 -x kitty" "$(cat "$tmp/pkill.log" 2>/dev/null)"
sleep 4   # give any autoreload time to happen
expect "eDP-1 still disabled after the apply" "DP-1:0 eDP-1:1" "$(state)"
a1=$(python3 -I -c 'import json,sys; t=json.load(open(sys.argv[1])); print(" ".join("ff"+t[k][1:] for k in ("a1","a2","line")))' "$home/.config/quickshell/colors.json")
read -r ca1 ca2 cline <<<"$a1"
want="gradient data: $ca1 $ca2 45deg / gradient data: $cline 0deg"
expect "running borders recoloured to the new palette" "$want" "$(border)"
# The shim logged every hyprctl call of the apply: it must have recoloured (eval) and
# must not have reloaded.
grep -q '^hyprctl eval ' "$tmp/hyprctl.log" 2>/dev/null && echo "PASS the apply's hyprctl calls went through the logging shim (eval seen)" \
    || { echo "FAIL no hyprctl eval logged by the shim: '$(cat "$tmp/hyprctl.log" 2>/dev/null)'"; fails=$((fails + 1)); }
grep -qE '^hyprctl (.* )?reload( |$)' "$tmp/hyprctl.log" 2>/dev/null && { echo "FAIL a reload was attempted: $(grep reload "$tmp/hyprctl.log")"; fails=$((fails + 1)); } \
    || echo "PASS no hyprctl reload during the apply"

H reload >/dev/null; sleep 1
expect "explicit reload (lid open) re-enables eDP-1" "DP-1:0 eDP-1:0" "$(state)"
expect "and reads the same colours back from colors.lua" "$want" "$(border)"

if [[ $fails -eq 0 ]]; then echo "PALETTE_LID OK"; else echo "PALETTE_LID FAILED ($fails)"; exit 1; fi
