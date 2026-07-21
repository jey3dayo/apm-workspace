# task_config.includes

Use `[task_config].includes` when you intentionally split a large mise setup across multiple task files.

## When to Use

- Personal `~/.config/mise` or dotfiles environments
- One maintainer supports multiple environments such as default, CI, Windows, or Raspberry Pi
- Shared task families are easier to manage as separate files like `tasks/format.toml` and `tasks/lint.toml`
- Large project-local repositories with clear task-family ownership, such as DB, env/dotenvx, secrets, infra, deploy, or tools

## When Not to Use

- Ordinary small to medium project repositories
- Small to medium `mise.toml` files that still fit comfortably in one file
- Cases where splitting would make onboarding or CI harder to understand

For normal repositories, prefer a single project-local `mise.toml`. For project-local task-family split rules, see `task-family-splitting.md`.

## Recommended Layout

```text
~/.config/
├── .mise.toml
└── mise/
    ├── config.toml
    ├── config.default.toml
    ├── config.ci.toml
    ├── config.windows.toml
    ├── tasks/            # explicit opt-in user-global tasks
    └── local-tasks/      # loaded only by ~/.config/.mise.toml
        ├── format.toml
        ├── lint.toml
        └── ci.toml
```

`~/.config/mise/tasks/` is mise's auto-loaded global task directory. Treat it as explicit opt-in: do not put a task there merely because it operates machine-wide state or the dotfiles repository owns it. Use a separate directory such as `local-tasks/` for files loaded through the dotfiles repository's `[task_config].includes`.

## Recommended Responsibilities

- `config.toml`
  - Shared settings only
  - `settings`, `env`, package-manager defaults
- `config.default.toml`, `config.ci.toml`, `config.windows.toml`
  - Environment-specific `[tools]`
  - Per-environment job counts and backend toggles
- `.mise.toml`
  - Local task entrypoint
  - `[task_config].includes` list
  - Optional directory-local hooks or env overrides

## Example

```toml
# ~/.config/mise/config.toml
[settings]
experimental = true

[settings.npm]
package_manager = "pnpm"
```

```toml
# ~/.config/mise/config.default.toml
[tools]
node = "lts"
python = "3.12"
shellcheck = "<verified-version>"
shfmt = "<verified-version>"
taplo = "<verified-version>"
"npm:prettier" = "<verified-version>"
"npm:tsx" = "<verified-version>"
```

```toml
# ~/.config/.mise.toml
[task_config]
includes = [
  ".config/mise/local-tasks/format.toml",
  ".config/mise/local-tasks/lint.toml",
  ".config/mise/local-tasks/ci.toml",
]

[hooks]
enter = "mise run --quiet setup-env"
```

## Task File Example

```toml
# ~/.config/mise/local-tasks/lint.toml
["lint:shell"]
description = "Check shell scripts"
run = "fd -e sh -X shellcheck"

["lint:yaml"]
description = "Check YAML files"
run = "fd -e yml -e yaml -X yamllint -f parsable"

["check:lint"]
description = "Aggregate lint checks"
depends = ["lint:shell", "lint:yaml"]
```

## Design Rules

- Split by responsibility, not by arbitrary file size
  - Good: `format.toml`, `lint.toml`, `ci.toml`
  - Bad: `tasks-a.toml`, `tasks-b.toml`
- Keep tool declarations near environment files, not task files
- Reserve `~/.config/mise/tasks/` for entry points the user explicitly wants to appear in every repository; machine-wide scope alone is insufficient
- Put dotfiles-repository checks and maintenance in `local-tasks/` (or another non-global directory) and load them from `~/.config/.mise.toml`
- Keep credential-dependent or destructive task families local unless the globally exposed subset is split and independently justified
- Wire added tools into real tasks
  - If `shellcheck` or `shfmt` is added under `[tools]`, expose `lint:shell` or `format:shell`
- Keep project-local examples separate from user-global examples
- In project-local repos, keep the root `mise.toml` as the entrypoint and split only responsibility-bound task families
- Prefer `depends` for aggregation-only tasks inside included task files

## Tradeoffs

### Benefits

- Cleaner separation between settings, tools, and task families
- Easier environment switching
- Lower edit conflict risk in personal dotfiles

### Costs

- Harder to understand at first glance
- More files to navigate
- Usually unnecessary for normal repos

## Review Checklist

- Is this a user-global or multi-environment setup?
- Should each task be visible from unrelated repositories, or only while working in the dotfiles repository?
- Is global visibility explicitly useful, rather than inferred from machine-wide data scope?
- Are global tasks cwd-independent through an explicit `dir` and stable runner path?
- If this is a project-local setup, is the split justified by clear task-family ownership?
- Would a single `mise.toml` be simpler?
- Are includes grouped by responsibility?
- Are tools defined in environment config files instead of task files?
- Are added tools actually wired into `format:*`, `lint:*`, or `ci:*` tasks?
- Are aggregation-only tasks using `depends` instead of serial `run` chains?
