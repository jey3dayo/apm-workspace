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

# 存在確認と同時に絶対パスへ代入する。代入しないまま後段で cd すると、
# AGMSG_CLAUDE_BIN に相対パスが渡された場合に cwd 基準の確認だけ通過して
# 起動時に解決できなくなる。PATH 名 `claude` も同じ経路で絶対化される。
claude_bin=${AGMSG_CLAUDE_BIN:-claude}
if ! claude_bin=$(command -v -- "$claude_bin"); then
	printf 'Claude executable not found: %s\n' "$claude_bin" >&2
	exit 1
fi

# `command -v` は PATH 名を絶対化するが、スラッシュを含む引数はそのまま返す。
# 相対のままだと後段の cd で解決できなくなるので payload_file と同じ正規化を通す。
if [[ "$claude_bin" != /* ]]; then
	claude_bin=$(cd -- "$(dirname -- "$claude_bin")" && printf '%s/%s\n' "$PWD" "$(basename -- "$claude_bin")")
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
	"$(cd -- "$HOME/.claude" && pwd -P)"
	"$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
	# Claude Code の Bash tool scratchpad は TMPDIR と無関係に /private/tmp/claude-<uid>/
	# 配下に作られる。launchd 配下では TMPDIR が /var/folders を指すため、/tmp を
	# 明示allowしないと worker の全 Bash 呼び出しが scratchpad mkdir の EPERM で死ぬ
	"$(cd -- /tmp && pwd -P)"
)

for state_path in \
	"$HOME/.agents/skills/agmsg/db" \
	"$HOME/.agents/skills/agmsg/teams" \
	"$HOME/.agents/skills/agmsg/run"; do
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
# worker は対象 project を cwd として開始する。launchd 配下の cwd は repo 外なので、
# ここで移らないと worker が相対パスを解決できない（実運用で reviewer が repo 外から
# 始まり relative path が繰り返し No such file になった）。profile・mcp_config・payload
# はいずれも絶対パスなので cwd 変更の影響を受けない。
cd -- "$project"

sandbox-exec -f "$profile" "$claude_bin" "${claude_args[@]}" <"$payload_file"
