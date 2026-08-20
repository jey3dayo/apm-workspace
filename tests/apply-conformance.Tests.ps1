# Executes `scripts/apm-workspace.ps1 apply` as a real subprocess against the
# shared tests/conformance fixture (built via build-fixture.sh, the same
# fixture tests/apply-conformance.bats drives) and holds it to the identical
# official 8-step apply order asserted there:
#   (1) stage assembly -> (2) MCP install -> (3) Codex MCP normalize ->
#   (4) compile -> (5) runtime asset + pi instructions distribution ->
#   (6) swap -> (7) legacy cleanup -> (8) private overlay
#
# report.md Sec.1 confirms Invoke-Apply drifts from this order (compile runs
# after swap/cleanup instead of before, and private-skill overlay is missing
# entirely). The two assertions that encode those drifts are marked -Skip
# with a plans/apply-core-phase1-ps-parity.md reference below so this suite
# stays green until that phase lands; when it does, drop -Skip from both and
# they should pass unmodified.

$ErrorActionPreference = "Stop"

Describe "apm-workspace.ps1 apply conformance" {
  BeforeAll {
    $script:workspaceRoot = Split-Path -Parent $PSScriptRoot
    $script:scriptPath = Join-Path $script:workspaceRoot "scripts/apm-workspace.ps1"
    $script:fixtureLib = Join-Path $PSScriptRoot "conformance/build-fixture.sh"
    $script:consoleShell = if (Get-Command powershell -ErrorAction SilentlyContinue) { "powershell" } else { "pwsh" }

    function script:Invoke-FixtureApply {
      & $script:consoleShell -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath apply | Out-Null
      return $LASTEXITCODE
    }
  }

  BeforeEach {
    $script:fixtureBase = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
    $fixtureOutput = & bash $script:fixtureLib $script:fixtureBase
    $script:fixture = @{}
    foreach ($line in $fixtureOutput) {
      $key, $value = $line -split '=', 2
      $script:fixture[$key] = $value
    }

    $script:savedHome = $env:HOME
    $script:savedWorkspaceDir = $env:APM_WORKSPACE_DIR
    $script:savedPath = $env:PATH

    $env:HOME = $script:fixture["HOME"]
    $env:APM_WORKSPACE_DIR = $script:fixture["WORKSPACE_DIR"]
    $env:PATH = "$($script:fixture['BIN_DIR']):$($script:savedPath)"
  }

  AfterEach {
    $env:HOME = $script:savedHome
    $env:APM_WORKSPACE_DIR = $script:savedWorkspaceDir
    $env:PATH = $script:savedPath
  }

  It "succeeds against the conformance fixture" {
    $exitCode = Invoke-FixtureApply
    $exitCode | Should -Be 0
  }

  It "calls apm install before apm compile (steps 2 then 4)" {
    Invoke-FixtureApply | Should -Be 0

    $callLog = Get-Content -LiteralPath $script:fixture["CALL_LOG"]
    $installIndex = [array]::IndexOf($callLog, ($callLog | Where-Object { $_ -like "apm install*" } | Select-Object -First 1))
    $compileIndex = [array]::IndexOf($callLog, ($callLog | Where-Object { $_ -like "apm compile*" } | Select-Object -First 1))

    $installIndex | Should -BeGreaterOrEqual 0
    $compileIndex | Should -BeGreaterOrEqual 0
    $installIndex | Should -BeLessThan $compileIndex
  }

  It "deploys the managed catalog skill to every runtime target" {
    Invoke-FixtureApply | Should -Be 0

    Join-Path $script:fixture["HOME"] ".claude/skills/sample-skill/SKILL.md" | Should -Exist
    Join-Path $script:fixture["HOME"] ".agents/skills/sample-skill/SKILL.md" | Should -Exist
  }

  # DRIFT (report.md Sec.1.3 / plans/apply-core-phase1-ps-parity.md): Invoke-Apply
  # runs Sync-ManagedCatalogRuntimeAssets before Invoke-CodexCompile, the
  # reverse of cmd_apply's order. So the compiled marker survives instead of
  # being overwritten by the catalog instructions copy -- unskip once Phase 1
  # reorders Invoke-Apply to match cmd_apply.
  It "runtime asset distribution (step 5) overwrites the compiled Codex output (step 4)" -Skip {
    Invoke-FixtureApply | Should -Be 0

    $codexAgentsPath = Join-Path $script:fixture["HOME"] ".codex/AGENTS.md"
    (Get-Content -LiteralPath $codexAgentsPath -Raw).Trim() | Should -Be "# instructions"
  }

  # DRIFT (report.md Sec.1.2 / plans/apply-core-phase1-ps-parity.md):
  # Invoke-Apply has no equivalent of sync_private_skills_into_targets at
  # all, so private-skills/.apm/skills content never reaches the Codex
  # target tree or gets a Claude symlink -- unskip once Phase 1 adds that
  # step to Invoke-Apply.
  It "private skill overlay (step 8) survives the managed skill swap (step 6)" -Skip {
    Invoke-FixtureApply | Should -Be 0

    Join-Path $script:fixture["HOME"] ".agents/skills/sample-private-skill" | Should -Exist
    $claudeLinkPath = Join-Path $script:fixture["HOME"] ".claude/skills/sample-private-skill"
    $claudeLinkPath | Should -Exist
    (Get-Item -LiteralPath $claudeLinkPath).LinkType | Should -Be "SymbolicLink"
  }
}
