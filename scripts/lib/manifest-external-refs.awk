# Emits every external dependency ref under `dependencies.apm:` in apm.yml,
# excluding the workspace's own catalog and local ./ refs. Structured git
# dependencies include a sibling `path:` in their identity. Unlike
# manifest-unpinned-refs.awk this does not care about pinning, it is a plain
# inventory. Invoked as:
#   awk -f scripts/lib/manifest-external-refs.awk <manifest_path>
function indent_level(line, trimmed) {
  trimmed = line
  sub(/^[[:space:]]+/, "", trimmed)
  return length(line) - length(trimmed)
}
function flush_dependency(ref) {
  if (dependency_ref == "") {
    return
  }
  ref = dependency_ref
  if (dependency_path != "") {
    ref = ref "/" dependency_path
  }
  if (ref !~ /^jey3dayo\/apm-workspace\/catalog(#|$)/ && ref !~ /^\.\//) {
    print ref
  }
  dependency_ref = ""
  dependency_path = ""
}
/^[^[:space:]#][^:]*:/ {
  flush_dependency()
  split($0, parts, ":")
  key = parts[1]
  in_dependencies = (key == "dependencies")
  dependencies_indent = in_dependencies ? 0 : -1
  in_apm = 0
  apm_indent = -1
  next
}
!in_dependencies {
  next
}
/^[[:space:]]+[^-[:space:]#][^:]*:/ {
  current_indent = indent_level($0)
  line = $0
  sub(/^[[:space:]]+/, "", line)
  split(line, parts, ":")
  key = parts[1]

  if (current_indent <= dependencies_indent) {
    in_dependencies = 0
    dependencies_indent = -1
    in_apm = 0
    apm_indent = -1
    next
  }

  if (current_indent == dependencies_indent + 2 && key == "apm") {
    in_apm = 1
    apm_indent = current_indent
    next
  }

  if (in_apm && current_indent <= apm_indent) {
    in_apm = 0
    apm_indent = -1
  }
  if (in_apm && current_indent == apm_indent + 4 && $0 ~ /^[[:space:]]+path:[[:space:]]*/) {
    line = $0
    sub(/^[[:space:]]*path:[[:space:]]*/, "", line)
    sub(/[[:space:]]+#.*$/, "", line)
    sub(/^["']/, "", line)
    sub(/["'][[:space:]]*$/, "", line)
    dependency_path = line
  }
  next
}
!in_apm {
  next
}
/^[[:space:]]*-[[:space:]]+/ {
  current_indent = indent_level($0)
  if (current_indent != apm_indent + 2) {
    next
  }
  flush_dependency()
  ref = $2
  if (ref == "git:") {
    ref = $3
  }
  if (ref == "") {
    next
  }
  dependency_ref = ref
  dependency_path = ""
}
END {
  flush_dependency()
}
