# APM Internal Skills First Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** internal bundled skills を global APM 運用へ巻き取るための first batch を定義し、external upstream refs と rollback 導線を混同しない migration path を固める。

**Architecture:** external skills は引き続き `~/.apm/apm.yml` に upstream ref で保持し、downloaded sources は `~/.apm/apm_modules/` に任せる。internal skills は別レーンとして inventory と contract を明文化し、simple batch から段階的に移行する。`apm install --global` では project-local `.apm/` content が deploy されないため、internal は workspace-local trick ではなく package/distribution strategy を明示的に選ぶ。

**Tech Stack:** APM CLI 0.8.11, mise, PowerShell, POSIX shell, Markdown docs

---

## File Map

- Create: `C:\Users\j138c\.apm\docs\superpowers\plans\2026-04-19-apm-internal-first-batch-plan.md`
- Modify: `C:\Users\j138c\.config\scripts\apm-workspace.ps1`
- Modify: `C:\Users\j138c\.config\scripts\apm-workspace.sh`
- Modify: `C:\Users\j138c\.config\templates\apm-workspace\mise.toml`
- Modify: `C:\Users\j138c\.config\mise\tasks\agents.toml`
- Modify: `C:\Users\j138c\.config\docs\tools\apm-workspace.md`
- Modify: `C:\Users\j138c\.config\docs\tools\mise-tasks.md`
- Modify: `C:\Users\j138c\.config\docs\tools\mise.md`
- Modify: `C:\Users\j138c\.config\agents\src\skills\apm-usage\SKILL.md`
- Modify: first-batch internal skill directories under `C:\Users\j138c\.config\agents\src\skills\`

## Current Constraints

- external global skills are already modeled correctly in `~/.apm/apm.yml` as upstream refs
- current `migrate` still copies internal skills into `~/.apm/packages/<id>` and leaves global `apm.yml` unchanged
- `packages/` is obsolete for the normal global path and should not become the new internal source of truth
- legacy rollback via `.config/agents/src/skills/<id>` and `agents:legacy:*` must remain available during the migration
- stale docs still describe `apm:bootstrap` or day-to-day flow in package-seed terms and must be corrected together with script changes

## Candidate Inventory

### First Batch Core: simple

These are the safest pilots because they are single-file skills with no helper assets:

| Skill | Shape | Why first |
| --- | --- | --- |
| `apm-usage` | `SKILL.md` only | owns the migration guidance and should reflect the new contract early |
| `atomic-commit` | `SKILL.md` only | small surface, easy to verify after migration |
| `greptileai` | `SKILL.md` only | minimal content, low risk |

### Next Simple Batch

These are still structurally light, but can wait until the first three succeed:

| Skill | Shape | Caution |
| --- | --- | --- |
| `codex-code-review` | `SKILL.md` only | content is Codex-workflow-specific and needs wording review |
| `codex-plan-review` | `SKILL.md` only | content is Codex-workflow-specific and needs wording review |
| `generate-svg` | `SKILL.md` only | low structure risk, but content review still needed |

### Second Batch: medium

These have extra assets and need package layout validation:

| Skill | Extra files |
| --- | --- |
| `rtk` | `agents/openai.yaml`, `references/command-reference.md` |
| `tauri-dev-screenshot` | `agents/openai.yaml`, `scripts/capture-tauri-window.ps1` |
| `tauri-webview-geometry` | `agents/openai.yaml`, `references/geometry-model.md` |

### Later Batch: heavy

These should wait until the contract is proven:

| Skill | Reason |
| --- | --- |
| `implementation-engine` | many examples/references, broader routing impact |
| `task-router` | many references/examples, central orchestration behavior |

## Contract To Freeze Before Implementation

- external:
  - keep using upstream refs in `~/.apm/apm.yml`
  - continue using `mise run migrate-external`
- internal:
  - do not reintroduce `./packages/*` into `~/.apm/apm.yml`
  - do not describe workspace-root `.apm/` content as a global deploy path
  - define one explicit distribution mechanism for internal bundled skills before migrating content
- rollback:
  - `.config/agents/src/skills` remains the rollback and seed source until the new mechanism is proven
  - `agents:legacy:*` remains intact

## Open Design Decision

Before code changes, choose and document exactly one internal distribution path:

1. dedicated installable internal APM package reference
2. generated/published internal bundle derived from `.config/agents/src/skills`
3. keep internal skills legacy-only until APM adds a clean user/global local-content mechanism

The plan assumes option `1` or `2`. If neither is viable in APM 0.8.11, stop after Task 2 and keep rollback-only status.

## Known Blockers

- internal skills do not yet have a canonical upstream or published package identity
- `agents/openai.yaml` sidecars do not map cleanly to APM's `.agent.md` conventions and need a translation strategy
- script-bearing skills need an explicit runtime contract for `sh`, PowerShell, or Python helpers
- some internal skills still assume legacy `.config` paths or `agents:legacy:*` workflows
- skill layouts are inconsistent today (`SKILL.md` at root vs nested `skills/SKILL.md`)
- heavier skills such as `cc-sdd`, `premortem`, `tsr`, `implementation-engine`, and `task-router` should not be used to prove the first batch

## Task 1: Freeze Internal Migration Contract

**Files:**
- Modify: `C:\Users\j138c\.config\docs\tools\apm-workspace.md`
- Modify: `C:\Users\j138c\.config\docs\tools\mise-tasks.md`
- Modify: `C:\Users\j138c\.config\docs\tools\mise.md`
- Modify: `C:\Users\j138c\.config\agents\src\skills\apm-usage\SKILL.md`

- [x] **Step 1: Add an internal-skills section to the workspace docs**

Expected:
- clearly separate external upstream refs from internal bundled skills
- explain that current `migrate` is legacy-only
- state the chosen internal distribution mechanism

- [x] **Step 2: Correct stale task descriptions**

Expected:
- no doc says `apm:bootstrap` initializes `packages/`
- no day-to-day flow recommends `mise run migrate -- ...` as the normal path

- [x] **Step 3: Update `apm-usage` guidance**

Expected:
- first-batch internal migration is documented
- rollback conditions are explicit

- [ ] **Step 4: Commit**

```bash
git add C:\Users\j138c\.config\docs\tools\apm-workspace.md C:\Users\j138c\.config\docs\tools\mise-tasks.md C:\Users\j138c\.config\docs\tools\mise.md C:\Users\j138c\.config\agents\src\skills\apm-usage\SKILL.md
git commit -m "docs(apm): define internal skills migration contract"
```

## Task 2: Replace Legacy-Only Internal Task Surface

**Files:**
- Modify: `C:\Users\j138c\.config\scripts\apm-workspace.ps1`
- Modify: `C:\Users\j138c\.config\scripts\apm-workspace.sh`
- Modify: `C:\Users\j138c\.config\templates\apm-workspace\mise.toml`
- Modify: `C:\Users\j138c\.config\mise\tasks\agents.toml`

- [x] **Step 1: Introduce a declarative first-batch inventory**

Expected:
- the scripts stop assuming ad hoc direct copies from `agents/src/skills`
- first-batch skill IDs are declared in one place

- [x] **Step 2: Split helper commands by responsibility**

Expected:
- external migration remains `migrate-external`
- internal migration gets a separate explicit command name and help text
- legacy package-seed wording is removed from the primary path

- [x] **Step 3: Keep rollback helpers intact**

Expected:
- `agents:legacy:*` continues to work
- old `migrate` path is either retained as clearly legacy or replaced by a compatibility alias

- [ ] **Step 4: Commit**

```bash
git add C:\Users\j138c\.config\scripts\apm-workspace.ps1 C:\Users\j138c\.config\scripts\apm-workspace.sh C:\Users\j138c\.config\templates\apm-workspace\mise.toml C:\Users\j138c\.config\mise\tasks\agents.toml
git commit -m "refactor(apm): separate internal skill migration from legacy seed flow"
```

## Task 3: Pilot The First Batch

**Files:**
- Modify: `C:\Users\j138c\.config\agents\src\skills\apm-usage\...`
- Modify: `C:\Users\j138c\.config\agents\src\skills\atomic-commit\...`
- Modify: `C:\Users\j138c\.config\agents\src\skills\greptileai\...`
- Modify: package/bundle source files for the chosen internal distribution mechanism

- [x] **Step 1: Normalize first-batch skill layout for packaging**

Expected:
- each skill has the exact files required by the chosen internal distribution mechanism
- no extra references/examples are pulled into the first batch

- [x] **Step 2: Register or publish the first batch through the chosen mechanism**

Expected:
- the global path for internal first-batch skills is reproducible
- a repo-tracked publish candidate exists at a stable path inside `apm-workspace`
- external `apm.yml` dependencies stay upstream-ref only

- [x] **Step 3: Keep rollback copies available**

Expected:
- `.config/agents/src/skills` still exists after the pilot
- docs explain when deletion can start

- [ ] **Step 4: Commit**

```bash
git add C:\Users\j138c\.config\agents\src\skills\apm-usage C:\Users\j138c\.config\agents\src\skills\atomic-commit C:\Users\j138c\.config\agents\src\skills\greptileai
git commit -m "feat(apm): pilot internal skill migration for first batch"
```

## Task 4: Verification

**Files:**
- Test only: `C:\Users\j138c\.config`
- Test only: `C:\Users\j138c\.apm`

- [x] **Step 1: Verify helper entrypoints**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\j138c\.config\scripts\apm-workspace.ps1 help
bash -n C:\Users\j138c\.config\scripts\apm-workspace.sh
```

- [x] **Step 2: Verify workspace task surface**

Run:
```powershell
cd C:\Users\j138c\.apm
mise install
mise run list
mise run validate
mise run doctor
```

Expected:
- external skills remain managed by upstream refs
- internal migration commands are visible and understandable
- no user-facing message implies `packages/` is the normal global path

- [x] **Step 3: Verify first-batch skill availability**

Expected:
- the chosen internal distribution mechanism yields deployable first-batch skills
- rollback path is still usable if the new mechanism fails

## Success Criteria

- a clear internal/global migration contract is documented
- first-batch internal skills are explicitly inventoried and prioritized
- task/docs/script surfaces stop implying that `~/.apm/packages` is the future path
- rollback remains available throughout the migration
- heavy internal skills are deferred until the first batch is proven
