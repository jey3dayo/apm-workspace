# Default Distribution Analysis

## Overview

`<distribution-root>/` is a representative bundled distribution root for the legacy Home Manager flow.

It is the source of truth for:

- bundled skills
- bundled rules
- bundled agents

The current Home Manager module does not deploy bundled `<distribution-root>/commands/`.

---

## Structure

```text
<distribution-root>/
├── skills/   (48 directories)
├── rules/    (2 markdown files, including nested paths)
├── agents/   (23 markdown files, including nested agent files)
└── commands/ (legacy directory, not part of active HM deployment)
```

---

## Skills

### Count

- 48 bundled skill directories

### Examples

- `agent-creator`
- `codex-code-review`
- `distributions-manager`
- `nix-dotfiles`
- `task-to-pr`

### Runtime Behavior

- scanned from `<distribution-root>/skills/`
- tagged as `source = "distribution"`
- override external skills with the same ID

---

## Rules

### Count

- 2 bundled rule files

### Examples

- `claude-md-design.md`
- `tools/...`

### Runtime Behavior

- scanned from `<distribution-root>/rules/`
- linked directly into target rules directories

---

## Agents

### Count

- 23 markdown agent files in total, including nested agent paths

### Examples

- `code-reviewer.md`
- `deployment.md`
- `orchestrator.md`
- `kiro/spec-design.md`

### Runtime Behavior

- scanned from `<distribution-root>/agents/`
- merged as `externalAgents // distributionAgents`
- bundled agents win on duplicate IDs

---

## Commands

### Current State

- `<distribution-root>/commands/` may still exist in the tree
- the active Home Manager module does not link bundled commands from `distributionResult.commands`
- top-level commands currently come from external `commandsPath` sources

That means `<distribution-root>/commands/` should not be documented as an active bundled deployment layer.

---

## Verification

```bash
mise run agents:legacy:install
mise run agents:legacy:list 2>/dev/null | jq '.skills[] | {id, source}'
```

Expected observations:

- bundled skills appear as `distribution`
- external selected skills appear with their source names
- bundled agents and rules are linked from `agents/src`

---

## Notes

- Treat `<distribution-root>/` as the canonical bundled source tree
- Do not reintroduce removed legacy layer names into active docs
- If you need bundled command support again, it requires runtime changes, not just documentation changes
