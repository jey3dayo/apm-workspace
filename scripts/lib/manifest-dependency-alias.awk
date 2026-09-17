# Prints the `alias:` value declared alongside the object-form dependency entry
# (`- git: <ref>` ... `alias: <name>`) matching the wanted ref, or nothing when
# the dependency has no object-form entry or no alias field. The wanted ref is
# matched against the literal git: value, the gist key, and the canonical
# lockfile form (see manifest-ref-normalize.awk), because apm.yml keeps
# whatever form the author wrote.
# Invoked as:
#   awk -v wanted=<ref> -f scripts/lib/manifest-ref-normalize.awk -f scripts/lib/manifest-dependency-alias.awk <manifest_path>
/^    - git:[[:space:]]*/ {
  current_ref = $3
  current_gist_key = gist_key($3)
  current_canonical_ref = canonical_ref($3)
  next
}
/^    - [^[:space:]]/ {
  current_ref = ""
  current_gist_key = ""
  current_canonical_ref = ""
  next
}
(current_ref != wanted) && (current_gist_key != wanted) && (current_canonical_ref != wanted) {
  next
}
/^      alias:[[:space:]]+/ {
  value = substr($0, index($0, ":") + 1)
  sub(/^[[:space:]]+/, "", value)
  sub(/[[:space:]]+#.*$/, "", value)
  sub(/[[:space:]]+$/, "", value)
  gsub(/"/, "", value)
  if (value != "") {
    print value
    exit
  }
}
