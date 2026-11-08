#!/usr/bin/env bash
# Lint an auto-memory directory: per-file frontmatter and the MEMORY.md index.
# A [[link]] to a memory not written yet is legal (it marks one worth writing),
# so it prints a `note:` line and does not fail. Read-only.
# Exit 0 clean, 1 findings, 2 usage.
set -euo pipefail

dir="${1:-}"
if [ ! -d "$dir" ]; then
  echo "usage: lint-memory.sh <memory-dir>" >&2
  exit 2
fi
index="$dir/MEMORY.md"
if [ ! -f "$index" ]; then
  echo "no MEMORY.md in $dir" >&2
  exit 2
fi

findings=0
report() {
  printf '%s\n' "$1"
  findings=$((findings + 1))
}

memory_files=()
for f in "$dir"/*.md; do
  [ -e "$f" ] || continue
  [ "$(basename "$f")" = MEMORY.md ] && continue
  memory_files+=("$f")
done

frontmatter_value() {
  # $1: frontmatter text, $2: key. Prints the first value, quotes stripped.
  printf '%s\n' "$1" | sed -n "s/^[[:space:]]*$2:[[:space:]]*//p" | head -n 1 | sed 's/^"\(.*\)"$/\1/'
}

for f in ${memory_files[@]+"${memory_files[@]}"}; do
  base=$(basename "$f" .md)
  if [ "$(head -n 1 "$f")" != "---" ]; then
    report "frontmatter: $base.md has no frontmatter"
    continue
  fi
  fm=$(awk 'NR == 1 { next } /^---$/ { exit } { print }' "$f")
  name=$(frontmatter_value "$fm" name)
  desc=$(frontmatter_value "$fm" description)
  type=$(frontmatter_value "$fm" type)
  [ "$name" = "$base" ] || report "name: $base.md declares name '${name}'"
  [ -n "$desc" ] || report "description: $base.md has no description"
  case "$type" in
    user | feedback | project | reference) ;;
    *) report "type: $base.md has type '${type}' (user|feedback|project|reference)" ;;
  esac
done

indexed=$(grep -oE '\]\([^)]+\.md\)' "$index" | sed 's/^](//; s/)$//' || true)

for target in $indexed; do
  [ -f "$dir/$target" ] || report "index: MEMORY.md points to missing $target"
done

for f in ${memory_files[@]+"${memory_files[@]}"}; do
  base=$(basename "$f")
  printf '%s\n' "$indexed" | grep -qxF "$base" || report "index: $base is not listed in MEMORY.md"
done

for f in ${memory_files[@]+"${memory_files[@]}"}; do
  links=$(grep -oE '\[\[[^]]+\]\]' "$f" | sort -u || true)
  for link in $links; do
    target=${link#\[\[}
    target=${target%\]\]}
    [ -f "$dir/$target.md" ] || printf 'note: %s links to unwritten [[%s]]\n' "$(basename "$f")" "$target"
  done
done

[ "$findings" -eq 0 ]
