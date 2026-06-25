---
name: quiet-command-auditor
description: Use when auditing noisy test, build, lint, package-manager, or CI commands before reducing output; deciding between tool-native quiet/silent/minimal options and optional agent-side compression; proposing changes that keep failures visible while suppressing successful boilerplate. Trigger when the user asks to audit noisy commands, quiet logs, reduce context, silence successful tests, or make CI less noisy. Do not edit command definitions unless the user explicitly approves the proposed change.
---

# Quiet Command Auditor

## Core Rule

Audit first, propose second, edit only after approval.

Prefer tool-native quiet, silent, minimal, non-color, or reporter options when they preserve failure diagnostics. Use agent-side compression only when the user explicitly asks for it or when changing the underlying command would make human CI logs less useful.

Do not silence output by redirecting to `/dev/null`, dropping stdout or stderr, adding `|| true`, or hand-rolling `grep` / `sed` filters. If the only available option is lossy redirection or filtering, report that no safe quieting option was found.

## Workflow

1. Locate the command owner.
   - Check `mise.toml`, included `mise/*.toml`, `package.json`, CI workflow YAML, Makefile or scripts.
   - Distinguish aggregate tasks from leaf tasks. Change leaf commands, not broad wrappers, unless the wrapper owns the real behavior.
   - If `mise` only calls a package script, place tool options in `package.json`. If `mise` owns the actual command, place options in `mise`.
2. Classify the command.
   - Good candidates: test, lint, format check, typecheck, static analysis.
   - Usually avoid changing command output: install, build, deploy, Docker, cloud CLIs, long CI-log inspection.
   - Default exclude: watch, dev server, interactive commands, destructive commands, secret/env decrypt commands, production apply/destroy commands.
3. Inspect the current noise.
   - Separate startup banners, repeated success rows, progress bars, summaries, warnings, failure diagnostics, artifacts and annotations.
   - Treat warnings, retry messages, slow-test signals, coverage/report paths, Terraform plans, GitHub Actions `::error::` / `::warning::`, and intentional phase `echo` lines as useful until proven otherwise.
4. Propose safe options.
   - Prefer options that suppress passing output while preserving failures.
   - Explain what disappears, what remains, and how to get verbose output back.
   - Include an agent-side compression option only when the user mainly wants to reduce agent context instead of changing CI or human terminal logs.
5. Wait for approval before editing command definitions.
6. After approval, make the smallest change and verify.
   - Run the changed command or the narrowest relevant command.
   - Confirm successful boilerplate is reduced, exit code semantics still work, and a verbose escape hatch remains.

## Recommendation Order

1. Tool-native option that keeps failures visible.
2. Tool-native reporter plus console-output control when both surfaces are noisy.
3. Optional agent-side compression without changing project behavior.
4. No change, with explanation, when the safe options would hide useful diagnostics.

## Common Patterns

### Vitest

Use reporter controls and console controls separately.

```bash
vitest run --project unit --silent=passed-only --reporter=minimal
```

- `--silent=passed-only` suppresses console output from passing tests while preserving logs from failing tests.
- `--reporter=minimal` reduces passed-test result rows and keeps failure output.
- Debug escape hatch: `--silent=false --reporter=verbose`.

### Optional Agent-Side Compression

Use an agent-side compression wrapper only when the command output should remain unchanged for humans or CI, but should be compact for the agent.

```bash
<compression-wrapper> test mise run test:unit
<compression-wrapper> vitest run --project unit
<compression-wrapper> proxy <command>
```

- Use this only when the user has selected a compression wrapper for the task.
- If filtered output is insufficient, rerun the command raw or through the wrapper's raw-output escape hatch.

### CI Workflows

Do not remove GitHub Actions annotations or failure summaries.

- Prefer changing the underlying tool command only when the CI log remains diagnosable.
- Prefer raw `gh` output for remote logs unless the user explicitly asks for agent-side compression.
- Keep artifacts, report paths, Terraform plans, Docker image tags, and deployment revision output.

### Build, Install, Deploy, Cloud

Be conservative. Build and deploy logs often contain the only useful failure context.

- Prefer raw commands or tool-native quiet modes for local agent work.
- Avoid making CI build logs quieter unless the tool has a documented mode that keeps diagnostics.
- Do not quiet production apply, destroy, decrypt, or approval-gated tasks by default.

## Proposal Format

```markdown
Target: `<command>`
Owner: `<file>` -> `<leaf command>`

Current noise:

- <repeated success/progress output>
- <useful output to keep>

Recommendation:

1. `<candidate command or diff>`
   - Removes: <what disappears>
   - Keeps: <failures, summary, annotations, artifacts>
   - Escape hatch: <verbose/raw command>
   - Scope: <local, CI, agent context>

Approval needed before editing:

- <files that would change>
```

## Guardrails

- Keep final summaries by default so success, counts and duration remain visible.
- Do not equate quieting with secret masking. Secrets need separate masking and redaction controls.
- Do not change exit-code behavior.
- Do not use lossy shell pipelines to hide output.
- Do not hide warnings without explicitly calling out the risk.
- Do not edit command definitions when the user only asked for an audit or proposal.
