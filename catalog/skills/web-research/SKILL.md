---
name: web-research
description: "Plan, route, collect, and synthesize public web research with cited evidence. Use as the default entry point when the user asks to research a topic online, look something up, find current information, compare options, produce a research report, or requests Jina search or X/Twitter signal. Delegates large investigations to parallel Sonnet subagents; collection is Jina Reader-first."
---

# Web Research

## Overview

Public web research from planning through synthesis. Collection is Jina Reader-first; X/Twitter is an indexed public-source signal, not complete platform coverage. Delegated subagents follow the Collection and Evidence Rules sections of this skill.

## Scope

- Use public sources by default.
- Do not use this for authenticated browsing, form submission, paid APIs, or internal source research unless another connector is explicitly available and allowed. If a task involves cost, publishing, or authenticated access, stop and confirm first.

## Workflow

1. Restate the research question, decision audience, time horizon, and required source types.
2. Size the task:
   - Small (single fact check, 1-2 sources, one clear question): collect directly in the main session; delegation overhead is not worth it.
   - Large (comparison, report, or investigation with independent angles): split into 2-5 non-overlapping subtopics and delegate each to a parallel subagent.
3. Collect per subtopic (see Collection).
4. Cluster findings by source type and evidence strength.
5. Synthesize a cited answer that separates observed evidence from inference.

## Delegated Research

For large tasks, spawn one subagent per subtopic with the Agent tool:

- Use `model: sonnet` for collection subagents; reserve the parent model for planning and synthesis.
- Launch independent subagents in a single message so they run in parallel (up to 3-5 at once).
- Instruct each subagent to:
  - Research one specific subtopic, stated without acronyms.
  - Follow this skill's Collection and Evidence Rules sections.
  - Stay within roughly 3-5 searches.
  - Write findings with key facts, quotes, and source URLs to `tmp/research_<topic>/findings_<subtopic>.md`.
- After all subagents finish, read every findings file before synthesizing. The parent owns integration, evidence ranking, and citations.

## Collection

Prefer the Jina MCP server's direct search tool (e.g. `search_web`) when it is exposed. Otherwise use the Jina `read_url` tool with Jina search URLs, URL-encoding the full query after `q=`:

- General search: `https://s.jina.ai/?q=<url-encoded query>`
- X search: `https://s.jina.ai/?q=site%3Ax.com%20<url-encoded query terms>`
- Twitter fallback: `https://s.jina.ai/?q=site%3Atwitter.com%20<url-encoded query terms>`
- Source-specific search: add `site:<domain>` to the query.

Read promising result URLs with Jina Reader when deeper source detail is needed.

### Login-Walled Sources (X/Twitter etc.)

Jina Reader renders pages server-side, so JS-heavy public pages usually work; login-walled content (X timelines, Instagram, paywalled articles) yields only indexed fragments. For X, search both `site:x.com` and `site:twitter.com`, cite snippets as excerpts (never as full post contents), attribute posts to their handle only, and prefer direct post URLs. Reaching protected or deleted content through a logged-in browser session needs an explicit user request.

## Source Type Notes

- GitHub repositories, issues, PRs, releases: prefer `gh` CLI or GitHub tools over web search.
- YouTube transcripts/captions, RSS feed parsing, or recurring source monitoring: ordinary web search only gets metadata; tell the user what deeper extraction would require instead of overclaiming.

## Evidence Rules

- Separate observed evidence from inference; cite URLs for every material claim.
- Rank findings by source authority: official sources first, then primary repositories or docs, then reputable journalism or expert posts, then community and social signals.
- Treat social and community signals as partial evidence unless corroborated by stronger sources.
- Name source gaps explicitly (blocked pages, deleted posts, index limitations).
- Include concrete dates when recency matters.
- Do not store API keys, cookies, bearer tokens, or other secrets in research files or repository artifacts.

## Output

Default to an in-chat brief unless the user asks for a saved report (saved reports go under `tmp/research_<topic>/`).

Include:

- Recommendation or answer.
- Findings grouped by evidence strength.
- Source map showing which source contributed what.
- X/Twitter signal section when searched.
- Gaps, caveats, and recommended next checks.
