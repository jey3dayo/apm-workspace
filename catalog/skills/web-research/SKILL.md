---
name: web-research
description: "Plan, route, collect, and synthesize public web research with cited evidence. Use as the default entry point when the user asks to research a topic online, look something up, find current information, compare options, produce a research report, or requests X/Twitter signal or Jina search. Delegates large investigations to parallel Sonnet subagents; collection uses the host's built-in web search and direct URL fetch, with Jina as a paid opt-in."
---

# Web Research

## Overview

Public web research from planning through synthesis. Collection uses the host's built-in search and direct fetch; X/Twitter is an indexed public-source signal, not complete platform coverage. Delegated subagents follow the Collection and Evidence Rules sections of this skill.

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
5. Re-check every load-bearing claim -- one the recommendation would change if it turned out to be false -- against its primary source before synthesizing. Three kinds go wrong most often: claims of state (unresolved, deprecated, fixed, a current default), claims of absence (no checksum block, no attestation, no primary source), and claims of applicability (a successor or fix that may require a version the user does not have). Open the issue, the file at the version in use, or the release note yourself rather than trusting the finding that cites it. A claim whose primary source you could not reach is reported as inference with the gap named, never as observed evidence.
6. Synthesize a cited answer that separates observed evidence from inference.

## Delegated Research

For large tasks, spawn one subagent per subtopic with the Agent tool:

- Use `model: sonnet` for collection subagents; reserve the parent model for planning and synthesis.
- Launch independent subagents in a single message so they run in parallel (up to 3-5 at once).
- Instruct each subagent to:
  - Research one specific subtopic, stated without acronyms.
  - Follow this skill's Collection and Evidence Rules sections.
  - Stop when the subtopic's load-bearing claims each have a primary source; when one has none, report the gap instead of widening the search.
  - Write findings with key facts, quotes, and source URLs to `tmp/research_<topic>/findings_<subtopic>.md`.
- After all subagents finish, read every findings file before synthesizing. The parent owns integration, the load-bearing re-check, evidence ranking, and citations.

## Collection

- Search with the host's built-in web search tool (Claude Code `WebSearch`, Codex `web_search`). Narrow with `site:<domain>`.
- Read a result or a user-given URL with `ax` (run `ax agent-context` once first) or the host's fetch tool (`WebFetch`). Use a browser tool only for pages that need JavaScript.

### Jina (paid opt-in)

Jina bills the user's account: a web search request is priced from 10,000 tokens, `search_web` sends one request per element of a query array, and `read_url` bills per output token. Use Jina only when the user names it for this task, and pass that permission to subagents explicitly. When using it, send one query per search and pass `question` to `read_url`. A `402 InsufficientBalanceError` means the balance is exhausted: switch to the built-in tools and tell the user.

### Login-Walled Sources (X/Twitter etc.)

Fetchers without a login session see only public markup: login-walled content (X timelines, Instagram, paywalled articles) yields only indexed fragments. For X, search both `site:x.com` and `site:twitter.com`, cite snippets as excerpts (never as full post contents), attribute posts to their handle only, and prefer direct post URLs. Reaching protected or deleted content through a logged-in browser session needs an explicit user request.

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
