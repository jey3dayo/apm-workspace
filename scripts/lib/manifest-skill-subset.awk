# Emits the skill names declared under `skills:` for the object-form dependency
# entry whose `git:` value equals the wanted ref. Invoked as:
#   awk -v wanted=<ref> -f scripts/lib/manifest-skill-subset.awk <manifest_path>
function indent_level(line, trimmed) {
  trimmed = line
  sub(/^[[:space:]]+/, "", trimmed)
  return length(line) - length(trimmed)
}
/^    - git:[[:space:]]*/ {
  current_ref = $3
  in_skills = 0
  skills_indent = -1
  next
}
/^    - [^[:space:]]/ {
  current_ref = ""
  in_skills = 0
  skills_indent = -1
  next
}
current_ref != wanted {
  next
}
/^      skills:[[:space:]]*$/ {
  in_skills = 1
  skills_indent = indent_level($0)
  next
}
in_skills && indent_level($0) <= skills_indent {
  in_skills = 0
  next
}
in_skills && /^[[:space:]]*-[[:space:]]+/ {
  value = $2
  gsub(/"/, "", value)
  print value
}
