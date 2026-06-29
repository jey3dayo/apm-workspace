---
name: command-creator
description: |
  [What] Guide for creating effective slash commands. Provides command structure, design patterns, integration points, and best practices. Use when creating new commands, improving existing commands, or understanding command design patterns.
  [When] Use when: using command-creator
  [Keywords] command creator, slash
---

# Command Creator

A guide for creating effective slash commands.

## About This Skill

Slash commands are explicit workflow entry points for users in Claude Code. They are triggered when a user types `/command` and execute specific tasks.

### What This Skill Provides

1. Command design patterns - 5 proven patterns
2. Integration guide - How to connect with Agents/Skills/Shared Libraries
3. Templates and checklists - Practical starter kit
4. Real-world examples - Best practices extracted from existing commands

## Command Structure

### Required Elements

All commands have the following structure:

```markdown
---
description: Brief description of the command (1 line, 20-100 characters)
argument-hint: [required-arg] [--optional-flag]
---

# Command Name

## Purpose

[The problem this command solves]

## Usage

[How to invoke the command and its arguments]

## Workflow

[Execution steps - simple or phase-based]

## Integration

[Agents/skills/shared libraries used]

## Examples

[Real usage examples]

## Error Handling

[Common issues and solutions]
```

### YAML Frontmatter

- description (required): Description shown in `/help`
  - Start with a clear verb (e.g., "Execute", "Analyze", "Create")
  - Describe the specific functionality
  - Aim for 20-100 characters

- argument-hint (optional): Usage pattern
  - `[]` = optional argument
  - `<>` = required argument (though `[]` is generally used)
  - `--flag` = option flag
  - Example: `[--simple] [--staged|--recent]`

## Detailed References

- For design patterns / implementation / integration / quality standards / testing, see `references/command-details.md`

## Next Steps

1. Define the purpose and inputs/outputs
2. Create using the template
3. Review testing and migration procedures
4. Consider the distribution method for the target runtime

## Distribution

For commands managed in `~/.apm`, follow the current APM catalog flow:

- Edit `catalog/commands/**` as the source of truth.
- Run `mise run prepare:catalog` before publishing catalog changes.
- Use `apm-usage` for source-of-truth, rollout, and deploy task selection.

## Related Resources

- `references/command-details.md`
- `apm-usage` skill - APM source-of-truth and rollout task selection
