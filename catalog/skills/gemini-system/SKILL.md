---
name: gemini-system
description: |
  PROACTIVELY consult Gemini CLI for research, large codebase comprehension,
  and multimodal data processing. Gemini excels at: massive context windows (1M tokens),
  Google Search grounding, video/audio/PDF analysis, and repository-wide understanding.
  Use for pre-implementation research, documentation analysis, and multimodal tasks.
  Explicit triggers: "research", "investigate", "analyze video/audio/PDF", "understand codebase".
metadata:
  short-description: Claude Code ↔ Gemini CLI collaboration (research & multimodal)
---

# Gemini System — Research & Multimodal Specialist

## Gemini CLI is your research specialist with large-context, grounded search, and multimodal support

Model names move quickly. Prefer the configured default unless the task explicitly needs a specific model, and check official Gemini docs when exact model selection matters.

## Context Management (CRITICAL)

### Prefer Subagent Pattern

| Situation                              | Method                     |
| -------------------------------------- | -------------------------- |
| Codebase analysis                      | Via subagent (recommended) |
| Library research                       | Via subagent (recommended) |
| Multimodal                             | Via subagent (recommended) |
| Short questions (1-2 sentence answers) | Direct call OK             |

## Gemini vs Codex

| Task                          | Gemini | Codex |
| ----------------------------- | ------ | ----- |
| Repository-wide understanding | ✓      |       |
| Library research              | ✓      |       |
| Multimodal (PDF/video/audio)  | ✓      |       |
| Latest documentation search   | ✓      |       |
| Design decisions              |        | ✓     |
| Debugging                     |        | ✓     |
| Code implementation           |        | ✓     |

## When to Consult (MUST)

| Situation         | Trigger Examples                 |
| ----------------- | -------------------------------- |
| Research          | "Research" "Investigate"         |
| Library docs      | "Library" "Docs" "Documentation" |
| Codebase analysis | "Entire codebase" "Codebase"     |
| Multimodal        | "PDF" "Video" "Audio"            |

## When NOT to Consult

- Design decisions (use Codex)
- Debugging (use Codex)
- Code implementation (use Codex)
- Simple file operations (do directly)

## How to Consult

### Recommended: Subagent Pattern

### Use your platform's subagent mechanism to preserve main context

```
Subagent prompt shape:
- Research: {topic}
- Run Gemini in non-interactive mode with an English prompt
- Save reusable findings to a workspace-local path when persistence is useful
- Return a concise summary (5-7 bullets) in the main assistant's language
```

Codex:

```text
Use `spawn_agent` for the research worker, and have the worker run:
gemini -p "{research question in English}" 2>/dev/null
If the findings should be reusable, save them under `docs/research/{topic}.md`.
In Codex workflows, do not use `.claude/...` as the default persistence path.
```

Claude Code:

```text
Use the Task tool for the research worker, and have the worker run:
gemini -p "{research question in English}" 2>/dev/null
```

### Operational Readiness

- If you plan to run Gemini locally, confirm the CLI is available and authenticated before promising Gemini-based research.
- If Gemini is unavailable, report the blocker clearly instead of silently switching to a different research path.
- When saving findings, use a short kebab-case topic slug such as `tanstack-query-best-practices`.

### Direct Call (Short Questions Only)

For quick questions expecting brief answers:

```bash
gemini -p "Brief question" 2>/dev/null
```

### CLI Options Reference

```bash
# Codebase analysis
gemini -p "{question}" --include-directories . 2>/dev/null

# Multimodal (PDF/video/audio)
gemini -p "{prompt}" < /path/to/file.pdf 2>/dev/null

# JSON output
gemini -p "{question}" --output-format json 2>/dev/null
```

### Workflow (Subagent)

1. Spawn subagent with Gemini research prompt
2. Continue your work → Subagent runs in parallel
3. Receive summary → Subagent returns key findings
4. Save full output only when later reuse is useful → prefer `docs/research/{topic}.md`

## Language Protocol

1. Ask Gemini in **English**
2. Receive response in **English**
3. Synthesize and apply findings
4. Report to user in **their preferred language**

## Output Location

When the research should be reusable, save Gemini results to a workspace-local path such as:

```
docs/research/{topic}.md
```

Codex default:

- use `docs/research/{topic}.md`
- keep the path inside the current workspace when possible
- do not default to `.claude/...`

If persistence is unnecessary, return the summary only.

## Task Templates

### Pre-Implementation Research

```bash
gemini -p "Research best practices for {feature} in Python 2025.
Include:
- Common patterns and anti-patterns
- Library recommendations (with comparison)
- Performance considerations
- Security concerns
- Code examples" 2>/dev/null
```

### Repository Analysis

```bash
gemini -p "Analyze this repository:
1. Architecture overview
2. Key modules and responsibilities
3. Data flow between components
4. Entry points and extension points
5. Existing patterns to follow" --include-directories . 2>/dev/null
```

### Library Research

See: `references/lib-research-task.md`

### Multimodal Analysis

```bash
# Video
gemini -p "Analyze video: main concepts, key points, timestamps" < tutorial.mp4 2>/dev/null

# PDF
gemini -p "Extract: API specs, examples, constraints" < api-docs.pdf 2>/dev/null

# Audio
gemini -p "Transcribe and summarize: decisions, action items" < meeting.mp3 2>/dev/null
```

## Integration with Codex

| Workflow          | Steps                                 |
| ----------------- | ------------------------------------- |
| New feature       | Gemini research → Codex design review |
| Library choice    | Gemini comparison → Codex decision    |
| Bug investigation | Gemini codebase search → Codex debug  |

## Why Gemini?

- 1M token context: Entire repositories at once
- Google Search: Latest information and docs
- Multimodal: Native PDF/video/audio processing
- Fast exploration: Quick overview before deep work
- Shared context: Results saved for Claude/Codex
