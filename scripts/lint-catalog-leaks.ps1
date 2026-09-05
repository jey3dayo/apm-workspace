#!/usr/bin/env pwsh
# Windows mirror of scripts/lint-catalog-leaks.sh. The helper is vendored
# into this repository so the check is self-contained on any checkout.

[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

$scriptPath = if ($env:APM_LINT_CATALOG_LEAKS_SCRIPT) {
  $env:APM_LINT_CATALOG_LEAKS_SCRIPT
}
else {
  [IO.Path]::Combine($repoRoot, 'scripts', 'lint-catalog-leaks.ts')
}

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  Write-Error "Catalog leak lint helper missing: $scriptPath. The checkout is broken; restore scripts/lint-catalog-leaks.ts or point APM_LINT_CATALOG_LEAKS_SCRIPT at a copy."
  exit 1
}

$arguments = @($scriptPath) + $Args
& tsx @arguments
exit $LASTEXITCODE
