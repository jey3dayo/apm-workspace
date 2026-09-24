#!/usr/bin/env bash
#
# cursor-agent worker/reviewer launcher. cursor-agent reaches the same
# frontier models (claude-*, gpt-5.6-sol-xhigh) through a billing/rate pool that is
# separate from the Claude plan and Codex credits, so it can serve both
# roles: implement and review (see tmp/cursor-worker/design.md for the
# 2026-09-18 measurements this script encodes).
#
# Argument contract mirrors run-codex-worker.sh:
#   run-cursor-worker.sh <implement|review> <project> <model> <payload-file>

set -euo pipefail

if [[ $# -ne 4 ]]; then
	printf 'Usage: %s <implement|review> <project> <model> <payload-file>\n' "$0" >&2
	exit 2
fi

role=$1
project=$2
model=$3
payload_file=$4

if [[ "$role" != implement && "$role" != review ]]; then
	printf 'Unsupported role: %s\n' "$role" >&2
	exit 2
fi

# role ごとに許可する model を fail-closed で固定する。正本は orchestrator-worker
# の tier 表 (cursor 列) で、tests/run-cursor-worker.bats の drift テストが表と
# 本 allowlist の集合一致を検証する。
case "$role" in
implement) allowed_models=(claude-sonnet-5-thinking-high claude-opus-5-5-high) ;;
review) allowed_models=(claude-fable-5-1-thinking-xhigh claude-opus-5-5-high gpt-5.6-sol-xhigh) ;;
esac

model_allowed=0
for allowed in "${allowed_models[@]}"; do
	if [[ "$model" == "$allowed" ]]; then
		model_allowed=1
		break
	fi
done

if [[ "$model_allowed" -eq 0 ]]; then
	printf 'Model %s is not allowed for role %s (allowed: %s)\n' \
		"$model" "$role" "${allowed_models[*]}" >&2
	exit 2
fi

if [[ ! -d "$project" ]]; then
	printf 'Project directory does not exist: %s\n' "$project" >&2
	exit 2
fi

if [[ ! -r "$payload_file" ]]; then
	printf 'Payload file is not readable: %s\n' "$payload_file" >&2
	exit 2
fi

project=$(cd -- "$project" && pwd -P)
payload_file=$(cd -- "$(dirname -- "$payload_file")" && printf '%s/%s\n' "$PWD" "$(basename -- "$payload_file")")

runtime_dir=$(mktemp -d)
trap 'rm -rf -- "$runtime_dir"' EXIT

escape_sb_path() {
	local value=$1
	value=${value//\\/\\\\}
	value=${value//\"/\\\"}
	printf '%s' "$value"
}

write_paths=(
	/dev
	"$(cd -- "${TMPDIR:-/tmp}" && pwd -P)"
	"$(cd -- /tmp && pwd -P)"
	"$runtime_dir"
)

# agmsg は run/ を遅延生成する。sandbox 構築前に実体を用意しないと write_paths
# から落ち、起動直後の報告経路（send-report.sh）が親ディレクトリへの書込拒否で
# 失敗する。db / teams は ~/.local/state/agmsg への symlink なので mkdir -p は
# 既存パスに対する no-op になる。
for state_path in \
	"$HOME/.agents/skills/agmsg/db" \
	"$HOME/.agents/skills/agmsg/teams" \
	"$HOME/.agents/skills/agmsg/run"; do
	mkdir -p "$state_path" 2>/dev/null || true
	if [[ -d "$state_path" ]]; then
		write_paths+=("$(cd -- "$state_path" && pwd -P)")
	fi
done

# implement のときだけ対象 project を write allowlist に加える。review では
# 明示 deny する（run-claude-worker.sh の role 分岐と同じ形）。
if [[ "$role" == implement ]]; then
	write_paths+=("$project")
fi

# ~/.cursor と <project>/.cursor は全面 read 拒否する。当初案の「MCP 設定だけ塞ぐ」
# では足りなかった —— 実環境の ~/.cursor/hooks.json は beforeShellExecution /
# preToolUse / postToolUse を含む8イベントを定義しており、read を許すと worker が
# 利用者の hook をそのまま実行する。agents/ rules/ skills/ plugins/ も agent への
# 指示注入面であり、prompt_history.json / unified_repo_list.json / projects/ /
# ai-tracking/ は他 project の履歴である。全面 deny でも認証は維持されることを
# 実測済み（tmp/cursor-worker/design.md の実測表）。HOME 全体の隔離は認証ごと
# 落ちるため採らない。
read_deny_paths=(
	"$HOME/.cursor"
	"$project/.cursor"
)

build_profile() {
	printf '%s\n' '(version 1)' '(allow default)'
	printf '%s\n' '(deny file-write* (require-not (require-any'
	local write_path
	for write_path in "${write_paths[@]}"; do
		printf '  (subpath "%s")\n' "$(escape_sb_path "$write_path")"
	done
	printf '%s\n' ')))'
	if [[ "$role" == review ]]; then
		printf '(deny file-write* (subpath "%s"))\n' "$(escape_sb_path "$project")"
	fi
	local deny_path
	for deny_path in "${read_deny_paths[@]}"; do
		printf '(deny file-read* (subpath "%s"))\n' "$(escape_sb_path "$deny_path")"
	done
}

profile="$runtime_dir/cursor-worker.sb"
expected_profile=$(build_profile)
printf '%s\n' "$expected_profile" >"$profile"

# 期待内容照合: 生成直後に、書き込んだ内容が意図した内容と完全一致することを
# 検証してから起動する（Codex helper が review profile を cmp で照合しているのと
# 同じ役割）。write allowlist か read deny のどちらかが欠けたまま起動することを
# fail-closed で防ぐ。
actual_profile=$(cat -- "$profile")
if [[ "$actual_profile" != "$expected_profile" ]]; then
	printf '%s\n' 'Cursor sandbox profile does not match its expected content; refusing a fail-open launch.' >&2
	exit 2
fi

# profile 生成だけを検証するための出口。cursor-agent 本体・sandbox-exec・認証の
# いずれも要求せず、write allowlist と read deny の内容だけを確認できる。
if [[ "${AGMSG_CURSOR_SANDBOX_PROFILE_ONLY:-0}" == 1 ]]; then
	cat -- "$profile"
	exit 0
fi

if ! command -v sandbox-exec >/dev/null 2>&1; then
	printf '%s\n' 'sandbox-exec is required to enforce the cursor-agent worker write boundary.' >&2
	exit 1
fi

# --sandbox enabled は実測で書込境界を強制しない (--sandbox enabled --trust
# --force でも workspace 外への write が素通りした。tmp/cursor-worker/design.md)。
# sandbox-exec による OS 側の二層構成が前提であり、--force は sandbox-exec 経由の
# 起動でしか使わない（Claude helper の bypassPermissions と同じ扱い）。

# mise shim は使えない（opencode worker で踏んだ問題の再発防止）。実体は
# ~/.local/bin/cursor-agent → ~/.local/share/cursor-agent/versions/<ver>/cursor-agent
# であり mise 管理下ではない。AGMSG_CURSOR_BIN で上書き可能だが、shim path は
# 同様に拒否し、候補は実行可能であることまで確かめる。
is_shim_path() { case $1 in */shims/*) return 0 ;; *) return 1 ;; esac; }

resolve_cursor_bin() {
	local candidate=$1 resolved
	[[ -e "$candidate" ]] || return 1
	resolved=$(readlink -f -- "$candidate" 2>/dev/null) || return 1
	[[ -n "$resolved" ]] || return 1
	[[ -x "$resolved" ]] || return 1
	is_shim_path "$resolved" && return 1
	printf '%s' "$resolved"
}

cursor_bin_input=${AGMSG_CURSOR_BIN:-$HOME/.local/bin/cursor-agent}
if ! cursor_bin=$(resolve_cursor_bin "$cursor_bin_input"); then
	printf 'cursor-agent executable could not be resolved to a real, non-shim binary: %s (set AGMSG_CURSOR_BIN to override).\n' "$cursor_bin_input" >&2
	exit 1
fi

# version drift に fail-closed で反応する。MCP 遮断は文書化されていない
# ~/.cursor 全面 read 拒否の副作用に依存しているため、smoke 実施時と
# cursor-agent の version が変われば、再smoke するまで起動しない。未設定なら通す。
cursor_version=$("$cursor_bin" --version 2>/dev/null || true)
if [[ -z "$cursor_version" ]]; then
	printf '%s\n' 'Failed to read cursor-agent --version; refusing a fail-open launch.' >&2
	exit 1
fi
if [[ -n "${AGMSG_CURSOR_VERIFIED_VERSION:-}" ]] && [[ "$cursor_version" != *"$AGMSG_CURSOR_VERIFIED_VERSION"* ]]; then
	printf 'cursor-agent version (%s) does not contain AGMSG_CURSOR_VERIFIED_VERSION=%s; the ~/.cursor read-deny / MCP-blocking smoke was not verified against this version. Refusing to launch.\n' \
		"$cursor_version" "$AGMSG_CURSOR_VERIFIED_VERSION" >&2
	exit 2
fi

# capability check であって write 境界の成立証拠ではない。MCP が 0 件であることは
# sandbox 下で ~/.cursor を read 拒否した副作用が効いていることの確認にすぎず、
# write allowlist の証拠は別に smoke で取る (references/runtime-smoke.md)。
# 出力は cwd によって 2 つの形になる。cursor project entry を持たない cwd では
# "No MCP servers configured"、`~/.cursor/projects/<slug>/` を持つ cwd では
# その配下の mcp-approvals.json に対する EPERM になる（実測）。どちらも「MCP は
# ロードされていない」を意味するので両方を受理する。
#
# 受理する形を列挙するのは、禁止語を列挙する書き方だと将来の新しい出力を素通し
# させるためである。EPERM を受理するときは、拒否されたパスが自分で read deny した
# 根の下にあることまで確かめる——無関係な EPERM を成功と読まないため。
# EPERM 経路では mcp list 自体が非ゼロ終了するため、`|| true` で set -e から
# 逃がしてから出力を判定する（終了コードではなく出力形で判定する契約）。
mcp_output=$(sandbox-exec -f "$profile" "$cursor_bin" mcp list 2>&1) || true

if [[ -z "$mcp_output" ]]; then
	printf 'cursor-agent mcp list produced no output under the sandbox profile; refusing a fail-open launch.\n' >&2
	exit 2
fi

mcp_ok=0
if [[ "$mcp_output" == *'No MCP servers configured'* ]]; then
	mcp_ok=1
elif [[ "$mcp_output" == *'Failed to list MCP servers'* && "$mcp_output" == *EPERM* ]]; then
	for deny_path in "${read_deny_paths[@]}"; do
		if [[ "$mcp_output" == *"$deny_path"* ]]; then
			mcp_ok=1
			break
		fi
	done
fi

if [[ "$mcp_ok" -ne 1 ]]; then
	printf 'cursor-agent mcp list did not confirm an empty MCP surface under the sandbox profile; refusing to launch.\n' >&2
	printf '%s\n' "$mcp_output" >&2
	exit 2
fi

# capability check だけを走らせてモデルを起動しない出口。cwd 依存で出力形が変わる
# 判定を、課金なしで回帰テストに固定するために使う。
if [[ "${AGMSG_CURSOR_MCP_CHECK_ONLY:-0}" == 1 ]]; then
	printf 'mcp surface confirmed empty\n'
	exit 0
fi

prompt=$(cat -- "$payload_file")

cursor_args=(-p --output-format stream-json --trust --force --model "$model" "$prompt")

exec sandbox-exec -f "$profile" "$cursor_bin" "${cursor_args[@]}"
