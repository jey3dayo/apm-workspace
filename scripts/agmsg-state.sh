#!/usr/bin/env bash
set -euo pipefail

# agmsg resolves db/ and teams/ relative to its own script directory, so both
# live inside the deployed skill tree that `apm apply` rewrites wholesale —
# every deploy drops the message history and the roster, and every agent
# silently becomes unaddressable. AGMSG_STORAGE_PATH covers db/ only, and
# teams/ has no override until upstream fujibee/agmsg#285 (AGMSG_HOME) ships.
#
# Keep both outside the deploy target and re-link them after each apply, rather
# than copying back and forth: a symlink has no staleness window, so a write
# that lands between save and restore cannot be lost. Linking db/ as well means
# a shell that never picked up AGMSG_STORAGE_PATH still writes to the real
# store instead of silently starting an empty one beside it.

STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/agmsg"
SKILL_DIR="$HOME/.agents/skills/agmsg"
RUNTIME_DIRS="db teams"

# Move a runtime dir that is still a plain directory into the store, then leave
# the deploy target free for the symlink.
absorb_plain_dir() {
  local name="$1" target="$SKILL_DIR/$1" store="$STATE_ROOT/$1"
  [ -d "$target" ] && [ ! -L "$target" ] || return 0

  mkdir -p "$store"
  # -n keeps an existing store copy authoritative: a post-deploy runtime dir is
  # a freshly re-created subset, never a superset of what was already saved.
  cp -Rn "$target"/. "$store"/ 2>/dev/null || true
  rm -rf "$target"
}

case "${1:?Usage: agmsg-state.sh <save|restore>}" in
  save)
    for name in $RUNTIME_DIRS; do absorb_plain_dir "$name"; done
    ;;
  restore)
    if [ ! -d "$SKILL_DIR" ]; then
      echo "agmsg not deployed at $SKILL_DIR — skipping relink." >&2
      exit 0
    fi
    for name in $RUNTIME_DIRS; do
      mkdir -p "$STATE_ROOT/$name"
      absorb_plain_dir "$name"
      # Repoint even when a link exists, so a stale target is corrected.
      [ -L "$SKILL_DIR/$name" ] && rm -f "$SKILL_DIR/$name"
      ln -s "$STATE_ROOT/$name" "$SKILL_DIR/$name"
      echo "agmsg $name linked: $SKILL_DIR/$name -> $STATE_ROOT/$name"
    done
    ;;
  *)
    echo "Usage: agmsg-state.sh <save|restore>" >&2
    exit 1
    ;;
esac
