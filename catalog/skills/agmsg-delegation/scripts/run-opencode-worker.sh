#!/usr/bin/env bash
#
# opencode worker launcher. opencode is Worker-only: it cannot be assigned the
# review role (see agmsg-delegation SKILL.md / orchestrator-worker tier table).
#
# Argument contract mirrors run-codex-worker.sh:
#   run-opencode-worker.sh <role> <project> <model> <payload-file>

set -euo pipefail

if [[ $# -ne 4 ]]; then
	printf 'Usage: %s <implement> <project> <model> <payload-file>\n' "$0" >&2
	exit 2
fi

role=$1
project=$2
model=$3
payload_file=$4

if [[ "$role" != implement ]]; then
	printf 'Unsupported role for opencode: %s (opencode is Worker-only; supported roles: implement)\n' "$role" >&2
	exit 2
fi

# 正本は orchestrator-worker の tier 表 Worker 行。opencode 側は
# deepseek/deepseek-v4-flash の1つだけを許可する。tests/run-opencode-worker.bats
# の drift テストがこの1行と tier 表の集合一致を検証する。
allowed_models=(deepseek/deepseek-v4-flash)

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

variant=${AGMSG_OPENCODE_VARIANT:-high}
case "$variant" in
low | high | max) ;;
*)
	printf 'Unsupported AGMSG_OPENCODE_VARIANT: %s\n' "$variant" >&2
	exit 2
	;;
esac

project=$(cd -- "$project" && pwd -P)
payload_file=$(cd -- "$(dirname -- "$payload_file")" && printf '%s/%s\n' "$PWD" "$(basename -- "$payload_file")")

runtime_dir=$(mktemp -d)
trap 'rm -rf -- "$runtime_dir"' EXIT

mkdir -p "$runtime_dir/config" "$runtime_dir/data" "$runtime_dir/state" "$runtime_dir/cache"

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
	"$project"
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

# 意図して ~/.local/share/opencode（auth.json の所在）は write_paths に入れない。
# 実測で write 拒否を確認済み: opencode worker が資格情報ファイルを書き換え/削除
# できてはならない。
profile="$runtime_dir/opencode-worker.sb"
{
	printf '%s\n' '(version 1)' '(allow default)' '(deny file-write* (require-not (require-any'
	for write_path in "${write_paths[@]}"; do
		printf '  (subpath "%s")\n' "$(escape_sb_path "$write_path")"
	done
	printf '%s\n' ')))'
} >"$profile"

# profile 生成だけをテストで検証するための出口。opencode 本体・sandbox-exec・
# credential のいずれも要求せず、write allowlist の内容だけを確認できる。
if [[ "${AGMSG_OPENCODE_SANDBOX_PROFILE_ONLY:-0}" == 1 ]]; then
	cat -- "$profile"
	exit 0
fi

if ! command -v sandbox-exec >/dev/null 2>&1; then
	printf '%s\n' 'sandbox-exec is required to enforce the opencode worker write boundary.' >&2
	exit 1
fi

# --auto は「明示的に deny されていない permission を自動承認する」設定であり、
# opencode の permission config は harness 層の判定にすぎない。OS 側の
# sandbox-exec で書込境界を締める二層構成が前提で、sandbox-exec なしで --auto を
# 使わない。

if ! command -v python3 >/dev/null 2>&1; then
	printf '%s\n' 'python3 is required to resolve the DeepSeek credential and verify the effective opencode config.' >&2
	exit 1
fi

# mise shim は使えない。XDG を隔離すると mise の trust 設定が外れて shim が失敗する
# （実測）。launchd の PATH には ~/.mise/shims が含まれるため、`command -v opencode` は
# 黙って shim を返す——そのまま起動すると `debug config` が失敗し、fail-closed 検査が
# 起動拒否として現れて原因が見えなくなる（実測）。shim を明示的に拒否する。
# launchd 配下では mise 自体も対象 tool を解決できない（"not a mise bin"）ので、
# 最後に mise の install ツリーを直接引く。
is_shim_path() { case $1 in */shims/*) return 0 ;; *) return 1 ;; esac; }

opencode_bin=${AGMSG_OPENCODE_BIN:-}
if [[ -z "$opencode_bin" ]] && command -v mise >/dev/null 2>&1; then
	# mise は解決に失敗したとき診断文を stdout へ出すことがある。実行可能ファイルで
	# あることまで確かめてから採用する。
	candidate=$(mise which opencode 2>/dev/null || true)
	if [[ -n "$candidate" ]] && [[ -x "$candidate" ]] && ! is_shim_path "$candidate"; then
		opencode_bin=$candidate
	fi
fi
if [[ -z "$opencode_bin" ]]; then
	candidate=$(command -v opencode 2>/dev/null || true)
	if [[ -n "$candidate" ]] && [[ -x "$candidate" ]] && ! is_shim_path "$candidate"; then
		opencode_bin=$candidate
	fi
fi
if [[ -z "$opencode_bin" ]]; then
	for candidate in "$HOME"/.mise/installs/*opencode*/latest/opencode; do
		if [[ -x "$candidate" ]]; then
			opencode_bin=$candidate
			break
		fi
	done
fi
if [[ -z "$opencode_bin" ]]; then
	printf '%s\n' 'opencode executable could not be resolved to a real binary (a mise shim is not usable here). Set AGMSG_OPENCODE_BIN.' >&2
	exit 1
fi
if is_shim_path "$opencode_bin"; then
	printf 'AGMSG_OPENCODE_BIN points at a mise shim (%s); a real binary is required.\n' "$opencode_bin" >&2
	exit 1
fi
if [[ ! -x "$opencode_bin" ]]; then
	printf 'opencode executable not found or not executable: %s\n' "$opencode_bin" >&2
	exit 1
fi

# mise shim ではなく実バイナリの絶対パスで起動する。XDG を隔離すると mise の
# trust 設定が外れて shim が失敗することを実測済みのため。

if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
	deepseek_key=$DEEPSEEK_API_KEY
else
	auth_file="$HOME/.local/share/opencode/auth.json"
	if ! deepseek_key=$(python3 - "$auth_file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, ValueError):
    sys.exit(1)

entry = data.get("deepseek")
if not isinstance(entry, dict):
    sys.exit(1)

key = entry.get("key")
if not key:
    sys.exit(1)

print(key)
PY
	); then
		printf 'DeepSeek credential not found (set DEEPSEEK_API_KEY, or add a "deepseek" entry to %s).\n' "$auth_file" >&2
		exit 1
	fi
fi

export OPENCODE_DISABLE_PROJECT_CONFIG=1
export XDG_CONFIG_HOME="$runtime_dir/config"
export XDG_DATA_HOME="$runtime_dir/data"
export XDG_STATE_HOME="$runtime_dir/state"
export XDG_CACHE_HOME="$runtime_dir/cache"
export DEEPSEEK_API_KEY="$deepseek_key"
unset deepseek_key

# project 側の opencode.json は project config として merge され、
# XDG_CONFIG_HOME の隔離だけでは落ちない（実測済み）。
# OPENCODE_DISABLE_PROJECT_CONFIG=1 が MCP 遮断の要。起動前に解決済み config の
# mcp 件数を fail-closed で検査し、キー名・値は出力しない。
if ! config_json=$("$opencode_bin" debug config 2>/dev/null); then
	printf '%s\n' 'Failed to read the effective opencode config; refusing a fail-open launch.' >&2
	exit 1
fi

mcp_count=$(printf '%s' "$config_json" | python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except ValueError:
    print(-1)
else:
    print(len(data.get("mcp") or {}))
')

if [[ "$mcp_count" -lt 0 ]]; then
	printf '%s\n' 'Failed to parse the effective opencode config; refusing a fail-open launch.' >&2
	exit 1
fi

if [[ "$mcp_count" -ne 0 ]]; then
	printf 'Effective opencode config still exposes %s MCP server(s); refusing to launch (fail-closed).\n' "$mcp_count" >&2
	exit 2
fi

prompt=$(cat -- "$payload_file")

opencode_args=(run --dir "$project" -m "$model" --variant "$variant" --auto "$prompt")

exec sandbox-exec -f "$profile" "$opencode_bin" "${opencode_args[@]}"
