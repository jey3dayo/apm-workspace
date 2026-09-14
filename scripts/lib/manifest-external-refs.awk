# Emits every external dependency ref under `dependencies.apm:` in apm.yml,
# excluding the workspace's own catalog and local ./ refs. Unlike
# manifest-unpinned-refs.awk this does not care about pinning, it is a plain
# inventory. Invoked as:
#   awk -f scripts/lib/manifest-external-refs.awk <manifest_path>
function indent_level(line, trimmed) {
  trimmed = line
  sub(/^[[:space:]]+/, "", trimmed)
  return length(line) - length(trimmed)
}
/^[^[:space:]#][^:]*:/ {
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
  next
}
!in_apm {
  next
}
/^[[:space:]]*-[[:space:]]+/ {
  if (indent_level($0) != apm_indent + 2) {
    next
  }
  ref = $2
  if (ref == "git:") {
    ref = $3
  }
  if (ref == "") {
    next
  }
  if (ref ~ /^jey3dayo\/apm-workspace\/catalog(#|$)/) {
    next
  }
  if (ref ~ /^\.\//) {
    next
  }
  print ref
}
