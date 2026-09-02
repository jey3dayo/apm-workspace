# Executes `scripts/apm-workspace.ps1 apply` as a real subprocess against the
# shared tests/conformance fixture (built via build-fixture.sh, the same
# fixture tests/apply-conformance.bats drives) and holds it to the identical
# official 8-step apply order asserted there:
#   (1) stage assembly -> (2) MCP install -> (3) Codex MCP normalize ->
#   (4) compile -> (5) runtime asset + pi instructions distribution ->
#   (6) swap -> (7) legacy cleanup -> (8) private overlay
#
# report.md Sec.1 originally found Invoke-Apply drifting from this order
# (compile ran after swap/cleanup instead of before, and private-skill
# overlay was missing entirely). plans/apply-core-phase1-ps-parity.md closed
# both gaps, so every assertion below now runs unskipped.

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

    # Identifies the on-disk directory instance. On Unix use the inode (same
    # contract as apply-conformance.bats): .NET's CreationTimeUtc on Linux is
    # not a stable birth time and moves when children are added or removed,
    # which made the root-swap assertion fail on ubuntu CI while the root was
    # in fact never recreated. Windows has a real creation time, so keep it.
    function script:Get-DirectoryIdentity {
      param([Parameter(Mandatory = $true)][string]$Path)
      if ($IsWindows) {
        return (Get-Item -LiteralPath $Path).CreationTimeUtc.Ticks.ToString()
      }
      $statFormat = if ($IsMacOS) { @("-f", "%i") } else { @("-c", "%i") }
      return (& stat @statFormat -- $Path).Trim()
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

  It "runtime asset distribution (step 5) overwrites the compiled Codex output (step 4)" {
    Invoke-FixtureApply | Should -Be 0

    $codexAgentsPath = Join-Path $script:fixture["HOME"] ".codex/AGENTS.md"
    (Get-Content -LiteralPath $codexAgentsPath -Raw).Trim() | Should -Be "# instructions"
  }

  It "private skill overlay (step 8) survives the managed skill swap (step 6)" {
    Invoke-FixtureApply | Should -Be 0

    Join-Path $script:fixture["HOME"] ".agents/skills/sample-private-skill" | Should -Exist
    $claudeLinkPath = Join-Path $script:fixture["HOME"] ".claude/skills/sample-private-skill"
    $claudeLinkPath | Should -Exist
    (Get-Item -LiteralPath $claudeLinkPath).LinkType | Should -Be "SymbolicLink"
  }

  # Contract: the managed skill swap (step 6, Reconcile-SkillsRootFromStage)
  # never moves or removes the skills root directory itself -- only its
  # child skill dirs are replaced one at a time. A root-level swap (the old
  # Replace-DirectoryTreeFromSource-for-the-whole-root behavior) would make
  # the root briefly not exist, which is unsafe for a live agent depending
  # on in-place state under that root (e.g. agmsg's helper scripts) between
  # apply runs. Get-DirectoryIdentity (inode on Unix, creation time on
  # Windows) identifies the on-disk directory instance: a Move-Item swap
  # would produce a new directory even if the path is identical afterward.
  It "does not recreate the skills root directory itself during swap" {
    $claudeSkillsRoot = Join-Path $script:fixture["HOME"] ".claude/skills"
    $staleSkillDir = Join-Path $claudeSkillsRoot "stale-skill"
    New-Item -ItemType Directory -Path $staleSkillDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $staleSkillDir "SKILL.md") -Value "# stale"
    $rootIdentityBefore = Get-DirectoryIdentity -Path $claudeSkillsRoot

    Invoke-FixtureApply | Should -Be 0

    Get-DirectoryIdentity -Path $claudeSkillsRoot | Should -Be $rootIdentityBefore
    $staleSkillDir | Should -Not -Exist
    Join-Path $claudeSkillsRoot "sample-skill/SKILL.md" | Should -Exist
  }

  # Also seeds a `.apm-skills-backup-*` dir as if a previous apply run had
  # crashed mid-swap and left its backup behind: Reconcile-SkillsRootFromStage
  # must still sweep it, not just avoid creating new ones of its own. The old
  # whole-root swap cleaned these incidentally (the parent dir holding them
  # was the very root being replaced); the new per-child reconcile has no
  # such side effect, so it sweeps known-stale `.apm-skills-*` prefixes
  # explicitly instead.
  It "leaves no swap staging/backup directories under the skills root" {
    $claudeSkillsRoot = Join-Path $script:fixture["HOME"] ".claude/skills"
    $staleBackupDir = Join-Path $claudeSkillsRoot ".apm-skills-backup-deadbeef"
    New-Item -ItemType Directory -Path $staleBackupDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $staleBackupDir "SKILL.md") -Value "# stale backup"

    Invoke-FixtureApply | Should -Be 0

    $leftoverSwapDirs = @(Get-ChildItem -LiteralPath $claudeSkillsRoot -Force -Directory | Where-Object { $_.Name -like ".apm-*" })
    $leftoverSwapDirs.Count | Should -Be 0
    $staleBackupDir | Should -Not -Exist
  }
}
