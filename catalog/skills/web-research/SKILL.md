---
name: web-research
description: "Plan, route, and synthesize public web research with cited evidence. Use as the default entry point when the user asks to research a topic online, look something up, find current information, compare options, or produce a research report. Delegates large investigations to parallel Sonnet subagents and uses jina-web-research for the actual collection workflow."
---

# Web Research

## Overview

Use this skill as the entry point for public web research. It decides how much orchestration a research task needs, keeps collection work in `jina-web-research` (the Jina Reader-first collection workflow), and owns planning, delegation, and synthesis.

This skill stays thin on collection mechanics. Search URL formats, X/Twitter evidence rules, and Reader usage live in `jina-web-research`; do not duplicate them here.

## Workflow

1. Restate the research question, decision audience, time horizon, and required source types.
2. Size the task:
   - Small (single fact check, 1-2 sources, one clear question): follow `jina-web-research` directly in the main session. Do not delegate; the overhead is not worth it.
   - Large (comparison, report, or investigation with independent angles): split into 2-5 non-overlapping subtopics and delegate each to a parallel subagent.
3. Synthesize a cited answer that separates observed evidence from inference.

## Delegated Research

For large tasks, spawn one subagent per subtopic with the Agent tool:

- Use `model: sonnet` for collection subagents; reserve the parent model for planning and synthesis.
- Launch independent subagents in a single message so they run in parallel (up to 3-5 at once).
- Instruct each subagent to:
  - Research one specific subtopic, stated without acronyms.
  - Follow the `jina-web-research` skill's collection workflow (Jina search via `search_web` or `s.jina.ai` URLs, page reading via Reader).
  - Stay within roughly 3-5 searches.
  - Write findings with key facts, quotes, and source URLs to `tmp/research_<topic>/findings_<subtopic>.md`.
- After all subagents finish, read every findings file before synthesizing. The parent owns integration, evidence ranking, and citations.

## Source Type Notes

- Ordinary public web, docs, vendor pages, articles, and indexed X/Twitter signal: `jina-web-research` covers it.
- GitHub repositories, issues, PRs, releases: prefer `gh` CLI or GitHub tools over web search.
- YouTube transcripts/captions, RSS feed parsing, or recurring source monitoring: ordinary web search only gets metadata; tell the user what deeper extraction would require instead of overclaiming.
- Authenticated, private, paid, or internal sources: use only an explicitly available and permitted connector. If a task involves cost, publishing, or authenticated access, stop and confirm first.

## Evidence Handling

- Separate observed evidence from inference.
- Rank findings by source authority: official sources first, then primary repositories or docs, then reputable journalism or expert posts, then community and social signals.
- Treat social and community signals as partial evidence unless corroborated by stronger sources.
- Name source gaps explicitly (blocked pages, deleted posts, index limitations).
- Include concrete dates when recency matters, and cite URLs for every material claim.

## Output

Default to an in-chat brief unless the user asks for a saved report (saved reports go under `tmp/research_<topic>/`).

Include:

- Recommendation or answer.
- Findings grouped by evidence strength.
- Source map showing which source contributed what.
- Gaps, caveats, and recommended next checks.
