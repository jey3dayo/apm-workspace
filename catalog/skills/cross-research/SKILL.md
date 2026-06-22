---
name: cross-research
description: "Route and synthesize cross-source research across web, GitHub, social platforms, video, and community sources. Use when a research task may require multiple source types, source-routing decisions, Agent Reach, Jina Reader, or delegated web research."
---

# Cross Research

## Overview

Use this skill as the routing layer for research that may need more than one public source type. Keep the actual collection work in the most appropriate underlying workflow: `jina-web-research` for Reader-first web research, `web-research` for delegated multi-topic investigations, and Agent Reach when platform-specific reach or diagnostics are needed.

This skill should stay thin. Do not duplicate the full instructions from the underlying skills or tools; decide the route, preserve evidence quality, and synthesize the result.

## Routing Workflow

1. Restate the research question, decision audience, time horizon, and required source types.
2. Classify the task using the source routing matrix.
3. Choose the smallest capable route, preferring `jina-web-research` for ordinary public web research.
4. Use Agent Reach only when the requested evidence depends on platform-specific access, CLI diagnostics, transcripts, feeds, or community/social sources that ordinary web search is likely to miss.
5. For broad investigations, split into 2-5 non-overlapping subtopics and use `web-research` or subagents only when parallel work materially improves coverage.
6. Synthesize findings with source strength, caveats, and citations for every material claim.

## Source Routing Matrix

| Research need                                            | Primary route                                       | Add Agent Reach when                                                                             |
| -------------------------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Official docs, vendor pages, public articles, blog posts | `jina-web-research`                                 | Search results are incomplete, blocked, or require alternate fetch diagnostics                   |
| Current public web signals with citations                | `jina-web-research`                                 | Multiple source classes must be normalized through one reach layer                               |
| Large comparison or report with independent subtopics    | `web-research`                                      | Subtopics include social, video, feed, or repository-specific collection                         |
| GitHub repositories, issues, pull requests, releases     | GitHub tools or public web search                   | The task needs GitHub CLI-backed reach checks or repository signals alongside other platforms    |
| X/Twitter, Reddit, forums, community chatter             | `jina-web-research` for indexed public search       | The user asks for platform-native reach, broader social scan, or diagnostic coverage gaps        |
| YouTube videos, captions, channels, or transcripts       | Public web search for basic metadata                | Captions/transcripts or yt-dlp-style extraction are required                                     |
| RSS or recurring source monitoring                       | Public web search for ad hoc lookup                 | Feed discovery, feed parsing, or repeated source polling is required                             |
| Authenticated, private, paid, or internal sources        | Relevant connector or explicit user-provided access | Agent Reach is configured for the specific authorized source and the user explicitly permits use |

## Route Selection Rules

- Default to `jina-web-research` when the user asks to research, compare, verify, or summarize public information and does not require platform-specific collection.
- Use `web-research` when the work is naturally decomposable and a single-pass search would mix unrelated evidence.
- Add Agent Reach when the main risk is reachability rather than synthesis: platform coverage, login/cookie constraints, transcripts, RSS, CLI availability, or source diagnostics.
- Do not use Agent Reach only because a source is mentioned. Use it when its platform reach changes what evidence can be collected or verified.
- If a task involves cost, publishing, authenticated access, secrets, or rate-limited accounts, stop and confirm before using those capabilities.

## Evidence Handling

- Separate observed evidence from inference.
- Rank findings by source authority and relevance: official sources first, then primary repositories or docs, then reputable journalism or expert posts, then community and social signals.
- Treat social and community signals as partial evidence unless corroborated by stronger sources.
- Name source gaps explicitly, such as unavailable posts, missing captions, blocked pages, deleted content, or indexed-search limitations.
- Include concrete dates when recency matters.
- Cite URLs for every material claim in the final answer.

## Output

Default to an in-chat brief unless the user asks for a saved report.

Include:

- Recommendation or answer.
- Routes used and why.
- Findings grouped by evidence strength.
- Source map showing which source class contributed what.
- Gaps, caveats, and recommended next checks.
