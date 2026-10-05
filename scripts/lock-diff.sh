#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_PATH="${APM_LOCK_DIFF_SCRIPT:-$REPO_ROOT/scripts/lock-diff.ts}"

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Lock diff helper missing: $SCRIPT_PATH" >&2
  exit 1
fi

exec tsx "$SCRIPT_PATH" "$@"
