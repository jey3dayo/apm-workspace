#!/usr/bin/env bash
# Optional X search through the xAI Responses API (x_search tool).
# Runs only when XAI_API_KEY is available. If it is unset, the script re-runs itself once
# through `dotenvx run` with ${XDG_CONFIG_HOME:-~/.config}/.env.secrets (when that file is
# readable and dotenvx exists). If the key is still empty, it exits 2 without calling
# anything, and the caller falls back to site:x.com / site:twitter.com web search.
# Usage: x-search.sh "<question>" [--handles a,b] [--from YYYY-MM-DD] [--to YYYY-MM-DD]
# --from and --to are both inclusive (UTC days); --to is sent to the API as the next day
# because xAI's to_date is an exclusive bound.
# Env: XAI_API_KEY (required), XAI_MODEL (default grok-4.7), XAI_MAX_TURNS (default 2)
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
env_secrets="${config_home}/.env.secrets"
if [ -z "${XAI_API_KEY:-}" ] && [ -z "${_XSEARCH_SECRETS_TRIED:-}" ] && [ -r "$env_secrets" ] && command -v dotenvx >/dev/null 2>&1; then
  export _XSEARCH_SECRETS_TRIED=1
  export DOTENV_PRIVATE_KEY_PATH="${config_home}/.env.keys"
  exec dotenvx run --quiet -f "$env_secrets" -- "$0" "$@"
fi

if [ -z "${XAI_API_KEY:-}" ]; then
  exit 2
fi

query="${1:-}"
[ -n "$query" ] || { echo "usage: x-search.sh \"<question>\" [--handles a,b] [--from YYYY-MM-DD] [--to YYYY-MM-DD]" >&2; exit 64; }
shift
handles="" from="" to=""
while [ $# -gt 0 ]; do
  case "$1" in
    --handles) handles="${2:-}"; shift 2 ;;
    --from) from="${2:-}"; shift 2 ;;
    --to) to="${2:-}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

if [ -n "$to" ]; then
  to=$(date -j -v+1d -f %Y-%m-%d "$to" +%Y-%m-%d 2>/dev/null || date -u -d "$to +1 day" +%Y-%m-%d 2>/dev/null) || {
    echo "invalid --to date (want YYYY-MM-DD)" >&2
    exit 64
  }
fi

body=$(jq -n \
  --arg model "${XAI_MODEL:-grok-4.7}" \
  --arg q "$query" \
  --arg handles "$handles" \
  --arg from "$from" \
  --arg to "$to" \
  --argjson turns "${XAI_MAX_TURNS:-2}" '
  {model: $model, input: $q, max_turns: $turns,
   tools: [({type: "x_search"}
     + (if $handles != "" then {allowed_x_handles: ($handles | split(",") | map(ltrimstr("@")))} else {} end)
     + (if $from != "" then {from_date: $from} else {} end)
     + (if $to != "" then {to_date: $to} else {} end))]}')

# The key goes to curl through a process-substituted header file so it never appears in argv.
if ! resp=$(curl -sS --fail-with-body --max-time 120 https://api.x.ai/v1/responses \
  -H "Content-Type: application/json" \
  -H @<(printf 'Authorization: Bearer %s\n' "$XAI_API_KEY") \
  -d "$body"); then
  echo "x_search request failed; fall back to site:x.com search" >&2
  exit 1
fi

printf '%s\n' "$resp" | jq -r '
  "## Answer",
  ([.output[]? | select(.type == "message") | .content[]? | .text? // empty] | join("\n")),
  "",
  ([.output[]? | .content[]? | .annotations[]? | .url? // empty] | unique) as $cited
  | "## Cited in answer",
  ($cited[] | "- " + .),
  "",
  "## Other URLs encountered (not cited in the answer)",
  ([.citations[]? | if type == "string" then . else .url? // empty end] | unique - $cited | .[] | "- " + .),
  "",
  "x_posts_fetched: \(.usage.server_side_tool_usage_details.x_posts_fetched // "unknown")",
  "x_users_fetched: \(.usage.server_side_tool_usage_details.x_users_fetched // "unknown")"'
