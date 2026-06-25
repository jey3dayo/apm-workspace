# MCP Placement

Use this reference when deciding whether an MCP server should be global, repo-local, on-demand, or not installed.

## Decision Classes

| Class            | Use when                                                                                                                           | Typical examples                                                                   |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `global`         | Cross-repo, frequent, low-risk, low-context-noise foundation                                                                       | docs lookup, lightweight research, local notification, core agent bridge           |
| `repo-local`     | Useful only when a specific project runtime, framework, or app is present                                                          | Tauri tools, browser/devtools for frontend repos, project DB tools                 |
| `on-demand`      | Useful but heavy, rare, visual, highly privileged, or likely to slow startup/status checks                                         | screen automation, browser automation, one-off external service connectors         |
| `do-not-install` | Duplicates built-in capabilities, overlaps an existing connector, is unmaintained, or requires excessive privilege for the benefit | filesystem access when the agent already has FS, stale packages, broad credentials |

## Review Workflow

1. Identify the job the MCP server would do.
2. Check whether the agent or app already has that capability through native tools, plugins, or connectors.
3. Check current public signals when the server choice is trend-sensitive:
   - official repository activity and recent releases
   - package downloads or install base when available
   - docs quality and setup clarity
   - issue volume and unresolved startup/security reports
   - recent community mentions, with X/Twitter treated as anecdotal unless corroborated
   - credible alternatives in the same category
4. Estimate local cost:
   - process count and startup fan-out
   - tool-list noise and wrong-tool risk
   - credential scope and secret handling
   - network dependency
   - impact on client status checks, diff UI, or project startup
5. Choose the narrowest placement that preserves the useful workflow.
6. Record the reason near the source of truth for the runtime configuration.

## Default Placement Heuristics

- Keep docs and research MCPs global only when they are used across many repos and have current maintenance signals.
- Keep notification or core bridge MCPs global when they support every session and have small operational cost.
- Put framework-specific MCPs in the repo that owns the framework or app runtime.
- Put browser, screen, and visual automation MCPs in repo-local or on-demand lanes unless the user explicitly wants them globally.
- Put credentialed SaaS MCPs in the narrowest scope possible and prefer existing authenticated connectors when available.
- Do not install filesystem MCPs just to access local files when the agent runtime already has local filesystem tools.

## Common Current Categories

| Category                                         | Default                              | Notes                                                                                            |
| ------------------------------------------------ | ------------------------------------ | ------------------------------------------------------------------------------------------------ |
| Current docs lookup (`context7`-style)           | `global` or `on-demand`              | Global is reasonable when library/SDK work is frequent; otherwise use on demand or web research. |
| Web research/readers (`jina-reader`-style)       | `global` or `on-demand`              | Global is reasonable for repeated public research; verify auth/search reliability.               |
| Browser/devtools (`chrome-devtools`, Playwright) | `repo-local`                         | Useful for frontend work but often noisy/heavy globally.                                         |
| Tauri tools                                      | `repo-local`                         | Only install where `src-tauri`/Tauri runtime exists.                                             |
| Screen automation (`peekaboo`-style)             | `on-demand`                          | Visual access is situational and can add process/status overhead.                                |
| GitHub/project management                        | `global` only if no connector exists | Avoid duplicating Codex/GitHub/Linear/Gmail/Calendar connectors.                                 |
| Database/SaaS observability                      | `repo-local` or `on-demand`          | Scope credentials narrowly; prefer project-owned env loading.                                    |

## APM-Managed Runtimes

When the source of truth is an APM workspace:

- Use `apm-usage` before editing manifests, lockfiles, catalog guidance, or deployed targets.
- Edit the tracked APM source, such as `apm.yml` or `catalog/**`.
- Do not hand-edit deployed targets such as `~/.codex/config.toml`, `~/.claude/**`, or `~/.agents/skills/**`.
- If repo-local MCP distribution does not exist yet, record the target placement as guidance and keep global registration lightweight.
