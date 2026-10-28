#!/usr/bin/env bash
# Start a coding agent (claude / codex / ...) in a new sibling Herdr pane.
# Splits next to the current pane (or --pane) without taking focus, waits
# for the new shell to be idle, runs `herdr agent start`, then reads the
# pane back and checks that the expected agent kind runs in the expected cwd.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: spawn-agent.sh --kind KIND [--cwd DIR] [--session NAME] [--pane TARGET]
                      [--direction right|down] [--name NAME] [--focus]
                      [--shell-timeout MS] [--timeout MS] [--json]
                      [-- AGENT_ARGS...]

  --kind KIND         claude, codex, ... (any kind `herdr agent` lists)
  --cwd DIR           working directory of the new pane (default: $PWD)
  --session NAME      herdr session (pass explicitly; HERDR_SESSION does not
                      switch sessions inside a pane). Requires --pane.
  --pane TARGET       pane to split next to (default: the calling pane)
  --direction DIR     right or down (default: right when the pane is wide,
                      down when it is narrow or tall)
  --name NAME         live agent name, [a-z][a-z0-9_-]{0,31}
                      (default: KIND-N, the first free N)
  --focus             focus the new pane (default: keep focus where it is)
  --shell-timeout MS  wait this long for the new shell to be idle (default: 15000)
  --timeout MS        `herdr agent start` readiness timeout, 3001..300000
                      (default: herdr's 30000)
  --json              print the result as JSON instead of the bare pane_id
  -- AGENT_ARGS...    native agent arguments passed through to the agent

exit: 0 started and verified, 1 herdr command failed (split / agent start),
      2 usage or validation error, 3 the new shell never became idle,
      4 agent started but read-back did not match the kind or cwd
USAGE
  exit 2
}

die() { echo "error: $1" >&2; exit "${2:-2}"; }

kind="" cwd="" session="" pane="" direction="" name="" focus=--no-focus
shell_timeout=15000 start_timeout="" mode=pane agent_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --kind) kind="${2:?}"; shift ;;
    --cwd) cwd="${2:?}"; shift ;;
    --session) session="${2:?}"; shift ;;
    --pane) pane="${2:?}"; shift ;;
    --direction) direction="${2:?}"; shift ;;
    --name) name="${2:?}"; shift ;;
    --focus) focus=--focus ;;
    --shell-timeout) shell_timeout="${2:?}"; shift ;;
    --timeout) start_timeout="${2:?}"; shift ;;
    --json) mode=json ;;
    -h | --help) usage ;;
    --) shift; agent_args=("$@"); break ;;
    *) echo "error: unknown argument: $1" >&2; usage ;;
  esac
  shift
done

command -v jq >/dev/null || die "jq is required"
herdr="${HERDR_BIN_PATH:-herdr}"
h() { "$herdr" ${session:+--session "$session"} "$@"; }

[ -n "$kind" ] || die "--kind is required"
# `herdr agent` prints its group help (with the kinds line) to stderr, exit 2.
kinds=$({ "$herdr" agent 2>&1 || true; } | sed -n 's/^ *kinds: *//p' | tr '|' ' ')
if [ -n "$kinds" ] && [[ " $kinds " != *" $kind "* ]]; then
  die "unknown kind '$kind' (herdr knows: $kinds)"
fi
case "$direction" in "" | right | down) ;; *) die "--direction must be right or down" ;; esac
[[ "$shell_timeout" =~ ^[0-9]+$ ]] || die "--shell-timeout must be milliseconds"
# herdr 0.9.5 rejects agent start timeouts <= 3000 or > 300000 (invalid_agent_timeout).
if [ -n "$start_timeout" ] && { ! [[ "$start_timeout" =~ ^[0-9]+$ ]] ||
  [ "$start_timeout" -le 3000 ] || [ "$start_timeout" -gt 300000 ]; }; then
  die "--timeout must be milliseconds in 3001..300000"
fi
if [ -n "$name" ] && ! [[ "$name" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
  die "--name must match [a-z][a-z0-9_-]{0,31}"
fi
cwd="${cwd:-$PWD}"
[ -d "$cwd" ] || die "--cwd is not a directory: $cwd"
cwd=$(cd "$cwd" && pwd)
cwd_physical=$(cd "$cwd" && pwd -P)

# Pane ids are unique only within a session, so the calling pane is only a
# valid default when we stay in the caller's own session.
if [ -n "$pane" ]; then
  target=(--pane "$pane")
elif [ -n "$session" ]; then
  die "--session needs an explicit --pane (pane ids are per session)"
elif [ -n "${HERDR_PANE_ID:-}" ]; then
  target=(--current)
else
  die "not inside a Herdr pane; pass --pane (and --session)"
fi

agents=$(h agent list) || die "herdr agent list failed" 1
if [ -z "$name" ]; then
  n=1
  while jq -e --arg n "$kind-$n" 'any(.result.agents[]; .name == $n)' <<<"$agents" >/dev/null; do
    n=$((n + 1))
  done
  name="$kind-$n"
elif jq -e --arg n "$name" 'any(.result.agents[]; .name == $n)' <<<"$agents" >/dev/null; then
  die "agent name '$name' is already live"
fi

# Wide panes split right, narrow or tall ones split down (cells are ~1:2).
if [ -z "$direction" ]; then
  layout=$(h pane layout "${target[@]}") || die "herdr pane layout failed" 1
  direction=$(jq -r --arg p "${pane:-${HERDR_PANE_ID:-}}" '.result.layout as $l
    | (first($l.panes[] | select(.pane_id == $p)) // first($l.panes[]) | .rect)
    | if .width >= 2 * .height then "right" else "down" end' <<<"$layout")
fi

split=$(h pane split "${target[@]}" --direction "$direction" --cwd "$cwd" "$focus") ||
  die "herdr pane split failed" 1
new_pane=$(jq -r '.result.pane.pane_id' <<<"$split")
[ -n "$new_pane" ] && [ "$new_pane" != null ] || die "pane split returned no pane id" 1

# The shell is idle once it owns the foreground process group (no rc-file
# command, no TUI running). `agent start` refuses anything else.
tries=$((shell_timeout / 200 + 1))
until info=$(h pane process-info --pane "$new_pane") &&
  jq -e '.result.process_info | .foreground_process_group_id == .shell_pid' <<<"$info" >/dev/null; do
  tries=$((tries - 1))
  if [ "$tries" -le 0 ]; then
    echo "error: shell in $new_pane not idle after ${shell_timeout}ms; pane left open" >&2
    exit 3
  fi
  sleep 0.2
done

start=(agent start "$name" --kind "$kind" --pane "$new_pane")
[ -z "$start_timeout" ] || start+=(--timeout "$start_timeout")
[ "${#agent_args[@]}" -eq 0 ] || start+=(-- "${agent_args[@]}")
# The shell can own the foreground before its prompt is drawn; herdr then
# answers agent_pane_busy, so retry that one error within the shell timeout.
while ! err=$(h "${start[@]}" 2>&1 >/dev/null); do
  tries=$((tries - 1))
  if [[ "$err" != *agent_pane_busy* ]] || [ "$tries" -le 0 ]; then
    echo "$err" >&2
    echo "error: herdr agent start failed in $new_pane; pane left open" >&2
    exit 1
  fi
  sleep 0.2
done

# Read back instead of trusting the start response.
agents=$(h agent list) || die "herdr agent list failed" 1
info=$(h pane process-info --pane "$new_pane") || die "herdr pane process-info failed" 1
result=$(jq -n --arg session "$session" --arg pane "$new_pane" --arg name "$name" \
  --arg direction "$direction" --argjson a "$agents" --argjson i "$info" '
  ($a.result.agents[] | select(.pane_id == $pane)) as $ag
  | {session: (if $session == "" then null else $session end),
     pane_id: $pane, name: ($ag.name // null), kind: ($ag.agent // null),
     status: ($ag.agent_status // null), cwd: ($ag.foreground_cwd // $ag.cwd // null),
     workspace_id: ($ag.workspace_id // null), tab_id: ($ag.tab_id // null),
     direction: $direction,
     processes: [$i.result.process_info.foreground_processes[] | {pid, cmdline, cwd}]}
  ' 2>/dev/null) || result=""
if [ -z "$result" ]; then
  echo "error: no agent found in $new_pane after start" >&2
  exit 4
fi
if ! jq -e --arg kind "$kind" --arg c "$cwd" --arg cp "$cwd_physical" '
  .kind == $kind and (.cwd == $c or .cwd == $cp)' <<<"$result" >/dev/null; then
  echo "error: read-back of $new_pane does not match --kind $kind / --cwd $cwd:" >&2
  jq -c . <<<"$result" >&2
  exit 4
fi

if [ "$mode" = json ]; then jq . <<<"$result"; else echo "$new_pane"; fi
