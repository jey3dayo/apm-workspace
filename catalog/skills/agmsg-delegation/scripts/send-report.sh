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

send_script=${AGMSG_SEND_SCRIPT:-/Users/t00114/.agents/skills/agmsg/scripts/send.sh}

if [[ ! -x "$send_script" ]]; then
	printf 'agmsg send helper is not executable: %s\n' "$send_script" >&2
	exit 1
fi

exec "$send_script" "$team" "$from_agent" "$to_agent" "$report_body"
