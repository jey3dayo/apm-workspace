# task_config.includes

Use `[task_config].includes` when you intentionally split a large user-global mise setup across multiple task files.

## When to Use

- Personal `~/.config/mise` or dotfiles environments
- One maintainer supports multiple environments such as default, CI, Windows, or Raspberry Pi
- Shared task families are easier to manage as separate files like `tasks/format.toml` and `tasks/lint.toml`

## When Not to Use

- Ordinary project repositories
- Small to medium `mise.toml` files that still fit comfortably in one file
- Cases where splitting would make onboarding or CI harder to understand

For normal repositories, prefer a single project-local `mise.toml`.

## Recommended Layout

```text
~/.config/
├── .mise.toml
└── mise/
    ├── config.toml
    ├── config.default.toml
    ├── config.ci.toml
    ├── config.windows.toml
    └── tasks/
        ├── format.toml
        ├── lint.toml
        └── ci.toml
```

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
shellcheck = "latest"
shfmt = "latest"
taplo = "latest"
"npm:prettier" = "latest"
"npm:tsx" = "latest"
```

```toml
# ~/.config/.mise.toml
[task_config]
includes = [
  ".config/mise/tasks/format.toml",
  ".config/mise/tasks/lint.toml",
  ".config/mise/tasks/ci.toml",
]

[hooks]
enter = "mise run --quiet setup-env"
```

## Task File Example

```toml
# ~/.config/mise/tasks/lint.toml
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
- Wire added tools into real tasks
  - If `shellcheck` or `shfmt` is added under `[tools]`, expose `lint:shell` or `format:shell`
- Keep project-local examples separate from user-global examples
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
- Would a single `mise.toml` be simpler?
- Are includes grouped by responsibility?
- Are tools defined in environment config files instead of task files?
- Are added tools actually wired into `format:*`, `lint:*`, or `ci:*` tasks?
- Are aggregation-only tasks using `depends` instead of serial `run` chains?
