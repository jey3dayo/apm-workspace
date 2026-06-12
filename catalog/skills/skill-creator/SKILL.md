---
name: skill-creator
description: Guide for creating and refactoring effective agent skills. Use when the user wants to create a new skill, update or refactor an existing skill, or improve a skill's structure, triggering description, or bundled resources such as scripts, references, and assets.
metadata:
  short-description: Create or update an agent skill
---

# Skill Creator

Guidance for creating and refactoring effective agent skills.

## About Skills

Skills are modular, self-contained folders that extend an agent's capabilities with specialized knowledge, workflows, and tools. Think of them as "onboarding guides" for specific domains: they turn a general-purpose agent into a specialized one equipped with procedural knowledge that no model fully possesses.

1. Specialized workflows - multi-step procedures for specific domains
2. Tool integrations - instructions for working with specific file formats or APIs
3. Domain expertise - company-specific knowledge, schemas, business logic
4. Bundled resources - scripts, references, and assets for complex and repetitive tasks

## Core Principles

### Concise is Key

The context window is a public good. Skills share it with everything else the agent needs: system prompt, conversation history, other skills' metadata, and the actual user request.

Default assumption: the agent is already very smart. Only add context the agent does not already have. Challenge each piece: "Does the agent really need this explanation?" and "Does this paragraph justify its token cost?" Prefer concise examples over verbose explanations.

### Set Appropriate Degrees of Freedom

Match specificity to the task's fragility and variability:

- High freedom (text instructions): multiple approaches are valid, decisions depend on context, or heuristics guide the approach.
- Medium freedom (pseudocode or scripts with parameters): a preferred pattern exists, some variation is acceptable, or configuration affects behavior.
- Low freedom (specific scripts, few parameters): operations are fragile and error-prone, consistency is critical, or a fixed sequence must be followed.

Think of the agent as exploring a path: a narrow bridge with cliffs needs guardrails (low freedom), while an open field allows many routes (high freedom).

### Abstract Reusable Implementation Boundaries

When turning a real task lesson into guidance, abstract it into an owner-folder and import-boundary rule rather than hard-coding a library name. Write "discover the repository's owner folder, implement the concern there, and import its public API elsewhere" instead of "never call this library directly" unless direct use is always wrong.

If the user does not name a target skill, locate the existing skill whose trigger, scope, or examples already own the lesson and update it, rather than creating a new one, unless no reasonable owner exists.

Concrete examples:

- `valibot` / schema validation -> define schemas in the `schemas/**`, `schema/**`, or validation owner folder.
- `neverthrow` / `Result` conversion -> keep error/result conversion at the repository, service, action, or adapter boundary that owns it.
- DB access, Drizzle, SQL, query builders, transactions -> keep data access in `db/**`, `repository/**`, or `repositories/**`, not scattered through UI, route, or feature code.

For broad validation work, split investigation across subagents by concern, but keep detailed review-loop mechanics in the dedicated `subagent-task-review-loop` skill.

### Prefer Relative Skill Paths

Inside skill content, solve path problems relative to the skill folder: `SKILL.md`, `references/foo.md`, `scripts/foo.py`, `assets/template/`, `agents/openai.yaml`. Avoid OS-specific absolute paths. Use an absolute path only when the user provides a concrete local file or a verification step cannot be described safely otherwise; even then, document the reusable pattern with a relative path.

## Anatomy of a Skill

Every skill consists of a required SKILL.md file and optional bundled resources:

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter metadata (required)
│   │   ├── name: (required)
│   │   └── description: (required)
│   └── Markdown instructions (required)
├── agents/ (recommended)
│   └── openai.yaml - UI metadata for skill lists and chips
└── Bundled Resources (optional)
    ├── scripts/          - Executable code (Python/Bash/etc.)
    ├── references/       - Documentation intended to be loaded into context as needed
    └── assets/           - Files used in output (templates, icons, fonts, etc.)
```

### SKILL.md (required)

- Frontmatter (YAML): `name` and `description` are the trigger surface. They are the only fields the agent reads to decide when the skill is used, so describe clearly what the skill does and when to use it.
- Body (Markdown): instructions and guidance. Loaded only after the skill triggers, if at all.

### Agents metadata (recommended)

- `agents/openai.yaml` holds UI-facing metadata for skill lists and chips.
- Compose `display_name`, `short_description`, and `default_prompt` yourself by reading the skill (the user does not supply them), then write the file by running `scripts/generate_openai_yaml.py <skill-folder> --interface key=value` (repeatable flag; also accepted by `init_skill.py` at init time). Do not hand-write the YAML. Include other optional interface fields (icons, brand color) only when the user provides them.
- On updates, verify `agents/openai.yaml` still matches SKILL.md and regenerate if stale.
- Read `references/openai_yaml.md` for field definitions and constraints before generating.

### Bundled Resources (optional)

- Scripts (`scripts/`): executable code (Python/Bash/etc.) for deterministic, repeatedly-rewritten work. Token efficient and runnable without loading into context, though the agent may still need to read a script to patch it or adjust for the environment.
- References (`references/`): documentation loaded into context as needed to inform the agent's process. Keep SKILL.md lean by moving schemas, API docs, and detailed guides here; never duplicate the same content in both SKILL.md and references. For files over 10k words, include grep patterns in SKILL.md so the agent can search them.
- Assets (`assets/`): files used in the agent's output rather than loaded into context, such as templates, icons, fonts, and boilerplate code (e.g. `assets/logo.png`, `assets/frontend-template/`).

### What Not to Include

A skill should contain only files that directly support its functionality. Do not add auxiliary documentation such as README.md, INSTALLATION_GUIDE.md, CHANGELOG.md, etc. The skill should hold only what an agent needs to do the job, not context about how the skill was made; extra files just add clutter and confusion.

## Progressive Disclosure

Skills use a three-level loading system to manage context:

1. Metadata (name + description) - always in context (~100 words)
2. SKILL.md body - loaded when the skill triggers (<5k words)
3. Bundled resources - loaded as needed; effectively unlimited because scripts run without being read into context

Keep the body under 500 lines and split content into separate files when approaching the limit. Always reference split-out files from SKILL.md with a clear "when to read" description so the reader knows they exist and when to use them.

Common patterns:

- High-level guide with references: keep core workflow in SKILL.md and link domain/feature guides that load only when needed.
- Domain or variant organization: split references by domain or variant so only the relevant file is read. Example:

  ```
  cloud-deploy/
  ├── SKILL.md (workflow + provider selection)
  └── references/
      ├── aws.md
      ├── gcp.md
      └── azure.md
  ```

- Conditional details: keep basic content inline and link advanced content (tracked changes, OOXML internals, etc.) so the agent reads it only when the feature is needed.

Guidelines:

- Keep references one level deep; all reference files should link directly from SKILL.md.
- For reference files over 100 lines, include a table of contents at the top.

## Skill Creation Process

1. Understand the skill with concrete examples
2. Plan reusable skill contents (scripts, references, assets)
3. Initialize the skill (run init_skill.py)
4. Edit the skill (implement resources and write SKILL.md)
5. Validate the skill (run quick_validate.py)
6. Iterate based on real usage

Follow these steps in order, skipping only when there is a clear reason they do not apply.

### Skill Naming

- Use lowercase letters, digits, and hyphens only; normalize titles to hyphen-case (e.g. "Plan Mode" -> `plan-mode`).
- Keep generated names under 64 characters (letters, digits, hyphens).
- Prefer short, verb-led phrases that describe the action.
- Namespace by tool when it improves clarity or triggering (e.g. `gh-address-comments`, `linear-address-issue`).
- Name the skill folder exactly after the skill name.

### Step 1: Understand the Skill with Concrete Examples

Clearly understand concrete examples of how the skill will be used, either from direct user examples or from generated examples validated with user feedback. Skip this step only when usage patterns are already clearly understood; it stays valuable even for existing skills.

For an image-editor skill, relevant questions include:

- "Can you give some examples of how this skill would be used?"
- "What would a user say that should trigger this skill?"

Avoid overwhelming users with too many questions in one message; start with the most important and follow up as needed. Conclude this step when there is a clear sense of the functionality the skill should support.

### Step 2: Plan Reusable Skill Contents

For each concrete example: (1) consider how to execute it from scratch, and (2) identify what scripts, references, and assets would help when running the workflow repeatedly. Then assemble the list of resources to include. Worked examples:

- `pdf-editor` ("rotate this PDF") -> `scripts/rotate_pdf.py`
- `frontend-webapp-builder` ("build me a todo app") -> `assets/hello-world/` template
- `bigquery` ("how many users logged in today?") -> `references/schema.md`

### Step 3: Initialize the Skill

Always run `init_skill.py` for a new skill; skip this step only if the skill already exists.

Usage:

```bash
scripts/init_skill.py <skill-name> --path <output-directory> [--resources scripts,references,assets] [--examples] [--interface key=value]
```

Example:

```bash
scripts/init_skill.py my-skill --path <skills-root> --resources scripts,references
```

In this workspace, managed personal skills live under `~/.apm/catalog/skills/` (see the `apm-usage` skill for ownership rules).

The script:

- Creates the skill directory at the specified path
- Generates a SKILL.md template with proper frontmatter and TODO placeholders
- Creates `agents/openai.yaml`
- Optionally creates resource directories based on `--resources`
- Optionally adds example files when `--examples` is set

openai.yaml values are passed via `--interface key=value` (see "Agents metadata" above).

### Step 4: Edit the Skill

The skill is written for another agent instance to use, so include procedural knowledge, domain-specific details, and reusable assets that would be non-obvious yet beneficial to that instance.

Start with the reusable resources (`scripts/`, `references/`, `assets/`); this may need user input, such as brand assets for a `brand-guidelines` skill. Test added scripts by actually running them and confirming the output; for many similar scripts, a representative sample is enough. Delete any unused `--examples` placeholder files.

Writing guidelines: use imperative/infinitive form throughout.

Never write literal slash-command placeholders in the body — a `$` immediately followed by a digit or by the word ARGUMENTS. When the skill is invoked as a slash command, those tokens are replaced with command arguments and silently corrupt code examples (e.g. an `rg --replace` capture reference). Reword such examples to avoid the token, for instance with `rg -o`.

Frontmatter rule: keep frontmatter minimal. `name` and `description` are required; `license`, `allowed-tools`, and `metadata` are the only other fields `quick_validate.py` accepts (`metadata` holds harness-specific extras such as `short-description`). Put all when-to-use triggers in `description` — the body loads only after triggering, so a "When to Use" section in the body cannot help trigger the skill. Quote the `description` value when it contains YAML-special characters such as colons. Example `description` for a `docx` skill: "Comprehensive document creation, editing, and analysis with support for tracked changes, comments, formatting preservation, and text extraction. Use when working with professional documents (.docx files) for: (1) creating new documents, (2) modifying or editing content, (3) working with tracked changes, (4) adding comments, or any other document tasks."

### Step 5: Validate the Skill

```bash
scripts/quick_validate.py <path/to/skill-folder>
```

This checks YAML frontmatter format, required fields, and naming rules. Fix any reported issues and run it again.

Also run a static consistency check before shipping: verify the `description`'s claimed triggers and scope match what the body actually covers. A description/body gap makes the skill trigger on tasks the body cannot guide (this is the same check as `empirical-prompt-tuning` Iteration 0).

For skills managed in `~/.apm`, do not stop at `quick_validate.py`. Use `apm-usage`: run `mise run check`, run `mise run deploy`, then verify `~/.agents/skills/<skill-name>/` contains the deployed skill. Use `mise run apply:skills:local` only when the user explicitly asks for a fast local-only refresh.

### Step 6: Iterate

After testing, users may request improvements, often right after using the skill with fresh context of how it performed:

1. Use the skill on real tasks
2. Notice struggles or inefficiencies
3. Identify how SKILL.md or bundled resources should change
4. Implement changes and test again

For systematic, bias-free evaluation of a skill (fresh-subagent execution, two-sided evaluation, convergence criteria), run the `empirical-prompt-tuning` skill when the user explicitly asks for an empirical eval.
