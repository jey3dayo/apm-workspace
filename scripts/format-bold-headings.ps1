#!/usr/bin/env pwsh
# Windows mirror of scripts/format-bold-headings.sh. See that file for why a
# missing helper is a hard failure rather than a silent skip.

[CmdletBinding()]
param(
  [ValidateSet("write", "check")]
  [string]$Mode = "write"
)

$ErrorActionPreference = "Stop"

$scriptPath = if ($env:APM_BOLD_HEADINGS_SCRIPT) {
  $env:APM_BOLD_HEADINGS_SCRIPT
}
else {
  [IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'), '.config', 'scripts', 'replace-bold-headings.ts')
}

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  if ($env:APM_ALLOW_MISSING_BOLD_HEADINGS -eq "1") {
    Write-Warning "Skipping bold heading $Mode`: $scriptPath not found (APM_ALLOW_MISSING_BOLD_HEADINGS=1)."
    exit 0
  }

  Write-Error "Bold heading helper missing: $scriptPath. Restore it, point APM_BOLD_HEADINGS_SCRIPT at a copy, or set APM_ALLOW_MISSING_BOLD_HEADINGS=1 to bypass."
  exit 1
}

$arguments = @($scriptPath, './catalog')
if ($Mode -eq "check") {
  $arguments += '--dry-run'
}

& tsx @arguments
exit $LASTEXITCODE
