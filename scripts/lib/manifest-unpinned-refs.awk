# Emits the repo value of each manifest apm dependency that is not yet pinned
# to a lockfile commit. A structured "- git: <repo>" entry with a sibling
# skills: list reports the repo value (never the literal "git:" key or the
# nested skill names) and is skipped once a sibling "ref:" key is present.
# Invoked as:
#   awk -f scripts/lib/manifest-unpinned-refs.awk <manifest_path>
function indent_level(line, trimmed) {
  trimmed = line
  sub(/^[[:space:]]+/, "", trimmed)
  return length(line) - length(trimmed)
}
function flush_pending() {
  if (pending_is_git && !pending_has_ref && pending_repo != "") {
    print pending_repo
  }
  pending_is_git = 0
  pending_has_ref = 0
  pending_repo = ""
  pending_indent = -1
}
BEGIN {
  pending_is_git = 0
  pending_has_ref = 0
  pending_repo = ""
  pending_indent = -1
}
/^[^[:space:]#][^:]*:/ {
  if (in_apm) {
    flush_pending()
  }
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
in_apm && /^[[:space:]]+ref:[[:space:]]+/ && indent_level($0) > apm_indent {
  if (pending_is_git && indent_level($0) == pending_indent + 2) {
    pending_has_ref = 1
  }
  next
}
/^[[:space:]]+[^-[:space:]#][^:]*:/ {
  current_indent = indent_level($0)
  line = $0
  sub(/^[[:space:]]+/, "", line)
  split(line, parts, ":")
  key = parts[1]

  if (current_indent <= dependencies_indent) {
    if (in_apm) {
      flush_pending()
    }
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
    flush_pending()
    in_apm = 0
    apm_indent = -1
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
  flush_pending()
  ref = $2
  if (ref == "git:") {
    pending_is_git = 1
    pending_has_ref = 0
    pending_repo = $3
    pending_indent = current_indent
    next
  }
  if (ref ~ /^jey3dayo\/apm-workspace\/catalog(#|$)/) {
    next
  }
  if (ref ~ /^\.\//) {
    next
  }
  if (ref !~ /#/) {
    print ref
  }
  next
}
END {
  flush_pending()
}
