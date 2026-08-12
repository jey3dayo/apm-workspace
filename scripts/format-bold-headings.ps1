#!/usr/bin/env pwsh
# Windows mirror of scripts/format-bold-headings.sh. See that file for why a
# missing helper is a hard failure rather than a silent skip. The helper is
# vendored into this repository (scripts/replace-bold-headings.ts) so the
# check is self-contained on any checkout, including CI runners.

[CmdletBinding()]
param(
  [ValidateSet("write", "check")]
  [string]$Mode = "write"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

$scriptPath = if ($env:APM_BOLD_HEADINGS_SCRIPT) {
  $env:APM_BOLD_HEADINGS_SCRIPT
}
else {
  [IO.Path]::Combine($repoRoot, 'scripts', 'replace-bold-headings.ts')
}

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  Write-Error "Bold heading helper missing: $scriptPath. The checkout is broken; restore scripts/replace-bold-headings.ts or point APM_BOLD_HEADINGS_SCRIPT at a copy."
  exit 1
}

$arguments = @($scriptPath, './catalog')
if ($Mode -eq "check") {
  $arguments += '--dry-run'
}

& tsx @arguments
exit $LASTEXITCODE
