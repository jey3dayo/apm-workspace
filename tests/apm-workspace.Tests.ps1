$ErrorActionPreference = "Stop"

$env:APM_WORKSPACE_LIB_ONLY = "1"
. "C:\Users\j138c\.config\scripts\apm-workspace.ps1"
Remove-Item Env:APM_WORKSPACE_LIB_ONLY -ErrorAction SilentlyContinue

Describe "catalog helpers" {
  BeforeEach {
    $WorkspaceDir = Join-Path $TestDrive "workspace"
    New-Item -ItemType Directory -Path $WorkspaceDir -Force | Out-Null
  }

  It "detects the catalog reference in apm.yml" {
    @"
name: apm-workspace
dependencies:
  apm:
  - jey3dayo/apm-workspace/catalog#main
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.yml")

    Test-ManifestHasCatalogReference | Should Be $true
  }

  It "lists skill ids from the tracked catalog tree" {
    $skillsRoot = Join-Path $WorkspaceDir "catalog\.apm\skills"
    New-Item -ItemType Directory -Path (Join-Path $skillsRoot "mypc-manager") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $skillsRoot "superpowers\brainstorming") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillsRoot "mypc-manager\SKILL.md") -Value "# mypc-manager"
    Set-Content -LiteralPath (Join-Path $skillsRoot "superpowers\brainstorming\SKILL.md") -Value "# brainstorming"

    $skillIds = @(Get-TrackedCatalogSkillIds)

    $skillIds | Should Be @("mypc-manager", "superpowers:brainstorming")
  }
}

Describe "public command surface" {
  It "shows only catalog commands in help output" {
    $help = & powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\j138c\.config\scripts\apm-workspace.ps1 help | Out-String

    $help | Should Match "validate-catalog"
    $help | Should Match "stage-catalog"
    $help | Should Match "register-catalog"
    $help | Should Not Match "validate-internal"
    $help | Should Not Match "stage-internal"
    $help | Should Not Match "register-internal"
    $help | Should Not Match "migrate-internal"
  }
}
