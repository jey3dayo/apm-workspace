# Emits the source form, base form, and canonical lockfile form of each
# manifest dependency reference. Load manifest-ref-normalize.awk first.
{
  if (NF == 0) {
    next
  }
  print $0
  base = $0
  sub(/#.*/, "", base)
  print base

  gist = gist_key(base)
  if (gist != "") {
    print gist
    next
  }

  canonical = canonical_ref(base)
  if (canonical != "") {
    print canonical
  }
}
