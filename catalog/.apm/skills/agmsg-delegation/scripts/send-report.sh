#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
	printf 'Usage: %s <team> <from> <to> (body on stdin)\n' "$0" >&2
	exit 2
fi

team=$1
from_agent=$2
to_agent=$3
report_body=$(cat)

if [[ -z "$report_body" ]]; then
	printf '%s\n' 'Report body must not be empty.' >&2
	exit 2
fi

# 報告 keyword には task_id を必須にする。WORKER.md で exact に指示しても model が
# bare `READY` を送る事例が実運用で発生した。orchestrator は task_id で照合するため、
# 欠けた報告は「どの task の報告か分からないもの」になり、無応答と区別できない。
# 生成側の遵守に任せず、transport の入口で fail-closed にする。
first_line=${report_body%%$'\n'*}

# 空白区切りは 1 文字以上を必須にする。`*` だと `READYtask-42` や `REVIEW: approve` が
# 通り、orchestrator が待つ exact `<KEYWORD> <task_id>` にならないまま送信される。
if [[ "$first_line" =~ ^(READY|WORKING|BLOCKED|DONE|REVIEW)([[:space:]]+([^[:space:]]+))?[[:space:]]*(.*)$ ]]; then
	keyword=${BASH_REMATCH[1]}
	task_id=${BASH_REMATCH[3]}
	if [[ -z "$task_id" ]]; then
		printf '%s report is missing its task_id; refusing to send.\n' "$keyword" >&2
		printf 'Send "%s <task_id>" as the first line (see WORKER.md).\n' "$keyword" >&2
		exit 2
	fi
fi

send_script=${AGMSG_SEND_SCRIPT:-$HOME/.agents/skills/agmsg/scripts/send.sh}

if [[ ! -x "$send_script" ]]; then
	printf 'agmsg send helper is not executable: %s\n' "$send_script" >&2
	exit 1
fi

exec "$send_script" "$team" "$from_agent" "$to_agent" "$report_body"
