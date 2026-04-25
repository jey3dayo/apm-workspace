# APM Global Distribution Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore `apm -g` based external skill ownership while keeping personal skills in `catalog/skills/**`, make `apply` offline, and deploy normalized skill trees to `~/.claude/skills` and `~/.codex/skills`.

**Architecture:** Keep two sources of truth: personal skills from `catalog/skills/**` and external skills from `apm install/uninstall` managed `apm.yml` plus `apm.lock.yaml`. Refactor `apply` into a lock-backed deployment planner plus target-specific filesystem application, and keep shared guidance sync separate from skill inventory handling.

**Tech Stack:** Bash, PowerShell, APM CLI, mise tasks, Pester, Markdown docs

---

## File Structure

- Modify: `/Users/t00114/.apm/scripts/apm-workspace.sh`
  - Replace catalog-only manifest assumptions
  - Add external-skill inventory parsing and target deployment planning
  - Keep shared guidance sync separate from skill deployment
- Modify: `/Users/t00114/.apm/scripts/apm-workspace.ps1`
  - Mirror shell behavior for Windows
  - Keep public command semantics aligned with shell
- Modify: `/Users/t00114/.apm/mise.toml`
  - Make `ci` verification-only
  - Keep `apply` deployment-only
  - Add `sync` as the end-to-end meta-task
- Modify: `/Users/t00114/.apm/tests/apm-workspace.Tests.ps1`
  - Add regression coverage for external lock parsing, target name normalization, new task semantics, and doc references
- Modify: `/Users/t00114/.apm/README.md`
  - Update day-to-day workflow and source-of-truth guidance
- Create: `/Users/t00114/.apm/llms.txt`
  - Add concise LLM/operator instructions for the new workflow
- Modify: `/Users/t00114/.apm/TODO.md`
  - Record the open concern around target name normalization
- Do Not Create: `/Users/t00114/.apm/AGENTS.md`
  - Keep repo-root agent guidance out of this implementation slice until the workflow settles

### Task 1: Lock In Regression Coverage First

**Files:**

- Modify: `/Users/t00114/.apm/tests/apm-workspace.Tests.ps1`
- Test: `/Users/t00114/.apm/tests/apm-workspace.Tests.ps1`

- [ ] **Step 1: Write failing tests for external lock parsing and target normalization**

Add these examples to `Describe "catalog helpers"` and `Describe "public command surface"` in `/Users/t00114/.apm/tests/apm-workspace.Tests.ps1`:

```powershell
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

It "normalizes codex skill names without creating duplicate aliases" {
  Format-SkillName -Target "claude" -SourceSkillId "superpowers:brainstorming" | Should Be "superpowers:brainstorming"
  Format-SkillName -Target "codex" -SourceSkillId "superpowers:brainstorming" | Should Be "brainstorming"
}
```

- [ ] **Step 2: Run the targeted Pester test to verify it fails**

Run:

```bash
pwsh -NoProfile -Command "Invoke-Pester /Users/t00114/.apm/tests/apm-workspace.Tests.ps1 -Output Detailed"
```

Expected: FAIL with missing function or stale catalog-only expectations around skill parsing and naming.

- [ ] **Step 3: Add failing tests for new mise semantics and documentation expectations**

Add these checks in the existing `It "publishes workspace mise tasks for formatting and ci flow"` and doc assertions:

```powershell
$miseToml | Should Match '\[tasks\.apply\]'
$miseToml | Should Match '\[tasks\.update\]'
$miseToml | Should Match '\[tasks\.sync\]'
$miseToml | Should Match '\[tasks\.ci\]'
$miseToml | Should Not Match 'Format, validate, and distribute the ~/.apm workspace locally'

$readme = Get-Content -LiteralPath C:\Users\j138c\.apm\README.md -Raw
$readme | Should Match 'apm install'
$readme | Should Match 'mise run apply'
$readme | Should Match 'mise run sync'

$todo = Get-Content -LiteralPath C:\Users\j138c\.apm\TODO.md -Raw
$todo | Should Match 'formatSkillName'
```

- [ ] **Step 4: Run the targeted Pester test again to verify the new assertions fail for the right reason**

Run:

```bash
pwsh -NoProfile -Command "Invoke-Pester /Users/t00114/.apm/tests/apm-workspace.Tests.ps1 -Output Detailed"
```

Expected: FAIL on old `mise.toml` descriptions, missing `sync`, and missing `formatSkillName` note in `TODO.md`.

- [ ] **Step 5: Commit the red test additions**

```bash
git add /Users/t00114/.apm/tests/apm-workspace.Tests.ps1
git commit -m "test: capture apm global distribution regressions"
```

### Task 2: Refactor Manifest and Inventory Handling

**Files:**

- Modify: `/Users/t00114/.apm/scripts/apm-workspace.sh`
- Modify: `/Users/t00114/.apm/scripts/apm-workspace.ps1`
- Test: `/Users/t00114/.apm/tests/apm-workspace.Tests.ps1`

- [ ] **Step 1: Replace catalog-only workspace manifest assumptions in the shell script**

In `/Users/t00114/.apm/scripts/apm-workspace.sh`, update `write_workspace_manifest_template` and related helpers so the workspace manifest remains command-managed and no longer implies catalog-only ownership:

```bash
write_workspace_manifest_template() {
  manifest_path="$WORKSPACE_DIR/apm.yml"
  project_name=$(workspace_project_name)
  author_name=$(workspace_author_name)

  cat >"$manifest_path" <<EOF
name: $project_name
version: 1.0.0
description: APM project for $project_name
author: $author_name
dependencies:
  apm:
    - jey3dayo/apm-workspace/catalog#main
  mcp: []
scripts: {}
EOF
}
```

Keep `write_catalog_manifest_template()` minimal for the published catalog package:

```bash
write_catalog_manifest_template() {
  destination_dir="$1"
  cat >"$destination_dir/apm.yml" <<EOF
name: $CATALOG_DIR_NAME
version: 1.0.0
description: Managed catalog package for shared runtime guidance
dependencies:
  apm: []
  mcp: []
scripts: {}
EOF
}
```

- [ ] **Step 2: Add shell helpers for external inventory and target name normalization**

Add these functions near the existing manifest and skill helper section in `/Users/t00114/.apm/scripts/apm-workspace.sh`:

```bash
format_skill_name() {
  target="$1"
  source_skill_id="$2"

  case "$target" in
    codex)
      printf '%s\n' "${source_skill_id#superpowers:}"
      ;;
    *)
      printf '%s\n' "$source_skill_id"
      ;;
  esac
}

locked_external_skill_records() {
  lock_path="$WORKSPACE_DIR/apm.lock.yaml"
  [ -f "$lock_path" ] || fail "Lock file not found: $lock_path"

  awk '
    $1 == "-" && $2 == "repo_url:" { repo=$3; commit=""; path="" }
    $1 == "resolved_commit:" { commit=$2 }
    $1 == "virtual_path:" { path=$2 }
    repo && commit && path { print repo "|" path "|" commit; repo=""; commit=""; path="" }
  ' "$lock_path"
}
```

- [ ] **Step 3: Mirror the same behavior in PowerShell**

In `/Users/t00114/.apm/scripts/apm-workspace.ps1`, add matching functions:

```powershell
function Format-SkillName {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$SourceSkillId
  )

  if ($Target -eq "codex" -and $SourceSkillId.StartsWith("superpowers:")) {
    return $SourceSkillId.Substring("superpowers:".Length)
  }

  return $SourceSkillId
}
```

Retain `Get-LockPinnedReferenceMap`, but add or adjust a companion function that emits lock-backed skill records instead of only pin references.

- [ ] **Step 4: Run the targeted regression test to verify the new helper layer passes**

Run:

```bash
pwsh -NoProfile -Command "Invoke-Pester /Users/t00114/.apm/tests/apm-workspace.Tests.ps1 -Output Detailed"
```

Expected: PASS for the new parsing and normalization tests, while later task-semantic and doc tests still fail.

- [ ] **Step 5: Commit the manifest and helper refactor**

```bash
git add /Users/t00114/.apm/scripts/apm-workspace.sh /Users/t00114/.apm/scripts/apm-workspace.ps1 /Users/t00114/.apm/tests/apm-workspace.Tests.ps1
git commit -m "refactor: restore external skill inventory handling"
```

### Task 3: Implement Offline Apply and Target-Specific Deployment

**Files:**

- Modify: `/Users/t00114/.apm/scripts/apm-workspace.sh`
- Modify: `/Users/t00114/.apm/scripts/apm-workspace.ps1`
- Test: `/Users/t00114/.apm/tests/apm-workspace.Tests.ps1`

- [ ] **Step 1: Write a failing deployment-plan regression**

Add a test covering the combined personal plus external inventory and Codex normalization:

```powershell
It "builds a codex-safe deployment plan from personal and external skills" {
  $plan = @(
    New-DeploymentPlanEntry -Target "claude" -SourceSkillId "superpowers:brainstorming" -SourcePath "/tmp/brainstorming"
    New-DeploymentPlanEntry -Target "codex" -SourceSkillId "superpowers:brainstorming" -SourcePath "/tmp/brainstorming"
  )

  ($plan | Where-Object Target -eq "claude").DeployedSkillName | Should Be "superpowers:brainstorming"
  ($plan | Where-Object Target -eq "codex").DeployedSkillName | Should Be "brainstorming"
}
```

- [ ] **Step 2: Run the targeted test to verify it fails**

Run:

```bash
pwsh -NoProfile -Command "Invoke-Pester /Users/t00114/.apm/tests/apm-workspace.Tests.ps1 -Output Detailed"
```

Expected: FAIL with missing deployment-plan constructor or stale apply behavior.

- [ ] **Step 3: Refactor `apply` to stage target trees from local materialized state**

In `/Users/t00114/.apm/scripts/apm-workspace.sh`, replace the current install-first flow inside `cmd_apply` with a plan-driven staged deployment:

```bash
cmd_apply() {
  require_apm
  ensure_workspace_repo
  ensure_workspace_scaffold
  cmd_validate_catalog
  ensure_workspace_mise_file

  deployment_root=$(mktemp -d "${TMPDIR:-/tmp}/apm-apply.XXXXXX")
  build_target_skill_trees "$deployment_root"
  sync_shared_guidance_assets
  replace_skill_targets_from_stage "$deployment_root"
  normalize_workspace_gitignore
  compile_codex
}
```

Add the plan-stage-apply helpers as separate functions:

```bash
build_target_skill_trees() {
  destination_root="$1"
  mkdir -p "$destination_root/claude" "$destination_root/codex"
  collect_personal_skill_records
  collect_external_skill_records
  validate_deployment_collisions
  stage_target_skill_records "$destination_root"
}
```

Do not call networked APM install commands from `cmd_apply`.

- [ ] **Step 4: Mirror the offline apply flow in PowerShell**

Update `Invoke-Apply` in `/Users/t00114/.apm/scripts/apm-workspace.ps1` to match:

```powershell
function Invoke-Apply {
  Require-Apm
  Ensure-WorkspaceRepo
  Ensure-WorkspaceScaffold
  Invoke-ValidateCatalog
  Ensure-WorkspaceMiseFile

  $stageDir = New-TemporaryDirectory -Prefix "apm-apply"
  Build-TargetSkillTrees -StageRoot $stageDir
  Sync-ManagedCatalogRuntimeAssets
  Replace-SkillTargetsFromStage -StageRoot $stageDir
  Normalize-WorkspaceGitignore
  Invoke-CodexCompile
}
```

- [ ] **Step 5: Run the full regression test and verify the apply behavior is now green**

Run:

```bash
pwsh -NoProfile -Command "Invoke-Pester /Users/t00114/.apm/tests/apm-workspace.Tests.ps1 -Output Detailed"
```

Expected: PASS for helper and deployment-plan tests, with only `mise.toml` and doc expectations still pending if not yet updated.

- [ ] **Step 6: Commit the offline apply implementation**

```bash
git add /Users/t00114/.apm/scripts/apm-workspace.sh /Users/t00114/.apm/scripts/apm-workspace.ps1 /Users/t00114/.apm/tests/apm-workspace.Tests.ps1
git commit -m "feat: make apm apply offline and target-aware"
```

### Task 4: Rework Mise Tasks and Command Surface

**Files:**

- Modify: `/Users/t00114/.apm/mise.toml`
- Modify: `/Users/t00114/.apm/scripts/apm-workspace.sh`
- Modify: `/Users/t00114/.apm/scripts/apm-workspace.ps1`
- Test: `/Users/t00114/.apm/tests/apm-workspace.Tests.ps1`

- [ ] **Step 1: Write the new `mise.toml` task layout**

Replace the task semantics in `/Users/t00114/.apm/mise.toml` so `ci` verifies only and `sync` becomes the meta-task:

```toml
[tasks.apply]
description = "Deploy local personal and external skills from lock-backed state"
run = "bash ./scripts/apm-workspace.sh apply"
run_windows = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\apm-workspace.ps1 apply"

[tasks.update]
description = "Update the ~/.apm checkout and refresh APM dependency state"
run = "bash ./scripts/apm-workspace.sh update"
run_windows = "powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\apm-workspace.ps1 update"

[tasks.ci]
description = "Run formatting, validation, smoke tests, and repository checks"
depends = ["check:format", "validate", "smoke-catalog"]

[tasks.sync]
description = "Refresh dependency state, verify it, and deploy locally"
run = [{ task = "update" }, { task = "ci" }, { task = "apply" }, { task = "doctor" }]
```

Keep `apply`, `update`, and `doctor` as leaf or command tasks. Move any old catalog-only orchestration that is still useful under clearly scoped maintenance names.

- [ ] **Step 2: Update help text in shell and PowerShell to match the new task meanings**

Adjust the help block in both scripts so the command descriptions align with the new roles:

```text
apply              Deploy local skill state from apm.yml/apm.lock.yaml without network access
update             Refresh the checkout and dependency state, then stop before deployment
doctor             Print workspace, manifest, lock, and target state
```

Ensure obsolete wording like “refresh APM dependencies and deploy” is removed from `update`.

- [ ] **Step 3: Run formatting and verify the task surface tests pass**

Run:

```bash
mise run format
pwsh -NoProfile -Command "Invoke-Pester /Users/t00114/.apm/tests/apm-workspace.Tests.ps1 -Output Detailed"
```

Expected: `format` succeeds and the `mise.toml` assertion block passes with the new `sync` task and verification-only `ci`.

- [ ] **Step 4: Commit the task-surface changes**

```bash
git add /Users/t00114/.apm/mise.toml /Users/t00114/.apm/scripts/apm-workspace.sh /Users/t00114/.apm/scripts/apm-workspace.ps1 /Users/t00114/.apm/tests/apm-workspace.Tests.ps1
git commit -m "refactor: separate update apply and ci workflows"
```

### Task 5: Update Operator and LLM Documentation

**Files:**

- Modify: `/Users/t00114/.apm/README.md`
- Create: `/Users/t00114/.apm/llms.txt`
- Modify: `/Users/t00114/.apm/TODO.md`
- Test: `/Users/t00114/.apm/tests/apm-workspace.Tests.ps1`

- [ ] **Step 1: Update `README.md` for the new operator workflow and Source Of Truth**

Revise the key workflow section in `/Users/t00114/.apm/README.md` to describe:

````md
## Daily Flow

```powershell
cd ~/.apm
apm install <external-skill-ref>
mise run update
mise run ci
mise run apply
```
````

- Personal skills: `~/.apm/catalog/skills/<id>/`
- External skills: managed by `apm install/uninstall` in `apm.yml` and `apm.lock.yaml`
- `mise run update` refreshes repository and dependency state
- `mise run apply` deploys local skills from lock-backed local state
- `mise run ci` verifies only and does not deploy

````

- [ ] **Step 2: Create `llms.txt` with concise workflow guidance**

Create `/Users/t00114/.apm/llms.txt` with:

```text
APM workspace operating model

- Source Of Truth
- Personal skills live in catalog/skills/**
- External skills are added and removed with apm install/uninstall and stored in apm.yml plus apm.lock.yaml
- Do not hand-edit apm.yml during normal operation
- Run mise run update to refresh checkout and dependency state
- Run mise run ci to verify formatting, validation, and tests
- Run mise run apply to deploy from local apm.yml, apm.lock.yaml, apm_modules, and catalog/skills/**
- Codex skill names may be normalized during deployment via formatSkillName(target, sourceSkillId)
````

- [ ] **Step 3: Explicitly defer repo-root `AGENTS.md` in this slice**

Do not create `/Users/t00114/.apm/AGENTS.md` in this implementation. Keep the source-of-truth guidance in `README.md` and `llms.txt`, and leave repo-root agent guidance for a later task once the workflow stabilizes.

- [ ] **Step 4: Add the open normalization concern to `TODO.md`**

Append this section to `/Users/t00114/.apm/TODO.md`:

```md
## Open Concerns

- `formatSkillName(target, sourceSkillId)` currently strips selected prefixes for Codex-target deployment.
- Keep the source skill id stable in authoring and lock data even if deployed names differ by target.
- Revisit the Codex normalization rule if future clients can consume the source id directly without duplicate display issues.
```

- [ ] **Step 5: Run documentation checks and the full repository verification flow**

Run:

```bash
mise run check:format
pwsh -NoProfile -Command "Invoke-Pester /Users/t00114/.apm/tests/apm-workspace.Tests.ps1 -Output Detailed"
bash -n /Users/t00114/.apm/scripts/apm-workspace.sh
```

Expected:

- `check:format` exits successfully
- Pester passes all assertions
- `bash -n` exits with status 0

- [ ] **Step 6: Commit the documentation updates**

```bash
git add /Users/t00114/.apm/README.md /Users/t00114/.apm/llms.txt /Users/t00114/.apm/TODO.md /Users/t00114/.apm/tests/apm-workspace.Tests.ps1
git commit -m "docs: describe the new apm distribution workflow"
```

### Task 6: Final End-to-End Verification

**Files:**

- Modify: `/Users/t00114/.apm/scripts/apm-workspace.sh`
- Modify: `/Users/t00114/.apm/scripts/apm-workspace.ps1`
- Modify: `/Users/t00114/.apm/mise.toml`
- Modify: `/Users/t00114/.apm/tests/apm-workspace.Tests.ps1`
- Modify: `/Users/t00114/.apm/README.md`
- Create: `/Users/t00114/.apm/llms.txt`
- Modify: `/Users/t00114/.apm/TODO.md`

- [ ] **Step 1: Run the verification suite in the final intended order**

Run:

```bash
mise run ci
bash ./scripts/apm-workspace.sh doctor
pwsh -NoProfile -Command "& { .\scripts\apm-workspace.ps1 doctor }"
```

Expected:

- `mise run ci` succeeds without mutating deployed targets
- both doctor commands report present manifests and target roots
- catalog validation and smoke tests pass

- [ ] **Step 2: Run `apply` explicitly to verify deployment still works after `ci`**

Run:

```bash
mise run apply
bash ./scripts/apm-workspace.sh doctor
```

Expected:

- `apply` succeeds without network access
- `doctor` reports `skills=present` for `claude` and `codex`

- [ ] **Step 3: Inspect the resulting tree names for Codex normalization**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
for root in (Path.home()/".claude"/"skills", Path.home()/".codex"/"skills"):
    names = sorted(p.name for p in root.iterdir() if p.is_dir())
    print(root, len(names), names[:20])
PY
```

Expected:

- Claude preserves source ids where supported
- Codex uses normalized names without duplicate alias directories

- [ ] **Step 4: Commit any final verification-driven fixes**

```bash
git add /Users/t00114/.apm
git commit -m "test: verify apm global distribution redesign"
```

## Self-Review

### Spec coverage

- Dual source of truth: covered by Tasks 2 and 3
- `apm.lock.yaml` keeping individual external entries: covered by Tasks 1 and 2
- Offline `apply`: covered by Task 3
- `mise.toml` redesign: covered by Task 4
- `README.md`, `llms.txt`, and `TODO.md` updates: covered by Task 5
- Verification-only `ci`: covered by Tasks 4 and 6

### Placeholder scan

- No `TODO`, `TBD`, or “implement later” placeholders remain in task steps
- Every code-changing step includes a concrete snippet or exact block to add or replace
- Every execution step includes an exact command and expected result

### Type and naming consistency

- The plan consistently uses `formatSkillName` / `Format-SkillName` for target normalization
- The plan consistently distinguishes `sourceSkillId` from `DeployedSkillName`
- `sync` is the only new end-to-end mise meta-task name used throughout the plan
