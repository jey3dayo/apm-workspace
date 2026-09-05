#!/usr/bin/env bash

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

# role ごとに許可するモデルを固定する。role だけ検証して model を素通しすると、
# implement=sol や review=luna のような role/model 不一致を runtime が拒否できず、
# 起動して初めて（あるいは請求で）気づくことになる。正本は orchestrator-worker の
# tier 表で、tests/run-codex-worker.bats が表と本 allowlist の一致を検証する。
case "$role" in
implement) allowed_models=(gpt-5.6-luna gpt-5.6-terra) ;;
review) allowed_models=(gpt-5.6-sol gpt-5.6-terra) ;;
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

codex_bin=${AGMSG_CODEX_BIN:-codex}
if ! command -v "$codex_bin" >/dev/null 2>&1; then
	printf 'Codex executable not found: %s\n' "$codex_bin" >&2
	exit 1
fi

# Codex は symlink 成分を含む writable_roots を拒否する ("symlinked writable roots are
# not supported")。不正な root が1つでもあると sandbox 構築自体が失敗し、無関係な
# コマンドまで起動前に全拒否される。worker からは「シェルすら起動できない」形で見え、
# 原因が設定にあると分からないまま停止するため、
# 起動前に検査して原因を名指しで報告する。
extract_writable_roots() {
	local file=$1
	[[ -r "$file" ]] || return 0
	awk '
		/^[[:space:]]*\[/ {
			in_section = ($0 ~ /^[[:space:]]*\[sandbox_workspace_write\][[:space:]]*$/)
			in_array = 0
		}
		in_section && /writable_roots[[:space:]]*=/ { in_array = 1 }
		in_array {
			line = $0
			sub(/#.*/, "", line)
			while (match(line, /"[^"]*"/)) {
				value = substr(line, RSTART + 1, RLENGTH - 2)
				if (value != "") print value
				line = substr(line, RSTART + RLENGTH)
			}
			if (line ~ /\]/) in_array = 0
		}
	' "$file"
}

# root 自身だけでなく途中の成分も検査する。Codex は成分に1つでも symlink があれば拒否する。
path_has_symlink_component() {
	local path=$1 prefix= component
	while IFS= read -r component; do
		[[ -n "$component" ]] || continue
		prefix="$prefix/$component"
		[[ -L "$prefix" ]] && return 0
	done < <(printf '%s\n' "${path//\//$'\n'}")
	return 1
}

assert_writable_roots_are_canonical() {
	local file=$1 origin=$2 root
	while IFS= read -r root; do
		[[ -n "$root" ]] || continue
		if path_has_symlink_component "$root"; then
			printf 'Writable root %s in %s (%s) contains a symlink component.\n' \
				"$root" "$origin" "$file" >&2
			printf '%s\n' 'Codex rejects symlinked writable roots and then denies every command in the sandbox.' >&2
			printf '%s\n' 'Replace it with the canonical path (resolve symlinks) and relaunch; refusing to start a worker that would stall.' >&2
			return 1
		fi
	done < <(extract_writable_roots "$file")
	return 0
}

project=$(cd -- "$project" && pwd -P)
payload_file=$(cd -- "$(dirname -- "$payload_file")" && printf '%s/%s\n' "$PWD" "$(basename -- "$payload_file")")
codex_args=(--strict-config -m "$model" -a never)
exec_args=(exec --ephemeral)
review_scratch=

codex_home=${CODEX_HOME:-$HOME/.codex}

# worker が継承する MCP と plugin を最小化する。leaf worker は実装かレビューだけを
# 行うので、認証情報 (1password)、GUI 操作 (computer-use / node_repl)、通知
# (voicevox)、タスク管理 (linear) は不要で、渡すこと自体が能力面の境界を広げる。
#
# 個別キーの上書き (`-c mcp_servers.X.enabled=false`) は config.toml に節を持つ
# サーバにしか効かない。plugin が持ち込む MCP には節が無く、`-c plugins."x@y".
# enabled=false` は実測で無視される (codex 0.153.2)。そのため worker には base
# config の複製から plugin と非 allowlist の MCP を落とした専用 CODEX_HOME を渡す。
# base の他の設定 (openai_base_url、service_tier、sandbox_workspace_write、
# projects の trust) はそのまま残すので、閉じるのは MCP と plugin だけになる。
#
# allowlist にするのは、config.toml へ新しい MCP を足したときに既定で worker へ
# 流れ込まないようにするため。明示したものだけ通す。
mcp_allow=${AGMSG_WORKER_MCP_ALLOW:-context7,jina-reader}

worker_home=$(mktemp -d "${TMPDIR:-/tmp}/agmsg-worker-home.XXXXXX")/codex
mkdir -p "$worker_home"
chmod 700 "$worker_home"
cleanup() {
	rm -rf -- "${worker_home%/codex}"
	[[ -n "$review_scratch" ]] && rm -rf -- "$review_scratch"
	return 0
}
trap cleanup EXIT

# auth は symlink で共有する。コピーするとトークン更新が worker 側に閉じ、
# 本体の auth.json が更新されないまま失効する。
if [[ -e "$codex_home/auth.json" ]]; then
	ln -s "$codex_home/auth.json" "$worker_home/auth.json"
fi

if [[ -f "$codex_home/config.toml" ]]; then
	awk -v allow=",$mcp_allow," '
		/^\[/ {
			in_notify = 0
			drop = 0
			if ($0 ~ /^\[plugins[.\]]/ || $0 ~ /^\[marketplaces[.\]]/) {
				drop = 1
			} else if (match($0, /^\[mcp_servers\.[^.\]]+/)) {
				name = substr($0, RSTART + 13, RLENGTH - 13)
				drop = (index(allow, "," name ",") == 0)
			}
		}
		# notify は人間の通知先へ turn 終了イベントと payload 本文を渡す。worker の
		# 出力を人間のデスクトップへ流す必要はなく、報告経路は agmsg 側にある。
		!drop && /^notify[[:space:]]*=/ { in_notify = ($0 !~ /\]/); next }
		in_notify { if ($0 ~ /\]/) in_notify = 0; next }
		!drop { print }
	' "$codex_home/config.toml" >"$worker_home/config.toml"
	chmod 600 "$worker_home/config.toml"
fi

codex_home=$worker_home
export CODEX_HOME="$worker_home"

if [[ "$role" == implement ]]; then
	# implement は profile を layer しないため base config の writable_roots が直接効く。
	if ! assert_writable_roots_are_canonical "$codex_home/config.toml" 'the Codex base config'; then
		exit 1
	fi

	codex_args+=(-C "$project" -s workspace-write)
	# worker の既定 effort。xhigh が品質/コストの損益分岐（Terra high 相当を最安で達成）。
	# 昇格時は AGMSG_WORKER_EFFORT=max で上書きする。
	worker_effort=${AGMSG_WORKER_EFFORT:-xhigh}
	case "$worker_effort" in
	none | low | medium | high | xhigh | max) ;;
	*)
		printf 'Unsupported AGMSG_WORKER_EFFORT: %s\n' "$worker_effort" >&2
		exit 2
		;;
	esac
	codex_args+=(-c "model_reasoning_effort=\"$worker_effort\"")
else
	# reviewer の effort は既定で Codex 既定に任せる。terra 昇格時などに
	# AGMSG_REVIEWER_EFFORT で明示指定する。
	reviewer_effort=${AGMSG_REVIEWER_EFFORT:-}
	if [[ -n "$reviewer_effort" ]]; then
		case "$reviewer_effort" in
		none | low | medium | high | xhigh | max) ;;
		*)
			printf 'Unsupported AGMSG_REVIEWER_EFFORT: %s\n' "$reviewer_effort" >&2
			exit 2
			;;
		esac
		codex_args+=(-c "model_reasoning_effort=\"$reviewer_effort\"")
	fi

	script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
	profile_source=${AGMSG_CODEX_PROFILE_SOURCE:-"$script_dir/../agmsg-review.config.toml"}
	# Codex は profile を $CODEX_HOME 直下から探す。既定値を $HOME/.codex 直書きにすると、
	# CODEX_HOME を設定した環境で「置く場所」と「読む場所」が食い違い、-p が base config へ
	# fail-open して read-only 境界が黙って消える。必ず解決済みの codex_home を使う。
	profile_expected=$codex_home/agmsg-review.config.toml
	profile_target=${AGMSG_CODEX_PROFILE_TARGET:-$profile_expected}

	# 上書きを許すが、Codex が実際に読む path 以外へ置かせない。ここを緩めると
	# 上と同じ fail-open が env 経由で再現する。
	if [[ "$profile_target" != "$profile_expected" ]]; then
		printf 'AGMSG_CODEX_PROFILE_TARGET must be %s (got %s); refusing fail-open launch.\n' \
			"$profile_expected" "$profile_target" >&2
		exit 1
	fi

	if [[ ! -f "$profile_source" ]]; then
		printf '%s\n' 'Codex review profile source is missing; refusing fail-open launch.' >&2
		exit 1
	fi

	# Codex の -p は profile が CODEX_HOME 直下に無いと exit 0 で base config へ落ちる
	# (fail-open)。CODEX_HOME は APM の配布面ではないため、正本から毎回置き直す。
	if ! install -m 600 "$profile_source" "$profile_target"; then
		printf '%s\n' 'Failed to deploy the Codex review profile; refusing fail-open launch.' >&2
		exit 1
	fi

	# コピー後も検証する。install が成功しても内容が一致しない状況 (競合書込み等) では
	# サンドボックス契約が保証できないため起動しない。
	if ! cmp -s "$profile_source" "$profile_target"; then
		printf '%s\n' 'Codex review profile differs from the deployed source; refusing fail-open launch.' >&2
		exit 1
	fi

	# profile の writable_roots は base config を置換する (実測済み) ため、review では
	# base config ではなく profile 側だけを検査する。
	if ! assert_writable_roots_are_canonical "$profile_target" 'the Codex review profile'; then
		exit 1
	fi

	# profile の workspace-write は cwd を必ず書込可能にする。cwd を対象 project に
	# したままでは reviewer が project を書き換えられてしまうため、専用スクラッチへ逃がす。
	# project へは read のみで到達でき、payload が絶対パスで指示する。
	review_scratch=$(mktemp -d "${TMPDIR:-/tmp}/agmsg-review-cwd.XXXXXX")
	chmod 700 "$review_scratch"
	# スクラッチは git repo でないため、trusted-directory 判定を明示的に飛ばす。
	codex_args+=(-C "$review_scratch" -p agmsg-review)
	exec_args+=(--skip-git-repo-check)
fi

"$codex_bin" "${codex_args[@]}" "${exec_args[@]}" - <"$payload_file"
