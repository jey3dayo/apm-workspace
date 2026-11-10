$ErrorActionPreference = "Stop"

Describe "APM 0.35 cache and doctor safeguards" -Tag "apm035" {
  BeforeAll {
    $script:originalWorkspaceEnv = $env:APM_WORKSPACE_DIR
    $script:fixtureRoot = Join-Path $TestDrive "guards-pester"
    New-Item -ItemType Directory -Path $script:fixtureRoot -Force | Out-Null
    $env:APM_WORKSPACE_DIR = $script:fixtureRoot
    $env:APM_WORKSPACE_LIB_ONLY = "1"
    . (Join-Path $PSScriptRoot "../scripts/apm-workspace.ps1")
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY
    $script:realGetPrunePreview = (Get-Command Get-PrunePreview).ScriptBlock
  }

  AfterAll {
    $env:APM_WORKSPACE_DIR = $script:originalWorkspaceEnv
  }

  BeforeEach {
    $script:WorkspaceDir = Join-Path $script:fixtureRoot ([guid]::NewGuid().ToString("N"))
    $WorkspaceDir = $script:WorkspaceDir
    $global:WorkspaceDir = $script:WorkspaceDir
    if (-not $WorkspaceDir.StartsWith($script:fixtureRoot)) { throw "Fixture escaped its worktree" }
    New-Item -ItemType Directory -Path (Join-Path $WorkspaceDir "apm_modules/owner/gist") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm_modules/owner/gist/SKILL.md") -Value "skill"
    Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.yml") -Value "dependencies:`n  apm: []"
    Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.lock.yaml") -Value "dependencies: []`nlocal_deployed_files:`n- .agents/skills/local"
    $script:preview = "[>] Analyzing installed packages vs apm.yml...`n[+] No orphaned packages found. apm_modules/ is clean."
    $script:listResult = [pscustomobject]@{
      ExitCode = 1
      Output = "[x] Error listing dependencies: Invalid local package path '': path segments must not be empty"
    }
    Mock Require-Apm {}
    Mock Get-PrunePreview { $script:preview }
    Mock Get-ApmReadOnlyOutput { $script:listResult }
    function global:apm {
      if (($args -join ' ') -ne 'deps tree -g') { throw "Unexpected native command: $args" }
      $global:LASTEXITCODE = 0
      Write-Output "dependency tree"
    }
  }

  AfterEach {
    Remove-Item Function:\apm -ErrorAction SilentlyContinue
  }

  It "reports the narrow self-entry fallback without changing the lockfile" {
    $lock = Join-Path $WorkspaceDir "apm.lock.yaml"
    $before = Get-FileHash -LiteralPath $lock
    $output = Write-DependencyState 3>&1 6>&1 | Out-String
    $output | Should -Match "reduced orphan detection"
    $output | Should -Match "dependency tree"
    (Get-FileHash -LiteralPath $lock).Hash | Should -Be $before.Hash
    $output | Should -Match "No orphaned packages found"
  }

  It "preserves a successful dependency listing" {
    $script:listResult = [pscustomobject]@{ ExitCode = 0; Output = "installed packages" }
    { Write-DependencyState } | Should -Not -Throw
    Should -Invoke Get-PrunePreview -Times 0
  }

  It "rejects unrelated errors and missing local deployment evidence" {
    $script:listResult.Output += "; unrelated failure"
    { Write-DependencyState } | Should -Throw '*deps list -g failed*'
    $script:listResult.Output = "[x] Error listing dependencies: Invalid local package path '': path segments must not be empty"
    Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.lock.yaml") -Value "dependencies: []"
    { Write-DependencyState } | Should -Throw '*deps list -g failed*'
    Should -Invoke Get-PrunePreview -Times 0
  }

  It "propagates failed fallback and preview commands" {
    function global:apm { $global:LASTEXITCODE = 2 }
    { Write-DependencyState } | Should -Throw '*deps tree -g failed*'
    function global:apm { $global:LASTEXITCODE = 0 }
    Mock Get-PrunePreview { throw "preview failed" }
    { Write-DependencyState } | Should -Throw '*preview failed*'
  }

  It "does not convert failed native preview into success" {
    Mock Get-ApmReadOnlyOutput { [pscustomobject]@{ ExitCode = 2; Output = "unsupported --dry-run" } }
    { & $script:realGetPrunePreview } | Should -Throw '*apm prune --dry-run failed*'
  }
}


Describe "native APM stderr capture" -Tag "apm035" {
  BeforeAll {
    $script:originalNativeWorkspaceEnv = $env:APM_WORKSPACE_DIR
    $script:nativeFixtureRoot = Join-Path $TestDrive "guards-native"
    New-Item -ItemType Directory -Path $script:nativeFixtureRoot -Force | Out-Null
    $env:APM_WORKSPACE_DIR = $script:nativeFixtureRoot
    $env:APM_WORKSPACE_LIB_ONLY = "1"
    . (Join-Path $PSScriptRoot "../scripts/apm-workspace.ps1")
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY
  }

  AfterAll {
    $env:APM_WORKSPACE_DIR = $script:originalNativeWorkspaceEnv
  }

  It "preserves native stderr and exit status <ExitStatus> under Stop and restores preferences" -TestCases @(
    @{ ExitStatus = 0 }
    @{ ExitStatus = 23 }
  ) {
    param($ExitStatus)
    $stubDir = Join-Path $script:nativeFixtureRoot ([guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    if ($env:OS -eq "Windows_NT") {
      $stubPath = Join-Path $stubDir "apm.cmd"
      @"
@echo off
echo native stdout
echo native stderr 1>&2
exit /b $ExitStatus
"@ | Set-Content -LiteralPath $stubPath -Encoding ASCII
    } else {
      $stubPath = Join-Path $stubDir "apm"
      @"
#!/bin/sh
printf '%s\n' 'native stdout'
printf '%s\n' 'native stderr' >&2
exit $ExitStatus
"@ | Set-Content -LiteralPath $stubPath -Encoding ASCII
      & /bin/chmod +x $stubPath
      if ($LASTEXITCODE -ne 0) { throw "Unable to prepare native fixture" }
    }

    $originalPath = $env:PATH
    $originalColumns = $env:COLUMNS
    $originalNoColor = $env:NO_COLOR
    $originalPreference = $ErrorActionPreference
    try {
      $env:PATH = $stubDir + [IO.Path]::PathSeparator + $originalPath
      $env:COLUMNS = "137"
      $env:NO_COLOR = "fixture-preserved"
      $ErrorActionPreference = "Stop"
      $resolved = Get-Command apm -ErrorAction Stop
      if ($resolved.CommandType -ne "Application" -or [IO.Path]::GetFullPath($resolved.Source) -ne [IO.Path]::GetFullPath($stubPath)) {
        throw "Native fixture did not resolve; refusing to invoke another apm"
      }

      $result = Get-ApmReadOnlyOutput -Arguments @("deps", "list", "-g")
      ($result.Output -split "`r?`n") | Should -Contain "native stdout"
      ($result.Output -split "`r?`n") | Should -Contain "native stderr"
      $result.ExitCode | Should -Be $ExitStatus
      $ErrorActionPreference | Should -Be "Stop"
      $env:COLUMNS | Should -Be "137"
      $env:NO_COLOR | Should -Be "fixture-preserved"
    }
    finally {
      $ErrorActionPreference = $originalPreference
      $env:PATH = $originalPath
      $env:COLUMNS = $originalColumns
      $env:NO_COLOR = $originalNoColor
    }
  }
}
