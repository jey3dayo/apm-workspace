$ErrorActionPreference = "Stop"

# APM_WORKSPACE_LIB_ONLY must NOT be set at the top level: Pester evaluates
# every file's top level during Discovery, before any file's Run phase, so a
# top-level set leaks into other test files' subprocess `apply` runs (making
# them silent no-ops) whenever this file appears later in the invocation list.
# Every dot-source site below sets and removes it inside its own BeforeAll.
$script:scriptPath = Join-Path $PSScriptRoot ".."
$script:scriptPath = Join-Path $script:scriptPath "scripts/apm-workspace.ps1"
$script:workspaceRoot = Split-Path -Parent $PSScriptRoot

Describe "catalog helpers" {
  BeforeAll {
    $env:APM_WORKSPACE_LIB_ONLY = "1"
    $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "scripts/apm-workspace.ps1"
    . (Resolve-Path -LiteralPath $modulePath).Path
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY -ErrorAction SilentlyContinue

    # Assert-CatalogCacheFreshness compares against git-tracked files, not a
    # raw filesystem walk, so fixtures exercising it must be real git repos.
    function Initialize-GitTrackedDirectory {
      param(
        [Parameter(Mandatory = $true)]
        [string]$Directory
      )

      & git -C $Directory init -q | Out-Null
      & git -C $Directory add -A | Out-Null
    }
  }

  BeforeEach {
    $script:WorkspaceDir = Join-Path $TestDrive "workspace"
    $WorkspaceDir = $script:WorkspaceDir
    $global:WorkspaceDir = $script:WorkspaceDir
    $workspaceDir = $script:WorkspaceDir
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
"@ | Set-Content -LiteralPath (Join-Path $workspaceDir "apm.yml")

    Test-ManifestHasCatalogReference | Should -Be $true
  }

  It "lists skill ids from the managed catalog tree" {
    $skillsRoot = Join-Path (Join-Path $TestDrive "catalog") "skills"
    New-Item -ItemType Directory -Path (Join-Path $skillsRoot "mypc-manager") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $skillsRoot "mattpocock\wayfinder") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillsRoot "mypc-manager\SKILL.md") -Value "# mypc-manager"
    Set-Content -LiteralPath (Join-Path $skillsRoot "mattpocock\wayfinder\SKILL.md") -Value "# wayfinder"

    $skillIds = @(Get-SkillIdsFromRoot -SkillsRoot $skillsRoot)

    $skillIds | Should -Be @("mattpocock:wayfinder", "mypc-manager")
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
    New-Item -ItemType Directory -Path $agentsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $commandsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $rulesRoot "tools") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $catalogRoot "AGENTS.md") -Value "# shared guidance"
    Set-Content -LiteralPath (Join-Path $agentsRoot "code-reviewer.md") -Value "# agent"
    Set-Content -LiteralPath (Join-Path $commandsRoot "review.md") -Value "# review"
    Set-Content -LiteralPath (Join-Path $commandsRoot "setup.md") -Value "# setup"
    Set-Content -LiteralPath (Join-Path $rulesRoot "claude-md-design.md") -Value "# rule"
    Set-Content -LiteralPath (Join-Path $rulesRoot "tools\example.md") -Value "# example"

    Mock Get-TrackedCatalogDir { $catalogRoot }
    @(Get-TrackedCatalogAgentRelativePaths) | Should -Be @("code-reviewer.md")
    @(Get-TrackedCatalogCommandRelativePaths) | Should -Be @("review.md", "setup.md")
    @(Get-TrackedCatalogRuleRelativePaths) | Should -Be @("claude-md-design.md", "tools/example.md")
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
  - repo_url: mattpocock/skills
    host: github.com
    resolved_commit: 1234567890abcdef
    virtual_path: skills/engineering/wayfinder
"@ | Set-Content -LiteralPath (Join-Path $workspaceDir "apm.lock.yaml")

    $map = Get-LockPinnedReferenceMap

    $map["openai/skills/skills/.curated/gh-address-comments"] | Should -Be "openai/skills/skills/.curated/gh-address-comments#abcdef1234567890"
    $map["mattpocock/skills/skills/engineering/wayfinder"] | Should -Be "mattpocock/skills/skills/engineering/wayfinder#1234567890abcdef"
  }

  It "normalizes external virtual paths beyond direct skills roots" {
    Get-ExternalSkillRelativePath -VirtualPath "understand-anything-plugin/skills/understand" | Should -Be "understand"
    Get-ExternalSkillRelativePath -VirtualPath "plugins/static-analysis/skills/codeql" | Should -Be "codeql"
    Get-ExternalSkillRelativePath -VirtualPath ".agents/skills/tauri" | Should -Be "tauri"
    Get-ExternalSkillRelativePath -VirtualPath "skills/.system/skill-creator" | Should -Be "skill-creator"
    Get-ExternalSkillRelativePath -VirtualPath "empirical-prompt-tuning" | Should -Be "empirical-prompt-tuning"
  }

  It "parses repo-root external lock records as distinct resolved skills" {
    @"
name: apm-workspace
dependencies:
  apm:
    - openai/skills
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $workspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: openai/skills
    host: github.com
    resolved_commit: abcdef1234567890
    virtual_path:
"@ | Set-Content -LiteralPath (Join-Path $workspaceDir "apm.lock.yaml")

    $repoRootSkillPath = Join-Path (Join-Path $script:WorkspaceDir "apm_modules") "openai"
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
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
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
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    $extraSkillPath = Join-Path (Join-Path $script:WorkspaceDir "apm_modules") "github.com"
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

  It "canonicalizes gist manifest references to owner/id aliases" {
    $gistUrl = "https://gist.github.com/octocat/5a123456.git"
    $keys = @(Get-ManifestReferenceCandidateKeys -Reference $gistUrl)
    $keys | Should -Contain $gistUrl
    $keys | Should -Contain "octocat/5a123456"

    $gistUrlWithSha = "https://gist.github.com/octocat/5a123456.git#abc123def456"
    $keys = @(Get-ManifestReferenceCandidateKeys -Reference $gistUrlWithSha)
    $keys | Should -Contain $gistUrlWithSha
    $keys | Should -Contain "https://gist.github.com/octocat/5a123456.git"
    $keys | Should -Contain "octocat/5a123456"
    $keys | Should -Contain "octocat/5a123456#abc123def456"
  }

  It "keeps non-gist references to the ref and its base form only" {
    $ref = "openai/skills/skills/.curated/gh-address-comments"
    $keys = @(Get-ManifestReferenceCandidateKeys -Reference "$ref#deadbeef")
    $keys | Should -Contain "$ref#deadbeef"
    $keys | Should -Contain $ref
    $keys | Should -Not -Contain "octocat/5a123456"
  }

  It "builds the manifest reference key set with gist aliases" {
    @"
name: apm-workspace
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - https://gist.github.com/alice/abc123.git
    - https://gist.github.com/bob/def456.git#deadbeef
    - openai/skills/skills/.curated/gh-address-comments
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")

    $keys = Get-ManifestReferenceKeys

    $keys | Should -Contain "https://gist.github.com/alice/abc123.git"
    $keys | Should -Contain "alice/abc123"
    $keys | Should -Contain "https://gist.github.com/bob/def456.git#deadbeef"
    $keys | Should -Contain "https://gist.github.com/bob/def456.git"
    $keys | Should -Contain "bob/def456"
    $keys | Should -Contain "bob/def456#deadbeef"
    $keys | Should -Contain "openai/skills/skills/.curated/gh-address-comments"
    # The managed catalog ref is intentionally filtered out of manifest keys.
    $keys | Should -Not -Contain "jey3dayo/apm-workspace/catalog#main"
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
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
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
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    $agentationPath = Join-Path (Join-Path (Join-Path $script:WorkspaceDir "apm_modules") "benjitaylor") "agentation"
    $agentationPath = Join-Path $agentationPath "skills/agentation"
    New-Item -ItemType Directory -Path $agentationPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $agentationPath "SKILL.md") -Value "# agentation"

    $records = @(Get-ExternalSkillRecords)

    $records.Count | Should -Be 1
    $records[0].SourceSkillId | Should -Be "agentation"
    $records[0].CanonicalReference | Should -Be "benjitaylor/agentation/skills/agentation"
  }

  It "hints apm lock -g when a lock record has no manifest declaration" {
    @"
name: apm-workspace
dependencies:
  apm:
    - benjitaylor/agentation/skills/agentation
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: acme/orphaned-dep
    host: github.com
    resolved_commit: 5555555555555555
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    { Get-ExternalSkillRecords } | Should -Throw "*apm lock -g*"
  }

  It "does not hint apm lock -g when a manifest ref is missing from the lock" {
    @"
name: apm-workspace
dependencies:
  apm:
    - acme/missing-from-lock
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies: []
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    { Get-ExternalSkillRecords } | Should -Throw
    try {
      Get-ExternalSkillRecords
    }
    catch {
      $_.Exception.Message | Should -Not -BeLike "*apm lock -g*"
    }
  }

  It "matches a manifest skill subset written as a full URL git: form the same as shorthand" {
    @"
name: apm-workspace
dependencies:
  apm:
    - git: https://github.com/nextlevelbuilder/ui-ux-pro-max-skill.git
      skills:
        - design
        - ui-ux-pro-max
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")

    # apm.lock.yaml's repo_url is recorded in canonical form (owner/repo), not
    # the literal git: value the manifest author wrote, so lookups must match
    # a full-URL git: entry against that canonical form too.
    $subset = @(Get-ManifestExternalSkillSubset -Reference "nextlevelbuilder/ui-ux-pro-max-skill")

    $subset | Should -Be @("design", "ui-ux-pro-max")
  }

  It "matches object git and path dependencies by their canonical reference for subsets and aliases" {
    @"
name: apm-workspace
dependencies:
  apm:
    - git: https://github.com/acme/tools.git
      alias: example-tools
      path: packages/example
      skills:
        - example
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")

    $references = @(Get-ManifestApmDependencyReferences)
    $references | Should -Contain "https://github.com/acme/tools.git/packages/example"

    $keys = @(Get-ManifestReferenceCandidateKeys -Reference $references[0])
    $keys | Should -Contain "acme/tools/packages/example"

    $subset = @(Get-ManifestExternalSkillSubset -Reference "acme/tools/packages/example")
    $subset | Should -Be @("example")

    $alias = Get-ManifestDependencyAlias -Reference "acme/tools" -Path "packages/example"
    $alias | Should -Be "example-tools"

    $aliasSkillDir = Join-Path (Join-Path (Join-Path $script:WorkspaceDir "apm_modules") "example-tools") "packages/example"
    New-Item -ItemType Directory -Path $aliasSkillDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $aliasSkillDir "SKILL.md") -Value "# example"

    Get-ExternalSkillId -RepoUrl "acme/tools" -VirtualPath "packages/example" | Should -Be "example-tools"
    Get-ExternalSkillInstallPath -RepoUrl "acme/tools" -VirtualPath "packages/example" -ResolvedCommit "abc123" | Should -Be $aliasSkillDir
  }

  It "does not match path dependencies as a bare repo or a sibling path" {
    @"
name: apm-workspace
dependencies:
  apm:
    - git: https://github.com/acme/tools.git
      alias: first-path
      skills:
        - first
      path: packages/first
    - git: https://github.com/acme/tools.git
      path: packages/second
      alias: second-path
      skills:
        - second
    - git: https://github.com/acme/tools.git
      alias: repo-only
      skills:
        - root-only
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")

    @(Get-ManifestExternalSkillSubset -Reference "acme/tools") | Should -Be @("root-only")
    @(Get-ManifestExternalSkillSubset -Reference "acme/tools/packages/first") | Should -Be @("first")
    @(Get-ManifestExternalSkillSubset -Reference "acme/tools/packages/second") | Should -Be @("second")

    Get-ManifestDependencyAlias -Reference "acme/tools" | Should -Be "repo-only"
    Get-ManifestDependencyAlias -Reference "acme/tools" -Path "packages/first" | Should -Be "first-path"
    Get-ManifestDependencyAlias -Reference "acme/tools" -Path "packages/second" | Should -Be "second-path"
    @(Get-GitReferenceCandidateKeys -Reference "https://github.com/acme/tools.git" -Path "packages/first") | Should -Not -Contain "acme/tools"
  }

  It "expands manual-skills package roots into copied skills" {
    $previousWorkspaceDir = $script:WorkspaceDir
    $previousGlobalWorkspaceDir = $global:WorkspaceDir
    $workspaceDir = Join-Path $TestDrive "workspace-manual-skills"
    $script:WorkspaceDir = $workspaceDir
    $WorkspaceDir = $workspaceDir
    $global:WorkspaceDir = $workspaceDir
    New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null

    @"
name: apm-workspace
version: 1.0.0
description: test
author: test
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - jey3dayo/apm-workspace/manual-skills
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: jey3dayo/apm-workspace
    host: github.com
    resolved_commit: 3333333333333333
    virtual_path: manual-skills
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    $manualSkillsRoot = Join-Path (Join-Path (Join-Path $script:WorkspaceDir "apm_modules") "jey3dayo") "apm-workspace"
    $manualSkillsRoot = Join-Path $manualSkillsRoot "manual-skills/.apm/skills"
    New-Item -ItemType Directory -Path (Join-Path $manualSkillsRoot "ui-ux-pro-max") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $manualSkillsRoot "ui-ux-pro-max/SKILL.md") -Value "# ui-ux-pro-max"
    New-Item -ItemType Directory -Path (Join-Path $manualSkillsRoot "sharp-edges") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $manualSkillsRoot "sharp-edges/SKILL.md") -Value "# sharp-edges"

    try {
      $records = @(Get-ExternalSkillRecords)

      $records.Count | Should -Be 2
      $skillIds = @($records | ForEach-Object SourceSkillId | Sort-Object)
      $skillIds | Should -Contain "sharp-edges"
      $skillIds | Should -Contain "ui-ux-pro-max"
      $canonicalRefs = @($records | ForEach-Object CanonicalReference | Sort-Object)
      $canonicalRefs | Should -Contain "jey3dayo/apm-workspace/manual-skills#sharp-edges"
      $canonicalRefs | Should -Contain "jey3dayo/apm-workspace/manual-skills#ui-ux-pro-max"
    }
    finally {
      $script:WorkspaceDir = $previousWorkspaceDir
      $global:WorkspaceDir = $previousGlobalWorkspaceDir
    }
  }

  It "expands repo-root package skills into copied skills" {
    $previousWorkspaceDir = $script:WorkspaceDir
    $previousGlobalWorkspaceDir = $global:WorkspaceDir
    $workspaceDir = Join-Path $TestDrive "workspace-root-package-skills"
    $script:WorkspaceDir = $workspaceDir
    $WorkspaceDir = $workspaceDir
    $global:WorkspaceDir = $workspaceDir
    New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null

    @"
name: apm-workspace
version: 1.0.0
description: test
author: test
dependencies:
  apm:
    - nextlevelbuilder/ui-ux-pro-max-skill
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: nextlevelbuilder/ui-ux-pro-max-skill
    host: github.com
    resolved_commit: 4444444444444444
    package_type: marketplace_plugin
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    $skillsRoot = Join-Path (Join-Path (Join-Path $script:WorkspaceDir "apm_modules") "nextlevelbuilder") "ui-ux-pro-max-skill"
    $skillsRoot = Join-Path $skillsRoot ".apm/skills"
    New-Item -ItemType Directory -Path (Join-Path $skillsRoot "ui-ux-pro-max") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillsRoot "ui-ux-pro-max/SKILL.md") -Value "# ui-ux-pro-max"

    try {
      $records = @(Get-ExternalSkillRecords)

      $records.Count | Should -Be 1
      $records[0].SourceSkillId | Should -Be "ui-ux-pro-max"
      $records[0].CanonicalReference | Should -Be "nextlevelbuilder/ui-ux-pro-max-skill#ui-ux-pro-max"
    }
    finally {
      $script:WorkspaceDir = $previousWorkspaceDir
      $global:WorkspaceDir = $previousGlobalWorkspaceDir
    }
  }

  It "prefers repo-root claude skills when a package also has apm skills" {
    $previousWorkspaceDir = $script:WorkspaceDir
    $previousGlobalWorkspaceDir = $global:WorkspaceDir
    $workspaceDir = Join-Path $TestDrive "workspace-root-package-claude-skills"
    $script:WorkspaceDir = $workspaceDir
    $WorkspaceDir = $workspaceDir
    $global:WorkspaceDir = $workspaceDir
    New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null

    @"
name: apm-workspace
version: 1.0.0
description: test
author: test
dependencies:
  apm:
    - nextlevelbuilder/ui-ux-pro-max-skill
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: nextlevelbuilder/ui-ux-pro-max-skill
    host: github.com
    resolved_commit: 4444444444444444
    package_type: marketplace_plugin
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    $packageRoot = Join-Path (Join-Path (Join-Path $script:WorkspaceDir "apm_modules") "nextlevelbuilder") "ui-ux-pro-max-skill"
    $apmSkillRoot = Join-Path $packageRoot ".apm/skills/ui-ux-pro-max"
    $claudeSkillRoot = Join-Path $packageRoot ".claude/skills/ui-ux-pro-max"
    New-Item -ItemType Directory -Path $apmSkillRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $claudeSkillRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $apmSkillRoot "SKILL.md") -Value "# thin ui-ux-pro-max"
    Set-Content -LiteralPath (Join-Path $claudeSkillRoot "SKILL.md") -Value "# full ui-ux-pro-max"

    try {
      $records = @(Get-ExternalSkillRecords)

      $records.Count | Should -Be 1
      $records[0].SourceSkillId | Should -Be "ui-ux-pro-max"
      $records[0].SourcePath | Should -Be $claudeSkillRoot
    }
    finally {
      $script:WorkspaceDir = $previousWorkspaceDir
      $global:WorkspaceDir = $previousGlobalWorkspaceDir
    }
  }

  It "resolves a plain skills/<name> bundle declared with a skills: subset" {
    $previousWorkspaceDir = $script:WorkspaceDir
    $previousGlobalWorkspaceDir = $global:WorkspaceDir
    $workspaceDir = Join-Path $TestDrive "workspace-plain-skills-bundle"
    $script:WorkspaceDir = $workspaceDir
    $WorkspaceDir = $workspaceDir
    $global:WorkspaceDir = $workspaceDir
    New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null

    @"
name: apm-workspace
version: 1.0.0
description: test
author: test
dependencies:
  apm:
    - git: acme/bundle
      skills:
        - a
        - c
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: acme/bundle
    host: github.com
    resolved_commit: 1111111111111111111111111111111111111111
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    $bundleSkillsRoot = Join-Path (Join-Path (Join-Path $script:WorkspaceDir "apm_modules") "acme") "bundle"
    $bundleSkillsRoot = Join-Path $bundleSkillsRoot "skills"
    New-Item -ItemType Directory -Path (Join-Path $bundleSkillsRoot "a") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $bundleSkillsRoot "b") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $bundleSkillsRoot "c") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $bundleSkillsRoot "a/SKILL.md") -Value "# a"
    Set-Content -LiteralPath (Join-Path $bundleSkillsRoot "b/SKILL.md") -Value "# b"
    Set-Content -LiteralPath (Join-Path $bundleSkillsRoot "c/SKILL.md") -Value "# c"

    try {
      $records = @(Get-ExternalSkillRecords)

      $records.Count | Should -Be 2
      $skillIds = @($records | ForEach-Object SourceSkillId | Sort-Object)
      $skillIds | Should -Be @("a", "c")
      $recordA = $records | Where-Object SourceSkillId -eq "a"
      $recordA.SourcePath | Should -Be (Join-Path $bundleSkillsRoot "a")
      $recordA.CanonicalReference | Should -Be "acme/bundle#a"
    }
    finally {
      $script:WorkspaceDir = $previousWorkspaceDir
      $global:WorkspaceDir = $previousGlobalWorkspaceDir
    }
  }

  It "prefers .apm/skills over a sibling top-level skills/ directory" {
    $previousWorkspaceDir = $script:WorkspaceDir
    $previousGlobalWorkspaceDir = $global:WorkspaceDir
    $workspaceDir = Join-Path $TestDrive "workspace-apm-skills-priority"
    $script:WorkspaceDir = $workspaceDir
    $WorkspaceDir = $workspaceDir
    $global:WorkspaceDir = $workspaceDir
    New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null

    @"
name: apm-workspace
version: 1.0.0
description: test
author: test
dependencies:
  apm:
    - git: acme/bundle2
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: acme/bundle2
    host: github.com
    resolved_commit: 2222222222222222222222222222222222222222
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    $packageRoot = Join-Path (Join-Path (Join-Path $script:WorkspaceDir "apm_modules") "acme") "bundle2"
    $apmSkillsRoot = Join-Path $packageRoot ".apm/skills/x"
    $plainSkillsRoot = Join-Path $packageRoot "skills/y"
    New-Item -ItemType Directory -Path $apmSkillsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $plainSkillsRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $apmSkillsRoot "SKILL.md") -Value "# x"
    Set-Content -LiteralPath (Join-Path $plainSkillsRoot "SKILL.md") -Value "# y"

    try {
      $records = @(Get-ExternalSkillRecords)

      $records.Count | Should -Be 1
      $records[0].SourceSkillId | Should -Be "x"
      $records[0].SourcePath | Should -Be $apmSkillsRoot
      $records[0].CanonicalReference | Should -Be "acme/bundle2#x"
    }
    finally {
      $script:WorkspaceDir = $previousWorkspaceDir
      $global:WorkspaceDir = $previousGlobalWorkspaceDir
    }
  }

  It "does not fall back to skills/ for a repo-root single skill with no subset declared" {
    $previousWorkspaceDir = $script:WorkspaceDir
    $previousGlobalWorkspaceDir = $global:WorkspaceDir
    $workspaceDir = Join-Path $TestDrive "workspace-rootskill-no-subset"
    $script:WorkspaceDir = $workspaceDir
    $WorkspaceDir = $workspaceDir
    $global:WorkspaceDir = $workspaceDir
    New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null

    @"
name: apm-workspace
version: 1.0.0
description: test
author: test
dependencies:
  apm:
    - acme/rootskill
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: acme/rootskill
    host: github.com
    resolved_commit: 3333333333333333333333333333333333333333
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    $packageRoot = Join-Path (Join-Path (Join-Path $script:WorkspaceDir "apm_modules") "acme") "rootskill"
    $nestedSkillRoot = Join-Path $packageRoot "skills/x"
    New-Item -ItemType Directory -Path $nestedSkillRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $packageRoot "SKILL.md") -Value "# rootskill"
    Set-Content -LiteralPath (Join-Path $nestedSkillRoot "SKILL.md") -Value "# x"

    try {
      $records = @(Get-ExternalSkillRecords)

      $records.Count | Should -Be 1
      $records[0].SourceSkillId | Should -Be "rootskill"
      $records[0].SourcePath | Should -Be $packageRoot
      $records[0].CanonicalReference | Should -Be "acme/rootskill"
    }
    finally {
      $script:WorkspaceDir = $previousWorkspaceDir
      $global:WorkspaceDir = $previousGlobalWorkspaceDir
    }
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
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

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
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    $records = @(Get-LockedExternalSkillRecords)

    $records.Count | Should -Be 1
    $records[0].Repo | Should -Be "openai/skills"
    $records[0].Path | Should -Be "skills/.curated/gh-address-comments"
    $records[0].Commit | Should -Be "abcdef1234567890"
  }

  It "passes when the local package cache matches the tracked catalog" {
    $catalogRoot = Join-Path $script:WorkspaceDir "catalog"
    $apmModulesRoot = Join-Path $script:WorkspaceDir "apm_modules"
    Remove-Item -LiteralPath $catalogRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $apmModulesRoot -Recurse -Force -ErrorAction SilentlyContinue
    $trackedDir = Join-Path $catalogRoot "skills\foo"
    $cacheDir = Join-Path $script:WorkspaceDir "apm_modules\jey3dayo\apm-workspace\catalog\skills\foo"
    New-Item -ItemType Directory -Path $trackedDir -Force | Out-Null
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $trackedDir "SKILL.md") -Value "a"
    Set-Content -LiteralPath (Join-Path $cacheDir "SKILL.md") -Value "a"
    Initialize-GitTrackedDirectory -Directory $catalogRoot

    { Assert-CatalogCacheFreshness } | Should -Not -Throw
  }

  It "throws naming deploy:fresh when a tracked file is missing from the cache" {
    $catalogRoot = Join-Path $script:WorkspaceDir "catalog"
    $apmModulesRoot = Join-Path $script:WorkspaceDir "apm_modules"
    Remove-Item -LiteralPath $catalogRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $apmModulesRoot -Recurse -Force -ErrorAction SilentlyContinue
    $trackedDir = Join-Path $catalogRoot "skills\new-skill"
    $cacheRoot = Join-Path $script:WorkspaceDir "apm_modules\jey3dayo\apm-workspace\catalog"
    New-Item -ItemType Directory -Path $trackedDir -Force | Out-Null
    New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $trackedDir "SKILL.md") -Value "a"
    Initialize-GitTrackedDirectory -Directory $catalogRoot

    { Assert-CatalogCacheFreshness } | Should -Throw "*deploy:fresh*"
  }

  It "throws naming deploy:fresh when the cache directory is absent" {
    $catalogRoot = Join-Path $script:WorkspaceDir "catalog"
    $apmModulesRoot = Join-Path $script:WorkspaceDir "apm_modules"
    Remove-Item -LiteralPath $catalogRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $apmModulesRoot -Recurse -Force -ErrorAction SilentlyContinue
    $trackedDir = Join-Path $catalogRoot "skills\foo"
    New-Item -ItemType Directory -Path $trackedDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $trackedDir "SKILL.md") -Value "a"
    Initialize-GitTrackedDirectory -Directory $catalogRoot

    { Assert-CatalogCacheFreshness } | Should -Throw "*deploy:fresh*"
  }

  It "ignores gitignored untracked files under the tracked catalog dir" {
    $catalogRoot = Join-Path $script:WorkspaceDir "catalog"
    $apmModulesRoot = Join-Path $script:WorkspaceDir "apm_modules"
    Remove-Item -LiteralPath $catalogRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $apmModulesRoot -Recurse -Force -ErrorAction SilentlyContinue
    $trackedDir = Join-Path $catalogRoot "skills\foo"
    $cacheDir = Join-Path $script:WorkspaceDir "apm_modules\jey3dayo\apm-workspace\catalog\skills\foo"
    New-Item -ItemType Directory -Path $trackedDir -Force | Out-Null
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $trackedDir "SKILL.md") -Value "a"
    Set-Content -LiteralPath (Join-Path $cacheDir "SKILL.md") -Value "a"
    $pycacheDir = Join-Path $trackedDir "__pycache__"
    New-Item -ItemType Directory -Path $pycacheDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $pycacheDir "module.cpython-314.pyc") -Value "compiled"

    # Use the repo-local exclude file rather than a tracked .gitignore just to
    # keep this fixture focused on the gitignore behavior in isolation. (A
    # tracked dotfile now works fine here too -- see the dedicated dotfile
    # tests below -- because Assert-CatalogCacheFreshness walks the
    # git-tracked path list directly instead of enumerating the cache with
    # Get-RelativeFilePaths, which is the .NET/Unix dotfile blind spot.)
    & git -C $catalogRoot init -q | Out-Null
    Add-Content -LiteralPath (Join-Path $catalogRoot ".git\info\exclude") -Value "*.pyc"
    & git -C $catalogRoot add -A | Out-Null

    { Assert-CatalogCacheFreshness } | Should -Not -Throw
  }

  It "passes when a tracked dotfile is present in the cache" {
    $catalogRoot = Join-Path $script:WorkspaceDir "catalog"
    $apmModulesRoot = Join-Path $script:WorkspaceDir "apm_modules"
    Remove-Item -LiteralPath $catalogRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $apmModulesRoot -Recurse -Force -ErrorAction SilentlyContinue
    $trackedDir = Join-Path $catalogRoot "skills\foo"
    $cacheDir = Join-Path $script:WorkspaceDir "apm_modules\jey3dayo\apm-workspace\catalog\skills\foo"
    New-Item -ItemType Directory -Path $trackedDir -Force | Out-Null
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $trackedDir "SKILL.md") -Value "a"
    Set-Content -LiteralPath (Join-Path $cacheDir "SKILL.md") -Value "a"
    Set-Content -LiteralPath (Join-Path $catalogRoot ".gitkeep") -Value ""
    Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm_modules\jey3dayo\apm-workspace\catalog\.gitkeep") -Value ""
    Initialize-GitTrackedDirectory -Directory $catalogRoot

    { Assert-CatalogCacheFreshness } | Should -Not -Throw
  }

  It "throws when a tracked dotfile is missing from the cache" {
    $catalogRoot = Join-Path $script:WorkspaceDir "catalog"
    $apmModulesRoot = Join-Path $script:WorkspaceDir "apm_modules"
    Remove-Item -LiteralPath $catalogRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $apmModulesRoot -Recurse -Force -ErrorAction SilentlyContinue
    $trackedDir = Join-Path $catalogRoot "skills\foo"
    $cacheDir = Join-Path $script:WorkspaceDir "apm_modules\jey3dayo\apm-workspace\catalog\skills\foo"
    New-Item -ItemType Directory -Path $trackedDir -Force | Out-Null
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $trackedDir "SKILL.md") -Value "a"
    Set-Content -LiteralPath (Join-Path $cacheDir "SKILL.md") -Value "a"
    Set-Content -LiteralPath (Join-Path $catalogRoot ".gitkeep") -Value ""
    Initialize-GitTrackedDirectory -Directory $catalogRoot

    { Assert-CatalogCacheFreshness } | Should -Throw "*.gitkeep*"
  }

  It "throws naming content differences when a cached file's contents differ from the tracked file" {
    $catalogRoot = Join-Path $script:WorkspaceDir "catalog"
    $apmModulesRoot = Join-Path $script:WorkspaceDir "apm_modules"
    Remove-Item -LiteralPath $catalogRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $apmModulesRoot -Recurse -Force -ErrorAction SilentlyContinue
    $trackedDir = Join-Path $catalogRoot "skills\foo"
    $cacheDir = Join-Path $script:WorkspaceDir "apm_modules\jey3dayo\apm-workspace\catalog\skills\foo"
    New-Item -ItemType Directory -Path $trackedDir -Force | Out-Null
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $trackedDir "SKILL.md") -Value "a"
    Set-Content -LiteralPath (Join-Path $cacheDir "SKILL.md") -Value "DIFFERENT"
    Initialize-GitTrackedDirectory -Directory $catalogRoot

    { Assert-CatalogCacheFreshness } | Should -Throw "*different contents*"
  }

  It "fails closed when git ls-files fails" {
    $catalogRoot = Join-Path $script:WorkspaceDir "catalog"
    $apmModulesRoot = Join-Path $script:WorkspaceDir "apm_modules"
    Remove-Item -LiteralPath $catalogRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $apmModulesRoot -Recurse -Force -ErrorAction SilentlyContinue
    $trackedDir = Join-Path $catalogRoot "skills\foo"
    $cacheDir = Join-Path $script:WorkspaceDir "apm_modules\jey3dayo\apm-workspace\catalog\skills\foo"
    New-Item -ItemType Directory -Path $trackedDir -Force | Out-Null
    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $trackedDir "SKILL.md") -Value "a"
    Set-Content -LiteralPath (Join-Path $cacheDir "SKILL.md") -Value "a"
    # Deliberately skip Initialize-GitTrackedDirectory: `git ls-files` fails
    # (not a git repository), and the gate must not treat that as "no
    # tracked files" and pass vacuously.

    { Assert-CatalogCacheFreshness } | Should -Throw
  }

}

Describe "Assert-TrackedCatalogPublished" {
  BeforeAll {
    $env:APM_WORKSPACE_LIB_ONLY = "1"
    $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "scripts/apm-workspace.ps1"
    . (Resolve-Path -LiteralPath $modulePath).Path
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY -ErrorAction SilentlyContinue

    function Initialize-PublishedWorkspace {
      param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteDir,

        [Parameter(Mandatory = $true)]
        [string]$WorkspaceDir
      )

      & git init -q --bare $RemoteDir | Out-Null
      & git clone -q $RemoteDir $WorkspaceDir | Out-Null
      & git -C $WorkspaceDir config user.email "test@example.com" | Out-Null
      & git -C $WorkspaceDir config user.name "Test" | Out-Null
      & git -C $WorkspaceDir checkout -q -b main | Out-Null
      New-Item -ItemType Directory -Path (Join-Path $WorkspaceDir "catalog\skills\foo") -Force | Out-Null
      Set-Content -LiteralPath (Join-Path $WorkspaceDir "catalog\skills\foo\SKILL.md") -Value "a"
      & git -C $WorkspaceDir add -A | Out-Null
      & git -C $WorkspaceDir commit -q -m "init" | Out-Null
      & git -C $WorkspaceDir push -q -u origin main | Out-Null
    }
  }

  BeforeEach {
    # Each fixture creates and pushes a real git repo, so every test needs
    # its own unique paths -- $TestDrive is shared across It blocks within
    # this Describe and is not reset between them.
    $script:caseId = [guid]::NewGuid().ToString("N")
    $script:WorkspaceDir = Join-Path $TestDrive "workspace-$script:caseId"
    $WorkspaceDir = $script:WorkspaceDir
    $global:WorkspaceDir = $script:WorkspaceDir
  }

  It "throws when the tracked catalog has uncommitted changes" {
    $remoteDir = Join-Path $TestDrive "remote-$script:caseId.git"
    Initialize-PublishedWorkspace -RemoteDir $remoteDir -WorkspaceDir $script:WorkspaceDir

    Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "catalog\skills\foo\SKILL.md") -Value "dirty"

    { Assert-TrackedCatalogPublished } | Should -Throw "*uncommitted changes*"
  }

  It "throws when the tracked catalog has commits not on the upstream" {
    $remoteDir = Join-Path $TestDrive "remote-$script:caseId.git"
    Initialize-PublishedWorkspace -RemoteDir $remoteDir -WorkspaceDir $script:WorkspaceDir

    Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "catalog\skills\foo\extra.md") -Value "b"
    & git -C $script:WorkspaceDir add -A | Out-Null
    & git -C $script:WorkspaceDir commit -q -m "unpushed" | Out-Null

    { Assert-TrackedCatalogPublished } | Should -Throw "*commits not on*"
  }

  It "fails closed when the workspace is not a git repository" {
    New-Item -ItemType Directory -Path (Join-Path $script:WorkspaceDir "catalog\skills\foo") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "catalog\skills\foo\SKILL.md") -Value "a"
    # Deliberately skip git init: git status/rev-list must fail, and the gate
    # must not treat that failure as "clean" / "pushed".

    { Assert-TrackedCatalogPublished } | Should -Throw
  }
}

Describe "public command surface" {
  BeforeAll {
    $env:APM_WORKSPACE_LIB_ONLY = "1"
    $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "scripts/apm-workspace.ps1"
    . (Resolve-Path -LiteralPath $modulePath).Path
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY -ErrorAction SilentlyContinue

    function Remove-MiseCommentLines {
      param([string]$Content)

      (($Content -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }
  }

  BeforeEach {
    $script:WorkspaceDir = Join-Path $TestDrive "workspace"
    $WorkspaceDir = $script:WorkspaceDir
    $global:WorkspaceDir = $script:WorkspaceDir
    New-Item -ItemType Directory -Path $script:WorkspaceDir -Force | Out-Null
  }

  It "runs apm install -g --only apm between agmsg save and restore" {
    $script:installPinsCalls = New-Object System.Collections.Generic.List[string]

    function global:apm {
      $script:installPinsCalls.Add("apm " + (@($args) -join ' '))
      $global:LASTEXITCODE = 0
    }

    try {
      Mock Require-Apm {}
      Mock Ensure-WorkspaceRepo {}
      Mock Ensure-WorkspaceScaffold {}
      Mock Refresh-WorkspaceCheckout {}
      Mock Invoke-AgmsgStateSave { $script:installPinsCalls.Add("save") }
      Mock Invoke-AgmsgStateRestoreOrThrow { $script:installPinsCalls.Add("restore") }
      Mock Invoke-AgmsgStateRestore { $script:installPinsCalls.Add("recovery-restore") }

      Invoke-InstallPins

      $script:installPinsCalls | Should -Be @("save", "apm install -g --only apm", "restore")
      Assert-MockCalled Refresh-WorkspaceCheckout -Times 0 -Exactly
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }
  }

  It "fails install-pins when apm install fails and still restores the agmsg roster" {
    $script:installPinsCalls = New-Object System.Collections.Generic.List[string]

    function global:apm {
      $script:installPinsCalls.Add("apm " + (@($args) -join ' '))
      $global:LASTEXITCODE = 1
    }

    try {
      Mock Require-Apm {}
      Mock Ensure-WorkspaceRepo {}
      Mock Ensure-WorkspaceScaffold {}
      Mock Invoke-AgmsgStateSave { $script:installPinsCalls.Add("save") }
      Mock Invoke-AgmsgStateRestoreOrThrow { $script:installPinsCalls.Add("restore") }
      Mock Invoke-AgmsgStateRestore { $script:installPinsCalls.Add("recovery-restore") }

      { Invoke-InstallPins } | Should -Throw "apm install -g --only apm failed."

      $script:installPinsCalls | Should -Be @("save", "apm install -g --only apm", "recovery-restore")
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }
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
    Mock Normalize-CodexMcpConfig {}
    Mock Invoke-CodexCompile {}
    # Invoke-AgmsgStateSave/Restore(OrThrow) shell out to agmsg-state.ps1
    # against the real $HOME by design (see its own subprocess-based test
    # suite); mocked here so this unit test doesn't touch this machine's real
    # agmsg roster.
    Mock Invoke-AgmsgStateSave {}
    Mock Invoke-AgmsgStateRestore {}
    Mock Invoke-AgmsgStateRestoreOrThrow {}

    Invoke-Apply

    Assert-MockCalled Install-WorkspaceMcpDependencies -Times 1 -Exactly
    Assert-MockCalled Normalize-CodexMcpConfig -Times 2 -Exactly
  }

  It "throws from Invoke-Apply when the final agmsg roster restore fails on an otherwise normal run" {
    Mock Require-Apm {}
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Invoke-ValidateCatalog {}
    Mock Ensure-WorkspaceMiseFile {}
    Mock Test-ManifestHasLocalPackages { $false }
    Mock New-TemporaryDirectory { Join-Path $TestDrive "apm-apply-restore-fail" }
    Mock Build-TargetSkillTrees {}
    Mock Sync-ManagedCatalogRuntimeAssets {}
    Mock Replace-SkillTargetsFromStage {}
    Mock Install-WorkspaceMcpDependencies {}
    Mock Normalize-CodexMcpConfig {}
    Mock Invoke-CodexCompile {}
    Mock Invoke-AgmsgStateSave {}

    # Invoke-Apply calls Invoke-AgmsgStateRestoreOrThrow twice on a normal
    # run: once right after the skill-tree swap, once more (after `trap -
    # EXIT`'s PowerShell equivalent, the $applySucceeded flag) at the very
    # end. Succeed the first call and fail the second, so this exercises the
    # normal-completion path specifically -- restore failing must not be
    # swallowed, and the failure-recovery-only Invoke-AgmsgStateRestore must
    # not run in its place.
    $script:agmsgRestoreOrThrowCallCount = 0
    Mock Invoke-AgmsgStateRestoreOrThrow {
      $script:agmsgRestoreOrThrowCallCount++
      if ($script:agmsgRestoreOrThrowCallCount -ge 2) {
        throw "agmsg roster restore ran but the roster link postcondition still fails; see the error above."
      }
    }
    Mock Invoke-AgmsgStateRestore {
      throw "Invoke-AgmsgStateRestore (failure-recovery only) must not run when Invoke-Apply completes normally."
    }

    { Invoke-Apply } | Should -Throw "*roster link postcondition still fails*"
    $script:agmsgRestoreOrThrowCallCount | Should -Be 2
  }

  It "preserves the original failure from Invoke-Apply and only reports (never masks) a recovery-restore failure" {
    Mock Require-Apm {}
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Invoke-ValidateCatalog {}
    Mock Ensure-WorkspaceMiseFile {}
    Mock Test-ManifestHasLocalPackages { $false }
    Mock New-TemporaryDirectory { Join-Path $TestDrive "apm-apply-original-failure" }
    Mock Build-TargetSkillTrees {}
    Mock Sync-ManagedCatalogRuntimeAssets {}
    Mock Replace-SkillTargetsFromStage {}
    Mock Install-WorkspaceMcpDependencies {}
    Mock Normalize-CodexMcpConfig {}
    Mock Invoke-AgmsgStateSave {}
    # Fails before the skill-tree swap ever runs, so the mid-apply
    # Invoke-AgmsgStateRestoreOrThrow call never happens either -- only the
    # outer `finally`'s recovery restore should run.
    Mock Invoke-CodexCompile { throw "boom: apm compile failed" }

    $script:recoveryRestoreCalled = $false
    Mock Invoke-AgmsgStateRestore {
      # Mirrors its real never-throws contract: report, don't propagate.
      $script:recoveryRestoreCalled = $true
    }
    Mock Invoke-AgmsgStateRestoreOrThrow {
      throw "Invoke-AgmsgStateRestoreOrThrow (normal-completion only) must not run when Invoke-Apply aborts early."
    }

    { Invoke-Apply } | Should -Throw "*boom: apm compile failed*"
    $script:recoveryRestoreCalled | Should -Be $true
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

  It "removes unsupported Codex MCP identity fields from project config" {
    $configDir = Join-Path $workspaceDir ".codex"
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    @"
[mcp_servers.context7]
command = "npx"
id = ""

[mcp_servers.context7.env]
id = "preserve nested"

[other]
id = "preserve"
"@ | Set-Content -LiteralPath (Join-Path $configDir "config.toml") -NoNewline

    Normalize-CodexMcpConfig -ConfigPath (Join-Path $configDir "config.toml")

    $config = Get-Content -LiteralPath (Join-Path $configDir "config.toml") -Raw
    $config | Should -Not -Match '(?m)^id = ""$'
    $config | Should -Match '(?m)^id = "preserve"$'
  }

  It "removes only top-level MCP identity fields from a user-global config" {
    $fakeHome = Join-Path $TestDrive "fake-home"
    $configDir = Join-Path $fakeHome ".codex"
    $configPath = Join-Path $configDir "config.toml"
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    @"
[notice.model_migrations]
id = "preserve notice"

[mcp_servers.mobbin]
transport = "http"
id = ""

[mcp_servers.mobbin.env]
id = "preserve nested"

[other]
id = "preserve other"
"@ | Set-Content -LiteralPath $configPath -NoNewline

    Normalize-CodexMcpConfig -ConfigPath $configPath

    $config = Get-Content -LiteralPath $configPath -Raw
    $config | Should -Not -Match '(?m)^id = ""$'
    $config | Should -Match '(?m)^id = "preserve notice"$'
    $config | Should -Match '(?m)^id = "preserve nested"$'
    $config | Should -Match '(?m)^id = "preserve other"$'
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

  It "keeps local workspace scripts self-contained" {
    $miseToml = Get-Content -LiteralPath (Join-Path $workspaceRoot "mise.toml") -Raw
    $shellScript = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/apm-workspace.sh") -Raw
    $powerShellScript = Get-Content -LiteralPath $scriptPath -Raw
    $miseTomlWithoutComments = Remove-MiseCommentLines $miseToml
    $shellScriptWithoutComments = Remove-MiseCommentLines $shellScript
    $powerShellScriptWithoutComments = Remove-MiseCommentLines $powerShellScript

    $miseTomlWithoutComments | Should -Not -Match 'APM_BOOTSTRAP_REPO'
    $shellScriptWithoutComments | Should -Not -Match 'APM_BOOTSTRAP_REPO'
    $shellScriptWithoutComments | Should -Not -Match '~/.config'
    $powerShellScriptWithoutComments | Should -Not -Match 'APM_BOOTSTRAP_REPO'
    $powerShellScriptWithoutComments | Should -Not -Match '\\.config\\scripts\\apm-workspace'
  }

  It "keeps workspace docs self-contained and preserves the bold headings exception" {
    $legacyDocsPattern = [regex]::Escape('~/.config/docs/')
    $files = @(
      (Join-Path $workspaceRoot "README.md")
      (Join-Path $workspaceRoot "llms.txt")
      (Join-Path $workspaceRoot "docs/apm-task-coverage.md")
    )

    foreach ($file in $files) {
      $content = Get-Content -LiteralPath $file -Raw
      $content | Should -Not -Match $legacyDocsPattern
    }

    # The helper path moved out of mise.toml into the task runners.
    foreach ($runner in @("scripts/format-bold-headings.sh", "scripts/format-bold-headings.ps1")) {
      $content = Get-Content -LiteralPath (Join-Path $workspaceRoot $runner) -Raw
      $content | Should -Match 'replace-bold-headings\.ts'
    }
  }

  It "maps runtime config filenames per target" {
    $targets = @(Get-ManagedCatalogRuntimeTargets)

    ($targets | Where-Object Name -eq "claude").ConfigName | Should -Be "CLAUDE.md"
    ($targets | Where-Object Name -eq "codex").ConfigName | Should -Be "AGENTS.md"
    ($targets | Where-Object Name -eq "cursor").ConfigName | Should -Be "AGENTS.md"
  }

  It "removes physical project skills while preserving bridge symlinks and adjacent files" {
    $agentsRoot = Join-Path $workspaceDir ".agents/skills"
    $claudeRoot = Join-Path $workspaceDir ".claude/skills"
    $bridgeSource = Join-Path $workspaceDir ".apm/skills/workspace-only"
    $adjacentFile = Join-Path $agentsRoot "notes/README.md"

    New-Item -ItemType Directory -Path $bridgeSource, (Join-Path $agentsRoot "stale-skill"), (Join-Path $claudeRoot "stale-skill"), (Split-Path -Parent $adjacentFile) -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $agentsRoot "stale-skill/SKILL.md") -Value "# stale"
    Set-Content -LiteralPath (Join-Path $claudeRoot "stale-skill/SKILL.md") -Value "# stale"
    Set-Content -LiteralPath $adjacentFile -Value "keep me"
    New-Item -ItemType SymbolicLink -Path (Join-Path $agentsRoot "workspace-only") -Target $bridgeSource | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $claudeRoot "workspace-only") -Target $bridgeSource | Out-Null

    Remove-LegacyWorkspaceSkillTargets

    Test-Path -LiteralPath (Join-Path $agentsRoot "stale-skill") | Should -Be $false
    Test-Path -LiteralPath (Join-Path $claudeRoot "stale-skill") | Should -Be $false
    (Get-Item -LiteralPath (Join-Path $agentsRoot "workspace-only") -Force).LinkType | Should -Be "SymbolicLink"
    (Get-Item -LiteralPath (Join-Path $claudeRoot "workspace-only") -Force).LinkType | Should -Be "SymbolicLink"
    (Get-Content -LiteralPath $adjacentFile -Raw).Trim() | Should -Be "keep me"
  }

  It "replaces managed agent trees without touching adjacent runtime assets" {
    $catalogRoot = Join-Path $TestDrive "catalog"
    $runtimeRoot = Join-Path $TestDrive "runtime"
    $targetRoot = Join-Path $runtimeRoot ".claude"
    $agentsSource = Join-Path $catalogRoot "agents"
    $agentsTarget = Join-Path $targetRoot "agents"
    $untouchedCommand = Join-Path $targetRoot "commands/untouched.md"

    New-Item -ItemType Directory -Path $agentsSource, $agentsTarget, (Split-Path -Parent $untouchedCommand) -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $agentsSource "current.md") -Value "current"
    Set-Content -LiteralPath (Join-Path $agentsTarget "current.md") -Value "old"
    Set-Content -LiteralPath (Join-Path $agentsTarget "stale.md") -Value "stale"
    Set-Content -LiteralPath $untouchedCommand -Value "outside"

    Mock Get-TrackedCatalogDir { $catalogRoot }
    Mock Get-ManagedCatalogRuntimeTargets {
      @([pscustomobject]@{ Name = "claude"; Root = $targetRoot; SkillsRoot = $targetRoot; ConfigName = "CLAUDE.md" })
    }

    Sync-ManagedCatalogRuntimeAssets

    ((Get-Content -LiteralPath (Join-Path $agentsTarget "current.md") -Raw) -replace '\r?\n$', '') | Should -Be "current"
    Test-Path -LiteralPath (Join-Path $agentsTarget "stale.md") | Should -Be $false
    ((Get-Content -LiteralPath $untouchedCommand -Raw) -replace '\r?\n$', '') | Should -Be "outside"
  }

  It "delivers commands but writes no config to a target with ConfigName '-'" {
    $catalogRoot = Join-Path $TestDrive "noconfig-catalog"
    $targetRoot = Join-Path $TestDrive "noconfig-target"
    $instructions = Join-Path $catalogRoot "CLAUDE.md"
    $commandsSource = Join-Path $catalogRoot "commands"

    New-Item -ItemType Directory -Path $commandsSource, $targetRoot -Force | Out-Null
    Set-Content -LiteralPath $instructions -Value "# instructions"
    Set-Content -LiteralPath (Join-Path $commandsSource "cmd.md") -Value "cmd"

    Mock Get-TrackedCatalogDir { $catalogRoot }
    Mock Get-TrackedCatalogInstructionsPath { $instructions }
    Mock Get-ManagedCatalogRuntimeTargets {
      @([pscustomobject]@{ Name = "opencode"; Root = $targetRoot; SkillsRoot = "-"; AgentsFace = "-"; ConfigName = "-" })
    }

    Sync-ManagedCatalogRuntimeAssets

    Test-Path -LiteralPath (Join-Path $targetRoot "CLAUDE.md") | Should -Be $false
    Test-Path -LiteralPath (Join-Path $targetRoot "commands/cmd.md") | Should -Be $true
  }

  It "removes a manifest-tracked file the catalog dropped" {
    $sourceDir = Join-Path $TestDrive "manifest-drop-source"
    $targetDir = Join-Path $TestDrive "manifest-drop-target"
    New-Item -ItemType Directory -Path $sourceDir, $targetDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceDir "kept.md") -Value "kept"
    Set-Content -LiteralPath (Join-Path $targetDir "kept.md") -Value "kept"
    Set-Content -LiteralPath (Join-Path $targetDir "dropped.md") -Value "dropped"
    Set-Content -LiteralPath (Join-Path $targetDir ".managed-catalog-manifest") -Value @("kept.md", "dropped.md")

    Sync-ManagedCatalogDirWithManifest -SourceDir $sourceDir -DestinationDir $targetDir

    Test-Path -LiteralPath (Join-Path $targetDir "kept.md") | Should -Be $true
    Test-Path -LiteralPath (Join-Path $targetDir "dropped.md") | Should -Be $false
    ((Get-Content -LiteralPath (Join-Path $targetDir ".managed-catalog-manifest")) -join "`n") | Should -Be "kept.md"
  }

  It "preserves a file the catalog never owned" {
    $sourceDir = Join-Path $TestDrive "manifest-preserve-source"
    $targetDir = Join-Path $TestDrive "manifest-preserve-target"
    New-Item -ItemType Directory -Path $sourceDir, $targetDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceDir "catalog.md") -Value "catalog"
    Set-Content -LiteralPath (Join-Path $targetDir "catalog.md") -Value "catalog"
    Set-Content -LiteralPath (Join-Path $targetDir "user-owned.md") -Value "mine"
    Set-Content -LiteralPath (Join-Path $targetDir ".managed-catalog-manifest") -Value @("catalog.md")

    Sync-ManagedCatalogDirWithManifest -SourceDir $sourceDir -DestinationDir $targetDir

    ((Get-Content -LiteralPath (Join-Path $targetDir "user-owned.md") -Raw) -replace '\r?\n$', '') | Should -Be "mine"
  }

  It "skips deletion on first sync when no manifest exists yet" {
    $sourceDir = Join-Path $TestDrive "manifest-first-source"
    $targetDir = Join-Path $TestDrive "manifest-first-target"
    New-Item -ItemType Directory -Path $sourceDir, $targetDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceDir "catalog.md") -Value "catalog"
    Set-Content -LiteralPath (Join-Path $targetDir "pre-existing.md") -Value "pre-existing"

    Sync-ManagedCatalogDirWithManifest -SourceDir $sourceDir -DestinationDir $targetDir

    Test-Path -LiteralPath (Join-Path $targetDir "pre-existing.md") | Should -Be $true
    Test-Path -LiteralPath (Join-Path $targetDir "catalog.md") | Should -Be $true
    ((Get-Content -LiteralPath (Join-Path $targetDir ".managed-catalog-manifest")) -join "`n") | Should -Be "catalog.md"
  }

  It "writes a manifest that matches the new source, including nested paths" {
    $sourceDir = Join-Path $TestDrive "manifest-nested-source"
    $targetDir = Join-Path $TestDrive "manifest-nested-target"
    New-Item -ItemType Directory -Path (Join-Path $sourceDir "nested"), $targetDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceDir "a.md") -Value "a"
    Set-Content -LiteralPath (Join-Path $sourceDir "nested/b.md") -Value "b"

    Sync-ManagedCatalogDirWithManifest -SourceDir $sourceDir -DestinationDir $targetDir

    ((Get-Content -LiteralPath (Join-Path $targetDir ".managed-catalog-manifest")) -join "`n") | Should -Be "a.md`nnested/b.md"
  }

  It "maps codex skills to ~/.agents while keeping config under ~/.codex and opts it out of the agents face" {
    $targets = @(Get-ManagedCatalogRuntimeTargets)
    $codex = $targets | Where-Object Name -eq "codex"

    $codex.Root | Should -Be (Join-Path $HOME ".codex")
    $codex.SkillsRoot | Should -Be (Join-Path $HOME ".agents")
    $codex.AgentsFace | Should -Be "-"
  }

  It "points opencode at the path OpenCode reads and opts it out of the skills and agents faces" {
    $targets = @(Get-ManagedCatalogRuntimeTargets)
    $opencode = $targets | Where-Object Name -eq "opencode"

    $opencode.Root | Should -Be (Join-Path $HOME ".config/opencode")
    $opencode.SkillsRoot | Should -Be "-"
    $opencode.AgentsFace | Should -Be "-"
  }

  It "marks opencode as having no config file because OpenCode never reads CLAUDE.md under its own root" {
    $opencode = @(Get-ManagedCatalogRuntimeTargets) | Where-Object Name -eq "opencode"

    $opencode.ConfigName | Should -Be "-"
  }

  It "uses the final segment of namespaced skill names for all targets" {
    Format-SkillName -Target "claude" -SourceSkillId "sample:spec-init" | Should -Be "spec-init"
    Format-SkillName -Target "codex" -SourceSkillId "mattpocock:wayfinder" | Should -Be "wayfinder"
    Format-SkillName -Target "claude" -SourceSkillId "plain" | Should -Be "plain"
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
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")

    @(Get-UnpinnedExternalReferences) | Should -Be @("openai/skills/skills/.curated/gh-address-comments")
  }

  It "reads unpinned refs from same-indent YAML lists under dependencies apm" {
    @"
name: apm-workspace
dependencies:
  apm:
  - jey3dayo/apm-workspace/catalog#main
  - mattpocock/skills/skills/engineering/wayfinder
  mcp:
  - ignored/mcp-entry
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")

    @(Get-UnpinnedExternalReferences) | Should -Be @("mattpocock/skills/skills/engineering/wayfinder")
  }

  It "treats a plain entry with a trailing YAML comment as unpinned" {
    @"
name: apm-workspace
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - openai/skills/skills/.curated/screenshot # openai/skills is deprecated; no migrated equivalent found in openai/plugins yet
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")

    @(Get-UnpinnedExternalReferences) | Should -Be @("openai/skills/skills/.curated/screenshot")
  }

  It "treats a structured git dependency without a ref sibling as unpinned" {
    @"
name: apm-workspace
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - git: nextlevelbuilder/ui-ux-pro-max-skill
      path: plugins/ui-ux-pro-max
      skills:
        - ui-ux-pro-max
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")

    @(Get-UnpinnedExternalReferences) | Should -Be @("nextlevelbuilder/ui-ux-pro-max-skill/plugins/ui-ux-pro-max")
  }

  It "treats a structured git dependency with a ref sibling as pinned" {
    @"
name: apm-workspace
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - git: nextlevelbuilder/ui-ux-pro-max-skill
      ref: 4444444444444444444444444444444444444444
      skills:
        - ui-ux-pro-max
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")

    @(Get-UnpinnedExternalReferences) | Should -Be @()
  }

  It "pin-external pins a plain reference while preserving its trailing YAML comment" {
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}

    @"
name: apm-workspace
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - openai/skills/skills/.curated/screenshot # openai/skills is deprecated; no migrated equivalent found in openai/plugins yet
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: openai/skills
    host: github.com
    resolved_commit: abcdef1234567890abcdef1234567890abcdef12
    virtual_path: skills/.curated/screenshot
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    Invoke-PinExternal

    $manifestLines = @(Get-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml"))
    $manifestLines | Should -Contain "    - openai/skills/skills/.curated/screenshot#abcdef1234567890abcdef1234567890abcdef12 # openai/skills is deprecated; no migrated equivalent found in openai/plugins yet"
    @(Get-UnpinnedExternalReferences) | Should -Be @()
  }

  It "pin-external matches a case-insensitive git reference while preserving the manifest's original casing" {
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}

    @"
name: apm-workspace
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - Jakubantalik/transitions-dev/skills/transitions-dev
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: jakubantalik/transitions-dev
    host: github.com
    resolved_commit: 1234567890abcdef1234567890abcdef12345678
    virtual_path: skills/transitions-dev
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    Invoke-PinExternal

    $manifestLines = @(Get-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml"))
    $manifestLines | Should -Contain "    - Jakubantalik/transitions-dev/skills/transitions-dev#1234567890abcdef1234567890abcdef12345678"
  }

  It "pin-external adds a ref sibling to a structured git dependency without changing the git value" {
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}

    @"
name: apm-workspace
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - git: nextlevelbuilder/ui-ux-pro-max-skill
      skills:
        - ui-ux-pro-max
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: nextlevelbuilder/ui-ux-pro-max-skill
    host: github.com
    resolved_commit: 4444444444444444444444444444444444444444
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    Invoke-PinExternal

    $manifestLines = @(Get-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml"))
    $manifestLines | Should -Contain "    - git: nextlevelbuilder/ui-ux-pro-max-skill"
    $manifestLines | Should -Contain "      ref: 4444444444444444444444444444444444444444"
    $gitLineIndex = [array]::IndexOf($manifestLines, "    - git: nextlevelbuilder/ui-ux-pro-max-skill")
    $manifestLines[$gitLineIndex + 1] | Should -Be "      ref: 4444444444444444444444444444444444444444"
    @(Get-UnpinnedExternalReferences) | Should -Be @()
  }

  It "pin-external matches a structured git dependency using its sibling path" {
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}

    @"
name: apm-workspace
dependencies:
  apm:
    - git: https://github.com/acme/tools.git
      path: packages/example
      alias: example-tools
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: acme/tools
    host: github.com
    resolved_commit: 1234567890abcdef1234567890abcdef12345678
    virtual_path: packages/example
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    Invoke-PinExternal

    $manifestLines = @(Get-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml"))
    $manifestLines | Should -Contain "      ref: 1234567890abcdef1234567890abcdef12345678"
    @(Get-UnpinnedExternalReferences) | Should -Be @()
  }

  It "pin-external does not use a repo-only lock record for a path dependency" {
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}

    @"
name: apm-workspace
dependencies:
  apm:
    - git: https://github.com/acme/tools.git
      path: packages/example
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies:
  - repo_url: acme/tools
    host: github.com
    resolved_commit: 1234567890abcdef1234567890abcdef12345678
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    Invoke-PinExternal

    @(Get-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")) | Should -Not -Contain "      ref: 1234567890abcdef1234567890abcdef12345678"
  }

  It "pin-external leaves an already-pinned structured git dependency unchanged" {
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}

    $manifestPath = Join-Path $script:WorkspaceDir "apm.yml"
    @"
name: apm-workspace
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
    - git: nextlevelbuilder/ui-ux-pro-max-skill
      ref: 1111111111111111111111111111111111111111
      skills:
        - ui-ux-pro-max
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath $manifestPath
    @"
lockfile_version: "1"
dependencies:
  - repo_url: nextlevelbuilder/ui-ux-pro-max-skill
    host: github.com
    resolved_commit: 4444444444444444444444444444444444444444
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    $beforeContent = Get-Content -LiteralPath $manifestPath -Raw

    Invoke-PinExternal

    $afterContent = Get-Content -LiteralPath $manifestPath -Raw
    $afterContent | Should -Be $beforeContent
  }

  It "builds target-aware managed skill inventory with logical names" {
    $targets = @(
      [pscustomobject]@{ Name = "claude"; Root = (Join-Path $TestDrive "claude"); ConfigName = "CLAUDE.md" }
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive "codex"); ConfigName = "AGENTS.md" }
    )

    $inventory = @(Get-ManagedCatalogSkillInventory -SkillIds @("mattpocock:wayfinder") -Targets $targets)

    ($inventory | Where-Object Target -eq "claude").DeployedSkillName | Should -Be "wayfinder"
    ($inventory | Where-Object Target -eq "codex").DeployedSkillName | Should -Be "wayfinder"
  }

  It "smoke:catalog normalizes Codex-installed skill paths for namespaced skill ids" {
    $buildDir = Join-Path $TestDrive "catalog-build"
    $buildSkillsRoot = Join-Path $buildDir "skills"
    $bundleSkillRoot = Join-Path (Join-Path $buildSkillsRoot "mattpocock") "wayfinder"
    $bundleRequestedSkillIds = New-Object System.Collections.Generic.List[string]
    $installCalls = New-Object System.Collections.Generic.List[string]
    $previousTemp = $env:TEMP
    $env:TEMP = $TestDrive

    function global:apm {
      $installCalls.Add(($args -join ' '))

      if ($args[0] -eq "install") {
        $installedSkillRoot = Join-Path (Join-Path $PWD ".agents/skills") "wayfinder"
        New-Item -ItemType Directory -Path (Join-Path $installedSkillRoot "references") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $installedSkillRoot "SKILL.md") -Value "# wayfinder"
        Set-Content -LiteralPath (Join-Path $installedSkillRoot "references/note.md") -Value "codex"
      }

      $global:LASTEXITCODE = 0
    }

    try {
      Mock Require-Apm {}
      Mock Get-RequestedCatalogSkillIds { @("mattpocock:wayfinder") }
      Mock Get-CatalogBuildDir { $buildDir }
      Mock Invoke-BundleCatalog {
        param([string[]]$RequestedSkillIds)

        foreach ($skillId in $RequestedSkillIds) {
          $bundleRequestedSkillIds.Add($skillId)
        }

        New-Item -ItemType Directory -Path (Join-Path $bundleSkillRoot "references") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $bundleSkillRoot "SKILL.md") -Value "# wayfinder"
        Set-Content -LiteralPath (Join-Path $bundleSkillRoot "references/note.md") -Value "catalog"
      }

      Invoke-SmokeCatalog -RequestedSkillIds @("mattpocock:wayfinder")

      $bundleRequestedSkillIds | Should -Be @("mattpocock:wayfinder")
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
      [pscustomobject]@{ SourceKind = "personal"; SourceSkillId = "mattpocock:wayfinder"; SourcePath = (Join-Path (Join-Path (Join-Path $TestDrive "source") "personal") "wayfinder") }
      [pscustomobject]@{ SourceKind = "external"; SourceSkillId = "gh-address-comments"; SourcePath = (Join-Path (Join-Path (Join-Path $TestDrive "source") "external") "gh-address-comments") }
    )

    New-Item -ItemType Directory -Path (Join-Path $skillRecords[0].SourcePath "references") -Force | Out-Null
    New-Item -ItemType Directory -Path $skillRecords[1].SourcePath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillRecords[0].SourcePath "SKILL.md") -Value "# wayfinder"
    Set-Content -LiteralPath (Join-Path (Join-Path $skillRecords[0].SourcePath "references") "note.md") -Value "personal"
    Set-Content -LiteralPath (Join-Path $skillRecords[1].SourcePath "SKILL.md") -Value "# gh-address-comments"

    $plan = @(Stage-TargetSkillRecords -StageRoot $stageRoot -SkillRecords $skillRecords -Targets $targets)

    $plan.Count | Should -Be 4
    ($plan | Where-Object { $_.Target -eq "claude" -and $_.SourceSkillId -eq "mattpocock:wayfinder" }).DeployedSkillName | Should -Be "wayfinder"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "mattpocock:wayfinder" }).DeployedSkillName | Should -Be "wayfinder"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "gh-address-comments" }).DeployedSkillName | Should -Be "gh-address-comments"
    $claudeSkillsRoot = Join-Path (Join-Path $stageRoot "claude") "skills"
    $codexSkillsRoot = Join-Path (Join-Path $stageRoot "codex") "skills"

    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[0].SourcePath -ActualRoot (Join-Path $claudeSkillsRoot "wayfinder") | Should -Be $true
    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[0].SourcePath -ActualRoot (Join-Path $codexSkillsRoot "wayfinder") | Should -Be $true
    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[1].SourcePath -ActualRoot (Join-Path $claudeSkillsRoot "gh-address-comments") | Should -Be $true
    Test-DirectoryTreeEqual -ExpectedRoot $skillRecords[1].SourcePath -ActualRoot (Join-Path $codexSkillsRoot "gh-address-comments") | Should -Be $true
  }

  It "keeps source kind in the combined deployment plan while normalizing codex skills" {
    $targets = @(
      [pscustomobject]@{ Name = "claude"; Root = (Join-Path $TestDrive "claude"); SkillsRoot = (Join-Path $TestDrive "claude"); ConfigName = "CLAUDE.md" }
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive "codex"); SkillsRoot = (Join-Path $TestDrive ".agents"); ConfigName = "AGENTS.md" }
    )
    $skillRecords = @(
      [pscustomobject]@{ SourceKind = "personal"; SourceSkillId = "mattpocock:wayfinder"; SourcePath = (Join-Path (Join-Path (Join-Path $TestDrive "source") "personal") "wayfinder") }
      [pscustomobject]@{ SourceKind = "external"; SourceSkillId = "gh-address-comments"; SourcePath = (Join-Path (Join-Path (Join-Path $TestDrive "source") "external") "gh-address-comments") }
    )

    $plan = @(Build-DeploymentPlanEntries -SkillRecords $skillRecords -Targets $targets)

    $plan.Count | Should -Be 4
    ($plan | Where-Object { $_.Target -eq "claude" -and $_.SourceSkillId -eq "mattpocock:wayfinder" }).SourceKind | Should -Be "personal"
    ($plan | Where-Object { $_.Target -eq "claude" -and $_.SourceSkillId -eq "mattpocock:wayfinder" }).DeployedSkillName | Should -Be "wayfinder"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "mattpocock:wayfinder" }).SourceKind | Should -Be "personal"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "mattpocock:wayfinder" }).DeployedSkillName | Should -Be "wayfinder"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "gh-address-comments" }).SourceKind | Should -Be "external"
    ($plan | Where-Object { $_.Target -eq "codex" -and $_.SourceSkillId -eq "gh-address-comments" }).DeployedSkillName | Should -Be "gh-address-comments"
  }

  It "replaces codex staged skills into ~/.agents/skills and removes legacy ~/.codex/skills" {
    $targets = @(
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive ".codex"); SkillsRoot = (Join-Path $TestDrive ".agents"); ConfigName = "AGENTS.md" }
    )
    $stageRoot = Join-Path $TestDrive "stage"
    $codexStageSkill = Join-Path (Join-Path (Join-Path $stageRoot "codex") "skills") "brainstorming"
    $legacyCodexSkill = Join-Path $TestDrive ".codex/skills/brainstorming"

    New-Item -ItemType Directory -Path $codexStageSkill -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $codexStageSkill "SKILL.md") -Value "# staged"
    New-Item -ItemType Directory -Path $legacyCodexSkill -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $legacyCodexSkill "SKILL.md") -Value "# legacy"

    Replace-SkillTargetsFromStage -StageRoot $stageRoot -Targets $targets

    Test-Path (Join-Path $TestDrive ".agents/skills/brainstorming/SKILL.md") | Should -Be $true
    Test-Path (Join-Path $TestDrive ".codex/skills") | Should -Be $false
  }

  It "quick-syncs requested local managed skills into the codex target only" {
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock New-TemporaryDirectory { Join-Path $TestDrive "apm-sync-local" }
    Mock Get-RequestedLocalSkillIds { @("mattpocock:wayfinder") }
    Mock Get-LocalSkillContentDir { Join-Path $TestDrive "catalog/skills/mattpocock/wayfinder" }
    Mock Get-LocalCodexSyncTarget {
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive ".codex"); SkillsRoot = (Join-Path $TestDrive ".agents"); ConfigName = "AGENTS.md" }
    }
    # Invoke-AgmsgStateSave/Restore(OrThrow) shell out to agmsg-state.ps1
    # against the real $HOME by design (see its own subprocess-based test
    # suite); mocked here so this unit test doesn't touch this machine's real
    # agmsg roster.
    Mock Invoke-AgmsgStateSave {}
    Mock Invoke-AgmsgStateRestore {}
    Mock Invoke-AgmsgStateRestoreOrThrow {}

    $sourcePath = Join-Path $TestDrive "catalog/skills/mattpocock/wayfinder"
    New-Item -ItemType Directory -Path (Join-Path $sourcePath "references") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourcePath "SKILL.md") -Value "# wayfinder"
    Set-Content -LiteralPath (Join-Path $sourcePath "references/note.md") -Value "local"
    New-Item -ItemType Directory -Path (Join-Path $TestDrive ".codex/skills/wayfinder") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $TestDrive ".codex/skills/wayfinder/SKILL.md") -Value "# legacy"
    New-Item -ItemType Directory -Path (Join-Path $TestDrive ".agents/skills/existing-skill") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $TestDrive ".agents/skills/existing-skill/SKILL.md") -Value "# existing"
    New-Item -ItemType Directory -Path (Join-Path $TestDrive ".agents/skills/wayfinder") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $TestDrive ".agents/skills/wayfinder/old.md") -Value "old"

    Invoke-SyncLocalSkills -RequestedSkillIds @("mattpocock:wayfinder")

    Test-Path (Join-Path $TestDrive ".agents/skills/wayfinder/SKILL.md") | Should -Be $true
    ((Get-Content -LiteralPath (Join-Path $TestDrive ".agents/skills/wayfinder/SKILL.md") -Raw) -replace '\r?\n$', '') | Should -Be "# wayfinder"
    ((Get-Content -LiteralPath (Join-Path $TestDrive ".agents/skills/wayfinder/references/note.md") -Raw) -replace '\r?\n$', '') | Should -Be "local"
    Test-Path (Join-Path $TestDrive ".agents/skills/existing-skill/SKILL.md") | Should -Be $true
    Test-Path (Join-Path $TestDrive ".agents/skills/wayfinder/old.md") | Should -Be $false
    Test-Path (Join-Path $TestDrive ".codex/skills/wayfinder/SKILL.md") | Should -Be $true
  }

  It "quick-sync removes a stale file that the source no longer has" {
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock New-TemporaryDirectory { Join-Path $TestDrive "apm-sync-local-stale" }
    Mock Get-RequestedLocalSkillIds { @("mattpocock:wayfinder") }
    Mock Get-LocalSkillContentDir { Join-Path $TestDrive "stale-quick-sync/catalog/skills/mattpocock/wayfinder" }
    Mock Get-LocalCodexSyncTarget {
      [pscustomobject]@{ Name = "codex"; Root = (Join-Path $TestDrive "stale-quick-sync/.codex"); SkillsRoot = (Join-Path $TestDrive "stale-quick-sync/.agents"); ConfigName = "AGENTS.md" }
    }
    Mock Invoke-AgmsgStateSave {}
    Mock Invoke-AgmsgStateRestore {}
    Mock Invoke-AgmsgStateRestoreOrThrow {}

    $sourcePath = Join-Path $TestDrive "stale-quick-sync/catalog/skills/mattpocock/wayfinder"
    New-Item -ItemType Directory -Path $sourcePath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sourcePath "SKILL.md") -Value "# wayfinder"

    $destinationSkillPath = Join-Path $TestDrive "stale-quick-sync/.agents/skills/wayfinder"
    New-Item -ItemType Directory -Path $destinationSkillPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $destinationSkillPath "old-reference.md") -Value "old"

    Invoke-SyncLocalSkills -RequestedSkillIds @("mattpocock:wayfinder")

    Test-Path (Join-Path $destinationSkillPath "SKILL.md") | Should -Be $true
    Test-Path (Join-Path $destinationSkillPath "old-reference.md") | Should -Be $false
  }

  It "fails validation when a Codex skill target tree is nested under another skills root" {
    Mock Get-CodexSkillTargetRoot { Join-Path $TestDrive "nested/.agents/skills" }

    $nestedSkill = Join-Path $TestDrive "nested/.agents/skills/outer/skills/inner"
    New-Item -ItemType Directory -Path $nestedSkill -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $nestedSkill "SKILL.md") -Value "# inner"

    { Test-CodexSkillTargetTree } | Should -Throw "*Nested Codex skill files found*"
  }

  It "fails validation when a Codex skill target tree is nested under a .apm skills root" {
    Mock Get-CodexSkillTargetRoot { Join-Path $TestDrive "apm-nested/.agents/skills" }

    $nestedSkill = Join-Path $TestDrive "apm-nested/.agents/skills/outer/.apm/skills/inner"
    New-Item -ItemType Directory -Path $nestedSkill -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $nestedSkill "SKILL.md") -Value "# inner"

    { Test-CodexSkillTargetTree } | Should -Throw "*Nested Codex skill files found*"
  }

  It "passes validation for a flat Codex skill target tree" {
    Mock Get-CodexSkillTargetRoot { Join-Path $TestDrive "flat/.agents/skills" }

    $flatSkill = Join-Path $TestDrive "flat/.agents/skills/sample-skill"
    New-Item -ItemType Directory -Path $flatSkill -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $flatSkill "SKILL.md") -Value "# sample"

    { Test-CodexSkillTargetTree } | Should -Not -Throw
  }

  It "passes validation when the Codex skill target root does not exist yet" {
    Mock Get-CodexSkillTargetRoot { Join-Path $TestDrive "does-not-exist/.agents/skills" }

    { Test-CodexSkillTargetTree } | Should -Not -Throw
  }

  It "does not let a nested Codex skill target make Invoke-Validate fail" {
    Mock Require-Apm {}
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Invoke-WorkspaceCommand {}
    Mock Test-ManifestShaPinsLocked {}
    Mock Get-CodexSkillTargetRoot { Join-Path $TestDrive "validate-nested/.agents/skills" }

    $nestedSkill = Join-Path $TestDrive "validate-nested/.agents/skills/outer/skills/inner"
    New-Item -ItemType Directory -Path $nestedSkill -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $nestedSkill "SKILL.md") -Value "# inner"

    { Invoke-Validate } | Should -Not -Throw
  }

  Context "manifest SHA pins versus apm.lock.yaml" {
    BeforeAll {
      $script:pinHint = "apm.yml SHA pins differ from apm.lock.yaml; run 'mise run deploy:pins' to re-resolve them before deploying."
      $script:pinLock = @"
lockfile_version: '2'
dependencies:
- repo_url: owner/str
  resolved_commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  virtual_path: skills/str
- repo_url: k16/obj
  resolved_commit: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
- repo_url: owner/multi
  resolved_commit: 9999999999999999999999999999999999999999
"@

      function Set-PinManifest {
        param([string]$Body)
        "name: ws`ndependencies:`n  apm:`n$Body" | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
      }
    }

    BeforeEach {
      $script:pinLock | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")
    }

    It "passes when every SHA pin, string or object form, is in the lock" {
      Set-PinManifest -Body @"
    - owner/str/skills/str#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v1.0.0
    - git: https://gist.github.com/k16/obj.git
      ref: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb # v1.2.3
"@
      { Test-ManifestShaPinsLocked } | Should -Not -Throw
    }

    It "fails naming a bumped string pin and prints the deploy:pins hint" {
      Set-PinManifest -Body "    - owner/str/skills/str#cccccccccccccccccccccccccccccccccccccccc"
      { Test-ManifestShaPinsLocked } | Should -Throw "*$($script:pinHint)*"
    }

    It "fails for a bumped object ref with a trailing comment" {
      Set-PinManifest -Body @"
    - git: https://gist.github.com/k16/obj.git
      ref: dddddddddddddddddddddddddddddddddddddddd # v1.2.3
"@
      { Test-ManifestShaPinsLocked } | Should -Throw "*$($script:pinHint)*"
    }

    It "passes an object pin with a skills subset against its own lock record" {
      Set-PinManifest -Body @"
    - git: owner/multi
      ref: 9999999999999999999999999999999999999999 # v2
      skills:
        - a
        - b
"@
      { Test-ManifestShaPinsLocked } | Should -Not -Throw
    }

    It "fails a string pin whose SHA exists only on an unrelated lock record" {
      Set-PinManifest -Body "    - owner/str/skills/str#bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      { Test-ManifestShaPinsLocked } | Should -Throw "*$($script:pinHint)*"
    }

    It "fails an object pin whose SHA exists only on an unrelated lock record" {
      Set-PinManifest -Body @"
    - git: owner/multi
      ref: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
"@
      { Test-ManifestShaPinsLocked } | Should -Throw "*$($script:pinHint)*"
    }

    It "fails a pinned new dependency that has no lock record" {
      Set-PinManifest -Body "    - owner/new/skills/x#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      { Test-ManifestShaPinsLocked } | Should -Throw "*$($script:pinHint)*"
    }

    It "ignores tag and branch refs" {
      Set-PinManifest -Body @"
    - owner/other#main
    - owner/other2#v1.2.3
    - git: owner/other3
      ref: release
"@
      { Test-ManifestShaPinsLocked } | Should -Not -Throw
    }

    It "accepts a short SHA that prefixes a locked commit" {
      Set-PinManifest -Body "    - owner/str/skills/str#aaaaaaa"
      { Test-ManifestShaPinsLocked } | Should -Not -Throw
    }

    It "ignores a SHA ref that appears only under mcp" {
      "name: ws`ndependencies:`n  apm: []`n  mcp:`n    - name: x`n      ref: eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee`n    - owner/x#eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
      { Test-ManifestShaPinsLocked } | Should -Not -Throw
    }

    It "fails when apm.lock.yaml is missing while SHA pins are declared" {
      Set-PinManifest -Body "    - owner/str/skills/str#aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      Remove-Item -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")
      { Test-ManifestShaPinsLocked } | Should -Throw "*$($script:pinHint)*"
    }
  }

  It "does not throw from Invoke-Doctor when all required outputs are present" {
    $targetRoot = Join-Path $TestDrive "doctor-valid/.codex"
    $skillsRoot = Join-Path $TestDrive "doctor-valid/.agents"
    $codexSkillsRoot = Join-Path $skillsRoot "skills"
    $sourceRoot = Join-Path $TestDrive "doctor-valid-source"
    $instructionsPath = Join-Path $sourceRoot "AGENTS.md"
    $agentsSource = Join-Path $sourceRoot "agents"
    $commandsSource = Join-Path $sourceRoot "commands"
    $rulesSource = Join-Path $sourceRoot "rules"

    New-Item -ItemType Directory -Path $targetRoot, $codexSkillsRoot, (Join-Path $targetRoot "agents"), (Join-Path $targetRoot "commands"), (Join-Path $targetRoot "rules"), $agentsSource, $commandsSource, $rulesSource -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $targetRoot "AGENTS.md") -Value "# instructions"
    Set-Content -LiteralPath $instructionsPath -Value "# instructions"

    Mock Require-Apm {}
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Get-CodexSkillTargetRoot { $codexSkillsRoot }
    Mock Test-AgmsgRosterLink {}
    Mock Get-TrackedCatalogInstructionsPath { $instructionsPath }
    Mock Get-TrackedCatalogAgentsRoot { $agentsSource }
    Mock Get-TrackedCatalogCommandsRoot { $commandsSource }
    Mock Get-TrackedCatalogRulesRoot { $rulesSource }
    Mock Get-ManagedCatalogRuntimeTargets {
      @([pscustomobject]@{ Name = "codex"; Root = $targetRoot; SkillsRoot = $skillsRoot; ConfigName = "AGENTS.md" })
    }
    Mock Get-ManagedCatalogSkillInventory { @() }
    Mock Get-UnpinnedExternalReferences { @() }
    Mock Write-CatalogSummary {}

    function global:apm {
      $global:LASTEXITCODE = 0
    }

    try {
      { Invoke-Doctor } | Should -Not -Throw
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }
  }

  It "reports the learning-intake inbox split into 未処理 and 保留 from Invoke-Doctor" {
    $targetRoot = Join-Path $TestDrive "doctor-inbox/.codex"
    $skillsRoot = Join-Path $TestDrive "doctor-inbox/.agents"
    $codexSkillsRoot = Join-Path $skillsRoot "skills"
    $sourceRoot = Join-Path $TestDrive "doctor-inbox-source"
    $instructionsPath = Join-Path $sourceRoot "AGENTS.md"
    $agentsSource = Join-Path $sourceRoot "agents"
    $commandsSource = Join-Path $sourceRoot "commands"
    $rulesSource = Join-Path $sourceRoot "rules"

    New-Item -ItemType Directory -Path $targetRoot, $codexSkillsRoot, (Join-Path $targetRoot "agents"), (Join-Path $targetRoot "commands"), (Join-Path $targetRoot "rules"), $agentsSource, $commandsSource, $rulesSource -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $targetRoot "AGENTS.md") -Value "# instructions"
    Set-Content -LiteralPath $instructionsPath -Value "# instructions"

    $learningIntakeDir = Join-Path $script:WorkspaceDir "tmp/learning-intake"
    $learningIntakeSubDir = Join-Path $learningIntakeDir "sub"
    New-Item -ItemType Directory -Path $learningIntakeSubDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $learningIntakeDir "20260101-0000-one.md") -Value "status: 未処理`n# report one" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $learningIntakeDir "20260101-0001-two.md") -Value "# report two, no status line" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $learningIntakeDir "20260101-0002-three.md") -Value "status: 保留`n不足: owner" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $learningIntakeDir "20260101-0003-four.md") -Value "- status: 保留" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $learningIntakeDir "20260101-0004-five.md") -Value "status: 保留（注記）" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $learningIntakeDir "20260101-0005-six.md") -Value "status: 未処理`nstatus: 保留" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $learningIntakeDir "UPPER.MD") -Value "status: 未処理" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $learningIntakeDir "note.txt") -Value "not a report" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $learningIntakeSubDir "nested.md") -Value "status: 未処理`n# nested report" -Encoding utf8

    Mock Require-Apm {}
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Get-CodexSkillTargetRoot { $codexSkillsRoot }
    Mock Test-AgmsgRosterLink {}
    Mock Get-TrackedCatalogInstructionsPath { $instructionsPath }
    Mock Get-TrackedCatalogAgentsRoot { $agentsSource }
    Mock Get-TrackedCatalogCommandsRoot { $commandsSource }
    Mock Get-TrackedCatalogRulesRoot { $rulesSource }
    Mock Get-ManagedCatalogRuntimeTargets {
      @([pscustomobject]@{ Name = "codex"; Root = $targetRoot; SkillsRoot = $skillsRoot; ConfigName = "AGENTS.md" })
    }
    Mock Get-ManagedCatalogSkillInventory { @() }
    Mock Get-UnpinnedExternalReferences { @() }
    Mock Write-CatalogSummary {}

    function global:apm {
      $global:LASTEXITCODE = 0
    }

    try {
      $output = Invoke-Doctor 6>&1 | Out-String
      $output | Should -Match "learning-intake inbox: 未処理 4 / 保留 2"
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $learningIntakeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "throws from Invoke-Doctor when the agmsg roster link is broken" {
    $targetRoot = Join-Path $TestDrive "doctor-agmsg-broken/.codex"
    $skillsRoot = Join-Path $TestDrive "doctor-agmsg-broken/.agents"
    $codexSkillsRoot = Join-Path $skillsRoot "skills"
    $sourceRoot = Join-Path $TestDrive "doctor-agmsg-broken-source"
    $instructionsPath = Join-Path $sourceRoot "AGENTS.md"
    $agentsSource = Join-Path $sourceRoot "agents"
    $commandsSource = Join-Path $sourceRoot "commands"
    $rulesSource = Join-Path $sourceRoot "rules"
    $agmsgSkillDir = Join-Path $TestDrive "doctor-agmsg-broken/.agents/skills/agmsg"
    $agmsgStateRoot = Join-Path $TestDrive "doctor-agmsg-broken/.local/state/agmsg"

    New-Item -ItemType Directory -Path $targetRoot, $codexSkillsRoot, (Join-Path $targetRoot "agents"), (Join-Path $targetRoot "commands"), (Join-Path $targetRoot "rules"), $agentsSource, $commandsSource, $rulesSource -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $targetRoot "AGENTS.md") -Value "# instructions"
    Set-Content -LiteralPath $instructionsPath -Value "# instructions"
    # A plain (non-symlink) db dir, as if it had been absorbed outside `apply`.
    New-Item -ItemType Directory -Path (Join-Path $agmsgSkillDir "db"), (Join-Path $agmsgStateRoot "teams") -Force | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $agmsgSkillDir "teams") -Target (Join-Path $agmsgStateRoot "teams") | Out-Null

    Mock Require-Apm {}
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Get-CodexSkillTargetRoot { $codexSkillsRoot }
    # Test-AgmsgRosterLink itself runs for real here (not mocked) so this
    # test proves Invoke-Doctor's try/catch -> $diagnostics.Add -> throw
    # wiring, not just the standalone check.
    Mock Get-AgmsgSkillDir { $agmsgSkillDir }
    Mock Get-AgmsgStateRoot { $agmsgStateRoot }
    Mock Get-TrackedCatalogInstructionsPath { $instructionsPath }
    Mock Get-TrackedCatalogAgentsRoot { $agentsSource }
    Mock Get-TrackedCatalogCommandsRoot { $commandsSource }
    Mock Get-TrackedCatalogRulesRoot { $rulesSource }
    Mock Get-ManagedCatalogRuntimeTargets {
      @([pscustomobject]@{ Name = "codex"; Root = $targetRoot; SkillsRoot = $skillsRoot; ConfigName = "AGENTS.md" })
    }
    Mock Get-ManagedCatalogSkillInventory { @() }
    Mock Get-UnpinnedExternalReferences { @() }
    Mock Write-CatalogSummary {}

    function global:apm {
      $global:LASTEXITCODE = 0
    }

    try {
      $exception = $null
      try {
        Invoke-Doctor
      }
      catch {
        $exception = $_.Exception
      }

      $exception | Should -Not -BeNullOrEmpty
      $exception.Message | Should -Match "agmsg roster link is a plain path, not a symlink"
      # A plain dir can hold roster updates written while the link was
      # severed; naming agmsg:state:restore here would steer straight at the
      # absorb-and-discard path that can lose them, so this case must not
      # suggest it.
      $exception.Message | Should -Not -Match "mise run agmsg:state:restore"
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }
  }

  It "throws from Invoke-Doctor when required outputs are missing or the wrong type" {
    $targetRoot = Join-Path $TestDrive "doctor-invalid/.codex"
    $skillsRoot = Join-Path $TestDrive "doctor-invalid/.agents"
    $codexSkillsRoot = Join-Path $TestDrive "doctor-invalid/.agents/skills"
    $sourceRoot = Join-Path $TestDrive "doctor-invalid-source"
    $instructionsPath = Join-Path $sourceRoot "AGENTS.md"
    $agentsSource = Join-Path $sourceRoot "agents"
    $commandsSource = Join-Path $sourceRoot "commands"
    $rulesSource = Join-Path $sourceRoot "rules"
    $configPath = Join-Path $targetRoot "AGENTS.md"
    $agentsPath = Join-Path $targetRoot "agents"
    $commandsPath = Join-Path $targetRoot "commands"
    $rulesPath = Join-Path $targetRoot "rules"
    $skillsPath = Join-Path $skillsRoot "skills"

    New-Item -ItemType Directory -Path $targetRoot, $configPath, $agentsSource, $commandsSource, $rulesSource -Force | Out-Null
    Set-Content -LiteralPath $instructionsPath -Value "# instructions"
    Set-Content -LiteralPath $agentsPath -Value "wrong type"

    Mock Require-Apm {}
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Get-CodexSkillTargetRoot { $codexSkillsRoot }
    Mock Test-AgmsgRosterLink {}
    Mock Get-TrackedCatalogInstructionsPath { $instructionsPath }
    Mock Get-TrackedCatalogAgentsRoot { $agentsSource }
    Mock Get-TrackedCatalogCommandsRoot { $commandsSource }
    Mock Get-TrackedCatalogRulesRoot { $rulesSource }
    Mock Get-ManagedCatalogRuntimeTargets {
      @([pscustomobject]@{ Name = "codex"; Root = $targetRoot; SkillsRoot = $skillsRoot; ConfigName = "AGENTS.md" })
    }
    Mock Get-ManagedCatalogSkillInventory { @() }
    Mock Get-UnpinnedExternalReferences { @() }
    Mock Write-CatalogSummary {}

    function global:apm {
      $global:LASTEXITCODE = 0
    }

    try {
      $exception = $null
      try {
        Invoke-Doctor
      }
      catch {
        $exception = $_.Exception
      }

      $exception | Should -Not -BeNullOrEmpty
      foreach ($path in @($configPath, $agentsPath, $commandsPath, $rulesPath, $skillsPath)) {
        $exception.Message | Should -Match ([regex]::Escape($path))
      }
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }
  }

  It "reports all diagnostics from multiple targets and nested Codex skills together" {
    $targetOneRoot = Join-Path $TestDrive "doctor-multiple/claude"
    $targetOneSkillsRoot = Join-Path $TestDrive "doctor-multiple/claude-skills"
    $targetTwoRoot = Join-Path $TestDrive "doctor-multiple/codex"
    $targetTwoSkillsRoot = Join-Path $TestDrive "doctor-multiple/codex-skills"
    $codexSkillsRoot = Join-Path $TestDrive "doctor-multiple/nested/.agents/skills"
    $nestedSkill = Join-Path $codexSkillsRoot "outer/skills/inner"
    $sourceRoot = Join-Path $TestDrive "doctor-multiple-source"
    $instructionsPath = Join-Path $sourceRoot "AGENTS.md"
    $agentsSource = Join-Path $sourceRoot "agents"
    $commandsSource = Join-Path $sourceRoot "commands"
    $rulesSource = Join-Path $sourceRoot "rules"
    $targetOneConfigPath = Join-Path $targetOneRoot "CLAUDE.md"
    $targetOneAgentsPath = Join-Path $targetOneRoot "agents"
    $targetOneCommandsPath = Join-Path $targetOneRoot "commands"
    $targetOneRulesPath = Join-Path $targetOneRoot "rules"
    $targetOneSkillsPath = Join-Path $targetOneSkillsRoot "skills"
    $targetTwoConfigPath = Join-Path $targetTwoRoot "AGENTS.md"
    $targetTwoAgentsPath = Join-Path $targetTwoRoot "agents"
    $targetTwoCommandsPath = Join-Path $targetTwoRoot "commands"
    $targetTwoRulesPath = Join-Path $targetTwoRoot "rules"

    New-Item -ItemType Directory -Path $targetOneRoot, $targetOneRulesPath, $targetTwoRoot, $targetTwoConfigPath, (Join-Path $targetTwoSkillsRoot "skills"), $nestedSkill, $agentsSource, $commandsSource, $rulesSource -Force | Out-Null
    Set-Content -LiteralPath $targetOneAgentsPath -Value "wrong type"
    Set-Content -LiteralPath $targetTwoCommandsPath -Value "wrong type"
    Set-Content -LiteralPath $instructionsPath -Value "# instructions"
    Set-Content -LiteralPath (Join-Path $nestedSkill "SKILL.md") -Value "# inner"

    Mock Require-Apm {}
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Get-CodexSkillTargetRoot { $codexSkillsRoot }
    Mock Test-AgmsgRosterLink {}
    Mock Get-TrackedCatalogInstructionsPath { $instructionsPath }
    Mock Get-TrackedCatalogAgentsRoot { $agentsSource }
    Mock Get-TrackedCatalogCommandsRoot { $commandsSource }
    Mock Get-TrackedCatalogRulesRoot { $rulesSource }
    Mock Get-ManagedCatalogRuntimeTargets {
      @(
        [pscustomobject]@{ Name = "claude"; Root = $targetOneRoot; SkillsRoot = $targetOneSkillsRoot; ConfigName = "CLAUDE.md" }
        [pscustomobject]@{ Name = "codex"; Root = $targetTwoRoot; SkillsRoot = $targetTwoSkillsRoot; ConfigName = "AGENTS.md" }
      )
    }
    Mock Get-ManagedCatalogSkillInventory { @() }
    Mock Get-UnpinnedExternalReferences { @() }
    Mock Write-CatalogSummary {}

    function global:apm {
      $global:LASTEXITCODE = 1
    }

    try {
      $exception = $null
      try {
        Invoke-Doctor
      }
      catch {
        $exception = $_.Exception
      }

      $exception | Should -Not -BeNullOrEmpty
      $exception.Message | Should -Match 'apm deps list -g failed\.'
      foreach ($path in @(
          $nestedSkill | ForEach-Object { Join-Path $_ "SKILL.md" }
          (Join-Path $targetOneRoot "CLAUDE.md")
          $targetOneAgentsPath
          $targetOneCommandsPath
          $targetOneSkillsPath
          $targetTwoConfigPath
          $targetTwoAgentsPath
          $targetTwoCommandsPath
          $targetTwoRulesPath
        )) {
        $exception.Message | Should -Match ([regex]::Escape($path))
      }
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }
  }

  It "does not require outputs whose source kind is absent" {
    $targetRoot = Join-Path $TestDrive "doctor-source-absent/.codex"
    $skillsRoot = Join-Path $TestDrive "doctor-source-absent/.agents"
    $codexSkillsRoot = Join-Path $skillsRoot "skills"
    $sourceRoot = Join-Path $TestDrive "doctor-source-absent-source"
    $instructionsPath = Join-Path $sourceRoot "AGENTS.md"
    $agentsSource = Join-Path $sourceRoot "agents"
    $commandsSource = Join-Path $sourceRoot "commands"
    $rulesSource = Join-Path $sourceRoot "rules"

    New-Item -ItemType Directory -Path $codexSkillsRoot -Force | Out-Null

    Mock Require-Apm {}
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Get-CodexSkillTargetRoot { $codexSkillsRoot }
    Mock Test-AgmsgRosterLink {}
    Mock Get-TrackedCatalogInstructionsPath { $instructionsPath }
    Mock Get-TrackedCatalogAgentsRoot { $agentsSource }
    Mock Get-TrackedCatalogCommandsRoot { $commandsSource }
    Mock Get-TrackedCatalogRulesRoot { $rulesSource }
    Mock Get-ManagedCatalogRuntimeTargets {
      @([pscustomobject]@{ Name = "codex"; Root = $targetRoot; SkillsRoot = $skillsRoot; ConfigName = "AGENTS.md" })
    }
    Mock Get-ManagedCatalogSkillInventory { @() }
    Mock Get-UnpinnedExternalReferences { @() }
    Mock Write-CatalogSummary {}

    function global:apm {
      $global:LASTEXITCODE = 0
    }

    try {
      { Invoke-Doctor } | Should -Not -Throw
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }
  }

  # agmsg resolves db/ and teams/ relative to $HOME/.agents/skills/agmsg,
  # which `apm apply` keeps symlinked into $XDG_STATE_HOME/agmsg (see
  # scripts/agmsg-state.ps1:34). If that link is absorbed into a plain dir
  # or dropped by anything outside apply, agmsg's own errors ("Team not
  # found", empty identities) give no hint the link is the actual cause.
  # Get-AgmsgSkillDir/Get-AgmsgStateRoot are mocked so these tests never
  # touch this machine's real $HOME roster.
  It "skips the agmsg roster link check when the agmsg skill face is not deployed" {
    $agmsgSkillDir = Join-Path $TestDrive "agmsg-roster-absent/.agents/skills/agmsg"
    Mock Get-AgmsgSkillDir { $agmsgSkillDir }

    { Test-AgmsgRosterLink } | Should -Not -Throw
  }

  It "passes when the agmsg roster link correctly points into the state root" {
    $agmsgSkillDir = Join-Path $TestDrive "agmsg-roster-ok/.agents/skills/agmsg"
    $agmsgStateRoot = Join-Path $TestDrive "agmsg-roster-ok/.local/state/agmsg"
    New-Item -ItemType Directory -Path $agmsgSkillDir, (Join-Path $agmsgStateRoot "db"), (Join-Path $agmsgStateRoot "teams") -Force | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $agmsgSkillDir "db") -Target (Join-Path $agmsgStateRoot "db") | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $agmsgSkillDir "teams") -Target (Join-Path $agmsgStateRoot "teams") | Out-Null

    Mock Get-AgmsgSkillDir { $agmsgSkillDir }
    Mock Get-AgmsgStateRoot { $agmsgStateRoot }

    { Test-AgmsgRosterLink } | Should -Not -Throw
  }

  It "fails on a plain-dir agmsg db link without naming agmsg:state:restore" {
    $agmsgSkillDir = Join-Path $TestDrive "agmsg-roster-plaindir/.agents/skills/agmsg"
    $agmsgStateRoot = Join-Path $TestDrive "agmsg-roster-plaindir/.local/state/agmsg"
    New-Item -ItemType Directory -Path (Join-Path $agmsgSkillDir "db"), (Join-Path $agmsgStateRoot "db"), (Join-Path $agmsgStateRoot "teams") -Force | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $agmsgSkillDir "teams") -Target (Join-Path $agmsgStateRoot "teams") | Out-Null

    Mock Get-AgmsgSkillDir { $agmsgSkillDir }
    Mock Get-AgmsgStateRoot { $agmsgStateRoot }

    $exception = $null
    try { Test-AgmsgRosterLink } catch { $exception = $_.Exception }

    $exception | Should -Not -BeNullOrEmpty
    $exception.Message | Should -Match "agmsg roster link is a plain path, not a symlink"
    # A plain dir can hold roster updates written while the link was
    # severed; naming agmsg:state:restore here would steer straight at the
    # absorb-and-discard path that can lose them, so this case must not
    # suggest it.
    $exception.Message | Should -Not -Match "mise run agmsg:state:restore"
  }

  It "fails and names agmsg:state:restore when the agmsg teams link is missing" {
    $agmsgSkillDir = Join-Path $TestDrive "agmsg-roster-missing/.agents/skills/agmsg"
    $agmsgStateRoot = Join-Path $TestDrive "agmsg-roster-missing/.local/state/agmsg"
    New-Item -ItemType Directory -Path $agmsgSkillDir, (Join-Path $agmsgStateRoot "db"), (Join-Path $agmsgStateRoot "teams") -Force | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $agmsgSkillDir "db") -Target (Join-Path $agmsgStateRoot "db") | Out-Null

    Mock Get-AgmsgSkillDir { $agmsgSkillDir }
    Mock Get-AgmsgStateRoot { $agmsgStateRoot }

    { Test-AgmsgRosterLink } | Should -Throw -ExpectedMessage "*agmsg roster link is missing*mise run agmsg:state:restore*"
  }

  It "fails and names agmsg:state:restore when the agmsg db link is dangling" {
    $agmsgSkillDir = Join-Path $TestDrive "agmsg-roster-dangling/.agents/skills/agmsg"
    $agmsgStateRoot = Join-Path $TestDrive "agmsg-roster-dangling/.local/state/agmsg"
    New-Item -ItemType Directory -Path $agmsgSkillDir, (Join-Path $agmsgStateRoot "teams") -Force | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $agmsgSkillDir "db") -Target (Join-Path $agmsgStateRoot "db") | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $agmsgSkillDir "teams") -Target (Join-Path $agmsgStateRoot "teams") | Out-Null

    Mock Get-AgmsgSkillDir { $agmsgSkillDir }
    Mock Get-AgmsgStateRoot { $agmsgStateRoot }

    { Test-AgmsgRosterLink } | Should -Throw -ExpectedMessage "*agmsg roster link is dangling*mise run agmsg:state:restore*"
  }

  # The next three tests cover the mixed db/teams cases the aggregate
  # recommendation exists for: `mise run agmsg:state:restore` relinks db and
  # teams together, so a per-item recommendation is wrong whenever the
  # *other* item is a plain path holding roster writes made while the link
  # was severed -- following it would run the restore anyway and let its
  # absorb-and-discard path clobber the plain path's contents.

  It "names agmsg:state:restore for neither item when db is a plain path and teams is missing" {
    $agmsgSkillDir = Join-Path $TestDrive "agmsg-roster-mixed1/.agents/skills/agmsg"
    $agmsgStateRoot = Join-Path $TestDrive "agmsg-roster-mixed1/.local/state/agmsg"
    New-Item -ItemType Directory -Path (Join-Path $agmsgSkillDir "db"), (Join-Path $agmsgStateRoot "db"), (Join-Path $agmsgStateRoot "teams") -Force | Out-Null

    Mock Get-AgmsgSkillDir { $agmsgSkillDir }
    Mock Get-AgmsgStateRoot { $agmsgStateRoot }

    $exception = $null
    try { Test-AgmsgRosterLink } catch { $exception = $_.Exception }

    $exception | Should -Not -BeNullOrEmpty
    $exception.Message | Should -Match "agmsg roster link is a plain path, not a symlink"
    $exception.Message | Should -Match "agmsg roster link is missing"
    $exception.Message | Should -Not -Match "mise run agmsg:state:restore"
  }

  It "names agmsg:state:restore for neither item when db is missing and teams is a plain path" {
    $agmsgSkillDir = Join-Path $TestDrive "agmsg-roster-mixed2/.agents/skills/agmsg"
    $agmsgStateRoot = Join-Path $TestDrive "agmsg-roster-mixed2/.local/state/agmsg"
    New-Item -ItemType Directory -Path (Join-Path $agmsgSkillDir "teams"), (Join-Path $agmsgStateRoot "db"), (Join-Path $agmsgStateRoot "teams") -Force | Out-Null

    Mock Get-AgmsgSkillDir { $agmsgSkillDir }
    Mock Get-AgmsgStateRoot { $agmsgStateRoot }

    $exception = $null
    try { Test-AgmsgRosterLink } catch { $exception = $_.Exception }

    $exception | Should -Not -BeNullOrEmpty
    $exception.Message | Should -Match "agmsg roster link is missing"
    $exception.Message | Should -Match "agmsg roster link is a plain path, not a symlink"
    $exception.Message | Should -Not -Match "mise run agmsg:state:restore"
  }

  It "names agmsg:state:restore when db and teams are both missing (no plain path)" {
    $agmsgSkillDir = Join-Path $TestDrive "agmsg-roster-mixed3/.agents/skills/agmsg"
    $agmsgStateRoot = Join-Path $TestDrive "agmsg-roster-mixed3/.local/state/agmsg"
    New-Item -ItemType Directory -Path $agmsgSkillDir, (Join-Path $agmsgStateRoot "db"), (Join-Path $agmsgStateRoot "teams") -Force | Out-Null

    Mock Get-AgmsgSkillDir { $agmsgSkillDir }
    Mock Get-AgmsgStateRoot { $agmsgStateRoot }

    { Test-AgmsgRosterLink } | Should -Throw -ExpectedMessage "*agmsg roster link is missing*agmsg roster link is missing*mise run agmsg:state:restore*"
  }

  It "syncs private skills into the Codex copy target and the Claude symlink target" {
    Mock Get-CodexSkillTargetRoot { Join-Path $TestDrive "private-sync/.agents/skills" }
    Mock Get-ClaudePrivateSkillTargetRoot { Join-Path $TestDrive "private-sync/.claude/skills" }

    $privateSkillDir = Join-Path $WorkspaceDir "private-skills/.apm/skills/sample-private-skill"
    New-Item -ItemType Directory -Path $privateSkillDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $privateSkillDir "SKILL.md") -Value "# private"

    Sync-PrivateSkillsIntoTargets

    $codexCopyPath = Join-Path $TestDrive "private-sync/.agents/skills/sample-private-skill/SKILL.md"
    Test-Path -LiteralPath $codexCopyPath | Should -Be $true

    $claudeLinkPath = Join-Path $TestDrive "private-sync/.claude/skills/sample-private-skill"
    $claudeLink = Get-Item -LiteralPath $claudeLinkPath
    $claudeLink.LinkType | Should -Be "SymbolicLink"
    $claudeLink.Target | Should -Be $privateSkillDir
  }

  It "removes a stale Claude private skill symlink once its private source is gone" {
    Mock Get-ClaudePrivateSkillTargetRoot { Join-Path $TestDrive "stale-sync/.claude/skills" }

    $privateSkillsRoot = Join-Path $WorkspaceDir "private-skills/.apm/skills"
    $goneSourceDir = Join-Path $privateSkillsRoot "gone-skill"
    $claudeSkillsRoot = Join-Path $TestDrive "stale-sync/.claude/skills"
    New-Item -ItemType Directory -Path $claudeSkillsRoot -Force | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $claudeSkillsRoot "gone-skill") -Target $goneSourceDir | Out-Null

    Remove-StaleClaudePrivateSkillSymlinks

    Test-Path -LiteralPath (Join-Path $claudeSkillsRoot "gone-skill") | Should -Be $false
  }

  It "falls back to copying a private skill when creating the Claude symlink is not permitted" {
    Mock Get-CodexSkillTargetRoot { Join-Path $TestDrive "fallback-sync/.agents/skills" }
    Mock Get-ClaudePrivateSkillTargetRoot { Join-Path $TestDrive "fallback-sync/.claude/skills" }
    Mock New-Item -ParameterFilter { $ItemType -eq "SymbolicLink" } { throw "symlink privilege not held" }
    Mock Write-WarnLine {}

    $privateSkillDir = Join-Path $WorkspaceDir "private-skills/.apm/skills/sample-private-skill"
    New-Item -ItemType Directory -Path $privateSkillDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $privateSkillDir "SKILL.md") -Value "# private"

    Sync-PrivateSkillsIntoTargets

    $claudeCopyPath = Join-Path $TestDrive "fallback-sync/.claude/skills/sample-private-skill/SKILL.md"
    Test-Path -LiteralPath $claudeCopyPath | Should -Be $true
    Assert-MockCalled Write-WarnLine -Times 1
    # This exercises the fallback branch by mocking New-Item's SymbolicLink
    # path to throw, since forcing a real symlink-permission failure isn't
    # reproducible on this host (macOS/Linux CI runs as a user that can
    # always create symlinks; only an unprivileged Windows account without
    # Developer Mode hits this naturally). Manual verification on such a
    # Windows account: run `mise run apply` and confirm the private skill
    # under ~/.claude/skills is a real copy (not a reparse point) plus a
    # "Symlink not permitted" warning on stdout.
  }

  It "keeps the bold heading runner behavior contract" {
    $boldHeadingRunner = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/format-bold-headings.sh") -Raw

    $boldHeadingRunner | Should -Match 'TARGET="\./catalog"'
    $boldHeadingRunner | Should -Match '(?s)"\$mode" = "check".*--dry-run'
  }

  It "updates the tracked catalog dependency when apm.yml already references it" {
    @"
name: apm-workspace
dependencies:
  apm:
  - jey3dayo/apm-workspace/catalog#main
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")

    Mock Invoke-WorkspaceUpdateCommand {}
    Mock Invoke-WorkspaceInstallCommand {}

    Install-TrackedCatalogDependency -Reference "jey3dayo/apm-workspace/catalog#main"

    Assert-MockCalled Invoke-WorkspaceUpdateCommand -Times 1 -Exactly -ParameterFilter {
      ($UpdateArgs -join ' ') -eq "-g --yes jey3dayo/apm-workspace/catalog"
    }
    Assert-MockCalled Invoke-WorkspaceInstallCommand -Times 0 -Exactly
  }

  It "installs the tracked catalog dependency when apm.yml has no catalog reference yet" {
    @"
name: apm-workspace
dependencies:
  apm: []
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")

    Mock Invoke-WorkspaceUpdateCommand {}
    Mock Invoke-WorkspaceInstallCommand {}

    Install-TrackedCatalogDependency -Reference "jey3dayo/apm-workspace/catalog#main"

    Assert-MockCalled Invoke-WorkspaceInstallCommand -Times 1 -Exactly -ParameterFilter {
      ($InstallArgs -join ' ') -eq "-g jey3dayo/apm-workspace/catalog#main"
    }
    Assert-MockCalled Invoke-WorkspaceUpdateCommand -Times 0 -Exactly
  }

  It "throws naming apm update failed when the update command exits non-zero" {
    try {
      function global:apm {
        $global:LASTEXITCODE = 1
        "update failed output"
      }

      { Invoke-WorkspaceUpdateCommand -UpdateArgs @("-g", "--yes", "jey3dayo/apm-workspace/catalog") } |
        Should -Throw "*apm update failed*"
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }
  }

}

Describe "Invoke-AgmsgStateRestore never-throw contract" {
  # Invoke-AgmsgStateRestore is only used from a `finally` recovering after
  # an already-failed command, so it must never propagate an exception of
  # its own -- doing so would replace the original failure with whatever
  # went wrong during recovery instead of merely reporting it. Every other
  # test in this file exercises that contract by mocking
  # Invoke-AgmsgStateRestore itself, which cannot prove the function's own
  # try/catch actually catches a terminating error raised by the child
  # `agmsg-state.ps1` process it shells out to (as opposed to just a
  # non-zero $LASTEXITCODE). This copies scripts/apm-workspace.ps1 into a
  # throwaway directory next to a stub agmsg-state.ps1 that really throws,
  # so $PSScriptRoot (fixed at the defining file's location, not
  # overridable via Mock) resolves to the stub instead of the tracked
  # scripts/agmsg-state.ps1 -- the tracked file itself is never touched.
  BeforeEach {
    $script:restoreFixtureDir = Join-Path $TestDrive "agmsg-restore-neverthrow"
    New-Item -ItemType Directory -Path $script:restoreFixtureDir -Force | Out-Null

    $realModulePath = (Resolve-Path -LiteralPath (Join-Path (Join-Path $PSScriptRoot "..") "scripts/apm-workspace.ps1")).Path
    $script:restoreFixtureModulePath = Join-Path $script:restoreFixtureDir "apm-workspace.ps1"
    Copy-Item -LiteralPath $realModulePath -Destination $script:restoreFixtureModulePath

    @'
Write-Error "agmsg-state.ps1 restore: forced failure for test" -ErrorAction Stop
'@ | Set-Content -LiteralPath (Join-Path $script:restoreFixtureDir "agmsg-state.ps1")

    $env:APM_WORKSPACE_LIB_ONLY = "1"
    . $script:restoreFixtureModulePath
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY -ErrorAction SilentlyContinue
  }

  It "does not throw when the child agmsg-state.ps1 raises a terminating error, and reports the child's failure" {
    # Assigning inside a `{ } | Should -Not -Throw` script block would not
    # observe $warnings out here (Should invokes the block in its own child
    # scope), so call and catch directly instead.
    $caughtException = $null
    $warnings = $null
    try {
      $warnings = Invoke-AgmsgStateRestore 3>&1
    }
    catch {
      $caughtException = $_.Exception
    }

    $caughtException | Should -BeNullOrEmpty
    ($warnings | Out-String) | Should -Match "agmsg-state.ps1 restore: forced failure for test"
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
    $WorkspaceDir = $script:WorkspaceDir
    $global:WorkspaceDir = $script:WorkspaceDir
    New-Item -ItemType Directory -Path $script:WorkspaceDir -Force | Out-Null
  }

  It "dedupes managed skill ids for internal cleanup" {
    Mock Get-ManagedSkillIds { @("brainstorming", "code-review", "brainstorming") }

    $cleanupSkillIds = @(Get-InternalCleanupSkillIds)

    $cleanupSkillIds | Should -Be @("brainstorming", "code-review")
  }
}
