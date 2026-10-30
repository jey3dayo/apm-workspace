BEGIN { expected = 0; actual = 0; changes = 0; complete = 0; started = 0 }
/^\[>\] Analyzing installed packages vs apm.yml\.\.\.$/ { started++; next }
/^\[i\] Retained .+: required package content\.$/ { next }
/^\[!\] Found [0-9]+ orphaned package\(s\):$/ { expected += $3; changes = 1; next }
/^\[!\]   - [A-Za-z0-9_.\/-]+ \(would be removed\)$/ {
  path = $3
  if (path ~ /^\// || path ~ /(^|\/)\.\.?($|\/)/ || path ~ /\/\//) { exit 1 }
  actual++; next
}
/^\[!\] Found [0-9]+ invalid deployment ownership record\(s\) in apm.lock.yaml\.$/ { changes = 1; next }
/^\[i\] Found [0-9]+ stale lockfile dependency record\(s\) without removable package content\.$/ { changes = 1; next }
/^\[i\] \[dry-run\] (remove [0-9]+ stale lockfile dependency record\(s\)|repair .+)$/ { changes = 1; next }
/^\[\*\] Dry run complete - no changes made$/ { complete++; next }
/^\[\+\] No orphaned packages found\. apm_modules\/ is clean\.$/ { complete++; next }
/^\[i\] No apm_modules\/ directory found\. Nothing to prune\.$/ { complete++; next }
{ invalid = 1 }
END {
  if (invalid || started != 1 || complete != 1 || expected != actual) { exit 1 }
  print changes ? "changes" : "clean"
}
