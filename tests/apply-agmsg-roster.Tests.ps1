# PowerShell parity for tests/apply-agmsg-roster.bats: Invoke-Apply
# (apm-workspace.ps1) now saves/restores the agmsg roster around its whole
# body via try/finally, so restore must run even when a step partway through
# throws. Reuses the shared tests/conformance fixture, exactly like
# apply-conformance.Tests.ps1, and forces the fixture's `apm` stub to fail on
# `compile` to simulate a mid-apply failure.
#
# XDG_STATE_HOME is pinned into the fixture explicitly: this session's real
# $XDG_STATE_HOME/agmsg is the actual live roster this suite must never
# touch, and agmsg-state.ps1 only honors $HOME for the deploy-target half of
# its paths, not the store half.

$ErrorActionPreference = "Stop"

Describe "apm-workspace.ps1 apply agmsg roster" {
  BeforeAll {
    $script:workspaceRoot = Split-Path -Parent $PSScriptRoot
    $script:scriptPath = Join-Path $script:workspaceRoot "scripts/apm-workspace.ps1"
    $script:fixtureLib = Join-Path $PSScriptRoot "conformance/build-fixture.sh"
    $script:consoleShell = if (Get-Command powershell -ErrorAction SilentlyContinue) { "powershell" } else { "pwsh" }

    function script:Invoke-FixtureApply {
      & $script:consoleShell -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath apply | Out-Null
      return $LASTEXITCODE
    }

    # Overrides the fixture's `apm` stub so `apm compile ...` fails partway
    # through Invoke-Apply, forcing a thrown error while still exercising the
    # steps before it (including the agmsg-state.ps1 save under test).
    function script:Set-FailingCompileStub {
      $apmBin = Join-Path $script:fixture["BIN_DIR"] "apm"
      $callLog = $script:fixture["CALL_LOG"]
      @"
#!/usr/bin/env bash
printf 'apm %s\n' "`$*" >>"$callLog"
case "`$1" in
  compile) exit 1 ;;
esac
exit 0
"@ | Set-Content -LiteralPath $apmBin -NoNewline
      & chmod +x $apmBin
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

    # Invoke-Apply's skill-tree swap (Replace-SkillTargetsFromStage) wipes
    # the entire deployed skills root and replaces it with only what's
    # staged from the catalog, so agmsg needs to be a managed catalog skill
    # here too — otherwise the swap would delete the agmsg skill dir
    # outright regardless of the save/restore wiring under test.
    $agmsgCatalogSkillDir = Join-Path $script:fixture["WORKSPACE_DIR"] "catalog/skills/agmsg"
    New-Item -ItemType Directory -Path $agmsgCatalogSkillDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $agmsgCatalogSkillDir "SKILL.md") -Value "# agmsg"

    $script:agmsgSkillDir = Join-Path $script:fixture["HOME"] ".agents/skills/agmsg"
    $script:agmsgStateRoot = Join-Path $script:fixture["HOME"] ".local/state/agmsg"
    New-Item -ItemType Directory -Path (Join-Path $script:agmsgSkillDir "db") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:agmsgSkillDir "teams/sample-team") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:agmsgSkillDir "db/messages.db") -Value "message-history" -NoNewline
    Set-Content -LiteralPath (Join-Path $script:agmsgSkillDir "teams/sample-team/config.json") -Value '{"members":[]}' -NoNewline

    $script:savedHome = $env:HOME
    $script:savedWorkspaceDir = $env:APM_WORKSPACE_DIR
    $script:savedPath = $env:PATH
    $script:savedXdg = $env:XDG_STATE_HOME

    $env:HOME = $script:fixture["HOME"]
    $env:APM_WORKSPACE_DIR = $script:fixture["WORKSPACE_DIR"]
    $env:PATH = "$($script:fixture['BIN_DIR']):$($script:savedPath)"
    $env:XDG_STATE_HOME = Join-Path $script:fixture["HOME"] ".local/state"
  }

  AfterEach {
    $env:HOME = $script:savedHome
    $env:APM_WORKSPACE_DIR = $script:savedWorkspaceDir
    $env:PATH = $script:savedPath
    if ($null -eq $script:savedXdg) {
      Remove-Item Env:XDG_STATE_HOME -ErrorAction SilentlyContinue
    }
    else {
      $env:XDG_STATE_HOME = $script:savedXdg
    }
  }

  It "relinks the agmsg roster even when apply fails partway through" {
    Set-FailingCompileStub

    $exitCode = Invoke-FixtureApply
    $exitCode | Should -Not -Be 0

    (Get-Item -LiteralPath (Join-Path $script:agmsgSkillDir "db")).LinkType | Should -Be "SymbolicLink"
    (Get-Item -LiteralPath (Join-Path $script:agmsgSkillDir "teams")).LinkType | Should -Be "SymbolicLink"
    Get-Content -LiteralPath (Join-Path $script:agmsgStateRoot "db/messages.db") -Raw | Should -Be "message-history"
    Get-Content -LiteralPath (Join-Path $script:agmsgStateRoot "teams/sample-team/config.json") -Raw | Should -Be '{"members":[]}'
  }

  It "relinks the agmsg roster on success too" {
    $exitCode = Invoke-FixtureApply
    $exitCode | Should -Be 0

    (Get-Item -LiteralPath (Join-Path $script:agmsgSkillDir "db")).LinkType | Should -Be "SymbolicLink"
    (Get-Item -LiteralPath (Join-Path $script:agmsgSkillDir "teams")).LinkType | Should -Be "SymbolicLink"
  }
}
