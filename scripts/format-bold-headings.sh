#!/usr/bin/env bash
set -euo pipefail

# Bold-heading normalization lives in scripts/replace-bold-headings.ts,
# vendored into this repository so the check is self-contained on any
# checkout (including CI runners, which have no ~/.config).
#
# Fail loudly when it is missing instead of skipping: this runs inside
# `format:check` -> `check` and both lefthook gates, so a silent skip would let
# the gate report success on a broken checkout — invisible precisely where it
# matters. APM_BOLD_HEADINGS_SCRIPT remains available to point at an alternate
# copy for development/testing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_PATH="${APM_BOLD_HEADINGS_SCRIPT:-$REPO_ROOT/scripts/replace-bold-headings.ts}"
TARGET="./catalog"

mode="${1:-write}"
case "$mode" in
  write | check) ;;
  *)
    echo "Usage: format-bold-headings.sh <write|check>" >&2
    exit 1
    ;;
esac

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Bold heading helper missing: $SCRIPT_PATH" >&2
  echo "The checkout is broken; restore scripts/replace-bold-headings.ts or point APM_BOLD_HEADINGS_SCRIPT at a copy." >&2
  exit 1
fi

if [ "$mode" = "check" ]; then
  exec tsx "$SCRIPT_PATH" "$TARGET" --dry-run
fi

exec tsx "$SCRIPT_PATH" "$TARGET"
