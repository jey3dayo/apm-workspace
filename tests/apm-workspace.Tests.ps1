$ErrorActionPreference = "Stop"

$env:APM_WORKSPACE_LIB_ONLY = "1"
. "C:\Users\j138c\.apm\scripts\apm-workspace.ps1"
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

    $map["openai/skills/skills/.curated/gh-address-comments"] | Should Be "openai/skills/skills/.curated/gh-address-comments#abcdef1234567890"
    $map["obra/superpowers/skills/brainstorming"] | Should Be "obra/superpowers/skills/brainstorming#1234567890abcdef"
  }
}

Describe "public command surface" {
  It "shows only catalog commands in help output" {
    $legacyMirrorPattern = 'transitional' + ' mirror'
    $help = & powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\j138c\.apm\scripts\apm-workspace.ps1 help | Out-String

    $help | Should Match "validate:catalog"
    $help | Should Match "stage-catalog"
    $help | Should Match "register-catalog"
    $help | Should Match "release-catalog"
    $help | Should Not Match $legacyMirrorPattern
    $help | Should Not Match "validate-internal"
    $help | Should Not Match "stage-internal"
    $help | Should Not Match "register-internal"
    $help | Should Not Match "migrate-internal"
  }

  It "does not reference removed install helpers" {
    $script = Get-Content -LiteralPath C:\Users\j138c\.apm\scripts\apm-workspace.ps1 -Raw

    $script | Should Not Match 'Invoke-InstallReference\b'
  }

  It "keeps local workspace scripts self-contained" {
    $shellScript = Get-Content -LiteralPath /Users/t00114/.apm/scripts/apm-workspace.sh -Raw
    $powerShellScript = Get-Content -LiteralPath C:\Users\j138c\.apm\scripts\apm-workspace.ps1 -Raw

    $shellScript | Should Not Match 'APM_BOOTSTRAP_REPO'
    $shellScript | Should Not Match '~/.config'
    $powerShellScript | Should Not Match 'APM_BOOTSTRAP_REPO'
    $powerShellScript | Should Not Match '\\.config\\scripts\\apm-workspace'
  }

  It "keeps workspace docs self-contained and preserves the bold headings exception" {
    $legacyDocsPattern = [regex]::Escape('~/.config/docs/')
    $files = @(
      'C:\Users\j138c\.apm\README.md'
      'C:\Users\j138c\.apm\llms.md'
      'C:\Users\j138c\.apm\docs\apm-task-coverage.md'
    )

    foreach ($file in $files) {
      $content = Get-Content -LiteralPath $file -Raw
      $content | Should Not Match $legacyDocsPattern
    }

    $miseToml = Get-Content -LiteralPath C:\Users\j138c\.apm\mise.toml -Raw
    $miseToml | Should Match 'replace-bold-headings\.ts" ./catalog/skills'
  }

  It "maps runtime config filenames per target" {
    $targets = @(Get-ManagedCatalogRuntimeTargets)

    ($targets | Where-Object Name -eq "claude").ConfigName | Should Be "CLAUDE.md"
    ($targets | Where-Object Name -eq "codex").ConfigName | Should Be "AGENTS.md"
    ($targets | Where-Object Name -eq "cursor").ConfigName | Should Be "AGENTS.md"
  }

  It "normalizes codex skill names without creating duplicate aliases" {
    Format-SkillName -Target "claude" -SourceSkillId "superpowers:brainstorming" | Should Be "superpowers:brainstorming"
    Format-SkillName -Target "codex" -SourceSkillId "superpowers:brainstorming" | Should Be "brainstorming"
  }

  It "publishes workspace mise tasks for formatting and ci flow" {
    $miseToml = Get-Content -LiteralPath C:\Users\j138c\.apm\mise.toml -Raw

    $miseToml | Should Match '\[tasks\.validate\]'
    $miseToml | Should Match '\[tasks\."validate:workspace"\]'
    $miseToml | Should Match '\[tasks\."validate:catalog"\]'
    $miseToml | Should Match '\[tasks\."format:markdown:bold-headings"\]'
    $miseToml | Should Match '\[tasks\."apm:install"\]'
    $miseToml | Should Match '\[tasks\."apm:update"\]'
    $miseToml | Should Match '\[tasks\.apply\]'
    $miseToml | Should Match '\[tasks\.update\]'
    $miseToml | Should Match '\[tasks\.sync\]'
    $miseToml | Should Match '\[tasks\.format\]'
    $miseToml | Should Match '\[tasks\."ci:check"\]'
    $miseToml | Should Match '\[tasks\.ci\]'
    $miseToml | Should Match '\[tasks\."catalog:release"\]'
    $miseToml | Should Match '\[tasks\."catalog:tidy"\]'
    $miseToml | Should Match 'run = "bash ./scripts/apm-workspace.sh apply"'
    $miseToml | Should Match 'run_windows = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\apm-workspace.ps1 apply"'
    $miseToml | Should Match 'replace-bold-headings\.ts" ./catalog/skills'
    $miseToml | Should Not Match 'Format, validate, and distribute the ~/.apm workspace locally'
    $miseToml | Should Not Match 'APM_BOOTSTRAP_REPO'
  }

  It "describes the catalog readme without legacy mirror wording" {
    $legacyMirrorPattern = 'transitional' + ' mirror'
    $readme = Get-CatalogReadmeContent

    $readme | Should Match '~/.apm/catalog/skills/<id>/'
    $readme | Should Not Match $legacyMirrorPattern
  }

  It "does not reference removed agents src paths in agent-facing docs" {
    $removedAgentsRoot = '~/.config/' + 'agents'
    $removedAgentsSrcPattern = [regex]::Escape($removedAgentsRoot) + '/src'
    $legacyMirrorPattern = 'transitional\s+' + 'mirror'
    $files = @(
      'C:\Users\j138c\.apm\catalog\.apm\skills\apm-usage\SKILL.md'
      'C:\Users\j138c\.apm\catalog\.apm\skills\skill-creator\SKILL.md'
      'C:\Users\j138c\.apm\catalog\.apm\skills\docs-index\indexes\agents-index.md'
      'C:\Users\j138c\.apm\catalog\.apm\skills\nix-dotfiles\SKILL.md'
      'C:\Users\j138c\.apm\catalog\.apm\skills\nix-dotfiles\README.md'
      'C:\Users\j138c\.apm\catalog\.apm\skills\nix-dotfiles\references\commands.md'
      'C:\Users\j138c\.apm\catalog\.apm\skills\nix-dotfiles\references\troubleshooting.md'
      'C:\Users\j138c\.apm\catalog\.apm\skills\rtk\SKILL.md'
      'C:\Users\j138c\.apm\catalog\.apm\skills\rtk\references\command-reference.md'
    )

    foreach ($file in $files) {
      $content = Get-Content -LiteralPath $file -Raw
      $content | Should Not Match $removedAgentsSrcPattern
      $content | Should Not Match $legacyMirrorPattern
    }

    $readme = Get-Content -LiteralPath C:\Users\j138c\.apm\README.md -Raw
    $todo = Get-Content -LiteralPath C:\Users\j138c\.apm\TODO.md -Raw

    $readme | Should Match 'apm add'
    $readme | Should Match 'mise run apply'
    $readme | Should Match 'mise run sync'
    $todo | Should Match 'formatSkillName'
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
  BeforeEach {
    $WorkspaceDir = Join-Path $TestDrive "workspace"
    New-Item -ItemType Directory -Path $WorkspaceDir -Force | Out-Null
  }

  It "includes legacy superpowers aliases for renamed managed skills" {
    $skillsRoot = Join-Path $WorkspaceDir "catalog\.apm\skills"
    New-Item -ItemType Directory -Path (Join-Path $skillsRoot "brainstorming") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $skillsRoot "code-review") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillsRoot "brainstorming\SKILL.md") -Value "# brainstorming"
    Set-Content -LiteralPath (Join-Path $skillsRoot "code-review\SKILL.md") -Value "# code-review"

    $cleanupSkillIds = @(Get-InternalCleanupSkillIds)

    $cleanupSkillIds | Should Be @("brainstorming", "code-review", "superpowers:brainstorming")
  }
}
