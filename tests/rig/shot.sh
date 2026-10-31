#!/usr/bin/env bash
# Screenshot one output of the nested compositor: shot.sh <output-name> <file.png>
set -euo pipefail
[[ $# -eq 2 ]] || { echo "usage: shot.sh <output-name> <file.png>" >&2; exit 2; }
# shellcheck source=tests/rig/rig_env.sh
source "$(dirname "$(realpath "$0")")/rig_env.sh"
grim -o "$1" "$2"
[[ -s "$2" ]] || { echo "shot.sh: $2 is empty" >&2; exit 1; }
echo "$2"
