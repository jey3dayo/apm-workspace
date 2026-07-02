---
name: apm-repo-bootstrap
description: Use when scanning a repository to create, update, or clean up a repo-local `apm.yml` and install appropriate local APM skills or MCPs. Use for requests like `repo に apm.yml を置いて`, `この repo におすすめ skill 入れて`, `ローカルスキル整理`, `repo-local APM bootstrap`, or moving infra/runtime-specific skills out of global APM. Coordinate with `apm-usage` for global workspace ownership, lockfile rollout, and deployed target rules.
metadata:
  short-description: Bootstrap repo-local APM dependencies
---

# APM Repo Bootstrap

Scan the current repository, choose repo-local APM dependencies from concrete source-tree signals, and create or update the repository's `apm.yml` without turning common global preferences into local clutter.

## Policy

- Keep web/common coding skills global when they match the user's normal day-to-day work.
  - Do not add React, Next.js, TypeScript, UI review, or general frontend best-practice skills to repo-local `apm.yml` by default.
- Treat browser MCPs separately from web skills.
  - Do not add `chrome-devtools` just because the repository is a web app.
  - Prefer `claude-in-chrome` or the Codex Chrome addon first for ordinary browser operation (click, form input, screenshot, console check) when available and sufficient.
  - Add `chrome-devtools` repo-local or on-demand only when the repository needs DevTools-specific depth (Lighthouse audit, performance trace, heap snapshot), project login/session state, local runtime coupling, or repeatable browser verification beyond what `claude-in-chrome`/Codex addon covers.
- Prefer repo-local dependencies for narrower, runtime-specific, infra-specific, presentation-specific, or credential-scoped tools.
  - Terraform skills belong near repositories that actually own Terraform modules, environments, or `.tftest.hcl` tests.
  - Tauri tools belong near repositories that actually own `src-tauri`.
  - Marp/slides/presentation skills belong near repositories that actually contain presentation sources.
  - Project-specific database, SaaS, observability, or private API MCPs belong near the project that owns their credentials and assumptions.
- Existing repo-local entries that no longer match the policy should be removed from `apm.yml`, but do not delete generated targets unless the user explicitly asks.
- Never edit global APM manifests from this skill. Use `apm-usage` for `~/.apm/apm.yml`, global lockfiles, and deployment.

Read `references/recommendations.md` when mapping repository signals to package refs.

## Workflow

1. Inspect the repository before editing.
   - Check `git status --short`.
   - Read existing `apm.yml` if present.
   - Search signals with `rg --files`, including `package.json`, `next.config.*`, `vite.config.*`, `src-tauri/**`, `terraform/**/*.tf`, `**/*.tftest.hcl`, `wrangler.toml`, `*.md`, and presentation sources.
2. Decide dependency scope.
   - Keep global-common web skills out of repo-local manifests unless the user explicitly asks to localize web skills too.
   - Treat MCPs separately from skills; `chrome-devtools` is a browser runtime tool, not a lightweight web skill.
   - Add repo-local skill package refs only when a repository signal matches the recommendation table.
   - Add repo-local MCPs only when the tool depends on that repository's runtime, credentials, browser/session state, or local service state.
3. Create or update `apm.yml`.
   - Preserve existing name, version, description, author, targets, includes, and scripts when present.
   - Merge dependencies without duplicates.
   - Remove entries made obsolete by the policy, especially web/common skills that should stay global.
   - Use `targets: [codex]` or the repository's existing target style.
4. Verify the manifest.
   - Run `apm install --dry-run --target codex` first.
   - If the user asked to install/distribute, run `apm install --target codex`.
   - Report unpinned dependency warnings; do not hide them.
5. Report results.
   - List changed files.
   - List installed skills/MCPs.
   - Mention existing dirty files not owned by this task.
   - State whether generated `.agents/skills/**`, `apm.lock.yaml`, `.gitignore`, or `apm_modules/` changed.

## Safety

- Do not hand-edit `.agents/skills/**` or `apm_modules/**`.
- Do not delete generated APM output as cleanup unless the user explicitly asks.
- Do not overwrite unrelated local edits. If `apm.yml` already has unrelated user changes, merge carefully.
- Prefer dry-run only unless the request clearly says to install, distribute, or place the APM setup.
- Keep the resulting `apm.yml` small. A local manifest is useful when it expresses what is special about the repository.
