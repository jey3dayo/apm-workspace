---
name: caad-skill-deployer
description: |
  Deploy named personal skills into the CAAD Claude Code marketplace repository as self-contained plugins. Use when a user asks to register, import, copy, arrange, publish, or hand off a personal skill to this repository, especially requests like "個人スキル skill-name をこのリポジトリに手配して" or "この skill を社内 marketplace に登録して". This skill covers source lookup, folder/category selection, plugin scaffolding, marketplace registration, validation, commit, and push without creating a PR.
---

# CAAD Skill Deployer

## Purpose

Move a named personal skill into this repository as a Claude Code marketplace plugin. Keep the result self-contained under `plugins/{category}/{skill-name}/` so marketplace installs do not depend on files outside the plugin directory.

`~/.apm/catalog/skills/<skill-name>/` is the local source of truth for managed personal skills. The CAAD marketplace repository is only a distribution and transfer target. Do not edit marketplace copies as the durable source; update the APM catalog source first, then redeploy the marketplace copy with this skill.

## Managed CAAD Targets

These skills are intentionally managed from the APM catalog into fixed CAAD marketplace plugin paths:

| Skill                         | APM source                                           | CAAD marketplace target                    |
| ----------------------------- | ---------------------------------------------------- | ------------------------------------------ |
| `perman-aws-vault`            | `~/.apm/catalog/skills/perman-aws-vault/`            | `plugins/infra/perman-aws-vault`           |
| `google-forms-survey-builder` | `~/.apm/catalog/skills/google-forms-survey-builder/` | `plugins/docs/google-forms-survey-builder` |

When one of these managed skills already exists in the CAAD marketplace, treat the marketplace copy as an import source only when bootstrapping a missing APM catalog source. After the APM source exists, all future changes flow from APM to CAAD.

## Source Lookup

Treat the user input as a skill name unless they provide an explicit path. Normalize names to lowercase kebab-case before probing default locations.

Search in this order:

1. `~/.apm/catalog/skills/<skill-name>/`
2. `~/.apm/private-skills/.apm/skills/<skill-name>/`
3. `~/.agents/skills/<skill-name>/`

Use `scripts/inspect_skill_source.py <skill-name>` to list candidates and read `SKILL.md` metadata. If multiple candidates exist, prefer the first source in the order above. For durable personal skills, treat `~/.apm/catalog/skills/` as the source of truth.

For managed CAAD targets, `~/.apm/catalog/skills/<skill-name>/` must exist before deployment. If it is missing but the CAAD marketplace copy exists, import the marketplace skill into the APM catalog first, then deploy from the APM source back to the marketplace target.

## Folder Policy

Read `references/folder-policy.md` before choosing the destination category. Default to one skill per plugin:

```text
plugins/{category}/{skill-name}/
├── .claude-plugin/plugin.json
└── skills/
    └── {skill-name}/
        ├── SKILL.md
        ├── agents/       # copy when present
        ├── scripts/      # copy when present
        ├── references/   # copy when present
        └── assets/       # copy when present
```

Use the same kebab-case value for the plugin name and skill folder. Do not create category bundle registrations for this repository; register the plugin directly in root `.claude-plugin/marketplace.json`. For managed CAAD targets, use the category/path recorded in the managed target table instead of reclassifying the skill.

## Deployment Workflow

1. Run `rtk git status --short` and preserve unrelated worktree changes.
2. Locate the source skill. If no source exists and no explicit path was given, report the missing skill and stop.
3. For managed CAAD targets, confirm the selected source is under `~/.apm/catalog/skills/<skill-name>/`. If not, stop or import the CAAD copy into the APM catalog before deployment.
4. Read source `SKILL.md` frontmatter and body. Confirm `name` and `description` exist and match the intended skill.
5. Choose the category using `references/folder-policy.md` or the managed target table.
6. Copy the skill into `plugins/{category}/{skill-name}/skills/{skill-name}/` as real files. Copy `SKILL.md`, `agents/`, `scripts/`, `references/`, and `assets/` when present. Do not keep symlinks that point outside the plugin.
7. Create or update `plugins/{category}/{skill-name}/.claude-plugin/plugin.json`:

```json
{
  "name": "<skill-name>",
  "version": "1.0.0",
  "description": "<short marketplace description>",
  "author": { "name": "caad" },
  "skillsPath": "skills"
}
```

1. Add or update one entry in root `.claude-plugin/marketplace.json` with `name`, `source`, `description`, `version`, and `author`.
2. Run `mise run format`, `mise run lint`, JSON parse checks for touched `plugin.json` files and root `marketplace.json`, link checks, and `rtk git diff --check`.
3. Review the diff manually. Check for unwanted absolute home paths, secrets, plugin-external symlinks, generated-output edits, and unrelated edits.
4. Stage only the deployed plugin and marketplace registration. Commit with a short message such as `Add <skill-name> marketplace plugin` or `Update <skill-name> marketplace plugin`.
5. Push the current branch. Do not create a PR.

## Validation Checklist

Before commit, verify:

- Root `marketplace.json` has exactly one new plugin entry.
- The plugin `source` exists and contains `.claude-plugin/plugin.json`.
- The plugin uses `skillsPath: "skills"`.
- `skills/<skill-name>/SKILL.md` has `name` and `description` frontmatter.
- All bundled resources needed by the skill are copied under the plugin directory.
- No plugin file is an external symlink.
- No secret values or machine-specific absolute paths were introduced unless the skill intentionally documents a fixed local path pattern.

## Failure Policy

If the same approach fails three times, stop and report the three attempts, concrete errors, and a different approach. Do not keep retrying the same command sequence.
