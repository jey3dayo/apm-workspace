#!/usr/bin/env bash
# Summarize every Herdr agent by the last `STATUS: <stage> | <note>` line in its pane.
# Read-only: it only calls find-agent.sh --json, `session list`, `pane current` and `pane read`.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: herd-status.sh [--lines N] [--json]

  --lines N  pane tail lines to scan for the STATUS line (default: 80)
  --json     print the classified agents as a JSON array instead of Markdown

A pane that cannot be read does not fail the run: exit 0, and its row reads "読み取り失敗" (partial result).
USAGE
  exit 2
}

lines=80 mode=md
while [ $# -gt 0 ]; do
  case "$1" in
    --lines) lines="${2:?}"; shift ;;
    --json) mode=json ;;
    -h | --help) usage ;;
    *) echo "error: unknown argument: $1" >&2; usage ;;
  esac
  shift
done
case "$lines" in '' | *[!0-9]* | 0) echo "error: --lines needs a positive integer" >&2; usage ;; esac

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 2; }

# stdin: pane text. stdout: {"stage": <stage or null>, "text": <note>} from the last STATUS line with a known stage.
parse_status() {
  jq -Rs '
    ["判断待ち", "CI待ち", "作業中", "完了", "停止"] as $stages
    | def trim: sub("^[\\s│┃]+"; "") | sub("[\\s│┃]+$"; "");
    [split("\n")[]
      | capture("^[^\\p{L}\\p{N}]*STATUS:(?<rest>.*)$")
      | (.rest | split("|")) as $parts
      | select($parts | length > 1)
      | {stage: ($parts[0] | trim), text: ($parts[1:] | join("|") | trim)}
      | select(.stage as $s | $stages | index($s))]
    | last // {stage: null, text: ""}'
}

classify_and_render() {
  jq -r --arg mode "$mode" '
    def esc: gsub("\\|"; "\\|");
    def previous: if .prev.stage then "前回: \(.prev.stage) \(.prev.text)" | sub("\\s+$"; "") else null end;
    def classified:
      if .read_failed then {stage: "STATUS なし", text: "読み取り失敗"}
      elif .agent_status == "working" then {stage: "作業中", text: (previous // "")}
      elif .agent_status == "blocked" then
        {stage: "判断待ち", text: ("承認・質問ダイアログ" + (if .prev.stage then "（\(.prev.stage) \(.prev.text)）" else "" end))}
      elif (.agent_status == "idle" or .agent_status == "done") and .prev.stage then
        {stage: .prev.stage, text: .prev.text}
      else {stage: "STATUS なし", text: (.agent_status + (if .prev.stage then "（\(previous)）" else "" end))}
      end;
    map(. + classified | del(.prev, .read_failed)) as $agents
    | if $mode == "json" then $agents
      else
        ["判断待ち", "CI待ち", "作業中", "停止", "完了", "STATUS なし"][] as $stage
        | [$agents[] | select(.stage == $stage)] | select(length > 0)
        | "**\($stage)**\n\n| workspace | pane | 内容 |\n| --- | --- | --- |",
          (.[] | "| \(.workspace | esc) | \((if (.title // "") == "" then .kind else .title end) | esc) | \(if .text == "" then "-" else .text | esc end) |"),
          ""
      end' <<<"$1"
}

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
herdr="${HERDR_BIN_PATH:-herdr}"

if agents=$("$here/find-agent.sh" --json); then :; else
  rc=$?
  jq -e 'type == "array" and length == 0' <<<"$agents" >/dev/null 2>&1 || {
    echo "error: find-agent.sh failed (exit $rc)" >&2
    exit "$rc"
  }
fi

if [ -n "${HERDR_PANE_ID:-}" ]; then
  session_list=$("$herdr" session list --json)
  current=$(jq -r --arg sock "${HERDR_SOCKET_PATH-}" --arg socket_set "${HERDR_SOCKET_PATH+x}" \
    --arg session_env "${HERDR_SESSION:-}" '
    if $socket_set != "" then
      .sessions[] | select(.socket_path == $sock) | .name
    elif $session_env != "" then
      $session_env
    else
      .sessions[] | select(.default) | .name
    end' <<<"$session_list")
  if [ -z "$current" ] || [[ "$current" == *$'\n'* ]]; then
    echo "error: could not resolve a unique current session; refusing to list without excluding this pane" >&2
    exit 2
  fi
  # HERDR_PANE_ID goes stale when the pane moves to another workspace.
  if ! self_pane=$("$herdr" pane current --current | jq -er '.result.pane.pane_id'); then
    echo "error: could not resolve the current pane (herdr pane current --current)" >&2
    exit 2
  fi
  agents=$(jq --arg pane "$self_pane" --arg cur "$current" \
    'map(select((.pane_id == $pane and .session == $cur) | not))' <<<"$agents")
fi

if [ "$(jq length <<<"$agents")" -eq 0 ]; then
  [ "$mode" = json ] && echo "[]" || echo "agent なし"
  exit 0
fi

rows="[]"
while IFS= read -r agent; do
  session=$(jq -r .session <<<"$agent")
  pane=$(jq -r .pane_id <<<"$agent")
  read_failed=false prev='{"stage": null, "text": ""}'
  if text=$("$herdr" --session "$session" pane read "$pane" --source recent-unwrapped --lines "$lines" </dev/null); then
    prev=$(parse_status <<<"$text")
  else
    echo "warning: could not read pane $pane in session '$session'; skipped" >&2
    read_failed=true
  fi
  rows=$(jq --argjson a "$agent" --argjson prev "$prev" --argjson failed "$read_failed" \
    '. + [$a | {session, pane_id, workspace, title, kind, agent_status: .status, prev: $prev, read_failed: $failed}]' <<<"$rows")
done < <(jq -c '.[]' <<<"$agents")

classify_and_render "$rows"
