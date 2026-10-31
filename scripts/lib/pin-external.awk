# Rewrites apm.yml so every external dependency ref carries its lockfile commit:
# literal refs get "#<sha>" appended, structured "- git: <repo>" entries get a
# sibling "ref: <sha>" inserted. Writes the rewritten manifest to stdout and the
# number of updated refs to stderr. Invoked as:
#   awk -v map_file=<canonical\tcommit list> -f scripts/lib/pin-external.awk <manifest_path>
function indent_level(line, trimmed) {
  trimmed = line
  sub(/^[[:space:]]+/, "", trimmed)
  return length(line) - length(trimmed)
}
# Case-insensitive fallback matches only the owner/repo segments, same as
# collect_external_skill_records() in scripts/apm-workspace.sh — a deeper path
# segment (e.g. a virtual_path under skills/) is a real, case-sensitive
# identifier, not GitHub-casing noise.
function normalize_repo(ref, parts, count, i, normalized) {
  if (index(ref, ":") > 0) {
    return ref
  }
  count = split(ref, parts, "/")
  if (count < 2) {
    return ref
  }
  normalized = tolower(parts[1]) "/" tolower(parts[2])
  for (i = 3; i <= count; i++) {
    normalized = normalized "/" parts[i]
  }
  return normalized
}
function canonical_git_ref(ref, working) {
  working = ref
  if (working ~ /^https:\/\//) {
    sub(/^https:\/\//, "", working)
    sub(/\.git\//, "/", working)
    sub(/\.git$/, "", working)
    sub(/\/$/, "", working)
    sub(/^github\.com\//, "", working)
    return working
  }
  if (working ~ /^git@/) {
    sub(/^git@/, "", working)
    sub(/\.git\//, "/", working)
    sub(/\.git$/, "", working)
    sub(/:/, "/", working)
    return working
  }
  return ""
}
function pinned_commit(ref, canonical, normalized) {
  if (ref in pinned) {
    return pinned[ref]
  }
  normalized = normalize_repo(ref)
  if (normalized in pinned_norm) {
    return pinned_norm[normalized]
  }
  canonical = canonical_git_ref(ref)
  if (canonical != "") {
    if (canonical in pinned) {
      return pinned[canonical]
    }
    normalized = normalize_repo(canonical)
    if (normalized in pinned_norm) {
      return pinned_norm[normalized]
    }
  }
  return ""
}
# Structured "- git: <repo>" entries are pinned by inserting a sibling
# "ref: <sha>" key right after git: (before skills:), never by appending
# "#<sha>" to the git: value itself (apm reads/writes ref: as a separate field;
# see apm_cli.models.dependency.reference for the entry["ref"] contract). The
# item is buffered so the insertion point is independent of where the item
# happens to dedent.
function flush_git_pending(i, pending_key, pin) {
  if (!pending_is_git) {
    return
  }
  pin = ""
  pending_key = pending_repo
  if (pending_path != "") {
    pending_key = pending_key "/" pending_path
  }
  pin = pinned_commit(pending_key)
  print git_line
  if (!pending_has_ref) {
    if (pin != "") {
      printf "%*sref: %s\n", pending_indent + 2, "", pin
      updated++
    }
  }
  for (i = 1; i <= buffer_count; i++) {
    print buffer[i]
  }
  pending_is_git = 0
  pending_has_ref = 0
  pending_repo = ""
  pending_path = ""
  pending_indent = 0
  buffer_count = 0
  git_line = ""
}
BEGIN {
  while ((getline map_line < map_file) > 0) {
    n = split(map_line, cols, "\t")
    if (n < 2) {
      continue
    }
    pinned[cols[1]] = cols[2]
    pinned_norm[normalize_repo(cols[1])] = cols[2]
  }
  close(map_file)
  updated = 0
  pending_is_git = 0
  pending_has_ref = 0
  pending_repo = ""
  pending_path = ""
  pending_indent = 0
  buffer_count = 0
}
{
  current_indent = indent_level($0)

  if (pending_is_git) {
    if ($0 ~ /^[[:space:]]+ref:[[:space:]]+/ && current_indent == pending_indent + 2) {
      pending_has_ref = 1
      buffer[++buffer_count] = $0
      next
    }
    if ($0 ~ /^[[:space:]]+path:[[:space:]]+/ && current_indent == pending_indent + 2) {
      pending_path = $2
      gsub(/["']/, "", pending_path)
      sub(/#.*/, "", pending_path)
    }
    if (current_indent > pending_indent) {
      buffer[++buffer_count] = $0
      next
    }
    flush_git_pending()
  }

  if ($0 ~ /^[[:space:]]*-[[:space:]]+git:[[:space:]]+[^[:space:]]+[[:space:]]*$/) {
    pending_is_git = 1
    pending_has_ref = 0
    pending_repo = $3
    pending_path = ""
    pending_indent = current_indent
    git_line = $0
    buffer_count = 0
    next
  }

  if ($0 ~ /^[[:space:]]*-[[:space:]]+[^[:space:]]+[[:space:]]*(#.*)?$/) {
    match($0, /-[[:space:]]+/)
    prefix = substr($0, 1, RSTART + RLENGTH - 1)
    rest = substr($0, RSTART + RLENGTH)
    match(rest, /^[^[:space:]]+/)
    ref = substr(rest, RSTART, RLENGTH)
    trailing = substr(rest, RLENGTH + 1)

    if (ref != "git:" && index(ref, "#") == 0) {
      if (ref in pinned) {
        print prefix ref "#" pinned[ref] trailing
        updated++
        next
      }
      norm_ref = normalize_repo(ref)
      if (norm_ref in pinned_norm) {
        print prefix ref "#" pinned_norm[norm_ref] trailing
        updated++
        next
      }
    }
  }

  print
}
END {
  flush_git_pending()
  printf "%d\n", updated > "/dev/stderr"
}
