# APM Global Skills Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `~/.apm` を user/global skill manifest として整理し、external skill を upstream refs だけで管理できる状態にする。

**Architecture:** `~/.apm/apm.yml` は global skill dependency manifest として扱い、skill の出自はすべて upstream ref で残す。ダウンロード済みソースは `~/.apm/apm_modules/` に置き、`packages/` や workspace-root `.apm/` は global skill の source of truth に使わない。legacy bundled skill は `.config` 側へ rollback / seed 用として残す。

**Tech Stack:** APM CLI 0.8.11, mise, PowerShell, POSIX shell, Markdown docs

---

## File Map

- Modify: `C:\Users\j138c\.apm\apm.yml`
- Modify: `C:\Users\j138c\.apm\apm.lock.yaml`
- Modify: `C:\Users\j138c\.apm\mise.toml`
- Modify: `C:\Users\j138c\.config\scripts\apm-workspace.ps1`
- Modify: `C:\Users\j138c\.config\scripts\apm-workspace.sh`
- Modify: `C:\Users\j138c\.config\templates\apm-workspace\mise.toml`
- Modify: `C:\Users\j138c\.config\docs\tools\apm-workspace.md`
- Modify: `C:\Users\j138c\.config\agents\src\skills\apm-usage\SKILL.md`

## Contract

- Global skill の source of truth は `~/.apm/apm.yml`
- External skill は upstream repo / primitive ref を `apm.yml` に記録する
- Downloaded dependency source は `~/.apm/apm_modules/` に入る
- `apm install -g` が global deploy の正規コマンド
- `packages/` は migration artifact であり、manifest truth ではない
- `.config/agents/src/skills` は rollback / seed 用に残すが、global manifest には入れない

## Task 1: Rewrite The Contract Surface

**Files:**
- Modify: `C:\Users\j138c\.config\docs\tools\apm-workspace.md`
- Modify: `C:\Users\j138c\.config\agents\src\skills\apm-usage\SKILL.md`

- [ ] **Step 1: Rewrite docs for global-only language**

Expected:
- `~/.apm/apm.yml` = manifest
- `~/.apm/apm_modules/` = downloaded sources
- no recommendation that `~/.apm/.apm/` or `packages/` is the source of truth for global skills
- obsolete `packages/` artifacts are removed from the workspace

- [ ] **Step 2: Mark `migrate` as legacy-only**

Expected:
- day-to-day flow mentions `mise run migrate-external` and `mise run apply`
- legacy bundled skill seeding is clearly labeled as rollback-only / non-primary

- [ ] **Step 3: Commit contract rewrite**

```bash
git add C:\Users\j138c\.config\docs\tools\apm-workspace.md C:\Users\j138c\.config\agents\src\skills\apm-usage\SKILL.md
git commit -m "docs(apm): rewrite workspace contract for global skills"
```

## Task 2: Align Task Surfaces And Scripts

**Files:**
- Modify: `C:\Users\j138c\.apm\mise.toml`
- Modify: `C:\Users\j138c\.config\templates\apm-workspace\mise.toml`
- Modify: `C:\Users\j138c\.config\scripts\apm-workspace.ps1`
- Modify: `C:\Users\j138c\.config\scripts\apm-workspace.sh`

- [ ] **Step 1: Make task descriptions match the global model**

Expected:
- `apply` = deploy global dependencies from `~/.apm/apm.yml`
- `migrate-external` = register upstream refs from `nix/agent-skills-sources.nix`
- `migrate` = legacy seed helper only, not manifest truth

- [ ] **Step 2: Remove package-based messaging from bootstrap and help output**

Expected:
- no “record ./packages/... in apm.yml” language
- no “packages are the normal install path” language

- [ ] **Step 3: Keep rollback helpers without making them primary**

Expected:
- legacy commands still exist
- normal path does not rely on them

- [ ] **Step 4: Commit task-surface alignment**

```bash
git add C:\Users\j138c\.apm\mise.toml C:\Users\j138c\.config\templates\apm-workspace\mise.toml C:\Users\j138c\.config\scripts\apm-workspace.ps1 C:\Users\j138c\.config\scripts\apm-workspace.sh
git commit -m "refactor(apm): align tasks with global skills model"
```

## Task 3: Rewrite The Global Manifest

**Files:**
- Modify: `C:\Users\j138c\.apm\apm.yml`
- Modify: `C:\Users\j138c\.apm\apm.lock.yaml`

- [ ] **Step 1: Replace `./packages/...` entries with upstream refs**

Expected:
- `apm-usage` is removed from `apm.yml`
- all external skills are represented by canonical upstream refs
- duplicate `ui-ux-pro-max` local entry is removed

- [ ] **Step 2: Re-resolve the lockfile**

Run:
```powershell
cd C:\Users\j138c\.apm
mise run apply
```

Expected:
- `apm.lock.yaml` no longer shows external packages as `_local/...`
- global deploy refresh completes from upstream refs

- [ ] **Step 3: Verify representative entries**

Check:
- `ui-ux-pro-max`
- one `superpowers:*` skill
- one OpenAI curated skill

- [ ] **Step 4: Commit manifest rewrite**

```bash
git add C:\Users\j138c\.apm\apm.yml C:\Users\j138c\.apm\apm.lock.yaml
git commit -m "feat(apm): manage global skills by upstream refs"
```

## Task 4: Smoke Verification

**Files:**
- Test only: `C:\Users\j138c\.apm`
- Test only: `C:\Users\j138c\.config`

- [ ] **Step 1: Validate script entrypoints**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\j138c\.config\scripts\apm-workspace.ps1 help
bash -n C:\Users\j138c\.config\scripts\apm-workspace.sh
```

- [ ] **Step 2: Validate the global workspace**

```powershell
cd C:\Users\j138c\.apm
mise run list
mise run validate
mise run doctor
```

Expected:
- `apm.yml` and `apm_modules/` are treated as the active global state
- no user-facing task suggests `packages/` as the main flow

- [ ] **Step 3: Record residual gaps**

Document:
- any remaining legacy artifacts
- any APM CLI limitations still observed
- anything not fully verified end-to-end

## Success Criteria

- `apm.yml` no longer uses `./packages/...`
- external global skills are recorded by upstream refs
- `apm_modules/` is the downloaded-source location
- docs and tasks no longer describe `packages/` or workspace-root `.apm/` as the global skill truth
- legacy rollback helpers still exist but are clearly secondary
