# Emits "entry|sha|mode|key" for every SHA-like (7-40 lowercase hex) ref declared under
# `dependencies.apm:` in apm.yml, in both the `- owner/repo/path#<sha>` string
# form and the `- git: <url>` + `ref: <sha>` object form. Tag/branch refs and
# the sibling `mcp:` subtree are ignored. `key` is the lock identity to match:
# mode "path" keys on repo_url[/virtual_path] (string form), mode "repo" on the
# normalized repo_url (object form). Invoked as:
#   awk -f scripts/lib/manifest-ref-normalize.awk -f scripts/lib/manifest-sha-pins.awk <manifest_path>
function emit(entry, ref, mode, key) {
  if (ref ~ /^[0-9a-f]+$/ && length(ref) >= 7 && length(ref) <= 40) {
    printf "%s|%s|%s|%s\n", entry, ref, mode, key
  }
}
function repo_key(git_value, key) {
  key = gist_key(git_value)
  if (key == "") {
    key = canonical_ref(git_value)
  }
  if (key == "") {
    key = git_value
  }
  return key
}
/^[[:space:]]*(#|$)/ {
  next
}
/^[^[:space:]]/ {
  in_dependencies = ($0 ~ /^dependencies:/)
  in_apm = 0
  next
}
!in_dependencies {
  next
}
/^  [^[:space:]-]/ {
  in_apm = ($0 ~ /^  apm:/)
  entry = ""
  next
}
!in_apm {
  next
}
/^    -[[:space:]]+/ {
  entry = ""
  value = $0
  sub(/^    -[[:space:]]+/, "", value)
  if (value ~ /^git:[[:space:]]+/) {
    sub(/^git:[[:space:]]+/, "", value)
    sub(/[[:space:]]+#.*$/, "", value)
    entry = value
    entry_key = repo_key(value)
    next
  }
  sub(/[[:space:]]+#.*$/, "", value)
  hash = index(value, "#")
  if (hash > 0) {
    emit(substr(value, 1, hash - 1), substr(value, hash + 1), "path", substr(value, 1, hash - 1))
  }
  next
}
/^      ref:[[:space:]]+/ {
  value = $0
  sub(/^      ref:[[:space:]]+/, "", value)
  sub(/[[:space:]]+#.*$/, "", value)
  if (entry != "") {
    emit(entry, value, "repo", entry_key)
  }
  next
}
