#!/usr/bin/env bash
# Optional X search through the xAI Responses API (x_search tool).
# Runs only when XAI_API_KEY is set; otherwise exits 2 without calling anything,
# and the caller falls back to site:x.com / site:twitter.com web search.
# Usage: x-search.sh "<question>" [--handles a,b] [--from YYYY-MM-DD] [--to YYYY-MM-DD]
# Env: XAI_API_KEY (required), XAI_MODEL (default grok-4.7), XAI_MAX_TURNS (default 2)
set -euo pipefail

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
  "## Sources",
  ([.output[]? | .content[]? | .annotations[]? | .url? // empty] + [.citations[]? | if type == "string" then . else .url? // empty end] | unique | .[] | "- " + .),
  "",
  "x_posts_fetched: \(.usage.server_side_tool_usage_details.x_posts_fetched // "unknown")",
  "x_users_fetched: \(.usage.server_side_tool_usage_details.x_users_fetched // "unknown")"'
