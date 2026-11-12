# Reads manifest pins ("entry|sha|mode|key" from manifest-sha-pins.awk), a "@@"
# separator line, then docs/dependency-holds.txt ("<repo> <held-sha> <reason>",
# "#" comment lines and blank lines skipped). Prints "repo|held-sha|actual|reason"
# for each hold with a pin (nested path pins included) on a different sha, or
# with none; actual is "(no SHA pin)" when apm.yml carries none. A pin belongs
# to a repo by the first two segments of its key ("owner/repo", a leading
# "github.com/" dropped), compared case-insensitively. Invoked as:
#   { pins; echo @@; cat holds; } | awk -f scripts/lib/dependency-holds-check.awk
function repo_id(key, segments) {
  sub(/^github\.com\//, "", key)
  split(key, segments, "/")
  return tolower(segments[1] "/" segments[2])
}
/^@@$/ {
  in_holds = 1
  next
}
!in_holds {
  split($0, pin, "|")
  pin_count++
  pin_key[pin_count] = repo_id(pin[4])
  pin_sha[pin_count] = pin[2]
  next
}
/^[[:space:]]*(#|$)/ {
  next
}
{
  repo = $1
  held = $2
  reason = $0
  sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]*/, "", reason)
  total = 0
  held_matches = 0
  actual = ""
  for (i = 1; i <= pin_count; i++) {
    if (pin_key[i] != repo_id(repo)) {
      continue
    }
    total++
    actual = actual (actual == "" ? "" : ",") pin_sha[i]
    if (pin_sha[i] == held) {
      held_matches++
    }
  }
  if (total == 0) {
    actual = "(no SHA pin)"
  }
  if (total == 0 || held_matches != total) {
    printf "%s|%s|%s|%s\n", repo, held, actual, reason
  }
}
