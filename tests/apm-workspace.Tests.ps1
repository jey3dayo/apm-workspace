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
}

Describe "public command surface" {
  BeforeAll {
    $env:APM_WORKSPACE_LIB_ONLY = "1"
    $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "scripts/apm-workspace.ps1"
    . (Resolve-Path -LiteralPath $modulePath).Path
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY -ErrorAction SilentlyContinue
  }

  It "shows shell help wording for update and catalog commands" {
    $legacyMirrorPattern = 'transitional' + ' mirror'
    $updateHelpPattern = '(?m)^  update\s+Refresh the (?:workspace checkout and deps only|checkout and dependencies only; does not deploy)$'
    $help = & /bin/bash (Join-Path $workspaceRoot "scripts/apm-workspace.sh") help | Out-String

    $help | Should -Match $updateHelpPattern
    $help | Should -Match "validate:catalog"
    $help | Should -Match "stage-catalog"
    $help | Should -Match "register-catalog"
    $help | Should -Match "release-catalog"
    $help | Should -Not -Match $legacyMirrorPattern
    $help | Should -Not -Match "validate-internal"
    $help | Should -Not -Match "stage-internal"
    $help | Should -Not -Match "register-internal"
    $help | Should -Not -Match "migrate-internal"
  }

  It "shows PowerShell help wording for update and catalog commands" {
    $legacyMirrorPattern = 'transitional' + ' mirror'
    $updateHelpPattern = '(?m)^  update\s+Refresh the (?:workspace checkout and deps only|checkout and dependencies only; does not deploy)$'
    $help = & $consoleShell -NoProfile -ExecutionPolicy Bypass -File $scriptPath help | Out-String

    $help | Should -Match $updateHelpPattern
    $help | Should -Match "validate:catalog"
    $help | Should -Match "stage-catalog"
    $help | Should -Match "register-catalog"
    $help | Should -Match "release-catalog"
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
      Mock Normalize-WorkspaceGitignore {}
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

  It "rejects local package refs before update deploys" {
    $shellScript = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/apm-workspace.sh") -Raw

    $shellScript | Should -Match '(?s)cmd_update\(\)\s*\{.*?if manifest_has_local_packages; then\s+fail "apm 0\.8\.11 cannot update \./packages/\* dependencies at user scope yet\. Refresh stopped before deps update; remove local package refs from ~/.apm/apm\.yml first\."\s+fi.*?apm deps update -g'
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
      Mock Normalize-WorkspaceGitignore {}
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

  It "normalizes codex skill names from superpowers aliases" {
    Format-SkillName -Target "claude" -SourceSkillId "superpowers:brainstorming" | Should -Be "superpowers:brainstorming"
    Format-SkillName -Target "codex" -SourceSkillId "superpowers:brainstorming" | Should -Be "brainstorming"
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

  It "builds target-aware managed skill inventory with normalized names" {
    $targets = @(
      [pscustomobject]@{ Name = "claude"; Root = (Join-Path $TestDrive "claude"); ConfigName = "CLAUDE.md" }
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive "codex"); ConfigName = "AGENTS.md" }
    )

    $inventory = @(Get-ManagedCatalogSkillInventory -SkillIds @("superpowers:brainstorming") -Targets $targets)

    ($inventory | Where-Object Target -eq "claude").DeployedSkillName | Should -Be "superpowers:brainstorming"
    ($inventory | Where-Object Target -eq "codex").DeployedSkillName | Should -Be "brainstorming"
  }

  It "stages target-aware deployment trees from personal and external skills" {
    $targets = @(
      [pscustomobject]@{ Name = "claude"; Root = (Join-Path $TestDrive "claude"); ConfigName = "CLAUDE.md" }
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive "codex"); ConfigName = "AGENTS.md" }
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
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "superpowers:brainstorming" }).DeployedSkillName | Should -Be "brainstorming"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "gh-address-comments" }).DeployedSkillName | Should -Be "gh-address-comments"
    $claudeSkillsRoot = Join-Path (Join-Path $stageRoot "claude") "skills"
    $codexSkillsRoot = Join-Path (Join-Path $stageRoot "codex") "skills"

    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[0].SourcePath -ActualRoot (Join-Path (Join-Path $claudeSkillsRoot "superpowers") "brainstorming") | Should -Be $true
    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[0].SourcePath -ActualRoot (Join-Path $codexSkillsRoot "brainstorming") | Should -Be $true
    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[1].SourcePath -ActualRoot (Join-Path $claudeSkillsRoot "gh-address-comments") | Should -Be $true
    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[1].SourcePath -ActualRoot (Join-Path $codexSkillsRoot "gh-address-comments") | Should -Be $true
  }

  It "keeps source kind in the combined deployment plan while normalizing codex skills" {
    $targets = @(
      [pscustomobject]@{ Name = "claude"; Root = (Join-Path $TestDrive "claude"); ConfigName = "CLAUDE.md" }
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive "codex"); ConfigName = "AGENTS.md" }
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
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "superpowers:brainstorming" }).DeployedSkillName | Should -Be "brainstorming"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "gh-address-comments" }).SourceKind | Should -Be "external"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "gh-address-comments" }).DeployedSkillName | Should -Be "gh-address-comments"
  }

  It "publishes workspace mise tasks for formatting, verification, and sync flow" {
    $miseToml = Get-Content -LiteralPath (Join-Path $workspaceRoot "mise.toml") -Raw

    $miseToml | Should -Match '\[tasks\.validate\]'
    $miseToml | Should -Match '\[tasks\."validate:workspace"\]'
    $miseToml | Should -Match '\[tasks\."validate:catalog"\]'
    $miseToml | Should -Match '\[tasks\."format:markdown:bold-headings"\]'
    $miseToml | Should -Match '\[tasks\."apm:install"\]'
    $miseToml | Should -Match '\[tasks\.apply\]'
    $miseToml | Should -Match '\[tasks\.update\]'
    $miseToml | Should -Match '\[tasks\.doctor\]'
    $miseToml | Should -Match '\[tasks\.format\]'
    $miseToml | Should -Match '\[tasks\.ci\]'
    $miseToml | Should -Match '\[tasks\.sync\]'
    $miseToml | Should -Match '\[tasks\."catalog:release"\]'
    $miseToml | Should -Match '\[tasks\."catalog:tidy"\]'
    $miseToml | Should -Match 'run = "bash ./scripts/apm-workspace.sh apply"'
    $miseToml | Should -Match 'replace-bold-headings\.ts'
    $miseToml | Should -Match '(?s)\[tasks\.ci\]\s*description = "Run verification-only checks for the ~/.apm workspace"\s*depends = \["check:format", "validate", "smoke-catalog"\]'
    $miseToml | Should -Match '(?s)\[tasks\.sync\].*?\{ task = "update" \}.*?\{ task = "ci" \}.*?\{ task = "apply" \}.*?\{ task = "doctor" \}'
    $miseToml | Should -Match '(?s)\[tasks\."catalog:release"\].*?\{ task = "sync" \}.*?release-catalog'
    $miseToml | Should -Not -Match 'APM_BOOTSTRAP_REPO'
  }

  It "describes the catalog readme without legacy mirror wording" {
    $legacyMirrorPattern = 'transitional' + ' mirror'
    $readme = Get-CatalogReadmeContent

    $readme | Should -Match '~/.apm/catalog/skills/<id>/'
    $readme | Should -Not -Match $legacyMirrorPattern
  }

  It "does not reference removed agents src paths in agent-facing docs" {
    $removedAgentsRoot = '~/.config/' + 'agents'
    $removedAgentsSrcPattern = [regex]::Escape($removedAgentsRoot) + '/src'
    $legacyMirrorPattern = 'transitional\s+' + 'mirror'
    $files = @(
      (Join-Path $workspaceRoot "catalog/skills/apm-usage/SKILL.md")
      (Join-Path $workspaceRoot "catalog/skills/skill-creator/SKILL.md")
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

    $readme | Should -Match 'mise run apply'
    $readme | Should -Match 'mise run stage-catalog'
    $todo | Should -Match 'managed catalog only'
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
