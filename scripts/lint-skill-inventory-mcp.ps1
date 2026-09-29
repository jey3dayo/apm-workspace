#!/usr/bin/env pwsh

[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

$scriptPath = if ($env:APM_LINT_SKILL_INVENTORY_MCP_SCRIPT) {
  $env:APM_LINT_SKILL_INVENTORY_MCP_SCRIPT
}
else {
  [IO.Path]::Combine($repoRoot, 'scripts', 'lint-skill-inventory-mcp.ts')
}

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  Write-Error "Skill inventory MCP lint helper missing: $scriptPath"
  exit 1
}

$arguments = @($scriptPath) + $Args
& tsx @arguments
exit $LASTEXITCODE
