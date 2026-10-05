#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_PATH="${APM_LINT_SKILL_INVENTORY_SCRIPT:-$REPO_ROOT/scripts/lint-skill-inventory.ts}"

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Skill inventory lint helper missing: $SCRIPT_PATH" >&2
  exit 1
fi

exec tsx "$SCRIPT_PATH" "$@"
