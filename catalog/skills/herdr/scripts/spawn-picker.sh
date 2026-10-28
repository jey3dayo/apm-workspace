#!/usr/bin/env bash
# Pick a repo (ghq) and an agent kind with fzf, then start the agent next to
# the active Herdr pane via spawn-agent.sh. Built for a `type = "popup"`
# keybinding: popups get HERDR_ACTIVE_PANE_ID / HERDR_ACTIVE_PANE_CWD (the
# tiled pane underneath) but no HERDR_PANE_ID of their own.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: spawn-picker.sh [-- SPAWN_AGENT_ARGS...]

Run from a Herdr popup keybinding. Pick a repo from `ghq list -p` (the
active pane's repo first), then a kind (claude, codex, then the other kinds
herdr knows), and run spawn-agent.sh --pane <active pane> --session <this
session> --cwd <repo> --kind <kind>. Esc cancels with exit 0. On failure the
error stays on screen until a key is pressed; the exit code is spawn-agent.sh's.
USAGE
  exit 2
}

extra=()
case "${1:-}" in
  "") ;;
  -h | --help) usage ;;
  --) shift; extra=("$@") ;;
  *) echo "error: unknown argument: $1" >&2; usage ;;
esac

herdr="${HERDR_BIN_PATH:-herdr}"
spawn="${SPAWN_AGENT_BIN:-$(dirname "${BASH_SOURCE[0]}")/spawn-agent.sh}"
fzf_opts=(--layout reverse --height 100% --no-multi)

fail() {
  echo "error: $1" >&2
  # Keep the popup open so the message can be read; tests have no tty.
  if [ -t 0 ]; then read -rsn1 -p "press any key to close" _ || true; echo; fi
  exit "${2:-1}"
}

for cmd in fzf ghq jq; do
  command -v "$cmd" >/dev/null || fail "$cmd is required" 2
done
pane="${HERDR_ACTIVE_PANE_ID:-${HERDR_PANE_ID:-}}"
[ -n "$pane" ] || fail "no active pane (run this from a Herdr keybinding)" 2
here="${HERDR_ACTIVE_PANE_CWD:-$PWD}"

# Pane ids are per session, so name the session the popup's socket belongs to.
session=$("$herdr" session list --json | jq -r --arg sock "${HERDR_SOCKET_PATH:-}" '
  first((.sessions[] | select($sock != "" and .socket_path == $sock)),
        (.sessions[] | select(.default)) | .name) // empty') ||
  fail "herdr session list failed"
[ -n "$session" ] || fail "cannot tell which herdr session this is" 2

# The repo that contains the active pane's cwd goes first.
repos=$(ghq list -p | awk -v here="$here" '
  { n = length($0)
    if ((here == $0 || substr(here, 1, n + 1) == $0 "/") && n > best) { best = n; top = $0 }
    all[NR] = $0 }
  END { if (top != "") print top
        for (i = 1; i <= NR; i++) if (all[i] != top) print all[i] }')
[ -n "$repos" ] || fail "ghq list -p returned no repositories" 2

repo=$(fzf "${fzf_opts[@]}" --prompt "repo> " --header "spawn next to $pane ($session)" <<<"$repos") ||
  exit 0

# `herdr agent` prints its group help (with the kinds line) to stderr, exit 2.
kinds=$({ "$herdr" agent 2>&1 || true; } | sed -n 's/^ *kinds: *//p' | tr '|' '\n' |
  grep -vx -e claude -e codex || true)
kind=$(printf '%s\n' claude codex "$kinds" | sed '/^$/d' |
  fzf "${fzf_opts[@]}" --prompt "kind> " --header "$repo") || exit 0

echo "starting $kind in $repo next to $pane ..."
rc=0
"$spawn" --kind "$kind" --session "$session" --pane "$pane" --cwd "$repo" \
  ${extra[@]+"${extra[@]}"} || rc=$?
[ "$rc" -eq 0 ] || fail "spawn-agent.sh exited $rc" "$rc"
