$ErrorActionPreference = "Stop"

# APM_WORKSPACE_LIB_ONLY must NOT be set at the top level: Pester evaluates
# every file's top level during Discovery, before any file's Run phase, so a
# top-level set leaks into other test files' subprocess runs (making
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

  It "reports no .apm claim when catalog/.apm is absent or holds only skills and agents" {
    Get-CatalogApmDirClaimMessage | Should -BeNullOrEmpty

    $skillDir = Join-Path (Join-Path (Join-Path (Get-TrackedCatalogDir) ".apm") "skills") "demo"
    $agentsDir = Join-Path (Join-Path (Get-TrackedCatalogDir) ".apm") "agents"
    New-Item -ItemType Directory -Path $skillDir, $agentsDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillDir "SKILL.md") -Value "# demo"
    Set-Content -LiteralPath (Join-Path $agentsDir "sample.agent.md") -Value "agent"

    Get-CatalogApmDirClaimMessage | Should -BeNullOrEmpty
  }

  It "claims a file under .apm/skills that no skill encloses" {
    Remove-Item -LiteralPath (Join-Path (Get-TrackedCatalogDir) ".apm") -Recurse -Force -ErrorAction SilentlyContinue
    $skillsDir = Join-Path (Join-Path (Get-TrackedCatalogDir) ".apm") "skills"
    New-Item -ItemType Directory -Path (Join-Path $skillsDir "draft"), (Join-Path $skillsDir "real") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillsDir "real/SKILL.md") -Value "skill"
    Set-Content -LiteralPath (Join-Path $skillsDir "draft/notes.md") -Value "draft notes"

    Get-CatalogApmDirClaimMessage | Should -BeLike "catalog/.apm holds skills/draft/notes.md, which the catalog build does not carry*"
  }

  It "claims a file directly under .apm/skills and one in a namespace directory that is not a skill" {
    Remove-Item -LiteralPath (Join-Path (Get-TrackedCatalogDir) ".apm") -Recurse -Force -ErrorAction SilentlyContinue
    $skillsDir = Join-Path (Join-Path (Get-TrackedCatalogDir) ".apm") "skills"
    New-Item -ItemType Directory -Path (Join-Path $skillsDir "ns/inner") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillsDir "ns/inner/SKILL.md") -Value "skill"
    Set-Content -LiteralPath (Join-Path $skillsDir "ns/notes.md") -Value "loose"
    Set-Content -LiteralPath (Join-Path $skillsDir "README.md") -Value "readme"

    $claimed = @(Get-CatalogApmDirClaimedPaths -ApmDir (Join-Path (Get-TrackedCatalogDir) ".apm"))
    $claimed.Count | Should -Be 2
    $claimed | Should -Contain "skills/README.md"
    $claimed | Should -Contain "skills/ns/notes.md"
  }

  It "allows nested skill files and files inside a skill's subdirectories" {
    Remove-Item -LiteralPath (Join-Path (Get-TrackedCatalogDir) ".apm") -Recurse -Force -ErrorAction SilentlyContinue
    $apmDir = Join-Path (Get-TrackedCatalogDir) ".apm"
    New-Item -ItemType Directory -Path (Join-Path $apmDir "skills/one/references"), (Join-Path $apmDir "skills/ns/inner/scripts"), (Join-Path $apmDir "agents") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $apmDir "skills/one/SKILL.md") -Value "skill"
    Set-Content -LiteralPath (Join-Path $apmDir "skills/one/references/guide.md") -Value "ref"
    Set-Content -LiteralPath (Join-Path $apmDir "skills/ns/inner/SKILL.md") -Value "skill"
    Set-Content -LiteralPath (Join-Path $apmDir "skills/ns/inner/scripts/run.sh") -Value "run"
    Set-Content -LiteralPath (Join-Path $apmDir "agents/sample.agent.md") -Value "agent"

    Get-CatalogApmDirClaimMessage | Should -BeNullOrEmpty
  }

  It "claims a symlink inside a skill directory" {
    Remove-Item -LiteralPath (Join-Path (Get-TrackedCatalogDir) ".apm") -Recurse -Force -ErrorAction SilentlyContinue
    $skillDir = Join-Path (Join-Path (Get-TrackedCatalogDir) ".apm") "skills/one"
    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillDir "SKILL.md") -Value "skill"
    $target = Join-Path $TestDrive "outside-reference.md"
    Set-Content -LiteralPath $target -Value "outside"
    New-Item -ItemType SymbolicLink -Path (Join-Path $skillDir "link.md") -Target $target | Out-Null

    Get-CatalogApmDirClaimMessage | Should -BeLike "catalog/.apm holds skills/one/link.md, but the catalog package carries only*"
  }

  It "claims an agent file that is not <name>.agent.md and an agent nested below .apm/agents" {
    Remove-Item -LiteralPath (Join-Path (Get-TrackedCatalogDir) ".apm") -Recurse -Force -ErrorAction SilentlyContinue
    $agentsDir = Join-Path (Join-Path (Get-TrackedCatalogDir) ".apm") "agents"
    New-Item -ItemType Directory -Path (Join-Path $agentsDir "team") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $agentsDir "good.agent.md") -Value "agent"
    Set-Content -LiteralPath (Join-Path $agentsDir "legacy-name.md") -Value "legacy"
    Set-Content -LiteralPath (Join-Path $agentsDir "team/helper.agent.md") -Value "nested"

    $claimed = @(Get-CatalogApmDirClaimedPaths -ApmDir (Join-Path (Get-TrackedCatalogDir) ".apm"))
    $claimed.Count | Should -Be 2
    $claimed | Should -Contain "agents/legacy-name.md"
    $claimed | Should -Contain "agents/team/helper.agent.md"
    Get-CatalogApmDirClaimMessage | Should -BeLike "*agents/<name>.agent.md*"
  }

  It "claims names that end with a newline after SKILL.md or .agent.md" -Skip:($IsWindows -eq $true) {
    Remove-Item -LiteralPath (Join-Path (Get-TrackedCatalogDir) ".apm") -Recurse -Force -ErrorAction SilentlyContinue
    $apmDir = Join-Path (Get-TrackedCatalogDir) ".apm"
    New-Item -ItemType Directory -Path (Join-Path $apmDir "skills/draft"), (Join-Path $apmDir "agents") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $apmDir "skills/draft/SKILL.md`n") -Value "decoy"
    Set-Content -LiteralPath (Join-Path $apmDir "skills/draft/notes.md") -Value "draft notes"
    Set-Content -LiteralPath (Join-Path $apmDir "agents/foo.agent.md`n") -Value "decoy agent"

    $claimed = @(Get-CatalogApmDirClaimedPaths -ApmDir $apmDir)
    $claimed | Should -Contain "skills/draft/notes.md"
    $claimed | Should -Contain "agents/foo.agent.md`n"
  }

  It "seeds the catalog build with skills and agents under .apm and no top-level skills or agents directory" {
    $trackedDir = Join-Path $TestDrive "tracked-catalog"
    $buildDir = Join-Path $TestDrive "build-catalog"
    foreach ($subdir in @(".apm/agents", "commands", "rules", ".apm/skills/demo", ".apm/instructions")) {
      New-Item -ItemType Directory -Path (Join-Path $trackedDir $subdir) -Force | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $trackedDir ".apm/skills/demo/SKILL.md") -Value "# demo"
    Set-Content -LiteralPath (Join-Path $trackedDir ".apm/agents/sample.agent.md") -Value "agent"
    Set-Content -LiteralPath (Join-Path $trackedDir "apm.yml") -Value "name: catalog"
    Set-Content -LiteralPath (Join-Path $trackedDir "README.md") -Value "# catalog"
    Set-Content -LiteralPath (Join-Path $trackedDir ".apm/instructions/ai-collaboration.instructions.md") -Value "---`ndescription: guide`n---`n`n# instructions"

    Mock Ensure-WorkspaceRepo {}
    Mock Ensure-WorkspaceScaffold {}
    Mock Ensure-WorkspaceMiseFile {}
    Mock Get-TrackedCatalogDir { $trackedDir }
    Mock Get-CatalogBuildDir { $buildDir }

    Invoke-SeedCatalogBuild

    Test-Path -LiteralPath (Join-Path $buildDir ".apm/skills/demo/SKILL.md") | Should -Be $true
    Test-Path -LiteralPath (Join-Path $buildDir ".apm/agents/sample.agent.md") | Should -Be $true
    Test-Path -LiteralPath (Join-Path $buildDir "skills") | Should -Be $false
    Test-Path -LiteralPath (Join-Path $buildDir "agents") | Should -Be $false
  }

  It "Test-CatalogApmDirRegularFile accepts only a regular file" {
    $file = Join-Path $TestDrive "regular-file"
    New-Item -ItemType File -Path $file | Out-Null
    $directory = Join-Path $TestDrive "regular-directory"
    New-Item -ItemType Directory -Path $directory | Out-Null
    $link = Join-Path $TestDrive "file-link"
    New-Item -ItemType SymbolicLink -Path $link -Target $file | Out-Null

    Test-CatalogApmDirRegularFile -Item (Get-Item -LiteralPath $file -Force) | Should -Be $true
    Test-CatalogApmDirRegularFile -Item (Get-Item -LiteralPath $directory -Force) | Should -Be $false
    Test-CatalogApmDirRegularFile -Item (Get-Item -LiteralPath $link -Force) | Should -Be $false
  }

  It "Test-CatalogApmDirRegularFile rejects a FIFO" -Skip:($IsWindows -eq $true -or -not (Get-Command mkfifo -ErrorAction SilentlyContinue)) {
    $fifo = Join-Path $TestDrive "fifo"
    & mkfifo $fifo

    Test-CatalogApmDirRegularFile -Item (Get-Item -LiteralPath $fifo -Force) | Should -Be $false
  }

  It "Test-CatalogApmDirRegularFile falls back to test -f when the item has no UnixStat" -Skip:($IsWindows -eq $true) {
    $file = Join-Path $TestDrive "fallback-file"
    New-Item -ItemType File -Path $file | Out-Null

    Test-CatalogApmDirRegularFile -Item ([pscustomobject]@{ FullName = $file; PSIsContainer = $false; LinkType = $null }) | Should -Be $true
  }

  It "Test-CatalogApmDirRegularFile rejects a FIFO through the test -f fallback" -Skip:($IsWindows -eq $true -or -not (Get-Command mkfifo -ErrorAction SilentlyContinue)) {
    $fifo = Join-Path $TestDrive "fallback-fifo"
    & mkfifo $fifo

    Test-CatalogApmDirRegularFile -Item ([pscustomobject]@{ FullName = $fifo; PSIsContainer = $false; LinkType = $null }) | Should -Be $false
  }

  It "Test-CatalogApmDirRegularFile fails closed when test cannot run" -Skip:($IsWindows -eq $true) {
    $file = Join-Path $TestDrive "fail-closed-file"
    New-Item -ItemType File -Path $file | Out-Null
    $savedPath = $env:PATH
    try {
      $env:PATH = Join-Path $TestDrive "no-such-bin"
      Test-CatalogApmDirRegularFile -Item ([pscustomobject]@{ FullName = $file; PSIsContainer = $false; LinkType = $null }) | Should -Be $false
    }
    finally {
      $env:PATH = $savedPath
    }
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
    $agentsRoot = Join-Path (Join-Path $catalogRoot ".apm") "agents"
    $commandsRoot = Join-Path $catalogRoot "commands"
    $rulesRoot = Join-Path $catalogRoot "rules"
    New-Item -ItemType Directory -Path $agentsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $commandsRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $rulesRoot "tools") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $catalogRoot ".apm/instructions") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $catalogRoot ".apm/instructions/ai-collaboration.instructions.md") -Value "---`ndescription: guide`n---`n`n# shared guidance"
    Set-Content -LiteralPath (Join-Path $agentsRoot "code-reviewer.agent.md") -Value "# agent"
    Set-Content -LiteralPath (Join-Path $commandsRoot "review.md") -Value "# review"
    Set-Content -LiteralPath (Join-Path $commandsRoot "setup.md") -Value "# setup"
    Set-Content -LiteralPath (Join-Path $rulesRoot "claude-md-design.md") -Value "# rule"
    Set-Content -LiteralPath (Join-Path $rulesRoot "tools\example.md") -Value "# example"

    Mock Get-TrackedCatalogDir { $catalogRoot }
    @(Get-TrackedCatalogAgentRelativePaths) | Should -Be @("code-reviewer.agent.md")
    @(Get-TrackedCatalogCommandRelativePaths) | Should -Be @("review.md", "setup.md")
    @(Get-TrackedCatalogRuleRelativePaths) | Should -Be @("claude-md-design.md", "tools/example.md")
    Test-Path -LiteralPath (Get-TrackedCatalogInstructionsPath) | Should -Be $true
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

    function Get-DoctorIntakeOutput {
      (Invoke-DoctorIntake 3>&1 6>&1 | ForEach-Object { $_.ToString() }) -join "`n"
    }

    function New-IntakePendingReports {
      param([string]$InboxDir, [int]$Count)

      New-Item -ItemType Directory -Path $InboxDir -Force | Out-Null
      foreach ($index in 1..$Count) {
        Set-Content -LiteralPath (Join-Path $InboxDir ("20261101-{0:D4}-report.md" -f $index)) -Value "status: 未処理" -Encoding utf8
      }
    }
  }

  BeforeEach {
    $script:WorkspaceDir = Join-Path $TestDrive "workspace"
    $WorkspaceDir = $script:WorkspaceDir
    $global:WorkspaceDir = $script:WorkspaceDir
    New-Item -ItemType Directory -Path $script:WorkspaceDir -Force | Out-Null
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

  It "hands claude and cursor agents to APM and opts codex and opencode out" {
    $targets = @(Get-ManagedCatalogRuntimeTargets)

    ($targets | Where-Object Name -eq "claude").AgentsFace | Should -Be "apm"
    ($targets | Where-Object Name -eq "cursor").AgentsFace | Should -Be "apm"
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
    $buildSkillsRoot = Join-Path (Join-Path $buildDir ".apm") "skills"
    $bundleSkillRoot = Join-Path (Join-Path $buildSkillsRoot "mattpocock") "wayfinder"
    $bundleRequestedSkillIds = New-Object System.Collections.Generic.List[string]
    $installCalls = New-Object System.Collections.Generic.List[string]
    $installHomes = New-Object System.Collections.Generic.List[string]
    $previousTemp = $env:TEMP
    $previousHome = $env:HOME
    $previousUserProfile = $env:USERPROFILE
    $env:TEMP = $TestDrive

    function global:apm {
      $installCalls.Add(($args -join ' '))

      if ($args[0] -eq "install") {
        $installHomes.Add(("{0}|{1}" -f $env:HOME, $env:USERPROFILE))
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
      $installCalls | Should -Contain ("install {0} --target agent-skills" -f $buildDir)
      $installHomes.Count | Should -Be 1
      $installHome, $installUserProfile = $installHomes[0] -split "\|"
      $installHome | Should -BeLike "*apm-catalog-smoke-*-home"
      $installUserProfile | Should -Be $installHome
      $env:HOME | Should -Be $previousHome
      $env:USERPROFILE | Should -Be $previousUserProfile
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
      $env:TEMP = $previousTemp
    }
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
      $script:pinHint = "apm.yml SHA pins differ from apm.lock.yaml; update the pinned entries of apm.lock.yaml to the same commits (no task re-resolves the root lock on a native HOME)."
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

    It "fails naming a bumped string pin and prints the lock update hint" {
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

  Context "agents owned by APM" {
    BeforeEach {
      $script:agentsRuntimeRoot = Join-Path $TestDrive "doctor-agents/.claude"
      $script:agentsSkillsRoot = Join-Path $script:agentsRuntimeRoot "skills"
      $script:agentsSource = Join-Path $TestDrive "doctor-agents-source/.apm/agents"
      $sourceRoot = Join-Path $TestDrive "doctor-agents-source"
      $commandsSource = Join-Path $sourceRoot "commands"
      $rulesSource = Join-Path $sourceRoot "rules"
      $instructionsPath = Join-Path $sourceRoot "AGENTS.md"

      New-Item -ItemType Directory -Path $script:agentsSkillsRoot, (Join-Path $script:agentsRuntimeRoot "agents"), (Join-Path $script:agentsRuntimeRoot "commands"), (Join-Path $script:agentsRuntimeRoot "rules"), $script:agentsSource, $commandsSource, $rulesSource -Force | Out-Null
      Set-Content -LiteralPath (Join-Path $script:agentsRuntimeRoot "CLAUDE.md") -Value "# instructions"
      Set-Content -LiteralPath $instructionsPath -Value "# instructions"
      Set-Content -LiteralPath (Join-Path $script:agentsSource "reviewer.agent.md") -Value "agent body"

      Mock Require-Apm {}
      Mock Ensure-WorkspaceRepo {}
      Mock Ensure-WorkspaceScaffold {}
      Mock Get-CodexSkillTargetRoot { $script:agentsSkillsRoot }
      Mock Test-AgmsgRosterLink {}
      Mock Get-TrackedCatalogInstructionsPath { $instructionsPath }
      Mock Get-TrackedCatalogAgentsRoot { $script:agentsSource }
      Mock Get-TrackedCatalogCommandsRoot { $commandsSource }
      Mock Get-TrackedCatalogRulesRoot { $rulesSource }
      Mock Get-ManagedCatalogRuntimeTargets {
        @([pscustomobject]@{ Name = "claude"; Root = $script:agentsRuntimeRoot; SkillsRoot = $script:agentsRuntimeRoot; AgentsFace = "apm"; ConfigName = "CLAUDE.md" })
      }
      Mock Get-ManagedCatalogSkillInventory { @() }
      Mock Get-UnpinnedExternalReferences { @() }
      Mock Write-CatalogSummary {}

      function global:apm {
        $global:LASTEXITCODE = 0
      }
    }

    AfterEach {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
    }

    It "does not throw when deployed agents match the catalog and extra agent files are present" {
      Set-Content -LiteralPath (Join-Path $script:agentsRuntimeRoot "agents/reviewer.md") -Value "agent body"
      Set-Content -LiteralPath (Join-Path $script:agentsRuntimeRoot "agents/mine.md") -Value "mine"

      { Invoke-Doctor } | Should -Not -Throw
    }

    It "throws when a deployed agent differs from the catalog" {
      Set-Content -LiteralPath (Join-Path $script:agentsRuntimeRoot "agents/reviewer.md") -Value "locally edited"

      { Invoke-Doctor } | Should -Throw "*agents*reviewer.md*"
    }

    It "throws when a catalog agent is missing from the target" {
      { Invoke-Doctor } | Should -Throw "*agents*reviewer.md*"
    }
  }

  It "leaves the learning-intake inbox to Invoke-DoctorIntake in Invoke-Doctor" {
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
    New-Item -ItemType Directory -Path $learningIntakeDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $learningIntakeDir "20260101-0000-one.md") -Value "status: 未処理" -Encoding utf8

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
      $output | Should -Not -Match "learning-intake"
    }
    finally {
      Remove-Item Function:\apm -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $learningIntakeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "reports the learning-intake inbox split into 未処理 and 保留 from Invoke-DoctorIntake" {
    $inboxDir = Join-Path $script:WorkspaceDir "tmp/learning-intake"
    $inboxSubDir = Join-Path $inboxDir "sub"
    New-Item -ItemType Directory -Path $inboxSubDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $inboxDir "20260101-0000-one.md") -Value "status: 未処理`n# report one" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "20260101-0001-two.md") -Value "# report two, no status line" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "20260101-0002-three.md") -Value "status: 保留`n不足: owner" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "20260101-0003-four.md") -Value "- status: 保留" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "20260101-0004-five.md") -Value "status: 保留（注記）" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "20260101-0005-six.md") -Value "status: 未処理`nstatus: 保留" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "UPPER.MD") -Value "status: 未処理" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "note.txt") -Value "not a report" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxSubDir "nested.md") -Value "status: 未処理`n# nested report" -Encoding utf8

    try {
      $output = Get-DoctorIntakeOutput
      $output | Should -Match "learning-intake inbox: 未処理 4 / 保留 2"
    }
    finally {
      Remove-Item -LiteralPath $inboxDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "stays quiet at 9 pending reports in Invoke-DoctorIntake" {
    $inboxDir = Join-Path $script:WorkspaceDir "tmp/learning-intake"
    New-IntakePendingReports -InboxDir $inboxDir -Count 9

    try {
      $output = Get-DoctorIntakeOutput
      $output | Should -Match "learning-intake inbox: 未処理 9 / 保留 0"
      $output | Should -Not -Match "溜まっています"
    }
    finally {
      Remove-Item -LiteralPath $inboxDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "warns at 10 pending reports in Invoke-DoctorIntake and does not throw" {
    $inboxDir = Join-Path $script:WorkspaceDir "tmp/learning-intake"
    New-IntakePendingReports -InboxDir $inboxDir -Count 10

    try {
      { Invoke-DoctorIntake 3>&1 6>&1 | Out-Null } | Should -Not -Throw
      $output = Get-DoctorIntakeOutput
      $output | Should -Match "learning-intake inbox: 未処理 10 / 保留 0"
      $output | Should -Match "learning-intake: 未処理 10 件が溜まっています（閾値 10）"
    }
    finally {
      Remove-Item -LiteralPath $inboxDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "leaves deferred reports out of the threshold and the oldest date in Invoke-DoctorIntake" {
    $inboxDir = Join-Path $script:WorkspaceDir "tmp/learning-intake"
    New-IntakePendingReports -InboxDir $inboxDir -Count 9
    Set-Content -LiteralPath (Join-Path $inboxDir "20200101-0001-deferred.md") -Value "status: 保留" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "20200102-0001-deferred.md") -Value "status: 保留" -Encoding utf8

    try {
      $output = Get-DoctorIntakeOutput
      $output | Should -Match "learning-intake inbox: 未処理 9 / 保留 2"
      $output | Should -Match "最古の未処理: 2026-11-01"
      $output | Should -Not -Match "2020-01-01"
      $output | Should -Not -Match "溜まっています"
    }
    finally {
      Remove-Item -LiteralPath $inboxDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "reports the oldest pending date across YYYYMMDD- and YYYY-MM-DD- names in Invoke-DoctorIntake" {
    $inboxDir = Join-Path $script:WorkspaceDir "tmp/learning-intake"
    New-Item -ItemType Directory -Path $inboxDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $inboxDir "20261105-0042-newer.md") -Value "x" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "2026-09-30-cursor-middle.md") -Value "x" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "20260815-0001-oldest.md") -Value "x" -Encoding utf8

    try {
      $output = Get-DoctorIntakeOutput
      $output | Should -Match "最古の未処理: 2026-08-15"
      $output | Should -Not -Match "日付不明"

      Remove-Item -LiteralPath (Join-Path $inboxDir "20260815-0001-oldest.md")
      Set-Content -LiteralPath (Join-Path $inboxDir "2026-07-04-cursor-oldest.md") -Value "x" -Encoding utf8

      $output = Get-DoctorIntakeOutput
      $output | Should -Match "最古の未処理: 2026-07-04"
    }
    finally {
      Remove-Item -LiteralPath $inboxDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "counts pending reports whose name carries no date in Invoke-DoctorIntake" {
    $inboxDir = Join-Path $script:WorkspaceDir "tmp/learning-intake"
    New-Item -ItemType Directory -Path $inboxDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $inboxDir "20261105-0042-dated.md") -Value "x" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "native-undated.md") -Value "x" -Encoding utf8
    Set-Content -LiteralPath (Join-Path $inboxDir "20261399-bad-month-day.md") -Value "x" -Encoding utf8

    try {
      $output = Get-DoctorIntakeOutput
      $output | Should -Match "最古の未処理: 2026-11-05"
      $output | Should -Match "日付不明: 2 件"
    }
    finally {
      Remove-Item -LiteralPath $inboxDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "prints no oldest date when every pending report is undated in Invoke-DoctorIntake" {
    $inboxDir = Join-Path $script:WorkspaceDir "tmp/learning-intake"
    New-Item -ItemType Directory -Path $inboxDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $inboxDir "native-undated.md") -Value "x" -Encoding utf8

    try {
      $output = Get-DoctorIntakeOutput
      $output | Should -Match "learning-intake inbox: 未処理 1 / 保留 0"
      $output | Should -Match "日付不明: 1 件"
      $output | Should -Not -Match "最古の未処理"
    }
    finally {
      Remove-Item -LiteralPath $inboxDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "reports an empty inbox without a warning in Invoke-DoctorIntake" {
    $inboxDir = Join-Path $script:WorkspaceDir "tmp/learning-intake"
    New-Item -ItemType Directory -Path $inboxDir -Force | Out-Null

    try {
      $output = Get-DoctorIntakeOutput
      $output | Should -Be "learning-intake inbox: 未処理 0 / 保留 0"
    }
    finally {
      Remove-Item -LiteralPath $inboxDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "reports a missing inbox directory without a warning in Invoke-DoctorIntake" {
    Remove-Item -LiteralPath (Join-Path $script:WorkspaceDir "tmp/learning-intake") -Recurse -Force -ErrorAction SilentlyContinue

    $output = Get-DoctorIntakeOutput
    $output | Should -Be "learning-intake inbox: 未処理 0 / 保留 0"
  }

  It "does not count an unreadable report as pending in Invoke-DoctorIntake (non-Windows: chmod 000)" -Skip:($IsWindows -eq $true) {
    $inboxDir = Join-Path $script:WorkspaceDir "tmp/learning-intake"
    New-Item -ItemType Directory -Path $inboxDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $inboxDir "20261101-0001-readable.md") -Value "status: 未処理" -Encoding utf8
    $lockedPath = Join-Path $inboxDir "20261101-0002-locked.md"
    Set-Content -LiteralPath $lockedPath -Value "status: 未処理" -Encoding utf8
    & chmod 000 $lockedPath

    try {
      $output = Get-DoctorIntakeOutput
      $output | Should -Match "learning-intake inbox: 未処理 1 / 保留 0"
      $output | Should -Match "読み取り不能な報告 1 件"
    }
    finally {
      & chmod 644 $lockedPath
      Remove-Item -LiteralPath $inboxDir -Recurse -Force -ErrorAction SilentlyContinue
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
    # A plain (non-symlink) db dir, as if it had been absorbed by something other than the roster restore.
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
  # which the agmsg state restore keeps symlinked into $XDG_STATE_HOME/agmsg (see
  # scripts/agmsg-state.ps1:34). If that link is absorbed into a plain dir
  # or dropped by anything else, agmsg's own errors ("Team not
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

  It "keeps the bold heading runner behavior contract" {
    $boldHeadingRunner = Get-Content -LiteralPath (Join-Path $workspaceRoot "scripts/format-bold-headings.sh") -Raw

    $boldHeadingRunner | Should -Match 'TARGET="\./catalog"'
    $boldHeadingRunner | Should -Match '(?s)"\$mode" = "check".*--dry-run'
  }

}

Describe "catalog instructions and user root migration" {
  BeforeAll {
    $env:APM_WORKSPACE_LIB_ONLY = "1"
    $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "scripts/apm-workspace.ps1"
    . (Resolve-Path -LiteralPath $modulePath).Path
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY -ErrorAction SilentlyContinue

    function Write-FixtureFile {
      param([string]$Path, [string]$Content)
      New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
      [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding $false))
    }

    # Writes a root the way apm compile does: the Build ID is the sha256 of the other lines joined by "`n".
    function Write-GeneratedRoot {
      param([string]$Path, [string]$Body)
      $sha = [System.Security.Cryptography.SHA256]::Create()
      $digest = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$ApmGeneratedRootMarker`n$Body"))
      $sha.Dispose()
      $buildId = (($digest | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 12)
      Write-FixtureFile -Path $Path -Content "$ApmGeneratedRootMarker`n<!-- Build ID: $buildId -->`n$Body`n"
    }
  }

  BeforeEach {
    # TestDrive lasts for the whole Describe, so each test gets its own workspace and home.
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    $script:WorkspaceDir = Join-Path $caseRoot "workspace"
    $WorkspaceDir = $script:WorkspaceDir
    $global:WorkspaceDir = $script:WorkspaceDir
    $script:rootsHome = Join-Path $caseRoot "home"
    Write-FixtureFile -Path (Join-Path $script:WorkspaceDir "catalog/.apm/instructions/ai-collaboration.instructions.md") -Content "---`ndescription: fixture guide`n---`n`n`n# Guide`n`nbody line`n"
    $script:guideBody = Join-Path $script:rootsHome "guide-body.md"
    Write-FixtureFile -Path $script:guideBody -Content "# Guide`n`nbody line`n"
    foreach ($dir in @(".claude", ".codex", ".cursor")) {
      New-Item -ItemType Directory -Path (Join-Path $script:rootsHome $dir) -Force | Out-Null
    }
  }

  It "renders the instruction body without frontmatter and leading blank lines, as APM renders a rule" {
    $body = Get-CatalogInstructionsBody -Path (Get-TrackedCatalogInstructionsPath)
    $body | Should -BeExactly ([System.IO.File]::ReadAllText($script:guideBody))
  }

  It "tells absent, generated, edited-generated, legacy, hand-written, hard-linked and directory roots apart" {
    $known = Get-LegacyCatalogInstructionsBlobs
    Copy-Item -LiteralPath $script:guideBody -Destination (Join-Path $script:rootsHome ".claude/CLAUDE.md")
    Write-GeneratedRoot -Path (Join-Path $script:rootsHome ".codex/AGENTS.md") -Body "# compiled"
    $editedPath = Join-Path $script:rootsHome "edited.md"
    Write-GeneratedRoot -Path $editedPath -Body "# compiled"
    Add-Content -LiteralPath $editedPath -Value "my own line" -NoNewline
    Write-FixtureFile -Path (Join-Path $script:rootsHome "no-build-id.md") -Content "$ApmGeneratedRootMarker`n# compiled`n"
    $generatedText = [System.IO.File]::ReadAllText((Join-Path $script:rootsHome ".codex/AGENTS.md"))
    $noteLines = $generatedText -split "`n"
    $noteLines[0] = $noteLines[0] + " my note"
    Write-FixtureFile -Path (Join-Path $script:rootsHome "marker-note.md") -Content ($noteLines -join "`n")
    Write-FixtureFile -Path (Join-Path $script:rootsHome "crlf.md") -Content $generatedText.Replace("`n", "`r`n")
    [System.IO.File]::WriteAllBytes((Join-Path $script:rootsHome "bom.md"), [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes($generatedText)))
    Write-FixtureFile -Path (Join-Path $script:rootsHome "hand.md") -Content "my own rules`n"
    New-Item -ItemType HardLink -Path (Join-Path $script:rootsHome "hard.md") -Target (Join-Path $script:rootsHome "hand.md") | Out-Null
    Write-FixtureFile -Path (Join-Path $script:rootsHome ".cursor/AGENTS.md") -Content "# Guide`n`nbody line`nmy own addition`n"
    New-Item -ItemType Directory -Path (Join-Path $script:rootsHome "dir.md") | Out-Null

    Get-UserRootState -Path (Join-Path $script:rootsHome "missing.md") -KnownBlobs $known | Should -Be "absent"
    Get-UserRootState -Path (Join-Path $script:rootsHome ".claude/CLAUDE.md") -KnownBlobs $known | Should -Be "legacy"
    Get-UserRootState -Path (Join-Path $script:rootsHome ".codex/AGENTS.md") -KnownBlobs $known | Should -Be "generated"
    Get-UserRootState -Path $editedPath -KnownBlobs $known | Should -Be "edited-generated"
    Get-UserRootState -Path (Join-Path $script:rootsHome "no-build-id.md") -KnownBlobs $known | Should -Be "edited-generated"
    # APM's own reading: the marker is a prefix, CRLF is LF, and a BOM hides the marker.
    Get-UserRootState -Path (Join-Path $script:rootsHome "marker-note.md") -KnownBlobs $known | Should -Be "edited-generated"
    Get-UserRootState -Path (Join-Path $script:rootsHome "crlf.md") -KnownBlobs $known | Should -Be "generated"
    Get-UserRootState -Path (Join-Path $script:rootsHome "bom.md") -KnownBlobs $known | Should -Be "hand-written"
    Get-UserRootState -Path (Join-Path $script:rootsHome "hard.md") -KnownBlobs $known | Should -Be "hand-written"
    Get-UserRootState -Path (Join-Path $script:rootsHome ".cursor/AGENTS.md") -KnownBlobs $known | Should -Be "hand-written"
    Get-UserRootState -Path (Join-Path $script:rootsHome "dir.md") -KnownBlobs $known | Should -Be "not-regular"
  }

  It "skips the same leading whitespace before the marker as APM's Python lstrip" {
    $compiled = Join-Path $script:rootsHome "compiled.md"
    Write-GeneratedRoot -Path $compiled -Body "# compiled"
    $text = [System.IO.File]::ReadAllText($compiled)
    $prefixed = Join-Path $script:rootsHome "prefixed.md"
    # form feed, U+001C, U+3000 and U+2028 are Python whitespace; U+200B is not.
    foreach ($prefix in @([string][char]0xC, [string][char]0x1C, [string][char]0x3000, ([string][char]0x2028 + "`n"))) {
      Write-FixtureFile -Path $prefixed -Content ($prefix + $text)
      Get-UserRootState -Path $prefixed -KnownBlobs (New-Object System.Collections.Generic.HashSet[string]) | Should -Be "edited-generated"
    }
    Write-FixtureFile -Path $prefixed -Content ([string][char]0x200B + $text)
    Get-UserRootState -Path $prefixed -KnownBlobs (New-Object System.Collections.Generic.HashSet[string]) | Should -Be "hand-written"
  }

  It "recognizes an older committed catalog/AGENTS.md as a legacy copy" {
    Write-FixtureFile -Path (Join-Path $script:WorkspaceDir "catalog/AGENTS.md") -Content "# Old guide`n"
    & git -C $script:WorkspaceDir init -q
    & git -C $script:WorkspaceDir add catalog/AGENTS.md
    & git -C $script:WorkspaceDir -c user.name=t -c user.email=t@example.invalid commit -q -m old
    & git -C $script:WorkspaceDir rm -q catalog/AGENTS.md
    & git -C $script:WorkspaceDir -c user.name=t -c user.email=t@example.invalid commit -q -m moved
    Write-FixtureFile -Path (Join-Path $script:rootsHome ".codex/AGENTS.md") -Content "# Old guide`n"

    Get-UserRootState -Path (Join-Path $script:rootsHome ".codex/AGENTS.md") -KnownBlobs (Get-LegacyCatalogInstructionsBlobs) | Should -Be "legacy"
  }
}

Describe "catalog lock deployed files" {
  BeforeAll {
    $env:APM_WORKSPACE_LIB_ONLY = "1"
    $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "scripts/apm-workspace.ps1"
    . (Resolve-Path -LiteralPath $modulePath).Path
    Remove-Item Env:APM_WORKSPACE_LIB_ONLY -ErrorAction SilentlyContinue

    function Write-CatalogLockFixture {
      param([string]$Path, [string]$RuleHash)
      $lock = @(
        "lockfile_version: '2'", "dependencies:",
        "- repo_url: other/repo", "  name: catalog-lookalike", "  virtual_path: skills/other", "  deployed_files:", "  - .agents/skills/other/SKILL.md",
        "- repo_url: jey3dayo/apm-workspace", "  name: catalog", "  virtual_path: catalog", "  package_type: apm_package", "  deployed_files:",
        "  - .agents/skills/demo", "  - .agents/skills/demo/SKILL.md", "  - .claude/rules/ai-collaboration.md", "  deployed_file_hashes:",
        "    .agents/skills/demo/SKILL.md: sha256:c0ffee", "    .claude/rules/ai-collaboration.md: sha256:$RuleHash",
        "- repo_url: jey3dayo/apm-workspace", "  name: manual-skills", "  virtual_path: manual-skills", "  deployed_files:", "  - .agents/skills/manual/SKILL.md"
      ) -join "`n"
      [System.IO.File]::WriteAllText($Path, "$lock`n", (New-Object System.Text.UTF8Encoding $false))
    }
  }

  It "reads only the catalog package's deployed files and hashes" {
    $lockPath = Join-Path $TestDrive "parse.lock.yaml"
    Write-CatalogLockFixture -Path $lockPath -RuleHash "abc123"

    $entries = Get-CatalogLockDeployedEntries -LockPath $lockPath

    @($entries | ForEach-Object { "{0} {1} {2}" -f $_.Kind, $_.Path, $_.Hash }) | Should -Be @(
      "F .agents/skills/demo ", "F .agents/skills/demo/SKILL.md ", "F .claude/rules/ai-collaboration.md ",
      "H .agents/skills/demo/SKILL.md c0ffee", "H .claude/rules/ai-collaboration.md abc123")
  }

  It "also reads a catalog installed from a local path" {
    $lockPath = Join-Path $TestDrive "local.lock.yaml"
    [System.IO.File]::WriteAllText($lockPath, "lockfile_version: '1'`ndependencies:`n- repo_url: _local/catalog`n  name: catalog`n  deployed_files:`n  - .claude/rules/ai-collaboration.md`n  source: local`ndeployments:`n- kind: project-relative`n  value: .claude/agents/x.md`n")
    @(Get-CatalogLockDeployedEntries -LockPath $lockPath | ForEach-Object { "{0} {1}" -f $_.Kind, $_.Path }) | Should -Be @("F .claude/rules/ai-collaboration.md")
  }

  It "returns a recorded file that is gone and only counts a changed one" {
    $homeDir = Join-Path $TestDrive "lock-home"
    New-Item -ItemType Directory -Path (Join-Path $homeDir ".agents/skills/demo"), (Join-Path $homeDir ".claude/rules") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $homeDir ".agents/skills/demo/SKILL.md") -Value "edited"
    $rulePath = Join-Path $homeDir ".claude/rules/ai-collaboration.md"
    Set-Content -LiteralPath $rulePath -Value "rule"
    $lockPath = Join-Path $TestDrive "check.lock.yaml"
    Write-CatalogLockFixture -Path $lockPath -RuleHash (Get-FileHash -LiteralPath $rulePath -Algorithm SHA256).Hash.ToLowerInvariant()

    $output = @(Test-CatalogLockDeployedFiles -LockPath $lockPath -HomeDir $homeDir 6>&1)
    ($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | Out-String) | Should -Match "listed=3 missing=0 stale=0 changed=1"
    @($output | Where-Object { $_ -is [string] }).Count | Should -Be 0

    Move-Item -LiteralPath $rulePath -Destination (Join-Path $homeDir "rule.aside")
    @(Test-CatalogLockDeployedFiles -LockPath $lockPath -HomeDir $homeDir 6>$null) | Should -Be @(".claude/rules/ai-collaboration.md")
  }

  It "only warns about a skill deleted from the working catalog until the lock is updated" {
    Mock Write-WarnLine {}
    $homeDir = Join-Path $TestDrive "stale-home"
    New-Item -ItemType Directory -Path (Join-Path $homeDir ".claude/rules") -Force | Out-Null
    $rulePath = Join-Path $homeDir ".claude/rules/ai-collaboration.md"
    Set-Content -LiteralPath $rulePath -Value "rule"
    $lockPath = Join-Path $TestDrive "stale.lock.yaml"
    Write-CatalogLockFixture -Path $lockPath -RuleHash (Get-FileHash -LiteralPath $rulePath -Algorithm SHA256).Hash.ToLowerInvariant()

    $output = @(Test-CatalogLockDeployedFiles -LockPath $lockPath -HomeDir $homeDir 6>&1)

    @($output | Where-Object { $_ -is [string] }).Count | Should -Be 0
    ($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | Out-String) | Should -Match "listed=3 missing=0 stale=2 changed=0"
    Should -Invoke Write-WarnLine -Times 1 -ParameterFilter { $Message -like "2 skill or agent file(s) recorded in apm.lock.yaml are gone*apm.lock.yaml is next updated*" }
  }
}
