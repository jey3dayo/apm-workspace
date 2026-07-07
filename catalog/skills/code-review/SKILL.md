---
name: code-review
description: >-
  Run configurable local code reviews with project-type detection and
  tech-stack-specific criteria. Use when the user asks to review code or a diff
  (staged, recent commit, or branch), requests a quality assessment or
  star-rated evaluation, or wants a review that integrates project-specific
  guidelines. Targets local changes, optionally addresses open PR comments, and
  reports results in Japanese.
metadata:
  short-description: Local code review with project detection
  argument-hint: "[--simple] [--staged|--recent|--branch <name>] [--with-impact] [--fix]"
---

# Code Review — Local Code Quality Assessment

Dual-mode local code review: detect the project type, integrate tech-stack-specific criteria, and deliver contextual, actionable feedback. All review results are output in Japanese.

## Execution Contract

- Review target selection:
  - Respect explicit target flags first: `--staged`, `--recent`, `--branch <name>`
  - If no target flag is given, fall back in order: staged changes → previous commit diff → diff against the primary development branch → recently modified reviewable files
  - Resolve the primary development branch in order: explicit `--branch` target → repo default branch from remote → `main` → `master`
  - Treat reviewable files as human-authored source, config, test, and narrowly relevant documentation; exclude generated artifacts, caches, vendor trees, and lockfiles unless the user explicitly asks for them
- Safety:
  - Do not create automatic git checkpoints, staging operations, or review-only commits
  - Do not discard changes or propose destructive rollback commands as part of normal review flow
  - Dirty worktrees are valid review targets; adapt to the current state without mutating unrelated files
- Optional tooling:
  - `--with-impact`, `--deep-analysis`, and `--verify-spec` are best-effort; if semantic tooling such as Serena is unavailable, continue with the standard detailed review and state that the optional analysis was skipped
  - If a referenced stack-specific skill is unavailable, keep the same review lens and continue with generic criteria instead of blocking
- Simple mode execution:
  - Prefer parallel specialist passes; if parallel subagents are unavailable, review the same four lenses sequentially: security, performance, code quality, architecture
  - Keep simple mode output severity-based; the star rating system belongs to detailed mode
- PR comment handling:
  - Review the code first, then optionally check open PR comments
  - If there is no PR, `gh` is unavailable, or authentication fails, skip comment handling silently unless the user asked for it explicitly
- No-signature policy (CRITICAL): never add AI attribution anywhere — no `Co-authored-by: Claude`, no "Generated with Claude Code", no emojis in commits, PRs, issues, or git content

## Review Modes

### Detailed Mode (default)

Comprehensive quality assessment: star-rated evaluation across dimensions, project type auto-detection, tech-stack skill integration, improvement proposals with action plans, optional Serena impact analysis.

Use for quality gates, pre-release assessment, architecture evaluation, mentoring, and quality baselines. Execution guide: `references/detailed-mode.md`.

### Simple Mode (`--simple`)

Quick practical analysis: parallel specialist passes (security, performance, quality, architecture), severity-classified findings, immediate actionable fixes.

Use for daily development, quick sanity checks, and CI/CD integration. Execution guide: `references/simple-mode.md`.

## Options

| Category          | Flag              | Effect                            |
| ----------------- | ----------------- | --------------------------------- |
| Mode              | `--simple`        | Simple mode (default: detailed)   |
| Target            | `--staged`        | Staged changes only               |
| Target            | `--recent`        | Previous commit only              |
| Target            | `--branch <name>` | Diff against the specified branch |
| Serena (detailed) | `--with-impact`   | API change impact analysis        |
| Serena (detailed) | `--deep-analysis` | Deep semantic analysis            |
| Serena (detailed) | `--verify-spec`   | Spec consistency verification     |
| Workflow          | `--fix`           | Apply auto-fix                    |
| Workflow          | `--create-issues` | Create GitHub issues              |
| Workflow          | `--learn`         | Record learning data              |
| Workflow          | `--no-comments`   | Skip PR review comment check      |

## Configuration

Configuration sources, in priority order:

1. Project config: `.code-review-config.json` in project root, or `.claude/code-review-config.json`
2. User config: `~/.claude/code-review/custom-projects.json`
3. Built-in defaults: `config/default-projects.json`

Project-specific review guidelines are auto-integrated into evaluation criteria when found at `./.claude/review-guidelines.md`, `./docs/review-guidelines.md`, or `./docs/guides/review-guidelines.md`. Format and customization examples: `references/project-customization.md`.

## Project Detection and Tech-Stack Criteria

Detect the project type (Next.js fullstack, Go clean architecture, Go API, React SPA, TypeScript Node.js, generic fallback) and apply the matching tech-stack criteria: typescript, react, golang, security, clean-architecture, semantic-analysis.

Detection algorithm, per-type criteria, and priority rules: `references/tech-stack-skills.md`. Detector definitions: `config/default-projects.json`.

## Quality Standards

All reviews must:

- Respond in Japanese
- Present findings first, ordered by severity, with specific file:line references
- Include concrete code examples and actionable remediation steps
- Respect the no-signature policy
- State explicitly when no findings were found

Star rating definitions and per-level criteria for detailed mode: `references/evaluation-framework.md`.

## References

Loaded as needed:

- `references/detailed-mode.md` — detailed mode execution guide
- `references/simple-mode.md` — parallel sub-agent execution guide
- `references/evaluation-framework.md` — star rating system definition
- `references/project-customization.md` — guidelines integration and config format
- `references/tech-stack-skills.md` — project detection and tech-specific criteria
- `references/pr-comment-integration.md` — post-review PR comment handling
- `examples/review-workflows.md` — practical workflows
- `examples/troubleshooting-solutions.md` — common issues and solutions

## Related

- `gh-fix-ci` — GitHub Actions CI failure diagnosis
- `gh-address-comments` — PR review comment handling
