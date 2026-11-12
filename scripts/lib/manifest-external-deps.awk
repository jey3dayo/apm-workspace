# Filters a manifest down to what an install probe needs: every top-level key is
# kept, `dependencies.apm` entries that point at jey3dayo/apm-workspace itself
# (string or `git:` object form) are dropped, and the `dependencies.mcp` subtree
# is dropped. With -v only=<dependency>, the whole `dependencies.apm` list is
# replaced by that single entry. Invoked as:
#   awk [-v only=<owner/repo#ref>] -f scripts/lib/manifest-external-deps.awk <manifest_path>
function flush() {
  if (entry != "" && index(tolower(entry), "jey3dayo/apm-workspace") == 0) {
    printf "%s", entry
  }
  entry = ""
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
  next
}
in_apm && entry != "" && /^      / {
  entry = entry $0 "\n"
  next
}
{
  flush()
  print
}
END {
  flush()
}
