#!/usr/bin/env bash
# Stage the deployed layout of this repo into a throwaway HOME, using chezmoi's own
# naming rules (dot_, executable_, create_), without touching the real HOME or the
# real chezmoi state:
#   stage.sh <dest-dir>      -> prints <dest-dir> (absolute) on success
#
# Staged targets: ~/.config/quickshell, ~/.local/bin, ~/.local/share/rice.
# chezmoi runs with an empty config file, its persistent state and cache inside
# <dest-dir>, and HOME / XDG_* pointed into <dest-dir>, so nothing is read from or
# written to ~/.config/chezmoi or ~/.cache/chezmoi. Idempotent: re-running re-applies
# the repo files (overwriting staged edits) but keeps create_ files that already exist,
# exactly like a real `chezmoi apply`. Refuses the real HOME, anything under the real
# ~/.config or ~/.local, and non-empty directories stage.sh did not create.
set -euo pipefail

die() { echo "stage.sh: $*" >&2; exit 1; }
[[ $# -eq 1 && -n "$1" ]] || die "usage: stage.sh <dest-dir>"
command -v chezmoi >/dev/null || die "chezmoi not found"

REPO="$(realpath "$(dirname "$(realpath "$0")")/../..")"
[[ -d "$REPO/dot_config/quickshell" ]] || die "repo root not found ($REPO)"

REAL_HOME="$(realpath "$(getent passwd "$(id -u)" | cut -d: -f6)")"
DEST="$(realpath -m -- "$1")"
[[ "$DEST" != "/" && "$DEST" != "$REAL_HOME" ]] || die "refusing to stage into $DEST"
case "$DEST/" in
    "$REAL_HOME/.config/"* | "$REAL_HOME/.local/"*)
        die "refusing to stage under the real ~/.config or ~/.local ($DEST)" ;;
esac
mkdir -p -- "$DEST"
if [[ ! -e "$DEST/.rice-stage" && -n "$(ls -A -- "$DEST")" ]]; then
    die "$DEST is not empty and was not created by stage.sh (no .rice-stage marker)"
fi
touch "$DEST/.rice-stage"

mkdir -p "$DEST/.config" "$DEST/.local/share" "$DEST/.local/state" "$DEST/.cache"
cfg="$DEST/.chezmoi-empty.toml"
: >"$cfg"

targets=("$DEST/.config/quickshell" "$DEST/.local/bin" "$DEST/.local/share/rice")
env HOME="$DEST" XDG_CONFIG_HOME="$DEST/.config" XDG_DATA_HOME="$DEST/.local/share" \
    XDG_STATE_HOME="$DEST/.local/state" XDG_CACHE_HOME="$DEST/.cache" \
    chezmoi --source "$REPO" --destination "$DEST" --config "$cfg" --config-format toml \
    --persistent-state "$DEST/.chezmoi-state.boltdb" --cache "$DEST/.chezmoi-cache" \
    --no-tty --no-pager --force --color false \
    apply "${targets[@]}" || die "chezmoi apply failed"

# Check what later units rely on.
for f in "$DEST/.config/quickshell/shell.qml" "$DEST/.config/quickshell/colors.json"; do
    [[ -s "$f" ]] || die "staged tree is missing $f"
done
for src in "$REPO"/dot_local/bin/executable_*; do
    [[ -e "$src" ]] || continue
    b="$DEST/.local/bin/${src##*/executable_}"
    [[ -f "$b" && -x "$b" ]] || die "staged $b is missing or not executable"
done
for src in "$REPO"/dot_local/share/rice/*.py; do
    [[ -e "$src" ]] || continue
    [[ -s "$DEST/.local/share/rice/${src##*/}" ]] || die "staged tree is missing .local/share/rice/${src##*/}"
done
echo "$DEST"
