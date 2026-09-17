# Shared ref-normalization helpers for apm.yml `git:` values. apm.yml keeps
# whatever form the author wrote (full URL, SCP-style, gist, shorthand), while
# apm records the lockfile repo_url in a canonical form: the scheme and a
# trailing .git are dropped, github.com (the default host) is dropped
# entirely (https://github.com/owner/repo(.git) -> owner/repo), a non-default
# host keeps its FQDN (https://gitlab.com/acme/repo(.git) -> gitlab.com/acme/repo),
# and an SCP-style ref (git@host:owner/repo.git) becomes host/owner/repo. Any
# awk script matching a `git:` value against a canonical `wanted` ref (repo_url
# or a virtual_path) must normalize the same way, or matching silently falls
# back to literal comparison and breaks on non-shorthand refs.
# Loaded as a shared `-f` file ahead of the script that uses these functions:
#   awk -v wanted=<ref> -f scripts/lib/manifest-ref-normalize.awk -f <script>.awk <manifest_path>
function gist_key(ref, stripped) {
  if (ref !~ /^https:\/\/gist\.github\.com\//) {
    return ""
  }
  stripped = ref
  sub(/^https:\/\/gist\.github\.com\//, "", stripped)
  sub(/\.git$/, "", stripped)
  return stripped
}
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
