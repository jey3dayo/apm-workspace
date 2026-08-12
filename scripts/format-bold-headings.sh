#!/usr/bin/env bash
set -euo pipefail

# Bold-heading normalization lives in ~/.config/scripts/replace-bold-headings.ts,
# the one operational dependency outside this repository that
# docs/apm-task-coverage.md explicitly sanctions.
#
# Fail loudly when it is missing instead of skipping: this runs inside
# `format:check` -> `check` and both lefthook gates, so a silent skip would let
# the gate report success on any host without the helper — invisible precisely
# where it matters. Set APM_ALLOW_MISSING_BOLD_HEADINGS=1 to opt out knowingly.

SCRIPT_PATH="${APM_BOLD_HEADINGS_SCRIPT:-$HOME/.config/scripts/replace-bold-headings.ts}"
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
  if [ "${APM_ALLOW_MISSING_BOLD_HEADINGS:-}" = "1" ]; then
    echo "Skipping bold heading $mode: $SCRIPT_PATH not found (APM_ALLOW_MISSING_BOLD_HEADINGS=1)." >&2
    exit 0
  fi
  echo "Bold heading helper missing: $SCRIPT_PATH" >&2
  echo "Restore it, point APM_BOLD_HEADINGS_SCRIPT at a copy, or set APM_ALLOW_MISSING_BOLD_HEADINGS=1 to bypass." >&2
  exit 1
fi

if [ "$mode" = "check" ]; then
  exec tsx "$SCRIPT_PATH" "$TARGET" --dry-run
fi

exec tsx "$SCRIPT_PATH" "$TARGET"
