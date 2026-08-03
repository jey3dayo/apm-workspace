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
codex_args=(--strict-config -m "$model" -a never -C "$project")

if [[ "$role" == implement ]]; then
	codex_args+=(-s workspace-write)
else
	script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
	profile_source=${AGMSG_CODEX_PROFILE_SOURCE:-"$script_dir/../agmsg-review.config.toml"}
	profile_target=${AGMSG_CODEX_PROFILE_TARGET:-/Users/t00114/.codex/agmsg-review.config.toml}

	if [[ ! -f "$profile_source" || ! -f "$profile_target" ]]; then
		printf '%s\n' 'Codex review profile is missing; refusing fail-open launch.' >&2
		exit 1
	fi

	if ! cmp -s "$profile_source" "$profile_target"; then
		printf '%s\n' 'Codex review profile differs from the deployed source; refusing fail-open launch.' >&2
		exit 1
	fi

	codex_args+=(-p agmsg-review)
fi

codex_args+=(exec --ephemeral -)
"$codex_bin" "${codex_args[@]}" <"$payload_file"
