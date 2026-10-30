#!/usr/bin/env bash
# Find coding agents (claude / codex / ...) running in Herdr, across every
# running named session. Read-only: it only calls `session list`,
# `workspace list` and `agent list`.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: find-agent.sh [QUERY] [--session NAME] [--kind KIND] [--status STATUS]
                     [--repo TEXT] [--title TEXT] [--name NAME] [-q | --json]

  QUERY           agent session id (full or prefix), herdr session name, or agent name
  --session NAME  only this herdr session (default: every running session)
  --kind KIND     claude, codex, ...
  --status STATUS idle, working, blocked, done, unknown
  --repo TEXT     substring of cwd / foreground_cwd (alias: --cwd)
  --title TEXT    substring of the terminal title (case-insensitive)
  --name NAME     live agent name
  -q              print only the pane_id; exit 1 if none match, 3 if ambiguous
  --json          print the matches as a JSON array
USAGE
  exit 2
}

query="" session="" kind="" status="" repo="" title="" name="" mode=table
while [ $# -gt 0 ]; do
  case "$1" in
    --session) session="${2:?}"; shift ;;
    --kind) kind="${2:?}"; shift ;;
    --status) status="${2:?}"; shift ;;
    --repo | --cwd) repo="${2:?}"; shift ;;
    --title) title="${2:?}"; shift ;;
    --name) name="${2:?}"; shift ;;
    -q | --pane-id-only) mode=pane ;;
    --json) mode=json ;;
    -h | --help) usage ;;
    -*) echo "error: unknown option: $1" >&2; usage ;;
    *) [ -z "$query" ] || usage; query="$1" ;;
  esac
  shift
done

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 2; }
herdr="${HERDR_BIN_PATH:-herdr}"

# --session beats HERDR_SOCKET_PATH, so each session is addressed explicitly.
session_list=$("$herdr" session list --json)
sessions=$(jq -r '.sessions[] | select(.running) | .name' <<<"$session_list")
current=$(jq -r --arg sock "${HERDR_SOCKET_PATH-}" --arg socket_set "${HERDR_SOCKET_PATH+x}" \
  --arg session_env "${HERDR_SESSION:-}" '
  if $socket_set != "" then
    .sessions[] | select(.socket_path == $sock) | .name
  elif $session_env != "" then
    $session_env
  else
    .sessions[] | select(.default) | .name
  end' <<<"$session_list")

rows="[]"
for s in $sessions; do
  [ -z "$session" ] || [ "$s" = "$session" ] || continue
  if ! agents=$("$herdr" --session "$s" agent list) ||
    ! workspaces=$("$herdr" --session "$s" workspace list); then
    echo "error: session '$s' did not answer; results are incomplete" >&2
    exit 2
  fi
  rows=$(jq -n --arg s "$s" --argjson acc "$rows" \
    --argjson a "$agents" --argjson w "$workspaces" '
    ($w.result.workspaces | map({(.workspace_id): .label}) | add // {}) as $labels
    | $acc + [$a.result.agents[] | {
        session: $s,
        pane_id,
        kind: .agent,
        status: .agent_status,
        name: (.name // null),
        workspace: ($labels[.workspace_id] // .workspace_id),
        cwd: (.foreground_cwd // .cwd),
        _repo_cwd: .cwd,
        title: (.terminal_title_stripped // null),
        agent_session: (.agent_session.value // null)
      }]')
done

matches=$(jq --arg q "$query" --arg kind "$kind" --arg status "$status" \
  --arg repo "$repo" --arg title "$title" --arg name "$name" '
  def has($v; $t): ($t == "") or (($v // "") | ascii_downcase | contains($t | ascii_downcase));
  [.[] | select(
    ($q == "" or .session == $q or .name == $q
      or ((.agent_session // "") | startswith($q)))
    and ($kind == "" or .kind == $kind)
    and ($status == "" or .status == $status)
    and ($name == "" or .name == $name)
    and (has(.cwd; $repo) or has(._repo_cwd; $repo))
    and has(.title; $title)
  ) | del(._repo_cwd)]' <<<"$rows")
count=$(jq length <<<"$matches")

case "$mode" in
  json) jq . <<<"$matches" ;;
  pane)
    if [ "$count" -ne 1 ]; then
      echo "error: $count agents match; narrow the query" >&2
      [ "$count" -eq 0 ] && exit 1 || exit 3
    fi
    jq -r '.[0].pane_id' <<<"$matches"
    # Pane ids are per session, and HERDR_SESSION loses to HERDR_SOCKET_PATH
    # inside a pane, so another session needs an explicit --session.
    jq -r --arg cur "$current" '.[0] | select(.session != $cur)
      | "note: in session \(.session); use: herdr --session \(.session) agent ..."' \
      <<<"$matches" >&2
    ;;
  table)
    jq -r --arg home "$HOME" '
      ["SESSION", "PANE", "KIND", "STATUS", "NAME", "WORKSPACE", "CWD", "TITLE", "AGENT_SESSION"],
      (.[] | [.session, .pane_id, .kind, .status, .name, .workspace,
        (.cwd | if startswith($home) then "~" + .[($home | length):] else . end),
        .title, .agent_session] | map(. // "-"))
      | @tsv' <<<"$matches" | if command -v column >/dev/null; then
      column -t -s "$(printf '\t')"
    else cat; fi
    ;;
esac
[ "$count" -gt 0 ]
