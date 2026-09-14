# Emits one "repo_url|virtual_path|resolved_commit|resolved_ref" record per
# entry under `dependencies:` in apm.lock.yaml. Invoked as:
#   awk -f scripts/lib/lockfile-dependencies.awk <lock_path>
function indent_level(line, trimmed) {
  trimmed = line
  sub(/^[[:space:]]+/, "", trimmed)
  return length(line) - length(trimmed)
}
function flush_record() {
  if (repo_url != "" && resolved_commit != "") {
    printf "%s|%s|%s|%s\n", repo_url, virtual_path, resolved_commit, resolved_ref
  }
}
/^[^[:space:]#-][^:]*:/ {
  if (in_dependencies && repo_url != "") {
    flush_record()
    repo_url = ""
    resolved_commit = ""
    resolved_ref = ""
    virtual_path = ""
    record_indent = -1
  }

  split($0, parts, ":")
  key = parts[1]
  in_dependencies = (key == "dependencies")
  dependencies_indent = in_dependencies ? 0 : -1
  next
}
!in_dependencies {
  next
}
/^[[:space:]]*-[[:space:]]+repo_url:[[:space:]]+/ {
  flush_record()
  repo_url = substr($0, index($0, ":") + 1)
  sub(/^[[:space:]]+/, "", repo_url)
  resolved_commit = ""
  resolved_ref = ""
  virtual_path = ""
  record_indent = indent_level($0)
  next
}
/^[[:space:]]+resolved_commit:[[:space:]]+/ {
  if (repo_url == "" || indent_level($0) <= record_indent) {
    next
  }
  resolved_commit = substr($0, index($0, ":") + 1)
  sub(/^[[:space:]]+/, "", resolved_commit)
  next
}
/^[[:space:]]+resolved_ref:[[:space:]]+/ {
  if (repo_url == "" || indent_level($0) <= record_indent) {
    next
  }
  resolved_ref = substr($0, index($0, ":") + 1)
  sub(/^[[:space:]]+/, "", resolved_ref)
  next
}
/^[[:space:]]+virtual_path:[[:space:]]+/ {
  if (repo_url == "" || indent_level($0) <= record_indent) {
    next
  }
  virtual_path = substr($0, index($0, ":") + 1)
  sub(/^[[:space:]]+/, "", virtual_path)
  next
}
END {
  flush_record()
}
