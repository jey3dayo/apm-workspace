#!/usr/bin/env pwsh
# Windows mirror of scripts/lint-frontmatter.sh. See that file for why a
# missing helper is a hard failure rather than a silent skip. The helper is
# vendored into this repository (scripts/lint-frontmatter.ts) so the check is
# self-contained on any checkout, including CI runners.

[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

$scriptPath = if ($env:APM_LINT_FRONTMATTER_SCRIPT) {
  $env:APM_LINT_FRONTMATTER_SCRIPT
}
else {
  [IO.Path]::Combine($repoRoot, 'scripts', 'lint-frontmatter.ts')
}

if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  Write-Error "Frontmatter lint helper missing: $scriptPath. The checkout is broken; restore scripts/lint-frontmatter.ts or point APM_LINT_FRONTMATTER_SCRIPT at a copy."
  exit 1
}

$arguments = @($scriptPath) + $Args
& tsx @arguments
exit $LASTEXITCODE
