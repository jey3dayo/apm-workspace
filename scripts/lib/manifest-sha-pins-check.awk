# Reads lock records ("repo_url|virtual_path|resolved_commit|resolved_ref"),
# a "@@" separator line, then manifest pins ("entry|sha|mode|key" from
# manifest-sha-pins.awk). Prints "entry#sha (reason)" for each pin whose own
# lock record(s) are absent or carry a different commit; a "path" pin matches
# the record keyed repo_url[/virtual_path], a "repo" pin every record of that
# repo_url; keys compare case-insensitively (GitHub owners). Invoked as:
#   { lock_records; echo @@; pins; } | awk -f scripts/lib/manifest-sha-pins-check.awk
/^@@$/ {
  in_pins = 1
  next
}
!in_pins {
  split($0, record, "|")
  count++
  repo[count] = record[1]
  path_key[count] = record[2] == "" ? record[1] : record[1] "/" record[2]
  commit[count] = record[3]
  next
}
{
  split($0, pin, "|")
  matched = 0
  stale = 0
  for (i = 1; i <= count; i++) {
    key_of_record = (pin[3] == "repo") ? repo[i] : path_key[i]
    if (tolower(key_of_record) != tolower(pin[4])) {
      continue
    }
    matched++
    if (index(commit[i], pin[2]) != 1) {
      stale++
    }
  }
  if (matched == 0) {
    printf "%s#%s (no lock record)\n", pin[1], pin[2]
  } else if (stale > 0) {
    printf "%s#%s (lock records a different commit)\n", pin[1], pin[2]
  }
}
