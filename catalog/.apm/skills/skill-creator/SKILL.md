---
name: skill-creator
description: Use when creating, migrating, or updating a managed skill for this `~/.apm` workspace, or when deciding where a new skill should live. Create skills in `~/.apm/catalog/.apm/skills/<id>/`, treat `~/.config/agents/src/**` as a mirror, and finish with `mise run stage-catalog`.
---

# Skill Creator

## Overview

This is the repo-specific `skill-creator` for this workspace.

Use it to create or update skills that belong to the managed catalog in this repository.

## Use This Skill When

- A user asks to create a new skill in this repository
- A user wants to migrate a skill from runtime or mirror paths into the managed catalog
- A user wants to rename, split, or replace a managed skill
- A user is unsure whether to work in `catalog/.apm/skills/`, `~/.config/agents/src/skills/`, or `~/.codex/skills/`

If the user is not yet sure whether the right artifact is a skill, agent, command, or rules file, use `knowledge-creator` first.

## Hard Rules

- Author managed skills only in `~/.apm/catalog/.apm/skills/<id>/`
- Treat `~/.config/agents/src/**` as a transitional mirror refreshed by `mise run stage-catalog`
- Treat runtime targets such as `~/.codex/skills/**` and `~/.claude/skills/**` as deploy outputs, not editing surfaces
- Keep the skill concise and focused on repeatable workflow guidance
- Prefer editing an existing managed skill when the scope overlaps
- Do not create README, CHANGELOG, or other auxiliary docs unless explicitly requested

## Minimal Workflow

1. Confirm that the change belongs to a managed skill in this repo
2. Choose a lowercase hyphenated skill id
3. Create or edit `~/.apm/catalog/.apm/skills/<id>/SKILL.md`
4. Add only the minimum extra files that improve repeatable execution:
   - `references/` for detailed docs loaded on demand
   - `scripts/` for deterministic repeated actions
   - `assets/` for output templates or static resources
5. If this skill replaces another one, update managed references in `catalog/` and workspace docs
6. Run `mise run stage-catalog`
7. Run `mise run format`
8. Run `mise run ci:check`
9. Run `mise run apply` when the new skill should be deployed locally

## Skill Layout

```text
~/.apm/catalog/.apm/skills/<id>/
  SKILL.md
  references/
  scripts/
  assets/
```

`SKILL.md` is required. The other directories are optional.

## Authoring Guidance

- Put repo-specific path rules and rollout steps in the body
- Keep frontmatter `name` and `description` explicit enough to trigger correctly
- Prefer short procedural sections over long general theory
- Move examples and deep reference material into `references/` once the main file starts getting long
- Cross-reference `apm-usage` for broader manifest, catalog, and deployment questions

## Migration Pattern

When replacing an existing external or misplaced skill:

1. Add the managed skill under `~/.apm/catalog/.apm/skills/<id>/`
2. Update managed references to the new id
3. Remove obsolete external refs from `~/.apm/apm.yml` if they are no longer needed
4. Run `mise run stage-catalog`
5. Run `mise run apply`
6. If stale ownership remains in runtime targets, run `apm prune` once and apply again
