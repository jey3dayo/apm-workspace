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

project=$(cd -- "$project" && pwd -P)
payload_file=$(cd -- "$(dirname -- "$payload_file")" && printf '%s/%s\n' "$PWD" "$(basename -- "$payload_file")")
codex_args=(--strict-config -m "$model" -a never)
exec_args=(exec --ephemeral)
review_scratch=

if [[ "$role" == implement ]]; then
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
	script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
	profile_source=${AGMSG_CODEX_PROFILE_SOURCE:-"$script_dir/../agmsg-review.config.toml"}
	profile_target=${AGMSG_CODEX_PROFILE_TARGET:-/Users/t00114/.codex/agmsg-review.config.toml}

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

	# profile の workspace-write は cwd を必ず書込可能にする。cwd を対象 project に
	# したままでは reviewer が project を書き換えられてしまうため、専用スクラッチへ逃がす。
	# project へは read のみで到達でき、payload が絶対パスで指示する。
	review_scratch=$(mktemp -d "${TMPDIR:-/tmp}/agmsg-review-cwd.XXXXXX")
	chmod 700 "$review_scratch"
	trap 'rm -rf -- "$review_scratch"' EXIT
	# スクラッチは git repo でないため、trusted-directory 判定を明示的に飛ばす。
	codex_args+=(-C "$review_scratch" -p agmsg-review)
	exec_args+=(--skip-git-repo-check)
fi

"$codex_bin" "${codex_args[@]}" "${exec_args[@]}" - <"$payload_file"
