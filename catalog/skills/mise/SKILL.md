---
name: mise
description: >-
  Guidance for mise (mise-en-place) as task runner, tool version manager, and
  package manager. Use when working with mise.toml, task definitions and
  dependency graphs (`mise run`, depends/run), `[task_config].includes` and
  global-vs-repository task placement (`~/.config/mise/tasks` vs local includes),
  DB/env/dotenvx/secrets/tools task-family splitting, tool/package
  centralization (npm:/pipx:), `mise upgrade` and `minimum_release_age`,
  Windows settings (`run_windows`, `config.windows.toml`), `mise skills add`,
  `mise bootstrap` and its config sections (`[bootstrap.packages]`,
  `[dotfiles]`, launchd/systemd units), `mise dotfiles apply`, or migrating a
  Brewfile to mise bootstrap.
  For `~/.apm` rollout work (apm.yml, lockfile, which APM task to run),
  coordinate with `apm-usage`. For Home Manager / Nix Flake dotfiles, use
  `nix-dotfiles`.
---

# mise - Task Runner Configuration

Design, review, and fix `mise.toml` configurations: task dependency graphs, tool/package management, and workflow automation.

## First Response Checklist

Classify the request into one mode and answer from that mode only:

1. Project-local repository mode — the user is editing a repository-owned `mise.toml`.
   - Prefer a single root `mise.toml` for small or medium task sets
   - For large repos, use `[task_config].includes` only when task families have clear owners (DB, env/dotenvx, secrets, infra, deploy, tools) — see `references/task-family-splitting.md`
   - Treat the repo's existing task names, workflow semantics, and source-of-truth rules as authoritative
2. User-global / dotfiles mode — the user is managing `~/.config/mise`, personal toolchains, or `mise skills add`.
   - Split layouts are valid here: settings-only `config.toml`, environment files such as `config.default.toml` / `config.ci.toml` / `config.windows.toml`, shared task files via `[task_config].includes` — see `references/task-config-includes.md`
   - Treat `~/.config/mise/tasks/` as an explicit opt-in surface for tasks intentionally available from any directory; keep dotfiles maintenance in a separate directory such as `~/.config/mise/local-tasks/` by default
   - `config.windows.toml` and `windows_default_*_shell_args` usually belong here unless the repository explicitly vendors its own Windows shell policy

If the request mentions `mise skills add`, `mise bootstrap`, `[dotfiles]`, personal/global setup, or `~/.config/mise`, treat it as user-global. Otherwise default to project-local.

## Global vs Repository-Local Tasks

- Determine both operational scope and exposure need from the real `dir`, runner path, data paths, environment and credential dependencies, and intended invocation. Do not infer placement from a family name such as `backup` or from machine-wide data scope alone.
- Default dotfiles and PC-maintenance tasks to repository-local includes even when they operate machine-wide state. Versioning and operating machine configuration in `~/.config` does not require exposing the commands in unrelated repositories.
- Use `~/.config/mise/tasks/` only when the user explicitly wants repeated cross-directory invocation and the whole exposed task family is suitable for that visibility.
- Keep credential-dependent or destructive task families repository-local by default. If only a safe subset truly needs global access, split that subset instead of exposing sibling tasks such as `restore-inplace`, `prune`, or `cleanup`.
- Keep a project task repository-local when it operates one repository's files, service, environment, credentials, or lifecycle. Define it in that repository's `mise.toml` or repository-local includes.
- Keep mise task placement separate from Agent skill placement. Task descriptions plus a named helper are often sufficient; add an Agent skill only when reusable, non-obvious operational guidance exceeds the task interface. Coordinate APM placement with `apm-usage` when that is the actual request.

## Repository Overrides

When the request targets a specific repository, read its local guidance and the actual `mise.toml` before falling back to generic advice:

- Prefer repo-local `AGENTS.md`, task docs, and current task names as authoritative
- Derive task meaning from the real `run` / `depends` graph, not from naming alone
- Repo-documented source-of-truth and generated-output rules override this skill's generic defaults
- If the repository has a dedicated workflow skill for its rollout model, use that skill for repo-specific routing

## Core Rules

### run vs depends

- `run`: WHAT this task does (imperative, executes serially)
- `depends`: WHAT must finish BEFORE (declarative, builds global DAG, enables parallelism)

```toml
[tasks.test]
description = "Run test suite"
depends = ["build", "lint"]  # build & lint run in parallel
run = "cargo test"
```

- Never call `mise <task>` inside run strings — use `{ task = "x" }`
- Never put ordering logic in `run` that belongs in `depends`
- Keep >3 lines of shell out of `run` arrays; place long scripts in `mise-tasks/` or `scripts/`
- Treat task TOML as an interface: keep its description, working directory, environment, dependencies, platform route, and one runner; move branching, cleanup, and command sequences into a named helper.
- Keep routine aggregate tasks non-destructive. Put reset, clean, prune, deploy, and in-place restore behind explicitly named tasks rather than including them in a generic `update`, `check`, or `ci` task.

### Aggregation vs alias

- Aggregation tasks (`check`, `lint`, `format`) coordinate independent prerequisites — prefer `depends`-only
- `alias = ["b"]` is optional CLI sugar; a task named `deploy` or `format` is not an alias unless it declares `alias = [...]`

### Entry points vs internal sub-tasks (`hide = true`)

- When a task exists only as a `depends` component of an aggregate (e.g. `lint:eslint`, `lint:stylelint` under `lint`), keep it as a separate task for DAG parallelism but mark it `hide = true` so `mise tasks` lists only user-facing entry points
- Hidden tasks still run via `depends` and remain directly runnable with `mise run <name>`; only listing/completion visibility changes
- Prefer "hide internal parts" over "inline them into the aggregate's `run` list" — inlining serializes independent work and loses parallelism
- If many sub-tasks are thin 1:1 wrappers around package-manager scripts, move the shell implementation to the package scripts (source of truth) and keep mise tasks as declarations of entry points + DAG only

### Configuration structure

Section order: `[settings]` → `[env]` → `[tools]` → `[tasks]`.
Within `[tasks]`: individual commands → aggregation tasks → aliases/meta-tasks, with separator comments (`# === Commands ===`).

### Naming

- Single-task commands: action-first names (`format`, `validate`, `prepare:catalog`)
- Orchestration workflows: workflow names (`check`, `verify`, `deploy`, `upgrade`)
- lowercase-kebab-case, always include `description`, group related tasks with common prefixes
- Prefix meta-tasks with `+` only when the repository already uses that convention

### Tool and package management

- Declare ALL npm/Python packages in `[tools]` as `"npm:<pkg>"` / `"pipx:<pkg>"`; never `npm install -g` or `pip install --user`
- Shared repositories: pin concrete LTS majors or exact patches (`node = "24"` or `node = "24.15.0"`); personal global configs may use symbolic channels (`node = "lts"`)
- Resolve the newest acceptable version first, then record the concrete version — no floating channels in committed configs or CI
- Add tools to `[tools]` only when tasks or documented setup flows actually invoke them
- pnpm is the pinning exception: mise only bootstraps it with a loose major pin (`pnpm = "11"`); the exact version is owned by each repository's `package.json` `packageManager` field (pnpm 10+ self-management switches automatically). Do not use corepack — Node 25+ no longer ships it
- Migration from `global-package.json`, pinning policy, pipx/CI caveats: `references/tool-management.md`

### mise skills add

Treat as a user-global workflow, not project-local task design:

1. Confirm the user is working in a personal/global mise setup
2. Run `mise skills add <skill>`, then `mise install` if it adds tool dependencies
3. Keep reusable automation in shared task files or `.mise.toml`, not ad hoc shell aliases

## mise bootstrap (user-global / dotfiles mode)

`mise bootstrap` (v2026.6.6+, completed v2026.6.14) is declarative machine setup: OS packages, repos, dotfiles, macOS defaults, launchd/systemd units, login shell, tools, and a final `[tasks.bootstrap]`. Classify these requests as user-global / dotfiles mode.

- Config keys must be nested tables (`[bootstrap.packages]`, not flat `bootstrap = ...`)
- Package backends: apk/apt/dnf/pacman/brew/brew-cask/mas; cask support is native (no Homebrew required); pin versions via name suffix (`brew:postgresql@17`), values are `"latest"`
- `packages import` is brew-formulae-only; `packages prune` is opt-in and prefix-inventory based — always `--dry-run` first
- Declarative sections converge idempotently; the custom `[tasks.bootstrap]` hook must be kept idempotent by the user

Sections, subcommands, prune safety, and Brewfile migration: `references/bootstrap.md`.

## Review Workflow

0. Classify the request: project-local vs user-global / dotfiles
1. Structure: section ordering and task organization
2. Dependencies: `depends` vs `run` usage; run `mise task deps <task>` to visualize the DAG
3. Parallelism: aggregation tasks that serialize independent work
4. Aliases: conflicts and intuitive naming
5. Task families: many DB/env/dotenvx/secrets/infra/deploy/tools tasks → consider responsibility-based include files

For repository-specific reviews, additionally verify the answer:

- Preserves the repo's documented lightweight-check, deep-verify, refresh, and deploy semantics where they differ
- Does not treat generated outputs as editing surfaces when the repo separates them from authoring surfaces
- Does not bake local Windows workstation PATH/shell failures into a mac/Linux-first task contract
- Separates task behavior as implemented from description wording that could be clearer

## Common Issues

| Issue                                                | Fix                                                                        |
| ---------------------------------------------------- | -------------------------------------------------------------------------- |
| `run = "mise build && mise test"` (nested processes) | `run = [{ task = "build" }, { task = "test" }]`                            |
| `{ task = "build" }` at the head of `run`            | Move to `depends = ["build"]`                                              |
| Serial `{ task = ... }` list of independent tasks    | Aggregate with `depends` for parallel execution                            |
| `run_windows` syntax mismatched with actual shell    | Inspect the real shell first; see `references/windows-shells.md`           |
| Generated `mise.toml` rejected after formatting      | Fix the template/generator; exclude generated outputs from formatter tasks |

## References

Load as needed:

- `references/best-practices.md` — full run-vs-depends mental model, command composition patterns, advanced features (`depends_post`, `wait_for`, `retry`, `timeout`), CI integration, performance
- `references/bootstrap.md` — mise bootstrap sections, packages subcommands/backends, prune safety, Brewfile migration
- `references/config-templates.md` — common mise.toml templates
- `references/current-patterns.md` — real-world dotfiles task patterns
- `references/task-family-splitting.md` — project-local split rules for DB/env/secrets/infra/deploy/tools families
- `references/task-config-includes.md` — user-global `[task_config].includes` split guidance
- `references/windows-shells.md` — Windows shell selection, `run_windows` syntax, quoting, generated-file pitfalls
- `references/tool-management.md` — version pinning policy, npm/pipx migration, troubleshooting
- `resources/examples/npm-package-migration.md` — worked npm migration example
- `resources/templates/mise-config-template.toml` — starter template
