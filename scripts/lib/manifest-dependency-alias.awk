# Prints the `alias:` value declared alongside the object-form dependency entry
# (`- git: <ref>` ... `alias: <name>`) matching the wanted ref, or nothing when
# the dependency has no object-form entry or no alias field. The wanted ref is
# matched against the literal git: value, the gist key, and the canonical
# lockfile form, because apm.yml keeps whatever form the author wrote.
# Invoked as:
#   awk -v wanted=<ref> -f scripts/lib/manifest-dependency-alias.awk <manifest_path>
function gist_key(ref, stripped) {
  if (ref !~ /^https:\/\/gist\.github\.com\//) {
    return ""
  }
  stripped = ref
  sub(/^https:\/\/gist\.github\.com\//, "", stripped)
  sub(/\.git$/, "", stripped)
  return stripped
}
# apm records the lockfile repo_url in a canonical form: the scheme and a
# trailing .git are dropped, github.com (the default host) is dropped entirely
# (https://github.com/owner/repo(.git) -> owner/repo), a non-default host keeps
# its FQDN (https://gitlab.com/acme/repo(.git) -> gitlab.com/acme/repo), and an
# SCP-style ref (git@host:owner/repo.git) becomes host/owner/repo. apm.yml keeps
# whatever form the author wrote under git:, so alias lookups must normalize the
# same way or an aliased dependency on a non-gist host silently falls back to
# the old repo_url-tail derivation.
function canonical_ref(ref, working) {
  working = ref
  if (working ~ /^https:\/\//) {
    sub(/^https:\/\//, "", working)
    sub(/\.git$/, "", working)
    sub(/\/$/, "", working)
    sub(/^github\.com\//, "", working)
    return working
  }
  if (working ~ /^git@/) {
    sub(/^git@/, "", working)
    sub(/\.git$/, "", working)
    sub(/:/, "/", working)
    return working
  }
  return ""
}
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
