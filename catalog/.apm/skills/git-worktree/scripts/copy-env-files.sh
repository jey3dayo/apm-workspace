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

wt_abs=$(cd -P "$wt" && pwd -P)
src_abs=$(cd -P "$src" && pwd -P)
if [ "$wt_abs" = "$src_abs" ]; then
  echo "error: source and destination are the same checkout: $src_abs" >&2
  exit 1
fi
if ! source_root=$(git -C "$src_abs" rev-parse --show-toplevel 2>/dev/null); then
  echo "error: source is not a Git checkout: $src_abs" >&2
  exit 1
fi
source_root_abs=$(cd -P "$source_root" && pwd -P)
if [ "$source_root_abs" != "$src_abs" ]; then
  echo "error: source must be a checkout root: $src_abs" >&2
  exit 1
fi

ensure_destination_parent_is_safe() {
  local rel="$1"
  local parent_rel
  local current="$wt_abs"
  local component

  case "$rel" in
    */*) parent_rel="${rel%/*}" ;;
    *) return 0 ;;
  esac
  while [ -n "$parent_rel" ]; do
    case "$parent_rel" in
      */*)
        component="${parent_rel%%/*}"
        parent_rel="${parent_rel#*/}"
        ;;
      *)
        component="$parent_rel"
        parent_rel=""
        ;;
    esac
    case "$component" in
      "" | .) continue ;;
      .git | .worktrees | node_modules | .pnpm-store | target | dist) return 1 ;;
    esac
    current="$current/$component"
    if [ -L "$current" ]; then
      return 1
    fi
    if [ -e "$current" ]; then
      [ -d "$current" ] || return 2
    else
      mkdir "$current" || return 2
    fi
    [ ! -e "$current/.git" ] || return 1
  done
}

copied=0
candidate_list=$(mktemp "${TMPDIR:-/tmp}/copy-env-files.XXXXXX")
trap 'rm -f "$candidate_list"' EXIT
if ! find "$src_abs" -mindepth 1 \
  \( -type d \( \
    -name .git -o \
    -name .worktrees -o \
    -name node_modules -o \
    -name .pnpm-store -o \
    -name target -o \
    -name dist -o \
    -exec test -e '{}/.git' \; \
  \) -prune \) -o \
  \( -type f \( -name .env -o -name .env.local -o -name .env.keys \) -print0 \) >"$candidate_list"; then
  echo "error: failed to scan source checkout for env files" >&2
  exit 1
fi

while IFS= read -r -d '' source_file; do
  rel="${source_file#"$src_abs"/}"
  if git --literal-pathspecs -C "$src_abs" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
    continue
  else
    git_status=$?
    if [ "$git_status" -ne 1 ]; then
      echo "error: failed to inspect source env path: $rel" >&2
      exit "$git_status"
    fi
  fi
  if [ -L "$source_file" ]; then
    echo "skipped unsafe path: $rel" >&2
    continue
  fi
  if ensure_destination_parent_is_safe "$rel"; then
    :
  else
    destination_path_status=$?
    if [ "$destination_path_status" -eq 1 ]; then
      echo "skipped unsafe path: $rel" >&2
      continue
    fi
    echo "error: destination directory unavailable for env path: $rel" >&2
    exit 1
  fi
  dest_file="$wt_abs/$rel"
  if [ -L "$dest_file" ] || { [ -e "$dest_file" ] && [ ! -f "$dest_file" ]; }; then
    echo "skipped unsafe path: $rel" >&2
    continue
  fi
  cp -p "$source_file" "$dest_file"
  copied=$((copied + 1))
  echo "copied: $rel"
done <"$candidate_list"

echo "done: $copied file(s) copied from $src_abs to $wt_abs"
