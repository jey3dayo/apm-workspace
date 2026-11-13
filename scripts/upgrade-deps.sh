#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi

HOLDS_FILE="docs/dependency-holds.txt"
MANIFEST="apm.yml"
LOCK="apm.lock.yaml"

held_repos=()
while IFS= read -r line; do
  [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
  held_repos+=("$(awk '{print $1}' <<<"$line")")
done <"$HOLDS_FILE"

echo "Held packages (will not be updated):"
printf '  - %s\n' "${held_repos[@]}"
echo

if $DRY_RUN; then
  echo "[DRY RUN] Would regenerate lock with: apm lock"
  echo "[DRY RUN] Manual pin updates in $MANIFEST must respect holds above"
else
  echo "Regenerating lock file..."
  apm lock
  echo "✓ Lock updated: $LOCK"
  echo "Note: Verify no held packages were updated with: mise run validate:workspace"
fi
