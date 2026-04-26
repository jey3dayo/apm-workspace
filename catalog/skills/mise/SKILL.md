---
name: mise
description: |
  [What] Skill for mise (mise-en-place) task runner, tool version manager, and
  package manager. Covers `mise.toml` structure, task definitions, dependency
  management, tool/package centralization, workflow automation, and skill
  installation via `mise skills add`.
  [When] Use when: users mention "mise", "mise-en-place", "mise.toml",
  `mise run`, `mise format`, `mise check`, `mise deploy`, `mise skills add`,
  task definitions, tool version management, formatter wiring such as
  `nixpkgs-fmt`, or Windows-specific mise settings such as `run_windows`,
  `config.windows.toml`, and `windows_default_*_shell_args`. Also use when
  asked whether a formatter or command is built in. Do not use for dotfile
  migration, Home Manager, Nix Flake, or non-mise `~/.config` management; use
  `nix-dotfiles` instead.
  [Keywords] mise, mise-en-place, mise.toml, tool management, package
  management, npm global, python packages, task runner, run, format, check, deploy,
  skills add, formatter, fmt, nixpkgs-fmt, config.ci.toml,
  config.default.toml
---

# mise - Task Runner Configuration Expert

## Overview

This skill provides specialized guidance for working with mise (mise-en-place), a modern task runner and development environment manager. Evaluate and create mise.toml configurations following 2025 best practices, focusing on task dependencies, parallel execution, and maintainable workflows.

mise combines:

- Task Runner: Execute development workflows with dependency management
- Tool Version Manager: Manage language runtimes and tools
- Environment Manager: Handle project-specific environment variables

## First Response Checklist

Before giving advice, classify the request into one of these two modes and answer from that mode only:

1. Project-local repository mode
   - The user is editing a repository-owned `mise.toml`
   - Prefer a single root `mise.toml` unless the repo clearly uses another structure
   - Use the repo's existing task names, workflow semantics, and source-of-truth rules as authoritative
2. User-global / dotfiles mode
   - The user is managing `~/.config/mise`, personal toolchains, or `mise skills add`
   - `~/.config/.mise.toml` and `[task_config].includes` are valid only when the setup is intentionally user-global or multi-environment
   - `config.windows.toml` and `windows_default_*_shell_args` usually belong here unless the repository explicitly vendors its own Windows shell policy

Do not mix the two modes in one answer. If the request mentions `mise skills add`, personal/global setup, or `~/.config/mise`, treat it as user-global. Otherwise default to project-local.

## Repository Overrides

When the request is about a specific repository, read that repository's local guidance and the actual `mise.toml` before falling back to generic mise advice.

- Prefer repo-local `AGENTS.md`, task docs, and current task names as authoritative
- Derive task meaning from the real `run` / `depends` graph, not from naming alone
- Treat repo-documented source-of-truth and generated-output rules as stronger than this skill's generic defaults
- If the repository already has a dedicated workflow skill for its rollout model, use that skill for repo-specific routing instead of hardcoding those conventions here

If a task description is shorter or slightly ambiguous, classify the operational intent from the implementation first, then report wording clarity as a secondary issue.

## Core Capabilities

### 1. Task Definition Design

Create well-structured task definitions with proper separation of concerns.

#### run - Task Implementation

Define what the task actually does:

- Purpose: Contains the actual commands to execute
- Execution: Runs serially inside the task's shell
- Usage: Core logic, command sequences, inline sub-tasks

### Example

```toml
[tasks.test]
description = "Run test suite"
run = [
  "cargo test --all-features",
  { task = "post-test-metrics" }  # Inline sub-task
]
```

#### depends - Prerequisites

Declare what must complete before this task starts:

- Purpose: Pure declarative prerequisites
- Execution: Builds global DAG, runs once, enables parallelism
- Usage: Ordering constraints, shared setup tasks, fan-out patterns

### Example

```toml
[tasks.test]
description = "Run test suite"
depends = ["build", "lint"]  # Parallel execution
run = "cargo test"
```

### Key Distinction

- `run`: WHAT this task does (imperative)
- `depends`: WHAT must finish BEFORE (declarative)

### 2. Aggregation vs Alias

Treat aggregation tasks and aliases as separate concerns.

#### Aggregation Tasks

- Purpose: Coordinate related checks or workflows
- Preferred shape: Use `depends` when the task mainly aggregates independent prerequisites
- Examples: `format`, `format:check`, `lint`, `check`, `deploy`

#### Alias Property

- Purpose: Provide shorter CLI shortcuts for frequently used tasks
- Usage: Optional `alias = ["b"]` or `alias = ["fmt"]`
- Rule: Do not confuse a workflow task named `deploy` or `format` with an actual alias unless it declares `alias = [...]`

### Alias Strategy

- Single character (`b`, `t`, `l`): Daily-use tasks (build, test, lint)
- Two characters (`cb`, `fmt`, `qa`): Common operations
- Prefix with `+` (`+deploy`, `+all`): Meta-tasks that orchestrate others

### Example

```toml
[tasks.build]
description = "Build project"
alias = ["b"]
run = "cargo build --release"

[tasks.test]
description = "Run tests"
alias = ["t"]
depends = ["build"]
run = "cargo test"

[tasks."+deploy"]
description = "Full delivery pipeline"
depends = ["check", "test", "build"]
```

### 3. Dependency Management

Structure task dependencies for optimal parallelism and correctness.

#### Pattern A: Parallel Fan-Out, Serial Fan-In

```toml
[tasks.build]
run = "cargo build --release"

[tasks.lint]
run = "eslint ."

[tasks.test]
depends = ["build", "lint"]  # build & lint run in parallel
run = "cargo test"
```

#### Pattern B: Meta-Task Orchestration

```toml
[tasks.release]
description = "Build, sign and publish"
run = [
  { task = "build" },
  { task = "sign" },
  { tasks = ["publish-github", "publish-s3"] },  # Parallel
]
```

#### Pattern C: File Task Integration

```bash
#!/usr/bin/env bash
#MISE description="Apply database migrations"
#MISE alias=["dbm"]
#MISE depends=["setup-db"]
prisma migrate deploy
```

### 4. Configuration Structure

Organize mise.toml for maintainability and clarity.

### Recommended Order

1. `[settings]` - Global mise settings
2. `[env]` - Project-wide environment variables
3. `[tools]` - Tool versions
4. `[tasks]` - Task definitions (see internal structure below)

### Exception: User-Global Dotfiles Configuration

For personal `~/.config/mise` setups, a split layout can be better than a single large file:

- Keep `config.toml` settings-only
- Put environment-specific tool definitions in files such as `config.default.toml`, `config.ci.toml`, or `config.windows.toml`
- Load shared task files via `[task_config].includes` from a local `~/.config/.mise.toml`

Use this pattern for user-global dotfiles or environment-switched setups, not for ordinary project repos.
For concrete examples, split-file structure, and do/don't guidance, see `references/task-config-includes.md`.
For Windows shell selection, quoting, `run_windows`, and generated-file pitfalls, see `references/windows-shells.md`.

### Task Section Internal Structure

Within the `[tasks]` section, organize tasks logically by responsibility:

1. Individual Commands - Concrete tasks that perform actual work
   - Example: `format:terraform`, `lint:app`, `build:frontend`
   - Characteristics: Contains `run` with actual commands

2. Aggregation Tasks - Tasks that orchestrate multiple related commands
   - Example: `format`, `lint`, `test`
   - Characteristics: Prefer `depends` when coordinating independent checks or prerequisites

3. Aliases/Meta-Tasks - Top-level orchestration for common workflows
   - Example: `deploy`, `verify`, `upgrade`, `+all`, `release`
   - Characteristics: High-level coordination, often used in CI/CD; may also declare `alias = [...]`

### Naming Model

Prefer one naming model consistently inside a repository:

1. Single-task commands: action-first names
   - Examples: `format`, `validate`, `smoke:catalog`, `prepare:catalog`, `install:catalog`
   - Rule: A reader should infer the immediate action without reading the implementation
2. Orchestration workflows: workflow names
   - Examples: `check`, `verify`, `deploy`, `upgrade`
   - Rule: A reader should infer that the task coordinates multiple lower-level tasks

Avoid mixing these styles arbitrarily. If a task both performs work and orchestrates other tasks, choose the name based on the primary user intent.

### Recommended Comment Structure

```toml
# ========================================
# グローバル設定
# ========================================
[env]
...

[tools]
...

# ========================================
# コマンド（実際の処理を行うタスク）
# ========================================
[tasks."format:terraform"]
...

[tasks."lint:app"]
...

# ========================================
# 集約タスク
# ========================================
[tasks.format]
depends = ["format:terraform", "format:docs"]

# ========================================
# エイリアス / メタタスク
# ========================================
[tasks.deploy]
depends = ["check", "test", "build"]
```

### Example

```toml
# mise.toml
[settings]
jobs = 8
paranoid = true

[env]
RUST_BACKTRACE = "1"
NODE_ENV = "development"

[tools]
node = "24" # Prefer current LTS major; pin patch versions when reproducibility matters
rust = "stable"

[tasks.build]
description = "Build project"
run = "cargo build"
```

### 5. Tool Version Management

Manage language runtimes and global packages in a unified, version-controlled manner.

#### Core Principle: Centralized Package Management

- ✅ DO: Declare ALL npm and Python packages in `mise.toml` using `"npm:<package>"` or `"pipx:<package>"`
- ❌ DON'T: Use `npm install -g` or `pip install --user` - leads to drift and reproducibility issues

### Tool Categories

```toml
[tools]
# Runtimes
node = "24" # Shared repos: prefer concrete LTS major or patch
python = "3.12"
rust = "stable"

# CLI Tools
github-cli = "latest"
shellcheck = "latest"

# NPM Global Packages
"npm:prettier" = "latest"
"npm:typescript" = "latest"
"npm:@fsouza/prettierd" = "latest"

# Python Global Packages
"pipx:black" = "latest"
"pipx:ruff" = "latest"
```

### Migration from global-package.json

1. Convert each dependency to `"npm:<package-name>" = "latest"`
2. Remove `global-package.json` and update docs
3. Run `mise install` to install all tools
4. Verify with `mise ls` and `which <command>`

### Benefits

- Single source of truth for all tools and packages
- Version control and team consistency
- Cross-platform reproducibility
- No global npm/pip pollution

### Versioning Guidance

- Shared repositories: prefer concrete LTS majors or exact patches (`node = "24"` or `node = "24.15.0"`)
- Personal global configs: symbolic channels such as `node = "lts"` can be acceptable when you intentionally want rolling local upgrades

### Formatter Wiring and `mise skills add`

Use `[tools]` for commands that tasks or setup docs actually invoke, including formatters such as `nixpkgs-fmt`.

```toml
[tools]
nixpkgs-fmt = "latest"

[tasks."format:nix"]
description = "Format Nix files"
run = "nixpkgs-fmt nix/**/*.nix"
```

When the user asks about `mise skills add`, treat it as a user-global workflow rather than a project-local task design question:

1. Confirm the user is working in a personal/global mise setup
2. Use `mise skills add <skill>` for installation
3. If that skill also adds tool or package dependencies, follow with `mise install`
4. Keep reusable automation in shared task files or `.mise.toml`, not in ad hoc shell aliases

### Reference

### 6. Advanced Features

Leverage mise's advanced capabilities for complex workflows.

### Additional Dependencies

- `depends_post`: Tasks that run after this task completes
- `wait_for`: Soft dependency (only waits if already running)

### Task Properties

- `retry`: Number of retries on failure
- `timeout`: Maximum execution time
- `dir`: Working directory override
- `env`: Task-specific environment variables

### Example

```toml
[tasks.integration-test]
description = "Integration tests with retry"
depends = ["build", "setup-db"]
depends_post = ["cleanup"]
retry = 2
timeout = "10m"
env = { DATABASE_URL = "postgresql://localhost/test" }
run = "pytest tests/integration"
```

## Best Practices Summary

### File Organization

✅ **DO:**

- Keep single mise.toml at project root
- Place long scripts in `mise-tasks/` or `scripts/`
- Order sections: settings → env → tools → tasks
- Within tasks section: individual commands → aggregation tasks → aliases/meta-tasks
- Use section separator comments for readability (`# === Commands ===`)
- Use descriptive task names and always include `description`
- Prefer `depends` for aggregation-only tasks such as `check`, `verify`, or `lint`
- Use action-first names for single-task commands and workflow names for orchestration tasks
- Add tools to `[tools]` only when they are used directly by tasks or documented setup flows

❌ **DON'T:**

- Embed >3 lines of shell in `run` arrays
- Call `mise <task>` inside run strings (use `{ task = "x" }`)
- Create circular dependencies
- Use conflicting alias names
- Add unused tools that are not wired into tasks, checks, or documented developer workflows

### Task Design

✅ **DO:**

- Use `depends` for prerequisites and parallelism
- Use `run` for core task logic
- Keep tasks focused on single responsibility
- Group related tasks with common prefixes
- Treat `alias = [...]` as optional UX sugar, not as a substitute for well-named aggregation tasks

❌ **DON'T:**

- Mix ordering logic in `run` that belongs in `depends`
- Create deeply nested inline tasks
- Duplicate common setup across tasks (extract to shared task)

### Naming Conventions

✅ **DO:**

- Use lowercase-kebab-case for task names
- Use action-first names for single-task commands (`format`, `validate`, `prepare:catalog`)
- Use workflow names for orchestration tasks (`check`, `verify`, `deploy`, `upgrade`)
- Prefix meta-tasks with `+` only when the repository already uses that convention
- Choose intuitive short aliases
- Document complex task dependencies

## Review Workflow

When reviewing existing mise.toml:

0. Classify the request first: project-local vs user-global / dotfiles
1. Check Structure: Verify section ordering and organization
2. Analyze Dependencies: Review `depends` vs `run` usage
3. Evaluate Parallelism: Identify opportunities for parallel execution
4. Validate Aliases: Check for conflicts and intuitive naming
5. Test DAG: Run `mise task deps <task>` to visualize
6. Check Best Practices: Verify against reference guidelines
7. Performance: Consider compilation time and execution efficiency

For repository-specific reviews, add these checks before proposing changes:

- Does the answer preserve the repo's documented lightweight-check, deep-verify, and deploy semantics where they differ?
- Does it keep refresh, rollout, and deploy semantics distinct where the repo does?
- Does it avoid treating generated outputs as editing surfaces if the repo separates them from authoring surfaces?
- Does it separate "task behavior as implemented" from "description wording that could be clearer"?

### Reference

## Common Issues

### Issue: Nested mise Calls

### Problem

```toml
[tasks.bad]
run = "mise build && mise test"  # ❌ Creates nested processes
```

### Solution

```toml
[tasks.good]
run = [
  { task = "build" },
  { task = "test" }
]
```

### Issue: Wrong Dependency Type

### Problem

```toml
[tasks.test]
run = [
  { task = "build" },  # ❌ Should be depends
  "cargo test"
]
```

### Solution

```toml
[tasks.test]
depends = ["build"]  # ✅ Proper prerequisite
run = "cargo test"
```

### Issue: Missing Parallelism

### Problem

```toml
[tasks.verify]
run = [
  { task = "lint" },
  { task = "test" },
  { task = "build" }
]  # ❌ All serial
```

### Solution

```toml
[tasks.deploy]
depends = ["lint", "test", "build"]  # ✅ Parallel execution
```

### Issue: Windows Shell Mismatch

### Problem

- `run_windows` uses PowerShell syntax, but mise is actually executing tasks through `bash -lc`
- `%USERPROFILE%` is written inside a PowerShell-oriented task body
- Generated files are reformatted by broad formatter tasks and then rejected by exact validation

### Solution

- Inspect which shell mise actually uses on Windows before changing task strings
- Match `run_windows` syntax to that shell, especially env vars, quoting, and script invocation
- If `mise.toml` is generated from a template, update the template or generator instead of only patching the generated file
- Exclude exact generated outputs from generic formatter tasks when the repository validates byte-for-byte serialization

See `references/windows-shells.md` for concrete patterns.

## Integration

### With CI Systems

- Expose a single delivery entry task such as `mise run deploy`
- Pin mise version: `mise use -g mise@2025.10`
- Set `MISE_JOBS=$(nproc)` for parallel execution
- Let mise orchestrate entire build pipeline

### With Development Tools

- Linters: Integrate via tasks with proper dependencies
- Formatters: Create format/format:check task pairs
- Test Runners: Use `depends` for setup tasks
- Build Systems: Coordinate with mise's DAG

## Resources

### references/

Detailed documentation loaded as needed:

- `best-practices.md` - 2025 field-tested best practices, comprehensive guide on run vs depends, command composition patterns
- `current-patterns.md` - Real-world examples from dotfiles project, practical task patterns
- `config-templates.md` - Common mise.toml templates and patterns
- `task-config-includes.md` - When and how to split user-global task files with `[task_config].includes`
- `windows-shells.md` - Windows shell selection, `run_windows` syntax, env var expansion, and generated-file pitfalls
- `tool-management.md` - Tool version management, Centralized Package Management, npm/Python migration guides, troubleshooting

### Usage

## 🤖 Agent Integration

このスキルはmiseタスクランナー設定タスクを実行するエージェントに専門知識を提供します:

### Orchestrator Agent

- 提供内容: mise.toml設計、タスク依存関係管理、ワークフロー最適化
- タイミング: miseタスクランナー設定・最適化時
- コンテキスト:
  - タスク定義ベストプラクティス
  - 依存関係管理（depends, run連鎖）
  - コマンド構成パターン
  - 並列実行とDAG構造

### Code-Reviewer Agent

- 提供内容: mise.toml品質評価、設定レビュー
- タイミング: mise設定レビュー時
- コンテキスト: タスク構造評価、依存関係検証、ベストプラクティス準拠

### Error-Fixer Agent

- 提供内容: mise設定エラー修正、タスク依存関係修正
- タイミング: mise実行エラー対応時
- コンテキスト: 設定エラー診断、依存関係ループ検出、タスク修正

### 自動ロード条件

- "mise"、"mise-en-place"、"mise.toml"に言及
- mise.tomlファイル操作時
- タスク依存関係、エイリアスについて質問
- ワークフロー自動化の最適化要求

### 統合例

```
ユーザー: "mise.tomlのタスク依存関係を最適化"
    ↓
TaskContext作成
    ↓
プロジェクト検出: mise設定
    ↓
スキル自動ロード: mise
    ↓
エージェント選択: orchestrator
    ↓ (スキルコンテキスト提供)
mise依存関係管理パターン + DAG構造最適化
    ↓
実行完了（並列実行可能化、依存関係明確化）
```

## Trigger Conditions

Activate this skill when:

- User mentions "mise", "mise-en-place", "mise.toml"
- Working with task runner configurations
- Questions about task dependencies or aliases
- Need to optimize workflow automation
- Reviewing or creating mise configurations
- Discussion of parallel execution or DAG structures
