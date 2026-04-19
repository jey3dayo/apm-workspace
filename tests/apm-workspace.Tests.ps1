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

  It "lists skill ids from the managed catalog tree" {
    $skillsRoot = Join-Path $WorkspaceDir "catalog\.apm\skills"
    New-Item -ItemType Directory -Path (Join-Path $skillsRoot "mypc-manager") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $skillsRoot "superpowers\brainstorming") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillsRoot "mypc-manager\SKILL.md") -Value "# mypc-manager"
    Set-Content -LiteralPath (Join-Path $skillsRoot "superpowers\brainstorming\SKILL.md") -Value "# brainstorming"

    $skillIds = @(Get-TrackedCatalogSkillIds)

    $skillIds | Should Be @("mypc-manager", "superpowers:brainstorming")
  }

  It "lists managed agent, command, and rule files plus instructions" {
    $agentsRoot = Join-Path $WorkspaceDir "catalog\agents"
    $commandsRoot = Join-Path $WorkspaceDir "catalog\commands"
    $rulesRoot = Join-Path $WorkspaceDir "catalog\rules"
    New-Item -ItemType Directory -Path (Join-Path $agentsRoot "kiro") -Force | Out-Null
    New-Item -ItemType Directory -Path $commandsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $rulesRoot "tools") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $WorkspaceDir "catalog\AGENTS.md") -Value "# shared guidance"
    Set-Content -LiteralPath (Join-Path $agentsRoot "code-reviewer.md") -Value "# agent"
    Set-Content -LiteralPath (Join-Path $agentsRoot "kiro\spec-design.md") -Value "# kiro"
    Set-Content -LiteralPath (Join-Path $commandsRoot "review.md") -Value "# review"
    Set-Content -LiteralPath (Join-Path $commandsRoot "setup.md") -Value "# setup"
    Set-Content -LiteralPath (Join-Path $rulesRoot "claude-md-design.md") -Value "# rule"
    Set-Content -LiteralPath (Join-Path $rulesRoot "tools\rtk.md") -Value "# rtk"

    @(Get-TrackedCatalogAgentRelativePaths) | Should Be @("code-reviewer.md", "kiro/spec-design.md")
    @(Get-TrackedCatalogCommandRelativePaths) | Should Be @("review.md", "setup.md")
    @(Get-TrackedCatalogRuleRelativePaths) | Should Be @("claude-md-design.md", "tools/rtk.md")
    Test-Path -LiteralPath (Get-TrackedCatalogInstructionsPath) | Should Be $true
  }
}

Describe "public command surface" {
  It "shows only catalog commands in help output" {
    $help = & powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\j138c\.config\scripts\apm-workspace.ps1 help | Out-String

    $help | Should Match "validate-catalog"
    $help | Should Match "stage-catalog"
    $help | Should Match "register-catalog"
    $help | Should Match "release-catalog"
    $help | Should Not Match "transitional mirror"
    $help | Should Not Match "validate-internal"
    $help | Should Not Match "stage-internal"
    $help | Should Not Match "register-internal"
    $help | Should Not Match "migrate-internal"
  }

  It "does not reference removed install helpers" {
    $script = Get-Content -LiteralPath C:\Users\j138c\.config\scripts\apm-workspace.ps1 -Raw

    $script | Should Not Match 'Invoke-InstallReference\b'
  }

  It "maps runtime config filenames per target" {
    $targets = @(Get-ManagedCatalogRuntimeTargets)

    ($targets | Where-Object Name -eq "claude").ConfigName | Should Be "CLAUDE.md"
    ($targets | Where-Object Name -eq "codex").ConfigName | Should Be "AGENTS.md"
    ($targets | Where-Object Name -eq "cursor").ConfigName | Should Be "AGENTS.md"
  }

  It "publishes workspace mise tasks for formatting and ci flow" {
    $miseToml = Get-Content -LiteralPath C:\Users\j138c\.apm\mise.toml -Raw

    $miseToml | Should Match '\[tasks\.validate-catalog\]'
    $miseToml | Should Match '\[tasks\.format\]'
    $miseToml | Should Match '\[tasks\."ci:check"\]'
    $miseToml | Should Match '\[tasks\.ci\]'
    $miseToml | Should Match '\[tasks\."catalog:release"\]'
    $miseToml | Should Match '\[tasks\."catalog:tidy"\]'
  }

  It "describes the catalog readme without legacy mirror wording" {
    $readme = Get-CatalogReadmeContent

    $readme | Should Match '~/.apm/catalog/.apm/skills/<id>/'
    $readme | Should Not Match 'transitional mirror'
  }

  It "runs catalog release as stage, release gate, and register flow" {
    Mock Invoke-StageCatalog {}
    Mock Assert-CatalogReleaseReady {}
    Mock Invoke-RegisterCatalog {}

    Invoke-ReleaseCatalog

    Assert-MockCalled Invoke-StageCatalog -Times 1 -Exactly
    Assert-MockCalled Assert-CatalogReleaseReady -Times 1 -Exactly
    Assert-MockCalled Invoke-RegisterCatalog -Times 1 -Exactly
  }
}

Describe "external overlap reporting" {
  It "finds skills selected both externally and by the managed catalog" {
    $previousExternalSourcesFile = $ExternalSourcesFile

    try {
      $ExternalSourcesFile = Join-Path $TestDrive "agent-skills-sources.nix"

      $skillsRoot = Join-Path $WorkspaceDir "catalog\.apm\skills"
      New-Item -ItemType Directory -Path (Join-Path $skillsRoot "dev-browser") -Force | Out-Null
      Set-Content -LiteralPath (Join-Path $skillsRoot "dev-browser\SKILL.md") -Value "# dev-browser"
      @"
{
  sawyerhood-dev-browser = {
    url = "github:sawyerhood/skills";
    catalogs = {
      default = "skills";
    };
    selection.enable = [
      "dev-browser"
      "gh-fix-ci"
    ];
  };
}
"@ | Set-Content -LiteralPath $ExternalSourcesFile

      $overlaps = @(Get-ManagedExternalOverlapEntries)

      $overlaps.Count | Should Be 1
      $overlaps[0].SourceName | Should Be "sawyerhood-dev-browser"
      $overlaps[0].SkillId | Should Be "dev-browser"
    }
    finally {
      $ExternalSourcesFile = $previousExternalSourcesFile
    }
  }
}
