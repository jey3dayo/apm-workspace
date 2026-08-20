# PowerShell parity tests for scripts/agmsg-state.ps1's save/restore/absorb
# contract, matching the three bash observations in tests/agmsg-state.sh.bats
# (save absorbs into the store, -n-equivalent skip of an already-authoritative
# store file, and "leave the target in place + fail loudly" on a real copy
# error) plus restore's relink behavior. Invoked as a subprocess via `pwsh
# -File`, mirroring the bash suite's subprocess-invocation style: the script
# has no dispatch guard, so dot-sourcing it would run its switch statement
# immediately with whatever $Command happened to be bound.

$ErrorActionPreference = "Stop"

Describe "agmsg-state.ps1 save/restore" {
  BeforeAll {
    $script:scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "scripts/agmsg-state.ps1"
    $script:consoleShell = if (Get-Command powershell -ErrorAction SilentlyContinue) { "powershell" } else { "pwsh" }

    function script:Invoke-AgmsgState {
      param([Parameter(Mandatory = $true)][string]$SubCommand)
      & $script:consoleShell -NoProfile -File $script:scriptPath $SubCommand 2>&1 | Out-Null
      return $LASTEXITCODE
    }
  }

  BeforeEach {
    $script:fixtureHome = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString())
    $script:skillDir = Join-Path $script:fixtureHome ".agents/skills/agmsg"
    $script:stateRoot = Join-Path $script:fixtureHome ".local/state/agmsg"
    New-Item -ItemType Directory -Path (Join-Path $script:skillDir "db") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:skillDir "db/messages.db") -Value "message-history" -NoNewline

    $script:savedHome = $env:HOME
    $script:savedXdg = $env:XDG_STATE_HOME
    $env:HOME = $script:fixtureHome
    $env:XDG_STATE_HOME = Join-Path $script:fixtureHome ".local/state"
  }

  AfterEach {
    if (Test-Path -LiteralPath (Join-Path $script:stateRoot "db")) {
      # Undo any permission lockdown a test applied, so TestDrive cleanup can
      # actually remove it afterward.
      & chmod -R u+w (Join-Path $script:stateRoot "db") 2>$null
    }
    $env:HOME = $script:savedHome
    if ($null -eq $script:savedXdg) {
      Remove-Item Env:XDG_STATE_HOME -ErrorAction SilentlyContinue
    }
    else {
      $env:XDG_STATE_HOME = $script:savedXdg
    }
  }

  It "save absorbs a plain runtime dir into the store and removes the original" {
    $exitCode = Invoke-AgmsgState -SubCommand "save"
    $exitCode | Should -Be 0

    (Join-Path $script:skillDir "db") | Should -Not -Exist
    Get-Content -LiteralPath (Join-Path $script:stateRoot "db/messages.db") -Raw | Should -Be "message-history"
  }

  It "save absorbs cleanly when -n-equivalent skips an already-authoritative store file" {
    New-Item -ItemType Directory -Path (Join-Path $script:stateRoot "db") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:stateRoot "db/messages.db") -Value "already-authoritative" -NoNewline

    $exitCode = Invoke-AgmsgState -SubCommand "save"
    $exitCode | Should -Be 0

    (Join-Path $script:skillDir "db") | Should -Not -Exist
    # The store's existing (authoritative) copy must not be overwritten.
    Get-Content -LiteralPath (Join-Path $script:stateRoot "db/messages.db") -Raw | Should -Be "already-authoritative"
  }

  It "save preserves the runtime dir and fails loudly when the copy into the store fails" {
    New-Item -ItemType Directory -Path (Join-Path $script:stateRoot "db") -Force | Out-Null
    & chmod 555 (Join-Path $script:stateRoot "db")

    $exitCode = Invoke-AgmsgState -SubCommand "save"
    $exitCode | Should -Not -Be 0

    # The history that was about to be discarded must still be on disk.
    (Join-Path $script:skillDir "db") | Should -Exist
    Get-Content -LiteralPath (Join-Path $script:skillDir "db/messages.db") -Raw | Should -Be "message-history"
  }

  It "restore relinks a plain runtime dir as a symlink pointing at the store" {
    $exitCode = Invoke-AgmsgState -SubCommand "restore"
    $exitCode | Should -Be 0

    (Get-Item -LiteralPath (Join-Path $script:skillDir "db")).LinkType | Should -Be "SymbolicLink"
    Get-Content -LiteralPath (Join-Path $script:stateRoot "db/messages.db") -Raw | Should -Be "message-history"
  }

  It "restore is idempotent when the runtime dir is already a symlink" {
    Invoke-AgmsgState -SubCommand "restore" | Out-Null

    $exitCode = Invoke-AgmsgState -SubCommand "restore"
    $exitCode | Should -Be 0

    (Get-Item -LiteralPath (Join-Path $script:skillDir "db")).LinkType | Should -Be "SymbolicLink"
    Get-Content -LiteralPath (Join-Path $script:stateRoot "db/messages.db") -Raw | Should -Be "message-history"
  }

  It "restore skips gracefully when agmsg was never deployed" {
    Remove-Item -LiteralPath $script:skillDir -Recurse -Force

    $exitCode = Invoke-AgmsgState -SubCommand "restore"
    $exitCode | Should -Be 0
  }
}
