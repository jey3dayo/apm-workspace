$ErrorActionPreference = "Stop"

# APM_WORKSPACE_LIB_ONLY must NOT be set at the top level: Pester evaluates
# every file's top level during Discovery, before any file's Run phase, so a
# top-level set leaks into other test files' subprocess `apply` runs (making
# them silent no-ops) whenever this file appears later in the invocation list.
# Every dot-source site below sets and removes it inside its own BeforeAll.
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

    function Get-MiseTasksJson {
      param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [switch]$Hidden
      )

      $arguments = @("-C", $Directory, "tasks", "--json")
      if ($Hidden) {
        $arguments += "--hidden"
      }

      $previousTrustedPaths = $env:MISE_TRUSTED_CONFIG_PATHS
      try {
        $env:MISE_TRUSTED_CONFIG_PATHS = $Directory
        $json = (& mise @arguments | Out-String)
        if ($LASTEXITCODE -ne 0) {
          throw "mise tasks --json failed for $Directory"
        }

        # Drop tasks contributed by the host's global mise config; only this
        # repository's own tasks are part of the contract under test.
        @($json | ConvertFrom-Json | Where-Object { -not $_.global })
      }
      finally {
        if ($null -eq $previousTrustedPaths) {
          Remove-Item Env:MISE_TRUSTED_CONFIG_PATHS -ErrorAction SilentlyContinue
        }
        else {
          $env:MISE_TRUSTED_CONFIG_PATHS = $previousTrustedPaths
        }
      }
    }

    function Get-MiseTask {
      param(
        [Parameter(Mandatory = $true)]
        [object[]]$Tasks,
        [Parameter(Mandatory = $true)]
        [string]$Name
      )

      $matches = @($Tasks | Where-Object { $_.name -eq $Name })
      if ($matches.Count -ne 1) {
        throw "Expected exactly one mise task named '$Name', found $($matches.Count)"
      }

      $matches[0]
    }

    function Assert-MisePublicTaskContract {
      param([object[]]$PublicTasks)

      $expectedNames = @(
        "apply",
        "apply:skills:local",
        "audit:ci:smoke",
        "check",
        "deploy",
        "doctor",
        "format",
        "format:check",
        "install:catalog",
        "prepare:catalog",
        "refresh",
        "test",
        "test:ps",
        "test:sh",
        "upgrade",
        "validate",
        "verify"
      )
      $actualNames = @($PublicTasks | ForEach-Object { $_.name })
      foreach ($expectedName in $expectedNames) {
        if ($actualNames -notcontains $expectedName) {
          throw "Expected public mise task '$expectedName'"
        }
      }
    }

    function Assert-MiseTaskVisibilityContract {
      param(
        [object[]]$PublicTasks,
        [object[]]$HiddenTasks
      )

      $publicNames = @($PublicTasks | ForEach-Object { $_.name })
      foreach ($name in @("bootstrap", "setup:mcp:host")) {
        $task = Get-MiseTask -Tasks $HiddenTasks -Name $name
        if ($task.hide -ne $true) {
          throw "Mise task '$name' must be hidden"
        }
        if ($publicNames -contains $name) {
          throw "Mise task '$name' must not be public"
        }
      }
    }

    function Assert-MiseCheckDependsContract {
      param([object[]]$Tasks)

      $task = Get-MiseTask -Tasks $Tasks -Name "check"
      $depends = @($task.depends)
      foreach ($required in @("format:check", "lint:yaml", "lint:frontmatter", "lint:catalog-leaks", "validate")) {
        if ($depends -notcontains $required) {
          throw "Mise task 'check' must depend on '$required'"
        }
      }
    }

    function Assert-MiseRunSequenceContract {
      param(
        [object[]]$Tasks,
        [string]$Name,
        [string[]]$Expected
      )

      $task = Get-MiseTask -Tasks $Tasks -Name $Name
      $actual = @($task.run) | ForEach-Object {
        if ($_ -is [string]) {
          "command:$_"
        }
        elseif ($null -ne $_.PSObject.Properties["task"]) {
          "task:$($_.task)"
        }
        else {
          throw "Mise task '$Name' has an unsupported run step"
        }
      }

      if (@($actual).Count -ne $Expected.Count) {
        throw "Mise task '$Name' run length was $(@($actual).Count), expected $($Expected.Count)"
      }
      for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ($actual[$index] -ne $Expected[$index]) {
          throw "Mise task '$Name' run step $index was '$($actual[$index])', expected '$($Expected[$index])'"
        }
      }
    }

    function Assert-MiseUpgradeContract {
      param([object[]]$Tasks)

      $task = Get-MiseTask -Tasks $Tasks -Name "upgrade"
      $run = @($task.run)
      if ($run.Count -ne 2 -or $run[0] -isnot [string] -or $run[0] -notlike "*apm update -g*" -or $run[0] -notlike "*--yes*") {
        throw "Mise task 'upgrade' must update APM with --yes before deploying"
      }
      if ($null -eq $run[1].PSObject.Properties["task"] -or $run[1].task -ne "deploy") {
        throw "Mise task 'upgrade' must run deploy second"
      }
    }

    function Assert-MiseCommandConnectionContract {
      param([object[]]$Tasks)

      $expectedCommands = @{
        "apply" = "bash ./scripts/apm-workspace.sh apply"
        "apply:skills:local" = "bash ./scripts/apm-workspace.sh apply:skills:local"
        "format:markdown:bold-headings" = "bash ./scripts/format-bold-headings.sh write"
        "format:markdown:bold-headings:check" = "bash ./scripts/format-bold-headings.sh check"
      }
      foreach ($entry in $expectedCommands.GetEnumerator()) {
        $task = Get-MiseTask -Tasks $Tasks -Name $entry.Key
        $run = @($task.run)
        if ($run.Count -ne 1 -or $run[0] -ne $entry.Value) {
          throw "Mise task '$($entry.Key)' is not connected to '$($entry.Value)'"
        }
      }
    }

    function Remove-MiseCommentLines {
      param([string]$Content)

      (($Content -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    function New-MiseTaskFixture {
      param([string]$Name)

      $fixture = Join-Path $TestDrive "mise-fixture-$Name"
      New-Item -ItemType Directory -Path $fixture -Force | Out-Null
      Copy-Item -LiteralPath (Join-Path $workspaceRoot "mise.toml") -Destination (Join-Path $fixture "mise.toml")
      Copy-Item -LiteralPath (Join-Path $workspaceRoot "mise") -Destination (Join-Path $fixture "mise") -Recurse
      $fixture
    }

    function Update-MiseTaskBlock {
      param(
        [string]$Path,
        [string]$Name,
        [scriptblock]$Transform
      )

      $content = Get-Content -LiteralPath $Path -Raw
      $header = if ($Name -match '^[a-zA-Z0-9_-]+$') {
        "\[tasks\.$([regex]::Escape($Name))\]"
      }
      else {
        '\[tasks\."' + [regex]::Escape($Name) + '"\]'
      }
      $match = [regex]::Match($content, "(?ms)^$header.*?(?=^\[|\z)")
      if (-not $match.Success) {
        throw "Could not find mise task '$Name' in $Path"
      }

      $replacement = & $Transform $match.Value
      $updated = $content.Substring(0, $match.Index) + $replacement + $content.Substring($match.Index + $match.Length)
      Set-Content -LiteralPath $Path -Value $updated -NoNewline
    }
  }

  BeforeEach {
    $script:WorkspaceDir = Join-Path $TestDrive "workspace"
    $WorkspaceDir = $script:WorkspaceDir
    $global:WorkspaceDir = $script:WorkspaceDir
    New-Item -ItemType Directory -Path $script:WorkspaceDir -Force | Out-Null
  }

  It "shows shell help wording for refresh and catalog commands" {
    $bashShell = @(
      "D:\Programs\Git\bin\bash.exe"
      "C:\Program Files\Git\bin\bash.exe"
      (Get-Command bash -ErrorAction SilentlyContinue).Path
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($bashShell)) {
      Set-ItResult -Skipped -Because "bash is not available on this host"
      return
    }

    $legacyMirrorPattern = 'transitional' + ' mirror'
    $updateHelpPattern = '(?m)^  refresh\s+Refresh the checkout and dependencies only; does not deploy$'
    $help = (& $bashShell (Join-Path $workspaceRoot "scripts/apm-workspace.sh") help | Out-String) -replace "`r`n", "`n" -replace "`r", "`n"

    $help | Should -Match $updateHelpPattern
    $help | Should -Match "validate:catalog"
    $help | Should -Match "prepare:catalog"
    $help | Should -Match "install:catalog"
    $help | Should -Not -Match "release:catalog"
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
    $help = (& $consoleShell -NoProfile -ExecutionPolicy Bypass -File $scriptPath help | Out-String) -replace "`r`n", "`n" -replace "`r", "`n"

    $help | Should -Match $updateHelpPattern
    $help | Should -Match "validate:catalog"
    $help | Should -Match "prepare:catalog"
    $help | Should -Match "install:catalog"
    $help | Should -Not -Match "release:catalog"
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
    # Invoke-AgmsgStateSave/Restore shell out to agmsg-state.ps1 against the
    # real $HOME by design (see its own subprocess-based test suite); mocked
    # here so this unit test doesn't touch this machine's real agmsg roster.
    Mock Invoke-AgmsgStateSave {}
    Mock Invoke-AgmsgStateRestore {}

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

  It "rejects local package refs before update deploys" {
    $shellScript = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/apm-workspace.sh") -Raw

    $shellScript | Should -Match '(?s)cmd_update\(\)\s*\{.*?if manifest_has_local_packages; then\s+fail "apm 0\.8\.11 cannot update \./packages/\* dependencies at user scope yet\. Refresh stopped before deps update; remove local package refs from ~/.apm/apm\.yml first\."\s+fi.*?apm deps update -g'
  }

  It "deploys managed MCP dependencies during shell apply" {
    $shellScript = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/apm-workspace.sh") -Raw
    $powerShellScript = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/apm-workspace.ps1") -Raw

    $shellScript | Should -Match '(?s)install_workspace_mcp_dependencies\(\)\s*\{\s*run_workspace_install_command -g --only mcp\s*\}'
    $shellScript | Should -Match '(?s)cmd_apply\(\)\s*\{.*?install_workspace_mcp_dependencies.*?normalize_codex_mcp_config.*?compile_codex.*?replace_skill_targets_from_stage "\$apply_stage_root".*?cleanup_legacy_workspace_skill_targets'
    $powerShellScript | Should -Match '(?s)function Invoke-Apply\s*\{.*?Install-WorkspaceMcpDependencies.*?Normalize-CodexMcpConfig.*?Invoke-CodexCompile.*?Sync-ManagedCatalogRuntimeAssets.*?Replace-SkillTargetsFromStage.*?Remove-LegacyWorkspaceSkillTargets'
  }

  It "keeps legacy workspace cleanup in full apply, not quick local sync" {
    $powerShellScript = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/apm-workspace.ps1") -Raw

    $powerShellScript | Should -Match '(?s)function Invoke-Apply\s*\{(?:(?!\r?\nfunction ).)*?Remove-LegacyWorkspaceSkillTargets'
    $powerShellScript | Should -Not -Match '(?s)function Invoke-SyncLocalSkills\s*\{(?:(?!\r?\nfunction ).)*?Remove-LegacyWorkspaceSkillTargets'
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

  It "maps codex skills to ~/.agents while keeping config under ~/.codex" {
    $targets = @(Get-ManagedCatalogRuntimeTargets)
    $codex = $targets | Where-Object Name -eq "codex"

    $codex.Root | Should -Be (Join-Path $HOME ".codex")
    $codex.SkillsRoot | Should -Be (Join-Path $HOME ".agents")
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
    # Invoke-AgmsgStateSave/Restore shell out to agmsg-state.ps1 against the
    # real $HOME by design (see its own subprocess-based test suite); mocked
    # here so this unit test doesn't touch this machine's real agmsg roster.
    Mock Invoke-AgmsgStateSave {}
    Mock Invoke-AgmsgStateRestore {}

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
    Mock Get-CodexSkillTargetRoot { Join-Path $TestDrive "validate-nested/.agents/skills" }

    $nestedSkill = Join-Path $TestDrive "validate-nested/.agents/skills/outer/skills/inner"
    New-Item -ItemType Directory -Path $nestedSkill -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $nestedSkill "SKILL.md") -Value "# inner"

    { Invoke-Validate } | Should -Not -Throw
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

  It "smoke-audits the workspace manifest via temp install" {
    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock New-TemporaryDirectory {
      $path = Join-Path $TestDrive "apm-audit-ci-smoke"
      New-Item -ItemType Directory -Path $path -Force | Out-Null
      $path
    }

    $previousWorkspaceDir = $script:WorkspaceDir
    $previousGlobalWorkspaceDir = $global:WorkspaceDir
    $workspaceDir = Join-Path $TestDrive "workspace-audit-ci-smoke"
    $script:WorkspaceDir = $workspaceDir
    $WorkspaceDir = $workspaceDir
    $global:WorkspaceDir = $workspaceDir
    New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null

    @"
name: apm-workspace
version: 1.0.0
dependencies:
  apm: []
  mcp: []
scripts: {}
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.yml")
    @"
lockfile_version: "1"
dependencies: []
"@ | Set-Content -LiteralPath (Join-Path $script:WorkspaceDir "apm.lock.yaml")

    $apmCalls = New-Object System.Collections.Generic.List[string]
    $script:installSawManifest = $false
    $script:auditSawManifest = $false

    function global:apm {
      $apmCalls.Add(($args -join ' '))

      if ($args[0] -eq "install" -and $args[1] -eq "--only" -and $args[2] -eq "apm") {
        if ((Test-Path -LiteralPath (Join-Path $PWD "apm.yml")) -and (Test-Path -LiteralPath (Join-Path $PWD "apm.lock.yaml"))) {
          $script:installSawManifest = $true
        }
      }

      if ($args[0] -eq "audit" -and $args[1] -eq "--ci") {
        if ((Test-Path -LiteralPath (Join-Path $PWD "apm.yml")) -and (Test-Path -LiteralPath (Join-Path $PWD "apm.lock.yaml"))) {
          $script:auditSawManifest = $true
        }
      }

      $global:LASTEXITCODE = 0
    }

    try {
      Invoke-AuditCiSmoke

      $apmCalls | Should -Be @("install --only apm", "audit --ci")
      $script:installSawManifest | Should -Be $true
      $script:auditSawManifest | Should -Be $true
      Test-Path (Join-Path $TestDrive "apm-audit-ci-smoke") | Should -Be $false
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
      $script:WorkspaceDir = $previousWorkspaceDir
      $global:WorkspaceDir = $previousGlobalWorkspaceDir
    }
  }

  It "publishes the expected public mise task set" {
    $publicTasks = Get-MiseTasksJson -Directory $workspaceRoot

    { Assert-MisePublicTaskContract -PublicTasks $publicTasks } | Should -Not -Throw
  }

  It "keeps recovery and host setup mise tasks hidden" {
    $publicTasks = Get-MiseTasksJson -Directory $workspaceRoot
    $hiddenTasks = Get-MiseTasksJson -Directory $workspaceRoot -Hidden

    { Assert-MiseTaskVisibilityContract -PublicTasks $publicTasks -HiddenTasks $hiddenTasks } | Should -Not -Throw
  }

  It "keeps the check task's complete inspection set" {
    $hiddenTasks = Get-MiseTasksJson -Directory $workspaceRoot -Hidden

    { Assert-MiseCheckDependsContract -Tasks $hiddenTasks } | Should -Not -Throw
  }

  It "keeps deploy verify and refresh-deploy workflow order" {
    $hiddenTasks = Get-MiseTasksJson -Directory $workspaceRoot -Hidden
    $workflowContracts = @{
      "deploy" = @("task:check", "task:apply", "task:doctor")
      "verify" = @("task:check", "task:test", "task:smoke:catalog")
      "refresh:deploy" = @("task:refresh", "task:deploy")
    }

    foreach ($entry in $workflowContracts.GetEnumerator()) {
      { Assert-MiseRunSequenceContract -Tasks $hiddenTasks -Name $entry.Key -Expected $entry.Value } | Should -Not -Throw
    }
  }

  It "keeps upgrade non-interactive and deploy-bound" {
    $hiddenTasks = Get-MiseTasksJson -Directory $workspaceRoot -Hidden

    { Assert-MiseUpgradeContract -Tasks $hiddenTasks } | Should -Not -Throw
  }

  It "connects mise tasks to the expected workspace commands" {
    $hiddenTasks = Get-MiseTasksJson -Directory $workspaceRoot -Hidden

    { Assert-MiseCommandConnectionContract -Tasks $hiddenTasks } | Should -Not -Throw
  }

  It "keeps the bold heading runner behavior contract" {
    $boldHeadingRunner = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/format-bold-headings.sh") -Raw

    $boldHeadingRunner | Should -Match 'TARGET="\./catalog"'
    $boldHeadingRunner | Should -Match '(?s)"\$mode" = "check".*--dry-run'
  }

  It "detects a visible bootstrap task in a negative mise fixture" {
    $fixture = New-MiseTaskFixture -Name "bootstrap-visible"
    try {
      Update-MiseTaskBlock -Path (Join-Path $fixture "mise.toml") -Name "bootstrap" -Transform {
        param($block)
        $block -replace '(?m)^\s*hide = true\r?\n', ''
      }
      $publicTasks = Get-MiseTasksJson -Directory $fixture
      $hiddenTasks = Get-MiseTasksJson -Directory $fixture -Hidden

      { Assert-MiseTaskVisibilityContract -PublicTasks $publicTasks -HiddenTasks $hiddenTasks } | Should -Throw
    }
    finally {
      Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "detects a missing check inspection dependency in a negative mise fixture" {
    $fixture = New-MiseTaskFixture -Name "check-missing-frontmatter"
    try {
      Update-MiseTaskBlock -Path (Join-Path $fixture "mise.toml") -Name "check" -Transform {
        param($block)
        $block -replace '(?m)^\s*"lint:frontmatter",\r?\n', ''
      }
      $hiddenTasks = Get-MiseTasksJson -Directory $fixture -Hidden

      { Assert-MiseCheckDependsContract -Tasks $hiddenTasks } | Should -Throw
    }
    finally {
      Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "detects reordered deploy steps in a negative mise fixture" {
    $fixture = New-MiseTaskFixture -Name "deploy-reordered"
    try {
      Update-MiseTaskBlock -Path (Join-Path $fixture "mise.toml") -Name "deploy" -Transform {
        param($block)
        $block -replace '\{ task = "check" \}, \{ task = "apply" \}, \{ task = "doctor" \}', '{ task = "check" }, { task = "doctor" }, { task = "apply" }'
      }
      $hiddenTasks = Get-MiseTasksJson -Directory $fixture -Hidden

      { Assert-MiseRunSequenceContract -Tasks $hiddenTasks -Name "deploy" -Expected @("task:check", "task:apply", "task:doctor") } | Should -Throw
    }
    finally {
      Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "detects an interactive upgrade command in a negative mise fixture" {
    $fixture = New-MiseTaskFixture -Name "upgrade-interactive"
    try {
      Update-MiseTaskBlock -Path (Join-Path $fixture "mise.toml") -Name "upgrade" -Transform {
        param($block)
        $block -replace 'apm update -g --yes', 'apm update -g'
      }
      $hiddenTasks = Get-MiseTasksJson -Directory $fixture -Hidden

      { Assert-MiseUpgradeContract -Tasks $hiddenTasks } | Should -Throw
    }
    finally {
      Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
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
    )

    foreach ($file in $files) {
      $content = Get-Content -LiteralPath $file -Raw
      $content | Should -Not -Match $removedAgentsSrcPattern
      $content | Should -Not -Match $legacyMirrorPattern
    }

  }

  It "documents public external skill workflow references in README" {
    $readme = Get-Content -LiteralPath (Join-Path $workspaceRoot "README.md") -Raw

    $readme | Should -Match 'mise run upgrade'
    $readme | Should -Match 'mise run check'
    $readme | Should -Match 'mise run verify'
    $readme | Should -Match 'mise run prepare:catalog'
    $readme | Should -Match 'docs/skill-inventory\.md'
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
