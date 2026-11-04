#!/usr/bin/env bash
# FAKE nvidia-smi for the U15 tests (never the real one). selftest-qs.sh copies it to
# <tmp>/nvbin/nvidia-smi and puts that directory first on PATH. Every start appends
#   start <pid> <epoch ms> <args...>
# to $FAKE_NV_LOG, so a test can count starts and check PIDs. Behaviour:
#   FAKE_NV_MODE=stream (default)  print $FAKE_NV_LINE every $FAKE_NV_INTERVAL s, forever
#   FAKE_NV_MODE=exit              print an error to stderr and exit 9 at once
#   FAKE_NV_MODE=die               print $FAKE_NV_LINE $FAKE_NV_COUNT times, then exit 1
# FAKE_NV_LINE defaults to "42, 1536, 4096" (utilization %, used MiB, total MiB).
set -u
log="${FAKE_NV_LOG:-/dev/null}"
line="${FAKE_NV_LINE:-42, 1536, 4096}"
interval="${FAKE_NV_INTERVAL:-1}"
echo "start $$ $(date +%s%3N) $*" >>"$log"
case "${FAKE_NV_MODE:-stream}" in
    exit)
        echo "NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver (fake)" >&2
        exit 9 ;;
    die)
        for ((i = 0; i < ${FAKE_NV_COUNT:-2}; i++)); do
            echo "$line"
            sleep "$interval"
        done
        exit 1 ;;
    *)
        while :; do
            echo "$line"
            sleep "$interval"
        done ;;
esac
