---
name: mise
description: >-
  Guidance for mise (mise-en-place) as task runner, tool version manager, and
  package manager. Use when working with mise.toml, task definitions and
  dependency graphs (`mise run`, depends/run), `[task_config].includes` and
  DB/env/dotenvx/secrets/tools task-family splitting, tool/package
  centralization (npm:/pipx:), `mise upgrade` and `minimum_release_age`,
  Windows settings (`run_windows`, `config.windows.toml`), or `mise skills add`.
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
   - `config.windows.toml` and `windows_default_*_shell_args` usually belong here unless the repository explicitly vendors its own Windows shell policy

If the request mentions `mise skills add`, personal/global setup, or `~/.config/mise`, treat it as user-global. Otherwise default to project-local.

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

### Aggregation vs alias

- Aggregation tasks (`check`, `lint`, `format`) coordinate independent prerequisites — prefer `depends`-only
- `alias = ["b"]` is optional CLI sugar; a task named `deploy` or `format` is not an alias unless it declares `alias = [...]`

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
- Migration from `global-package.json`, pinning policy, pipx/CI caveats: `references/tool-management.md`

### mise skills add

Treat as a user-global workflow, not project-local task design:

1. Confirm the user is working in a personal/global mise setup
2. Run `mise skills add <skill>`, then `mise install` if it adds tool dependencies
3. Keep reusable automation in shared task files or `.mise.toml`, not ad hoc shell aliases

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
- `references/config-templates.md` — common mise.toml templates
- `references/current-patterns.md` — real-world dotfiles task patterns
- `references/task-family-splitting.md` — project-local split rules for DB/env/secrets/infra/deploy/tools families
- `references/task-config-includes.md` — user-global `[task_config].includes` split guidance
- `references/windows-shells.md` — Windows shell selection, `run_windows` syntax, quoting, generated-file pitfalls
- `references/tool-management.md` — version pinning policy, npm/pipx migration, troubleshooting
- `resources/examples/npm-package-migration.md` — worked npm migration example
- `resources/templates/mise-config-template.toml` — starter template
