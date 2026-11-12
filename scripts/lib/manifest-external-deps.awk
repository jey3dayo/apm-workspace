# Filters a manifest down to what an install probe needs: every top-level key is
# kept, `dependencies.apm` entries whose repository is jey3dayo/apm-workspace
# (string or `git:` form; comments and refs are not consulted) are dropped, and
# the `dependencies.mcp` subtree is dropped. With -v only=<dependency>, the whole
# `dependencies.apm` list is replaced by that single entry. Invoked as:
#   awk [-v only=<owner/repo#ref>] -f scripts/lib/manifest-ref-normalize.awk -f scripts/lib/manifest-external-deps.awk <manifest_path>
function repo_id(value, id) {
  sub(/[[:space:]]+#.*$/, "", value)
  id = canonical_ref(value)
  if (id == "") {
    id = value
  }
  sub(/^github\.com\//, "", id)
  sub(/\.git$/, "", id)
  return tolower(id)
}
function note_entry_line(line, first, value) {
  value = line
  sub(/^[[:space:]]*(-[[:space:]]+)?/, "", value)
  if (value ~ /^git:[[:space:]]+/) {
    sub(/^git:[[:space:]]+/, "", value)
    entry_repo = repo_id(value)
  } else if (first) {
    sub(/[[:space:]]+#.*$/, "", value)
    sub(/#.*$/, "", value)
    entry_repo = repo_id(value)
  }
}
function flush() {
  if (entry != "" && entry_repo != "jey3dayo/apm-workspace" && index(entry_repo, "jey3dayo/apm-workspace/") != 1) {
    printf "%s", entry
  }
  entry = ""
  entry_repo = ""
}
/^[^[:space:]#]/ {
  flush()
  in_dependencies = ($0 ~ /^dependencies:/)
  in_apm = 0
  in_mcp = 0
  print
  next
}
in_dependencies && /^  [^[:space:]#-]/ {
  flush()
  in_apm = ($0 ~ /^  apm:/)
  in_mcp = ($0 ~ /^  mcp:/)
  if (!in_mcp) {
    print
  }
  if (in_apm && only != "") {
    print "    - " only
  }
  next
}
in_mcp || (in_apm && only != "") {
  next
}
in_apm && /^    -[[:space:]]/ {
  flush()
  entry = $0 "\n"
  note_entry_line($0, 1)
  next
}
in_apm && entry != "" && /^      / {
  entry = entry $0 "\n"
  note_entry_line($0, 0)
  next
}
{
  flush()
  print
}
END {
  flush()
}
