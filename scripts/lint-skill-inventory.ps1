#!/usr/bin/env pwsh

[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

$scriptPath = if ($env:APM_LINT_SKILL_INVENTORY_SCRIPT) {
  $env:APM_LINT_SKILL_INVENTORY_SCRIPT
}
else {
  [IO.Path]::Combine($repoRoot, 'scripts', 'lint-skill-inventory.ts')
}

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  Write-Error "Skill inventory lint helper missing: $scriptPath"
  exit 1
}

$arguments = @($scriptPath) + $Args
& tsx @arguments
exit $LASTEXITCODE
