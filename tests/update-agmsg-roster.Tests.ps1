# PowerShell parity for tests/update-agmsg-roster.bats: Invoke-Update
# (apm-workspace.ps1 `refresh`) must save/restore the agmsg roster around
# `apm deps update -g`, the same contract Invoke-Apply and
# Invoke-SyncLocalSkills already carry. Observed 2026-09-23: after
# `mise run refresh`, the agmsg db/teams symlinks under
# ~/.agents/skills/agmsg were absent, because Invoke-Update called
# `apm deps update -g` unprotected. Reuses the shared tests/conformance
# fixture, exactly like apply-agmsg-roster.Tests.ps1; the fixture's apm stub
# wipes the deployed agmsg skill dir on `deps update -g` (see
# build-fixture.sh) so this reproduces the bug against the unmodified script
# too.
#
# XDG_STATE_HOME is pinned into the fixture explicitly: this session's real
# $XDG_STATE_HOME/agmsg is the actual live roster this suite must never
# touch, and agmsg-state.ps1 only honors $HOME for the deploy-target half of
# its paths, not the store half.

$ErrorActionPreference = "Stop"

Describe "apm-workspace.ps1 refresh agmsg roster" {
  BeforeAll {
    $script:workspaceRoot = Split-Path -Parent $PSScriptRoot
    $script:scriptPath = Join-Path $script:workspaceRoot "scripts/apm-workspace.ps1"
    $script:fixtureLib = Join-Path $PSScriptRoot "conformance/build-fixture.sh"
    $script:consoleShell = if (Get-Command powershell -ErrorAction SilentlyContinue) { "powershell" } else { "pwsh" }

    function script:Invoke-FixtureRefresh {
      & $script:consoleShell -NoProfile -ExecutionPolicy Bypass -File $script:scriptPath refresh | Out-Null
      return $LASTEXITCODE
    }

    # Overrides the fixture's `apm` stub so `apm deps update -g` reproduces
    # the shared stub's roster wipe and then fails, forcing a thrown error
    # while still exercising the steps before it (including the
    # agmsg-state.ps1 save under test).
    function script:Set-FailingDepsUpdateStub {
      $apmBin = Join-Path $script:fixture["BIN_DIR"] "apm"
      $callLog = $script:fixture["CALL_LOG"]
      @"
#!/usr/bin/env bash
printf 'apm %s\n' "`$*" >>"$callLog"
if [ "`$*" = "deps update -g" ]; then
  if [ -n "`${HOME:-}" ] && [ -d "`$HOME/.agents/skills/agmsg" ]; then
    rm -rf "`$HOME/.agents/skills/agmsg"
    mkdir -p "`$HOME/.agents/skills/agmsg"
  fi
  exit 1
fi
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

  It "keeps the agmsg roster linked on a successful refresh" {
    $exitCode = Invoke-FixtureRefresh
    $exitCode | Should -Be 0

    (Get-Item -LiteralPath (Join-Path $script:agmsgSkillDir "db")).LinkType | Should -Be "SymbolicLink"
    (Get-Item -LiteralPath (Join-Path $script:agmsgSkillDir "teams")).LinkType | Should -Be "SymbolicLink"
    Get-Content -LiteralPath (Join-Path $script:agmsgStateRoot "db/messages.db") -Raw | Should -Be "message-history"
    Get-Content -LiteralPath (Join-Path $script:agmsgStateRoot "teams/sample-team/config.json") -Raw | Should -Be '{"members":[]}'
  }

  It "relinks the agmsg roster even when apm deps update -g fails" {
    Set-FailingDepsUpdateStub

    $exitCode = Invoke-FixtureRefresh
    $exitCode | Should -Not -Be 0

    (Get-Item -LiteralPath (Join-Path $script:agmsgSkillDir "db")).LinkType | Should -Be "SymbolicLink"
    (Get-Item -LiteralPath (Join-Path $script:agmsgSkillDir "teams")).LinkType | Should -Be "SymbolicLink"
    Get-Content -LiteralPath (Join-Path $script:agmsgStateRoot "db/messages.db") -Raw | Should -Be "message-history"
    Get-Content -LiteralPath (Join-Path $script:agmsgStateRoot "teams/sample-team/config.json") -Raw | Should -Be '{"members":[]}'
  }
}
