#!/usr/bin/env bash
set -euo pipefail

# Frontmatter validation lives in scripts/lint-frontmatter.ts, vendored into
# this repository so the check is self-contained on any checkout (including
# CI runners, which have no ~/.config).
#
# Fail loudly when it is missing instead of skipping: this runs inside
# `check`, and a silent skip would let the gate report success on a broken
# checkout — invisible precisely where it matters. APM_LINT_FRONTMATTER_SCRIPT
# remains available to point at an alternate copy for development/testing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_PATH="${APM_LINT_FRONTMATTER_SCRIPT:-$REPO_ROOT/scripts/lint-frontmatter.ts}"

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Frontmatter lint helper missing: $SCRIPT_PATH" >&2
  echo "The checkout is broken; restore scripts/lint-frontmatter.ts or point APM_LINT_FRONTMATTER_SCRIPT at a copy." >&2
  exit 1
fi

exec tsx "$SCRIPT_PATH" "$@"
