# Emits the skill names declared under `skills:` for the object-form dependency
# entry whose `git:` value matches the wanted ref. The wanted ref is matched
# against the literal git: value, the gist key, and the canonical lockfile
# form (see manifest-ref-normalize.awk), because apm.yml keeps whatever form
# the author wrote. Invoked as:
#   awk -v wanted=<ref> -f scripts/lib/manifest-ref-normalize.awk -f scripts/lib/manifest-skill-subset.awk <manifest_path>
function indent_level(line, trimmed) {
  trimmed = line
  sub(/^[[:space:]]+/, "", trimmed)
  return length(line) - length(trimmed)
}
function flush_dependency(i) {
  if (current_ref != "" && dependency_ref_matches(wanted, current_ref, current_path)) {
    for (i = 1; i <= skill_count; i++) {
      print skill_names[i]
    }
  }
  for (i = 1; i <= skill_count; i++) {
    delete skill_names[i]
  }
  current_ref = ""
  current_path = ""
  skill_count = 0
  in_skills = 0
  skills_indent = -1
}
/^    - git:[[:space:]]*/ {
  flush_dependency()
  current_ref = $3
  current_path = ""
  in_skills = 0
  skills_indent = -1
  next
}
/^    - [^[:space:]]/ {
  flush_dependency()
  next
}
/^      path:[[:space:]]*/ {
  current_path = $2
  gsub(/["']/, "", current_path)
  next
}
/^      skills:[[:space:]]*$/ {
  in_skills = 1
  skills_indent = indent_level($0)
  next
}
in_skills && indent_level($0) <= skills_indent {
  in_skills = 0
}
in_skills && /^[[:space:]]*-[[:space:]]+/ {
  value = $2
  gsub(/"/, "", value)
  skill_names[++skill_count] = value
}
END {
  flush_dependency()
}
