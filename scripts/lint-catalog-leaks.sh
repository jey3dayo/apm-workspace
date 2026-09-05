#!/usr/bin/env bash
set -euo pipefail

# Catalog leak validation lives in scripts/lint-catalog-leaks.ts and is
# vendored into this repository so the check is self-contained on any
# checkout, including CI runners.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_PATH="${APM_LINT_CATALOG_LEAKS_SCRIPT:-$REPO_ROOT/scripts/lint-catalog-leaks.ts}"

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Catalog leak lint helper missing: $SCRIPT_PATH" >&2
  echo "The checkout is broken; restore scripts/lint-catalog-leaks.ts or point APM_LINT_CATALOG_LEAKS_SCRIPT at a copy." >&2
  exit 1
fi

exec tsx "$SCRIPT_PATH" "$@"
