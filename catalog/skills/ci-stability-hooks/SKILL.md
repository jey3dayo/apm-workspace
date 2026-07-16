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
- File classes covered by CI format/lint tasks: at minimum JS/TS, JSON, CSS, Markdown, YAML, TOML, shell, Python, Dockerfile, Rust, Nix, and repo-specific config files when those tasks exist.

Prefer repository-defined tasks over inventing commands. If both `mise` and package scripts exist, treat `mise` as the orchestration layer when the repo already uses it for CI.

Completion condition: local hooks can be derived from existing repo commands or clearly justified additions.

### 3. Choose The Gate Split

Use this split unless the repo contract says otherwise:

- Put staged-file formatters and very fast linters in `pre-commit`.
- Keep test suites, builds, slow typechecks, network access, and full aggregate commands out of `pre-commit`; a commit gate that runs full CI pushes developers toward bypassing hooks.
- Put the repository CI-equivalent gate in `pre-push`.
- Prefer registering `mise run ci`'s constituent sub-tasks as separate `pre-push` jobs over one aggregate `run: mise run ci` job. An aggregate job only reports pass/fail for the whole gate; separate jobs show which stage failed and let Lefthook's per-job summary track progress. Inspect the aggregate task definition (e.g. `mise run ci`'s `run` block or `depends`) to enumerate its stages, and mirror that same order as one `pre-push` job per stage.
- Fall back to one aggregate `run: mise run ci` (or `mise run check`, `pnpm run ci`, `pnpm run check`) only when the aggregate task has no discoverable sub-tasks to split, or when the repo contract explicitly asks for a single gate.

For `pre-commit`, prefer named jobs per tool instead of one aggregate `mise run format`: a failed aggregate hides which formatter failed, while separate jobs make failures diagnosable. `mise run format` remains useful as a full auto-format pass before push or PR.

Before accepting the split, compare the CI/task inventory from step 2 with the hook file globs. If CI has a fast format or lint gate for a file class, add an equivalent staged-file job unless it is too slow, unsafe, or impossible to run on filenames. Do not forget non-code config surfaces such as `*.yml`, `*.yaml`, `*.toml`, workflow files, root package manager config, and repo-local tool config.

Completion condition: commit hooks stay fast and push hooks block the failures most likely to break CI.

### 4. Implement Lefthook

When adding or updating Lefthook:

- Use `glob`, `{staged_files}`, and `stage_fixed: true` for staged-file formatters when supported.
- Add separate jobs for fast non-code CI checks when the repo has them, such as YAML lint (`yamllint`), TOML format (`taplo`), Markdown lint, workflow lint, or lock/config validation.
- Use package-manager prefixes that match the repo: `pnpm exec`, `mise exec --`, or direct commands managed by the repo.
- Add Lefthook through the existing tool source: package dependency for package-managed repos, `mise` tool config for mise-managed dotfiles or tool repos.
- Add an install helper only when the repo already has a scripts/tasks pattern for setup.
- If the repo already uses `pnpm.onlyBuiltDependencies`, include `lefthook` there when needed for install stability.
- Preserve `.pre-commit-config.yaml` during a migration unless the user explicitly asks to remove it.
- Remember that `lefthook run` can synchronize `.git/hooks` and `stage_fixed: true` can stage modified files. Report that side effect when it occurs.
- If a Lefthook child exits but the hook process remains or Ctrl-C does not return, set `piped: true` on that hook; verify a known-failing job returns nonzero and leaves no hook or child process behind.

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
    - name: format:check
      run: mise run format:check
    - name: test:unit:ci
      run: mise run test:unit:ci
    - name: lint
      run: mise run lint
    - name: test:rust
      run: mise run test:rust
    - name: build
      run: mise run build
```

Lefthook runs a job list's entries sequentially by default (no `parallel: true`), so ordering the split jobs to match the aggregate task's own stage order preserves fail-fast behavior while naming which stage failed.

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
