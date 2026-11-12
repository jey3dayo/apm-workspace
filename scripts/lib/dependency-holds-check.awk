# Reads manifest pins ("entry|sha|mode|key" from manifest-sha-pins.awk), a "@@"
# separator line, then docs/dependency-holds.txt ("<repo> <held-sha> <reason>",
# "#" comment lines and blank lines skipped). Prints "repo|held-sha|actual|reason"
# for each hold whose repo is not pinned to the held sha; actual is "(no SHA pin)"
# when apm.yml carries none. Repos compare case-insensitively. Invoked as:
#   { pins; echo @@; cat holds; } | awk -f scripts/lib/dependency-holds-check.awk
/^@@$/ {
  in_holds = 1
  next
}
!in_holds {
  split($0, pin, "|")
  pin_count++
  pin_key[pin_count] = tolower(pin[4])
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
    if (pin_key[i] != tolower(repo)) {
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
