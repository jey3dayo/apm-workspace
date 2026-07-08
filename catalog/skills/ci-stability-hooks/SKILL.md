---
name: ci-stability-hooks
description: "Use when adding or reviewing CI-stability hooks and gates: Lefthook/pre-commit/pre-push configuration, aligning local push gates with GitHub Actions, deciding commit-vs-push gate scope, or migrating pre-commit to Lefthook. For mise task design itself, use `mise`; for debugging failing PR checks, use `gh-fix-ci`."
---

# CI Stability Hooks

## Goal

Make local hooks predict ordinary CI failures without making commits painful. Hooks call repo-defined quality commands; the gate split in step 3 decides what runs where.

## Workflow

### 1. Read The Repo Contract

Inspect the repository's source of truth before editing hook config:

- `AGENTS.md`, `CLAUDE.md`, `README.md`, and linked project guidance when present.
- `git status --short --branch` to identify unrelated dirty work.
- `mise.toml`, `mise.local.toml`, `package.json`, `pnpm-workspace.yaml`, and existing task definitions.
- `.github/workflows/**`, `lefthook.yml`, `.lefthook/**`, `.pre-commit-config.yaml`, and other hook config if present.

Completion condition: you know which files define quality gates and which dirty files are in scope.

### 2. Inventory Existing Gates

Build a small map of available commands:

- Auto-format commands: `mise run format`, `pnpm run format`, formatter-specific tasks.
- Format-check commands: `mise run format:check`, `pnpm run format:check`, `biome check`, `prettier --check`.
- Fast checks: lint, shellcheck, yaml lint, markdown lint, type-only checks if cheap.
- Heavy checks: typecheck, test, build, `mise run check`, `mise run ci`, `pnpm run check`, `pnpm run ci`.
- Workflow checks: ordinary CI jobs for format, lint, typecheck, test, build, and generated-file validation.

Prefer repository-defined tasks over inventing commands. If both `mise` and package scripts exist, treat `mise` as the orchestration layer when the repo already uses it for CI.

Completion condition: local hooks can be derived from existing repo commands or clearly justified additions.

### 3. Choose The Gate Split

Use this split unless the repo contract says otherwise:

- Put staged-file formatters and very fast linters in `pre-commit`.
- Keep test suites, builds, slow typechecks, network access, and full aggregate commands out of `pre-commit`; a commit gate that runs full CI pushes developers toward bypassing hooks.
- Put the repository CI-equivalent gate in `pre-push`.
- Prefer `mise run ci` for `pre-push` when it exists.
- Fall back in this order: `mise run check`, `pnpm run ci`, `pnpm run check`, or an explicit sequence matching GitHub Actions.

For `pre-commit`, prefer named jobs per tool instead of one aggregate `mise run format`: a failed aggregate hides which formatter failed, while separate jobs make failures diagnosable. `mise run format` remains useful as a full auto-format pass before push or PR.

Completion condition: commit hooks stay fast and push hooks block the failures most likely to break CI.

### 4. Implement Lefthook

When adding or updating Lefthook:

- Use `glob`, `{staged_files}`, and `stage_fixed: true` for staged-file formatters when supported.
- Use package-manager prefixes that match the repo: `pnpm exec`, `mise exec --`, or direct commands managed by the repo.
- Add Lefthook through the existing tool source: package dependency for package-managed repos, `mise` tool config for mise-managed dotfiles or tool repos.
- Add an install helper only when the repo already has a scripts/tasks pattern for setup.
- If the repo already uses `pnpm.onlyBuiltDependencies`, include `lefthook` there when needed for install stability.
- Preserve `.pre-commit-config.yaml` during a migration unless the user explicitly asks to remove it.
- Remember that `lefthook run` can synchronize `.git/hooks` and `stage_fixed: true` can stage modified files. Report that side effect when it occurs.

Example shape, adapt commands to the repository:

```yaml
pre-commit:
  parallel: true
  jobs:
    - name: prettier
      glob: "*.{md,yml,yaml,json}"
      run: pnpm exec prettier --write --ignore-unknown {staged_files}
      stage_fixed: true
    - name: biome
      glob: "*.{js,jsx,ts,tsx,json}"
      run: pnpm exec biome check --write --no-errors-on-unmatched {staged_files}
      stage_fixed: true

pre-push:
  jobs:
    - name: ci
      run: mise run ci
```

Completion condition: hooks are installable through repo tooling and each job's failure points to a specific tool or gate.

### 5. Review GitHub Actions Alignment

If `.github/workflows` exists:

- Compare `pre-push` with ordinary CI jobs.
- Ensure local push gates cover format, lint, typecheck, tests, build, and generated-file checks that normally fail PR/push CI.
- Do not include deploy, release, production, native-signing, cloud, or manual-only workflow jobs unless the repo already exposes them as the local CI gate.
- Prefer updating the repo's shared `ci` or `check` task over copying long workflow logic into `lefthook.yml`.

Completion condition: local push checks catch normal CI failures, and intentional gaps are reported.

### 6. Verify And Review

Run the cheapest meaningful validation first, then heavier checks when appropriate:

- Validate hook config through repo tooling, for example `pnpm exec lefthook validate` or `mise exec -- lefthook validate`.
- To exercise a hook with specific files, check `lefthook run --help` for the installed version. Lefthook v2 uses repeated `--file <path>` flags, not `--files`.
- Run `git diff --check`.
- Run focused formatter/linter commands for touched hook/task files.
- Run the selected `pre-push` gate when practical. If it is too expensive for the current turn, run the underlying focused checks and clearly report the skipped full gate.
- Manually review the diff for unrelated changes, noisy hooks, duplicated policy, and commands that depend on unstated local environment.

Completion condition: verification commands and any skipped full gates are explicit in the final report.
