#!/usr/bin/env bash
# Private PipeWire for the rig (pipewire-rig.conf: two null sinks, a `default` metadata
# object, no hardware, no session manager), so the rail's VOLUME section can be tested
# without the owner's real audio graph:
#   fake-pipewire.sh start <dir>             start the daemon with PIPEWIRE_RUNTIME_DIR=<dir>,
#                                            rig_sink_buds as the default sink; prints <dir>
#   fake-pipewire.sh default <dir> <node.name|-->   set (or, with --, clear) the default sink
#   fake-pipewire.sh stream <dir> <app name> <volume 0..1>
#                                            an application playback stream: a lingering
#                                            null node of class Stream/Output/Audio (no
#                                            session manager links real streams here);
#                                            prints its node id
#   fake-pipewire.sh volume <dir> <id> <volume 0..1>   both channels (cubic, as wpctl)
#   fake-pipewire.sh mute <dir> <id> <true|false>
#   fake-pipewire.sh destroy <dir> <id>
#   fake-pipewire.sh pw <dir> <pw-* command...>   e.g. pw-dump
#   fake-pipewire.sh stop <dir>              stop the daemon (PID checked by its marker)
# Pass PIPEWIRE_RUNTIME_DIR=<dir> to qs (qs-run.sh inherits it) to point it here. The
# live pipewire-0 under XDG_RUNTIME_DIR is never addressed: every command below runs
# with PIPEWIRE_RUNTIME_DIR=<dir> and PIPEWIRE_REMOTE=pipewire-0 inside it.
set -euo pipefail
R="$(dirname "$(realpath "$0")")"
die() { echo "fake-pipewire: $*" >&2; exit 1; }
[[ $# -ge 2 ]] || die "usage: fake-pipewire.sh {start|default|stream|volume|mute|destroy|stop} <dir> ..."
cmd="$1"
dir="$(realpath -m -- "$2")"
shift 2
run_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[[ "$dir" != "$run_dir" && "$dir" != / ]] || die "refusing $dir (the live runtime dir)"
pw() { env PIPEWIRE_RUNTIME_DIR="$dir" PIPEWIRE_REMOTE=pipewire-0 RICE_FAKE_PW="$dir" "$@"; }
ours() { [[ "$1" =~ ^[0-9]+$ && -O "/proc/$1" ]] && tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null | grep -qxF "RICE_FAKE_PW=$dir"; }
need() { [[ -S "$dir/pipewire-0" ]] || die "no daemon in $dir"; }
cube() { python3 -I -c 'import sys; v = max(0.0, float(sys.argv[1])); print(f"{v ** 3:.6f}")' "$1"; }

case "$cmd" in
    start)
        mkdir -p "$dir"
        [[ ! -e "$dir/pipewire-0" ]] || die "$dir/pipewire-0 exists (already running?)"
        (exec env PIPEWIRE_RUNTIME_DIR="$dir" PIPEWIRE_REMOTE=pipewire-0 RICE_FAKE_PW="$dir" \
            pipewire -c "$R/pipewire-rig.conf") >"$dir/daemon.log" 2>&1 </dev/null &
        echo $! >"$dir/daemon.pid"
        for _ in $(seq 50); do [[ -S "$dir/pipewire-0" ]] && break; sleep 0.1; done
        [[ -S "$dir/pipewire-0" ]] || die "daemon did not come up ($dir/daemon.log)"
        sleep 0.3
        "$0" default "$dir" rig_sink_buds
        echo "$dir" ;;
    default)
        need
        if [[ "$1" == -- ]]; then
            pw pw-metadata -n default -d 0 default.audio.sink >/dev/null
        else
            pw pw-metadata -n default 0 default.audio.sink "{ \"name\": \"$1\" }" Spa:String:JSON >/dev/null
        fi ;;
    stream)
        need
        [[ $# -eq 2 ]] || die "usage: stream <dir> <app name> <volume>"
        n=$(($(cat "$dir/streams.n" 2>/dev/null || echo 0) + 1))
        echo "$n" >"$dir/streams.n"
        app=${1//\\/\\\\}
        app=${app//\"/\\\"}
        pw pw-cli create-node adapter "{ factory.name = support.null-audio-sink node.name = rig-app-$n media.class = Stream/Output/Audio application.name = \"$app\" audio.position = [ FL FR ] object.linger = true }" >/dev/null
        id=""
        for _ in $(seq 20); do
            id=$(pw pw-dump | python3 -I -c 'import json, sys
print(next((o["id"] for o in json.load(sys.stdin) if o["type"].endswith(":Node") and o["info"]["props"].get("node.name") == sys.argv[1]), ""))' "rig-app-$n")
            [[ -n "$id" ]] && break
            sleep 0.1
        done
        [[ -n "$id" ]] || die "stream node rig-app-$n did not appear"
        "$0" volume "$dir" "$id" "$2"
        echo "$id" ;;
    volume)
        need
        v=$(cube "$2")
        pw pw-cli set-param "$1" Props "{ channelVolumes: [ $v, $v ] }" >/dev/null ;;
    mute)
        need
        pw pw-cli set-param "$1" Props "{ mute: $2 }" >/dev/null ;;
    pw)
        need
        pw "$@" ;;
    destroy)
        need
        pw pw-cli destroy "$1" >/dev/null ;;
    stop)
        p=$(cat "$dir/daemon.pid" 2>/dev/null || true)
        if ours "$p"; then
            kill -TERM "$p" 2>/dev/null || true
            for _ in $(seq 30); do [[ -e "/proc/$p" ]] || break; sleep 0.1; done
        fi
        rm -f "$dir/daemon.pid" "$dir/streams.n" "$dir/pipewire-0" "$dir/pipewire-0.lock" ;;
    *) die "unknown command $cmd" ;;
esac
