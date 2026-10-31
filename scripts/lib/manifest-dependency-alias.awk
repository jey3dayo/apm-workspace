# Prints the `alias:` value declared alongside the object-form dependency entry
# (`- git: <ref>` ... `alias: <name>`) matching the wanted ref, or nothing when
# the dependency has no object-form entry or no alias field. The wanted ref is
# matched against the literal git: value, the gist key, and the canonical
# lockfile form (see manifest-ref-normalize.awk), because apm.yml keeps
# whatever form the author wrote.
# Invoked as:
#   awk -v wanted=<ref> -f scripts/lib/manifest-ref-normalize.awk -f scripts/lib/manifest-dependency-alias.awk <manifest_path>
function flush_dependency() {
  if (current_ref != "" && current_alias != "" && dependency_ref_matches(wanted, current_ref, current_path)) {
    print current_alias
    found = 1
  }
  current_ref = ""
  current_path = ""
  current_alias = ""
}
/^    - git:[[:space:]]*/ {
  flush_dependency()
  if (found) {
    exit
  }
  current_ref = $3
  current_path = ""
  current_alias = ""
  next
}
/^    - [^[:space:]]/ {
  flush_dependency()
  if (found) {
    exit
  }
  next
}
/^      path:[[:space:]]*/ {
  current_path = $2
  gsub(/["']/, "", current_path)
  next
}
/^      alias:[[:space:]]+/ {
  value = substr($0, index($0, ":") + 1)
  sub(/^[[:space:]]+/, "", value)
  sub(/[[:space:]]+#.*$/, "", value)
  sub(/[[:space:]]+$/, "", value)
  gsub(/"/, "", value)
  current_alias = value
  next
}
END {
  if (!found && current_ref != "" && current_alias != "" && dependency_ref_matches(wanted, current_ref, current_path)) {
    print current_alias
  }
}
