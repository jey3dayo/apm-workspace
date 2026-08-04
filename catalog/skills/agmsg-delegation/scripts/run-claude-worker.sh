#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
	printf 'Usage: %s <implement|review> <project> <payload-file>\n' "$0" >&2
	exit 2
fi

role=$1
project=$2
payload_file=$3

if [[ "$role" != implement && "$role" != review ]]; then
	printf 'Unsupported role: %s\n' "$role" >&2
	exit 2
fi

if [[ "$role" == implement ]]; then
	model=sonnet
else
	model=fable
fi

if [[ ! -d "$project" ]]; then
	printf 'Project directory does not exist: %s\n' "$project" >&2
	exit 2
fi

if [[ ! -r "$payload_file" ]]; then
	printf 'Payload file is not readable: %s\n' "$payload_file" >&2
	exit 2
fi

if ! command -v sandbox-exec >/dev/null 2>&1; then
	printf '%s\n' 'sandbox-exec is required to enforce the Claude worker write boundary.' >&2
	exit 1
fi

claude_bin=${AGMSG_CLAUDE_BIN:-claude}
if ! command -v "$claude_bin" >/dev/null 2>&1; then
	printf 'Claude executable not found: %s\n' "$claude_bin" >&2
	exit 1
fi

project=$(cd -- "$project" && pwd -P)
payload_file=$(cd -- "$(dirname -- "$payload_file")" && printf '%s/%s\n' "$PWD" "$(basename -- "$payload_file")")
runtime_dir=$(mktemp -d)
trap 'rm -rf -- "$runtime_dir"' EXIT

profile="$runtime_dir/claude-worker.sb"
mcp_config="$runtime_dir/empty-mcp.json"
printf '%s\n' '{"mcpServers":{}}' >"$mcp_config"

escape_sb_path() {
	local value=$1
	value=${value//\\/\\\\}
	value=${value//\"/\\\"}
	printf '%s' "$value"
}

write_paths=(
	/dev
	"$(cd -- /Users/t00114/.claude && pwd -P)"
	"$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
)

for state_path in \
	/Users/t00114/.agents/skills/agmsg/db \
	/Users/t00114/.agents/skills/agmsg/teams \
	/Users/t00114/.agents/skills/agmsg/run; do
	if [[ -d "$state_path" ]]; then
		write_paths+=("$(cd -- "$state_path" && pwd -P)")
	fi
done

if [[ "$role" == implement ]]; then
	write_paths+=("$project")
fi

{
	printf '%s\n' '(version 1)' '(allow default)' '(deny file-write* (require-not (require-any'
	for write_path in "${write_paths[@]}"; do
		printf '  (subpath "%s")\n' "$(escape_sb_path "$write_path")"
	done
	printf '%s\n' ')))'
	if [[ "$role" == review ]]; then
		printf '(deny file-write* (subpath "%s"))\n' "$(escape_sb_path "$project")"
	fi
} >"$profile"

claude_args=(
	-p
	--model "$model"
	--output-format stream-json
	--verbose
	--permission-mode bypassPermissions
	--no-chrome
)

if [[ "$role" == review ]]; then
	claude_args+=(--fallback-model opus --disallowedTools Edit Write NotebookEdit)
fi

claude_args+=(--strict-mcp-config --mcp-config "$mcp_config")
sandbox-exec -f "$profile" "$claude_bin" "${claude_args[@]}" <"$payload_file"
