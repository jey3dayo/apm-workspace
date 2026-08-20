#!/usr/bin/env bash
# Copy ignored/untracked env files (.env, .env.local, .env.keys) from a source
# checkout into a worktree. Covers worktrees where wt.copy did not run.
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <worktree-path> [source-checkout-path]" >&2
  exit 2
}

wt="${1:-}"
[ -n "$wt" ] || usage
[ -d "$wt" ] || { echo "error: worktree not found: $wt" >&2; exit 1; }

# Default source: the main worktree of the same repository.
src="${2:-$(git -C "$wt" worktree list --porcelain | awk '/^worktree /{print $2; exit}')}"
[ -d "$src" ] || { echo "error: source checkout not found: $src" >&2; exit 1; }

wt_abs=$(cd "$wt" && pwd)
src_abs=$(cd "$src" && pwd)
if [ "$wt_abs" = "$src_abs" ]; then
  echo "error: source and destination are the same checkout: $src_abs" >&2
  exit 1
fi

copied=0
while IFS= read -r rel; do
  case "$(basename "$rel")" in
    .env | .env.local | .env.keys) ;;
    *) continue ;;
  esac
  mkdir -p "$wt_abs/$(dirname "$rel")"
  cp -p "$src_abs/$rel" "$wt_abs/$rel"
  copied=$((copied + 1))
  echo "copied: $rel"
done < <(
  git -C "$src_abs" ls-files --others --ignored --exclude-standard
  git -C "$src_abs" ls-files --others --exclude-standard
)

echo "done: $copied file(s) copied from $src_abs to $wt_abs"
