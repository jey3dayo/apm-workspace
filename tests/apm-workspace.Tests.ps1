$ErrorActionPreference = "Stop"

$env:APM_WORKSPACE_LIB_ONLY = "1"
$script:scriptPath = Join-Path $PSScriptRoot ".."
$script:scriptPath = Join-Path $script:scriptPath "scripts/apm-workspace.ps1"
$script:workspaceRoot = Split-Path -Parent $PSScriptRoot
$script:consoleShell = if (Get-Command powershell -ErrorAction SilentlyContinue) { "powershell" } else { "pwsh" }

Describe "catalog helpers" {
  BeforeAll {
    $env:APM_WORKSPACE_LIB_ONLY = "1"
    $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "scripts/apm-workspace.ps1"
    . (Resolve-Path -LiteralPath $modulePath).Path
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY -ErrorAction SilentlyContinue
  }

  BeforeEach {
    $script:WorkspaceDir = Join-Path $TestDrive "workspace"
    $global:WorkspaceDir = $script:WorkspaceDir
    New-Item -ItemType Directory -Path $script:WorkspaceDir -Force | Out-Null
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

    Test-ManifestHasCatalogReference | Should -Be $true
  }

  It "lists skill ids from the managed catalog tree" {
    $skillsRoot = Join-Path (Join-Path $TestDrive "catalog") "skills"
    New-Item -ItemType Directory -Path (Join-Path $skillsRoot "mypc-manager") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $skillsRoot "superpowers\brainstorming") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillsRoot "mypc-manager\SKILL.md") -Value "# mypc-manager"
    Set-Content -LiteralPath (Join-Path $skillsRoot "superpowers\brainstorming\SKILL.md") -Value "# brainstorming"

    $skillIds = @(Get-SkillIdsFromRoot -SkillsRoot $skillsRoot)

    $skillIds | Should -Be @("mypc-manager", "superpowers:brainstorming")
  }

  It "defaults catalog build requests to tracked catalog skills only" {
    Mock Get-TrackedCatalogSkillIds { @("codex-system", "gh-create-pr") }

    $skillIds = @(Get-RequestedCatalogSkillIds)

    $skillIds | Should -Be @("codex-system", "gh-create-pr")
  }

  It "lists managed agent, command, and rule files plus instructions" {
    $catalogRoot = Join-Path $TestDrive "catalog"
    $agentsRoot = Join-Path $catalogRoot "agents"
    $commandsRoot = Join-Path $catalogRoot "commands"
    $rulesRoot = Join-Path $catalogRoot "rules"
    New-Item -ItemType Directory -Path (Join-Path $agentsRoot "kiro") -Force | Out-Null
    New-Item -ItemType Directory -Path $commandsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $rulesRoot "tools") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $catalogRoot "AGENTS.md") -Value "# shared guidance"
    Set-Content -LiteralPath (Join-Path $agentsRoot "code-reviewer.md") -Value "# agent"
    Set-Content -LiteralPath (Join-Path $agentsRoot "kiro\spec-design.md") -Value "# kiro"
    Set-Content -LiteralPath (Join-Path $commandsRoot "review.md") -Value "# review"
    Set-Content -LiteralPath (Join-Path $commandsRoot "setup.md") -Value "# setup"
    Set-Content -LiteralPath (Join-Path $rulesRoot "claude-md-design.md") -Value "# rule"
    Set-Content -LiteralPath (Join-Path $rulesRoot "tools\rtk.md") -Value "# rtk"

    Mock Get-TrackedCatalogDir { $catalogRoot }
    @(Get-TrackedCatalogAgentRelativePaths) | Should -Be @("code-reviewer.md", "kiro/spec-design.md")
    @(Get-TrackedCatalogCommandRelativePaths) | Should -Be @("review.md", "setup.md")
    @(Get-TrackedCatalogRuleRelativePaths) | Should -Be @("claude-md-design.md", "tools/rtk.md")
    Test-Path -LiteralPath (Get-TrackedCatalogInstructionsPath) | Should -Be $true
  }

  It "parses external lock records as distinct resolved skills" {
    @"
lockfile_version: "1"
dependencies:
  - repo_url: openai/skills
    host: github.com
    resolved_commit: abcdef1234567890
    virtual_path: skills/.curated/gh-address-comments
  - repo_url: obra/superpowers
    host: github.com
    resolved_commit: 1234567890abcdef
    virtual_path: skills/brainstorming
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.lock.yaml")

    $map = Get-LockPinnedReferenceMap

    $map["openai/skills/skills/.curated/gh-address-comments"] | Should -Be "openai/skills/skills/.curated/gh-address-comments#abcdef1234567890"
    $map["obra/superpowers/skills/brainstorming"] | Should -Be "obra/superpowers/skills/brainstorming#1234567890abcdef"
  }

  It "normalizes external virtual paths beyond direct skills roots" {
    Get-ExternalSkillRelativePath -VirtualPath "understand-anything-plugin/skills/understand" | Should -Be "understand"
    Get-ExternalSkillRelativePath -VirtualPath "plugins/static-analysis/skills/codeql" | Should -Be "codeql"
    Get-ExternalSkillRelativePath -VirtualPath ".agents/skills/tauri" | Should -Be "tauri"
    Get-ExternalSkillRelativePath -VirtualPath "skills/.system/skill-creator" | Should -Be "skill-creator"
  }

  It "maps obra superpowers external skills to superpowers aliases" {
    $skillId = Get-ExternalSkillId -RepoUrl "obra/superpowers" -VirtualPath "skills/brainstorming"

    $skillId | Should -Be "superpowers:brainstorming"
  }

  It "parses repo-root external lock records as distinct resolved skills" {
    @"
name: apm-workspace
dependencies:
  apm:
    - openai/skills
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: openai/skills
    host: github.com
    resolved_commit: abcdef1234567890
    virtual_path:
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.lock.yaml")

    $repoRootSkillPath = Join-Path (Join-Path $WorkspaceDir "apm_modules") "openai"
    $repoRootSkillPath = Join-Path $repoRootSkillPath "skills"
    New-Item -ItemType Directory -Path $repoRootSkillPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $repoRootSkillPath "SKILL.md") -Value "# openai skills"

    $lockedRecords = @(Get-LockedExternalSkillRecords)
    $skillId = Get-ExternalSkillId -RepoUrl $lockedRecords[0].Repo -VirtualPath $lockedRecords[0].Path
    $sourcePath = Get-ExternalSkillInstallPath -RepoUrl $lockedRecords[0].Repo -VirtualPath $lockedRecords[0].Path -ResolvedCommit $lockedRecords[0].Commit
    $map = Get-LockPinnedReferenceMap

    $lockedRecords.Count | Should -Be 1
    $lockedRecords[0].Repo | Should -Be "openai/skills"
    $lockedRecords[0].Path | Should -Be ""
    $lockedRecords[0].Commit | Should -Be "abcdef1234567890"
    $skillId | Should -Be "skills"
    $sourcePath | Should -Be $repoRootSkillPath
    $map["openai/skills"] | Should -Be "openai/skills#abcdef1234567890"
  }

  It "retains top-level lock records when apm.yml omits them" {
    @"
name: apm-workspace
dependencies:
  apm:
    - openai/skills
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: openai/skills
    host: github.com
    resolved_commit: abcdef1234567890
    virtual_path:
  - repo_url: github.com/extra-skill
    host: github.com
    resolved_commit: 1234567890abcdef
    virtual_path:
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.lock.yaml")

    $extraSkillPath = Join-Path (Join-Path $WorkspaceDir "apm_modules") "github.com"
    $extraSkillPath = Join-Path $extraSkillPath "extra-skill"
    New-Item -ItemType Directory -Path $extraSkillPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $extraSkillPath "SKILL.md") -Value "# extra skill"

    $lockedRecords = @(Get-LockedExternalSkillRecords)
    $manifestReferences = @(Get-ManifestApmDependencyReferences)

    $lockedRecords.Count | Should -Be 2
    $lockedRecords | Where-Object Repo -eq "github.com/extra-skill" | Should -Not -BeNullOrEmpty
    $manifestReferences | Should -Contain "openai/skills"
    $manifestReferences | Should -Not -Contain "github.com/extra-skill"
  }

  It "ignores the managed catalog lock record when collecting external skills" {
    @"
name: apm-workspace
version: 1.0.0
description: test
author: test
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - benjitaylor/agentation/skills/agentation
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: jey3dayo/apm-workspace
    host: github.com
    resolved_commit: 1111111111111111
    virtual_path: catalog
  - repo_url: benjitaylor/agentation
    host: github.com
    resolved_commit: 2222222222222222
    virtual_path: skills/agentation
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.lock.yaml")

    $agentationPath = Join-Path (Join-Path (Join-Path $WorkspaceDir "apm_modules") "benjitaylor") "agentation"
    $agentationPath = Join-Path $agentationPath "skills/agentation"
    New-Item -ItemType Directory -Path $agentationPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $agentationPath "SKILL.md") -Value "# agentation"

    $records = @(Get-ExternalSkillRecords)

    $records.Count | Should -Be 1
    $records[0].SourceSkillId | Should -Be "agentation"
    $records[0].CanonicalReference | Should -Be "benjitaylor/agentation/skills/agentation"
  }

  It "keeps superpowers aliases when collecting external skills" {
    @"
name: apm-workspace
version: 1.0.0
description: test
author: test
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - obra/superpowers/skills/brainstorming
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: obra/superpowers
    host: github.com
    resolved_commit: 2222222222222222
    virtual_path: skills/brainstorming
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.lock.yaml")

    $skillPath = Join-Path (Join-Path (Join-Path $WorkspaceDir "apm_modules") "obra") "superpowers"
    $skillPath = Join-Path $skillPath "skills/brainstorming"
    New-Item -ItemType Directory -Path $skillPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillPath "SKILL.md") -Value "# brainstorming"

    $records = @(Get-ExternalSkillRecords)

    $records.Count | Should -Be 1
    $records[0].SourceSkillId | Should -Be "superpowers:brainstorming"
    $records[0].CanonicalReference | Should -Be "obra/superpowers/skills/brainstorming"
  }

  It "reads only top-level lock dependency records" {
    @"
lockfile_version: "1"
metadata:
  dependencies:
    - repo_url: ignored/nested
      resolved_commit: 0000000000000000
dependencies:
  - repo_url: openai/skills
    host: github.com
    resolved_commit: abcdef1234567890
    virtual_path: skills/.curated/gh-address-comments
other_records:
  - repo_url: ignored/top-level
    resolved_commit: ffffffffffffffff
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.lock.yaml")

    $records = @(Get-LockedExternalSkillRecords)

    $records.Count | Should -Be 1
    $records[0].Repo | Should -Be "openai/skills"
    $records[0].Path | Should -Be "skills/.curated/gh-address-comments"
    $records[0].Commit | Should -Be "abcdef1234567890"
  }

  It "reads top-level lock dependency records from same-indent YAML lists" {
    @"
lockfile_version: "1"
dependencies:
- repo_url: openai/skills
  host: github.com
  resolved_commit: abcdef1234567890
  virtual_path: skills/.curated/gh-address-comments
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.lock.yaml")

    $records = @(Get-LockedExternalSkillRecords)

    $records.Count | Should -Be 1
    $records[0].Repo | Should -Be "openai/skills"
    $records[0].Path | Should -Be "skills/.curated/gh-address-comments"
    $records[0].Commit | Should -Be "abcdef1234567890"
  }

}

Describe "public command surface" {
  BeforeAll {
    $env:APM_WORKSPACE_LIB_ONLY = "1"
    $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "scripts/apm-workspace.ps1"
    . (Resolve-Path -LiteralPath $modulePath).Path
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY -ErrorAction SilentlyContinue
  }

  BeforeEach {
    $script:WorkspaceDir = Join-Path $TestDrive "workspace"
    $global:WorkspaceDir = $script:WorkspaceDir
    New-Item -ItemType Directory -Path $script:WorkspaceDir -Force | Out-Null
  }

  It "shows shell help wording for refresh and catalog commands" {
    $legacyMirrorPattern = 'transitional' + ' mirror'
    $updateHelpPattern = '(?m)^  refresh\s+Refresh the checkout and dependencies only; does not deploy$'
    $help = & /bin/bash (Join-Path $workspaceRoot "scripts/apm-workspace.sh") help | Out-String

    $help | Should -Match $updateHelpPattern
    $help | Should -Match "validate:catalog"
    $help | Should -Match "prepare:catalog"
    $help | Should -Match "install:catalog"
    $help | Should -Match "release:catalog"
    $help | Should -Not -Match "format-catalog-metadata"
    $help | Should -Not -Match "check-catalog-metadata"
    $help | Should -Not -Match $legacyMirrorPattern
    $help | Should -Not -Match "validate-internal"
    $help | Should -Not -Match "stage-internal"
    $help | Should -Not -Match "register-internal"
    $help | Should -Not -Match "migrate-internal"
  }

  It "shows PowerShell help wording for refresh and catalog commands" {
    $legacyMirrorPattern = 'transitional' + ' mirror'
    $updateHelpPattern = '(?m)^  refresh\s+Refresh the checkout and dependencies only; does not deploy$'
    $help = & $consoleShell -NoProfile -ExecutionPolicy Bypass -File $scriptPath help | Out-String

    $help | Should -Match $updateHelpPattern
    $help | Should -Match "validate:catalog"
    $help | Should -Match "prepare:catalog"
    $help | Should -Match "install:catalog"
    $help | Should -Match "release:catalog"
    $help | Should -Not -Match "format-catalog-metadata"
    $help | Should -Not -Match "check-catalog-metadata"
    $help | Should -Not -Match $legacyMirrorPattern
    $help | Should -Not -Match "validate-internal"
    $help | Should -Not -Match "stage-internal"
    $help | Should -Not -Match "register-internal"
    $help | Should -Not -Match "migrate-internal"
  }

  It "keeps update on the non-deploy path" {
    $apmCalls = New-Object System.Collections.Generic.List[string]

    function global:apm {
      $argsText = @($args)

      $apmCalls.Add(($argsText -join ' '))
      $global:LASTEXITCODE = 0
    }

    try {
      Mock Require-Apm {}
      Mock Ensure-WorkspaceRepo {}
      Mock Refresh-WorkspaceCheckout {}
      Mock Ensure-WorkspaceScaffold {}
      Mock Invoke-ValidateCatalog {}
      Mock Test-ManifestHasLocalPackages { $false }
      Mock Remove-InternalTargetReparsePoints {}
      Mock Get-InternalCleanupSkillIds { @() }
      Mock Invoke-WorkspaceInstallCommand {}
      Mock Invoke-CodexCompile {}
      Mock Invoke-Apply {}
      Mock Build-TargetSkillTrees {}
      Mock Replace-SkillTargetsFromStage {}
      Mock Sync-ManagedCatalogRuntimeAssets {}
      Mock Invoke-StageCatalog {}

      Invoke-Update

      $apmCalls | Should -Be @("deps update -g")
      Assert-MockCalled Invoke-WorkspaceInstallCommand -Times 0 -Exactly
      Assert-MockCalled Invoke-Apply -Times 0 -Exactly
      Assert-MockCalled Build-TargetSkillTrees -Times 0 -Exactly
      Assert-MockCalled Replace-SkillTargetsFromStage -Times 0 -Exactly
      Assert-MockCalled Sync-ManagedCatalogRuntimeAssets -Times 0 -Exactly
      Assert-MockCalled Invoke-StageCatalog -Times 0 -Exactly
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }
  }

  It "applies managed MCP dependencies during PowerShell deploy" {
    Mock Require-Apm {}
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Invoke-ValidateCatalog {}
    Mock Ensure-WorkspaceMiseFile {}
    Mock Test-ManifestHasLocalPackages { $false }
    Mock New-TemporaryDirectory { Join-Path $TestDrive "apm-apply" }
    Mock Build-TargetSkillTrees {}
    Mock Sync-ManagedCatalogRuntimeAssets {}
    Mock Replace-SkillTargetsFromStage {}
    Mock Install-WorkspaceMcpDependencies {}
    Mock Invoke-CodexCompile {}

    Invoke-Apply

    Assert-MockCalled Install-WorkspaceMcpDependencies -Times 1 -Exactly
  }

  It "installs MCP dependencies with apm install only mcp" {
    $apmCalls = New-Object System.Collections.Generic.List[string]

    function global:apm {
      $argsText = @($args)
      $apmCalls.Add(($argsText -join ' '))
      $global:LASTEXITCODE = 0
    }

    try {
      Mock Test-ApmInstallDiagnosticsFailure { $false }

      Install-WorkspaceMcpDependencies

      $apmCalls | Should -Be @("install -g --only mcp")
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }
  }

  It "rejects local package refs before update deploys" {
    $shellScript = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/apm-workspace.sh") -Raw

    $shellScript | Should -Match '(?s)cmd_update\(\)\s*\{.*?if manifest_has_local_packages; then\s+fail "apm 0\.8\.11 cannot update \./packages/\* dependencies at user scope yet\. Refresh stopped before deps update; remove local package refs from ~/.apm/apm\.yml first\."\s+fi.*?apm deps update -g'
  }

  It "deploys managed MCP dependencies during shell apply" {
    $shellScript = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/apm-workspace.sh") -Raw

    $shellScript | Should -Match '(?s)install_workspace_mcp_dependencies\(\)\s*\{\s*run_workspace_install_command -g --only mcp\s*\}'
    $shellScript | Should -Match '(?s)cmd_apply\(\)\s*\{.*?replace_skill_targets_from_stage "\$apply_stage_root".*?install_workspace_mcp_dependencies.*?compile_codex'
  }

  It "rejects local package refs before PowerShell update deploys" {
    $apmCalls = New-Object System.Collections.Generic.List[string]

    function global:apm {
      $argsText = @($args)

      $apmCalls.Add(($argsText -join ' '))
      $global:LASTEXITCODE = 0
    }

    Mock Require-Apm {}
    Mock Ensure-WorkspaceRepo {}
    Mock Refresh-WorkspaceCheckout {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Invoke-ValidateCatalog {}
    Mock Test-ManifestHasLocalPackages { $true }

    { Invoke-Update } | Should -Throw 'apm 0.8.11 cannot update ./packages/* dependencies at user scope yet. Refresh stopped before deps update; remove local package refs from ~/.apm/apm.yml first.'

    $apmCalls | Should -Be @()
  }

  It "keeps update on the non-deploy path for PowerShell local packages" {
    $apmCalls = New-Object System.Collections.Generic.List[string]

    function global:apm {
      $argsText = @($args)

      $apmCalls.Add(($argsText -join ' '))
      $global:LASTEXITCODE = 0
    }

    try {
      Mock Require-Apm {}
      Mock Ensure-WorkspaceRepo {}
      Mock Refresh-WorkspaceCheckout {}
      Mock Ensure-WorkspaceScaffold {}
      Mock Invoke-ValidateCatalog {}
      Mock Test-ManifestHasLocalPackages { $false }
      Mock Remove-InternalTargetReparsePoints {}
      Mock Get-InternalCleanupSkillIds { @() }
      Mock Invoke-WorkspaceInstallCommand {}
      Mock Invoke-CodexCompile {}
      Mock Invoke-Apply {}
      Mock Build-TargetSkillTrees {}
      Mock Replace-SkillTargetsFromStage {}
      Mock Sync-ManagedCatalogRuntimeAssets {}
      Mock Invoke-StageCatalog {}

      Invoke-Update

      $apmCalls | Should -Be @("deps update -g")
      Assert-MockCalled Invoke-WorkspaceInstallCommand -Times 0 -Exactly
      Assert-MockCalled Invoke-Apply -Times 0 -Exactly
      Assert-MockCalled Build-TargetSkillTrees -Times 0 -Exactly
      Assert-MockCalled Replace-SkillTargetsFromStage -Times 0 -Exactly
      Assert-MockCalled Sync-ManagedCatalogRuntimeAssets -Times 0 -Exactly
      Assert-MockCalled Invoke-StageCatalog -Times 0 -Exactly
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }
  }

  It "does not reference removed install helpers" {
    $script = Get-Content -LiteralPath $scriptPath -Raw

    $script | Should -Not -Match 'Invoke-InstallReference\b'
  }

  It "keeps local workspace scripts self-contained" {
    $shellScript = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/apm-workspace.sh") -Raw
    $powerShellScript = Get-Content -LiteralPath $scriptPath -Raw

    $shellScript | Should -Not -Match 'APM_BOOTSTRAP_REPO'
    $shellScript | Should -Not -Match '~/.config'
    $powerShellScript | Should -Not -Match 'APM_BOOTSTRAP_REPO'
    $powerShellScript | Should -Not -Match '\\.config\\scripts\\apm-workspace'
  }

  It "keeps workspace docs self-contained and preserves the bold headings exception" {
    $legacyDocsPattern = [regex]::Escape('~/.config/docs/')
    $files = @(
      (Join-Path $workspaceRoot "README.md")
      (Join-Path $workspaceRoot "llms.md")
      (Join-Path $workspaceRoot "docs/apm-task-coverage.md")
    )

    foreach ($file in $files) {
      $content = Get-Content -LiteralPath $file -Raw
      $content | Should -Not -Match $legacyDocsPattern
    }

    $miseToml = Get-Content -LiteralPath (Join-Path $workspaceRoot "mise.toml") -Raw
    $miseToml | Should -Match 'replace-bold-headings\.ts'
  }

  It "maps runtime config filenames per target" {
    $targets = @(Get-ManagedCatalogRuntimeTargets)

    ($targets | Where-Object Name -eq "claude").ConfigName | Should -Be "CLAUDE.md"
    ($targets | Where-Object Name -eq "codex").ConfigName | Should -Be "AGENTS.md"
    ($targets | Where-Object Name -eq "cursor").ConfigName | Should -Be "AGENTS.md"
  }

  It "maps codex skills to ~/.agents while keeping config under ~/.codex" {
    $targets = @(Get-ManagedCatalogRuntimeTargets)
    $codex = $targets | Where-Object Name -eq "codex"

    $codex.Root | Should -Be (Join-Path $HOME ".codex")
    $codex.SkillsRoot | Should -Be (Join-Path $HOME ".agents")
  }

  It "normalizes codex skill names from superpowers aliases" {
    Format-SkillName -Target "claude" -SourceSkillId "superpowers:brainstorming" | Should -Be "superpowers:brainstorming"
    Format-SkillName -Target "codex" -SourceSkillId "superpowers:brainstorming" | Should -Be "superpowers-brainstorming"
  }

  It "reads unpinned refs only from dependencies apm" {
    @"
name: apm-workspace
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - openai/skills/skills/.curated/gh-address-comments
  mcp:
    - ignored/mcp-entry
scripts:
  sync:
    - ignored/script-entry
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.yml")

    @(Get-UnpinnedExternalReferences) | Should -Be @("openai/skills/skills/.curated/gh-address-comments")
  }

  It "reads unpinned refs from same-indent YAML lists under dependencies apm" {
    @"
name: apm-workspace
dependencies:
  apm:
  - jey3dayo/apm-workspace/catalog#main
  - obra/superpowers/skills/using-superpowers
  mcp:
  - ignored/mcp-entry
"@ | Set-Content -LiteralPath (Join-Path $WorkspaceDir "apm.yml")

    @(Get-UnpinnedExternalReferences) | Should -Be @("obra/superpowers/skills/using-superpowers")
  }

  It "builds target-aware managed skill inventory with normalized names" {
    $targets = @(
      [pscustomobject]@{ Name = "claude"; Root = (Join-Path $TestDrive "claude"); ConfigName = "CLAUDE.md" }
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive "codex"); ConfigName = "AGENTS.md" }
    )

    $inventory = @(Get-ManagedCatalogSkillInventory -SkillIds @("superpowers:brainstorming") -Targets $targets)

    ($inventory | Where-Object Target -eq "claude").DeployedSkillName | Should -Be "superpowers:brainstorming"
    ($inventory | Where-Object Target -eq "codex").DeployedSkillName | Should -Be "superpowers-brainstorming"
  }

  It "smoke:catalog normalizes Codex-installed skill paths for superpowers aliases" {
    $buildDir = Join-Path $TestDrive "catalog-build"
    $buildSkillsRoot = Join-Path $buildDir ".apm/skills"
    $bundleSkillRoot = Join-Path (Join-Path $buildSkillsRoot "superpowers") "brainstorming"
    $bundleRequestedSkillIds = New-Object System.Collections.Generic.List[string]
    $installCalls = New-Object System.Collections.Generic.List[string]
    $previousTemp = $env:TEMP
    $env:TEMP = $TestDrive

    function global:apm {
      $installCalls.Add(($args -join ' '))

      if ($args[0] -eq "install") {
        $installedSkillRoot = Join-Path (Join-Path $PWD ".agents/skills") "superpowers-brainstorming"
        New-Item -ItemType Directory -Path (Join-Path $installedSkillRoot "references") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $installedSkillRoot "SKILL.md") -Value "# brainstorming"
        Set-Content -LiteralPath (Join-Path $installedSkillRoot "references/note.md") -Value "codex"
      }

      $global:LASTEXITCODE = 0
    }

    try {
      Mock Require-Apm {}
      Mock Get-RequestedCatalogSkillIds { @("superpowers:brainstorming") }
      Mock Get-CatalogBuildDir { $buildDir }
      Mock Invoke-BundleCatalog {
        param([string[]]$RequestedSkillIds)

        foreach ($skillId in $RequestedSkillIds) {
          $bundleRequestedSkillIds.Add($skillId)
        }

        New-Item -ItemType Directory -Path (Join-Path $bundleSkillRoot "references") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $bundleSkillRoot "SKILL.md") -Value "# brainstorming"
        Set-Content -LiteralPath (Join-Path $bundleSkillRoot "references/note.md") -Value "catalog"
      }

      Invoke-SmokeCatalog -RequestedSkillIds @("superpowers:brainstorming")

      $bundleRequestedSkillIds | Should -Be @("superpowers:brainstorming")
      $installCalls | Should -Contain ("install {0} --target codex" -f $buildDir)
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
      $env:TEMP = $previousTemp
    }
  }

  It "stages target-aware deployment trees from personal and external skills" {
    $targets = @(
      [pscustomobject]@{ Name = "claude"; Root = (Join-Path $TestDrive "claude"); SkillsRoot = (Join-Path $TestDrive "claude"); ConfigName = "CLAUDE.md" }
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive "codex"); SkillsRoot = (Join-Path $TestDrive ".agents"); ConfigName = "AGENTS.md" }
    )
    $stageRoot = Join-Path $TestDrive "stage"
    $skillRecords = @(
      [pscustomobject]@{ SourceKind = "personal"; SourceSkillId = "superpowers:brainstorming"; SourcePath = (Join-Path (Join-Path (Join-Path $TestDrive "source") "personal") "brainstorming") }
      [pscustomobject]@{ SourceKind = "external"; SourceSkillId = "gh-address-comments"; SourcePath = (Join-Path (Join-Path (Join-Path $TestDrive "source") "external") "gh-address-comments") }
    )

    New-Item -ItemType Directory -Path (Join-Path $skillRecords[0].SourcePath "references") -Force | Out-Null
    New-Item -ItemType Directory -Path $skillRecords[1].SourcePath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillRecords[0].SourcePath "SKILL.md") -Value "# brainstorming"
    Set-Content -LiteralPath (Join-Path (Join-Path $skillRecords[0].SourcePath "references") "note.md") -Value "personal"
    Set-Content -LiteralPath (Join-Path $skillRecords[1].SourcePath "SKILL.md") -Value "# gh-address-comments"

    $plan = @(Stage-TargetSkillRecords -StageRoot $stageRoot -SkillRecords $skillRecords -Targets $targets)

    $plan.Count | Should -Be 4
    ($plan | Where-Object { $_.Target -eq "claude" -and $_.SourceSkillId -eq "superpowers:brainstorming" }).DeployedSkillName | Should -Be "superpowers:brainstorming"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "superpowers:brainstorming" }).DeployedSkillName | Should -Be "superpowers-brainstorming"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "gh-address-comments" }).DeployedSkillName | Should -Be "gh-address-comments"
    $claudeSkillsRoot = Join-Path (Join-Path $stageRoot "claude") "skills"
    $codexSkillsRoot = Join-Path (Join-Path $stageRoot "codex") "skills"

    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[0].SourcePath -ActualRoot (Join-Path (Join-Path $claudeSkillsRoot "superpowers") "brainstorming") | Should -Be $true
    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[0].SourcePath -ActualRoot (Join-Path $codexSkillsRoot "superpowers-brainstorming") | Should -Be $true
    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[1].SourcePath -ActualRoot (Join-Path $claudeSkillsRoot "gh-address-comments") | Should -Be $true
    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[1].SourcePath -ActualRoot (Join-Path $codexSkillsRoot "gh-address-comments") | Should -Be $true
  }

  It "keeps source kind in the combined deployment plan while normalizing codex skills" {
    $targets = @(
      [pscustomobject]@{ Name = "claude"; Root = (Join-Path $TestDrive "claude"); SkillsRoot = (Join-Path $TestDrive "claude"); ConfigName = "CLAUDE.md" }
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive "codex"); SkillsRoot = (Join-Path $TestDrive ".agents"); ConfigName = "AGENTS.md" }
    )
    $skillRecords = @(
      [pscustomobject]@{ SourceKind = "personal"; SourceSkillId = "superpowers:brainstorming"; SourcePath = (Join-Path (Join-Path (Join-Path $TestDrive "source") "personal") "brainstorming") }
      [pscustomobject]@{ SourceKind = "external"; SourceSkillId = "gh-address-comments"; SourcePath = (Join-Path (Join-Path (Join-Path $TestDrive "source") "external") "gh-address-comments") }
    )

    $plan = @(Build-DeploymentPlanEntries -SkillRecords $skillRecords -Targets $targets)

    $plan.Count | Should -Be 4
    ($plan | Where-Object { $_.Target -eq "claude" -and $_.SourceSkillId -eq "superpowers:brainstorming" }).SourceKind | Should -Be "personal"
    ($plan | Where-Object { $_.Target -eq "claude" -and $_.SourceSkillId -eq "superpowers:brainstorming" }).DeployedSkillName | Should -Be "superpowers:brainstorming"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "superpowers:brainstorming" }).SourceKind | Should -Be "personal"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "superpowers:brainstorming" }).DeployedSkillName | Should -Be "superpowers-brainstorming"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "gh-address-comments" }).SourceKind | Should -Be "external"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "gh-address-comments" }).DeployedSkillName | Should -Be "gh-address-comments"
  }

  It "replaces codex staged skills into ~/.agents/skills and removes legacy ~/.codex/skills" {
    $targets = @(
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive ".codex"); SkillsRoot = (Join-Path $TestDrive ".agents"); ConfigName = "AGENTS.md" }
    )
    $stageRoot = Join-Path $TestDrive "stage"
    $codexStageSkill = Join-Path (Join-Path (Join-Path $stageRoot "codex") "skills") "superpowers-brainstorming"
    $legacyCodexSkill = Join-Path $TestDrive ".codex/skills/superpowers-brainstorming"

    New-Item -ItemType Directory -Path $codexStageSkill -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $codexStageSkill "SKILL.md") -Value "# staged"
    New-Item -ItemType Directory -Path $legacyCodexSkill -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $legacyCodexSkill "SKILL.md") -Value "# legacy"

    Replace-SkillTargetsFromStage -StageRoot $stageRoot -Targets $targets

    Test-Path (Join-Path $TestDrive ".agents/skills/superpowers-brainstorming/SKILL.md") | Should -Be $true
    Test-Path (Join-Path $TestDrive ".codex/skills") | Should -Be $false
  }

  It "quick-syncs requested local managed skills into the codex target only" {
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock New-TemporaryDirectory { Join-Path $TestDrive "apm-sync-local" }
    Mock Get-RequestedCatalogSkillIds { @("superpowers:brainstorming") }
    Mock Get-ManagedSkillContentDir { Join-Path $TestDrive "catalog/skills/superpowers/brainstorming" }
    Mock Get-LocalCodexSyncTarget {
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive ".codex"); SkillsRoot = (Join-Path $TestDrive ".agents"); ConfigName = "AGENTS.md" }
    }

    $sourcePath = Join-Path $TestDrive "catalog/skills/superpowers/brainstorming"
    New-Item -ItemType Directory -Path (Join-Path $sourcePath "references") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourcePath "SKILL.md") -Value "# brainstorming"
    Set-Content -LiteralPath (Join-Path $sourcePath "references/note.md") -Value "local"
    New-Item -ItemType Directory -Path (Join-Path $TestDrive ".codex/skills/superpowers-brainstorming") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $TestDrive ".codex/skills/superpowers-brainstorming/SKILL.md") -Value "# legacy"
    New-Item -ItemType Directory -Path (Join-Path $TestDrive ".agents/skills/existing-skill") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $TestDrive ".agents/skills/existing-skill/SKILL.md") -Value "# existing"
    New-Item -ItemType Directory -Path (Join-Path $TestDrive ".agents/skills/superpowers-brainstorming") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $TestDrive ".agents/skills/superpowers-brainstorming/old.md") -Value "old"

    Invoke-SyncLocalSkills -RequestedSkillIds @("superpowers:brainstorming")

    Test-Path (Join-Path $TestDrive ".agents/skills/superpowers-brainstorming/SKILL.md") | Should -Be $true
    ((Get-Content -LiteralPath (Join-Path $TestDrive ".agents/skills/superpowers-brainstorming/SKILL.md") -Raw) -replace '\r?\n$', '') | Should -Be "# brainstorming"
    ((Get-Content -LiteralPath (Join-Path $TestDrive ".agents/skills/superpowers-brainstorming/references/note.md") -Raw) -replace '\r?\n$', '') | Should -Be "local"
    Test-Path (Join-Path $TestDrive ".agents/skills/existing-skill/SKILL.md") | Should -Be $true
    Test-Path (Join-Path $TestDrive ".agents/skills/superpowers-brainstorming/old.md") | Should -Be $true
    Test-Path (Join-Path $TestDrive ".codex/skills/superpowers-brainstorming/SKILL.md") | Should -Be $true
  }

  It "publishes workspace mise tasks for formatting, verification, and workflow orchestration" {
    $miseToml = Get-Content -LiteralPath (Join-Path $workspaceRoot "mise.toml") -Raw

    $miseToml | Should -Match '\[tasks\.validate\]'
    $miseToml | Should -Match '\[tasks\."validate:workspace"\]'
    $miseToml | Should -Match '\[tasks\."validate:catalog"\]'
    $miseToml | Should -Match '\[tasks\."format:markdown:bold-headings"\]'
    $miseToml | Should -Match '\[tasks\."apm:install"\]'
    $miseToml | Should -Match '\[tasks\.apply\]'
    $miseToml | Should -Match '\[tasks\."apply:skills:local"\]'
    $miseToml | Should -Match '\[tasks\.refresh\]'
    $miseToml | Should -Not -Match '\[tasks\."apm:update"\]'
    $miseToml | Should -Match '\[tasks\.doctor\]'
    $miseToml | Should -Match '\[tasks\.format\]'
    $miseToml | Should -Match '\[tasks\."format:check"\]'
    $miseToml | Should -Not -Match '\[tasks\."format:catalog-metadata"\]'
    $miseToml | Should -Not -Match '\[tasks\."format:catalog-metadata:check"\]'
    $miseToml | Should -Match '\[tasks\.check\]'
    $miseToml | Should -Match '\[tasks\.verify\]'
    $miseToml | Should -Match '\[tasks\.deploy\]'
    $miseToml | Should -Match '\[tasks\.upgrade\]'
    $miseToml | Should -Match '\[tasks\."refresh:deploy"\]'
    $miseToml | Should -Match '\[tasks\."prepare:catalog"\]'
    $miseToml | Should -Match '\[tasks\."install:catalog"\]'
    $miseToml | Should -Match '\[tasks\."smoke:catalog"\]'
    $miseToml | Should -Match '\[tasks\."release:catalog"\]'
    $miseToml | Should -Match '\[tasks\."verify:catalog"\]'
    $miseToml | Should -Match 'run = "bash ./scripts/apm-workspace.sh apply"'
    $miseToml | Should -Match 'run = "bash ./scripts/apm-workspace.sh apply:skills:local"'
    $miseToml | Should -Match 'replace-bold-headings\.ts'
    $miseToml | Should -Match 'replace-bold-headings\.ts.*\./catalog"'
    $miseToml | Should -Match 'replace-bold-headings\.ts.*\./catalog --dry-run'
    $miseToml | Should -Match '(?s)\[tasks\."format:check"\]\s*description = "Check workspace docs and manifest formatting"\s*depends = \['
    $miseToml | Should -Match '(?s)\[tasks\.check\]\s*description = "Run lightweight pre-deploy checks for the ~/.apm workspace"\s*depends = \["format:check", "validate"\]'
    $miseToml | Should -Match '(?s)\[tasks\.verify\]\s*description = "Run deep verification for the ~/.apm workspace"\s*run = \[\{ task = "check" \}, \{ task = "smoke:catalog" \}\]'
    $miseToml | Should -Match '(?s)\[tasks\.deploy\]\s*description = "Run checks, deploy the current workspace state, and inspect targets"\s*run = \[\{ task = "check" \}, \{ task = "apply" \}, \{ task = "doctor" \}\]'
    $miseToml | Should -Match '(?s)\[tasks\.upgrade\].*?apm install -g --update.*?\{ task = "deploy" \}'
    $miseToml | Should -Match '(?s)\[tasks\."refresh:deploy"\].*?\{ task = "refresh" \}.*?\{ task = "deploy" \}'
    $miseToml | Should -Match '(?s)\[tasks\."release:catalog"\].*?\{ task = "refresh:deploy" \}.*?release:catalog'
    $miseToml | Should -Not -Match 'APM_BOOTSTRAP_REPO'
  }

  It "describes the catalog readme without legacy mirror wording" {
    $legacyMirrorPattern = 'transitional' + ' mirror'
    $readme = Get-Content -LiteralPath (Join-Path $workspaceRoot "catalog/README.md") -Raw

    $readme | Should -Match '~/.apm/catalog/skills/<id>/'
    $readme | Should -Not -Match $legacyMirrorPattern
  }

  It "does not reference removed agents src paths in agent-facing docs" {
    $removedAgentsRoot = '~/.config/' + 'agents'
    $removedAgentsSrcPattern = [regex]::Escape($removedAgentsRoot) + '/src'
    $legacyMirrorPattern = 'transitional\s+' + 'mirror'
    $files = @(
      (Join-Path $workspaceRoot "catalog/skills/apm-usage/SKILL.md")
      (Join-Path $workspaceRoot "catalog/skills/docs-index/indexes/agents-index.md")
      (Join-Path $workspaceRoot "catalog/skills/nix-dotfiles/SKILL.md")
      (Join-Path $workspaceRoot "catalog/skills/nix-dotfiles/README.md")
      (Join-Path $workspaceRoot "catalog/skills/nix-dotfiles/references/commands.md")
      (Join-Path $workspaceRoot "catalog/skills/nix-dotfiles/references/troubleshooting.md")
      (Join-Path $workspaceRoot "catalog/skills/rtk/SKILL.md")
      (Join-Path $workspaceRoot "catalog/skills/rtk/references/command-reference.md")
    )

    foreach ($file in $files) {
      $content = Get-Content -LiteralPath $file -Raw
      $content | Should -Not -Match $removedAgentsSrcPattern
      $content | Should -Not -Match $legacyMirrorPattern
    }

  }

  It "documents external skill workflow references in README and TODO" {
    $readme = Get-Content -LiteralPath (Join-Path $workspaceRoot "README.md") -Raw
    $todo = Get-Content -LiteralPath (Join-Path $workspaceRoot "TODO.md") -Raw

    $readme | Should -Match 'mise run upgrade'
    $readme | Should -Match 'mise run refresh:deploy'
    $readme | Should -Match 'mise run check'
    $readme | Should -Match 'mise run verify'
    $readme | Should -Match 'mise run prepare:catalog'
    $todo | Should -Match 'managed source of truth'
  }

  It "runs catalog release as stage, release gate, and register flow" {
    Mock Ensure-WorkspaceMiseFile {}
    Mock Invoke-StageCatalog {}
    Mock Assert-CatalogReleaseReady {}
    Mock Invoke-RegisterCatalog {}

    Invoke-ReleaseCatalog

    Assert-MockCalled Invoke-StageCatalog -Times 1 -Exactly
    Assert-MockCalled Assert-CatalogReleaseReady -Times 1 -Exactly
    Assert-MockCalled Invoke-RegisterCatalog -Times 1 -Exactly
  }
}

Describe "internal cleanup skill ids" {
  BeforeAll {
    $env:APM_WORKSPACE_LIB_ONLY = "1"
    $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "scripts/apm-workspace.ps1"
    . (Resolve-Path -LiteralPath $modulePath).Path
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY -ErrorAction SilentlyContinue
  }

  BeforeEach {
    $script:WorkspaceDir = Join-Path $TestDrive "workspace"
    $global:WorkspaceDir = $script:WorkspaceDir
    New-Item -ItemType Directory -Path $script:WorkspaceDir -Force | Out-Null
  }

  It "includes legacy superpowers aliases for renamed managed skills" {
    Mock Get-ManagedSkillIds { @("brainstorming", "code-review") }

    $cleanupSkillIds = @(Get-InternalCleanupSkillIds)

    $cleanupSkillIds | Should -Be @("brainstorming", "superpowers:brainstorming", "code-review")
  }
}
