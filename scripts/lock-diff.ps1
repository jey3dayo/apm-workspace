#!/usr/bin/env pwsh

[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

$scriptPath = if ($env:APM_LOCK_DIFF_SCRIPT) {
  $env:APM_LOCK_DIFF_SCRIPT
}
else {
  [IO.Path]::Combine($repoRoot, 'scripts', 'lock-diff.ts')
}

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  Write-Error "Lock diff helper missing: $scriptPath"
  exit 1
}

$arguments = @($scriptPath) + $Args
& tsx @arguments
exit $LASTEXITCODE
