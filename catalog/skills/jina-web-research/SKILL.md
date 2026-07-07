---
name: jina-web-research
description: "Run Jina Reader-first public web research with cited synthesis. Use when the user asks to research current public web signals, search X/Twitter via Jina, compare public sources, or produce a concise evidence-backed research brief using s.jina.ai."
---

# Jina Web Research

## Overview

Use this skill for current public web research that should prefer Jina Reader. It adapts the `web-research` planning pattern, but uses Jina search URLs as the primary collection path and treats X/Twitter as an indexed public-source signal, not complete platform coverage.

## Scope

- Use public sources by default.
- Prefer Jina Reader for search and page reading.
- Use X/Twitter search when the user asks for social signal, user complaints, launch reactions, product sentiment, or current chatter.
- Cross-check important claims with non-X sources when possible.
- Do not use this for authenticated browsing, form submission, paid APIs, or internal source research unless another connector is explicitly available and allowed.

## Workflow

1. Restate the research question, audience, time horizon, and scope.
2. Create a temporary research folder under `tmp/research_<topic>/` when saving intermediate files.
3. Break the question into 1-5 non-overlapping subtopics.
4. Search each subtopic with Jina Reader search URLs.
5. Read promising result URLs with Jina Reader when deeper source detail is needed.
6. Cluster findings by source type and evidence strength.
7. Synthesize a cited answer that separates observed evidence from inference.

## Jina Search

Prefer the Jina MCP server's direct search tool (e.g. `search_web`) when it is exposed. Otherwise use the Jina `read_url` tool with Jina search URLs, URL-encoding the full query after `q=`:

- General search: `https://s.jina.ai/?q=<url-encoded query>`
- X search: `https://s.jina.ai/?q=site%3Ax.com%20<url-encoded query terms>`
- Twitter fallback: `https://s.jina.ai/?q=site%3Atwitter.com%20<url-encoded query terms>`
- Source-specific search: add `site:<domain>` to the query.

## X/Twitter Handling

- Always search both `site:x.com` and `site:twitter.com` when X signal matters.
- Record search terms and date searched.
- Treat indexed X results as partial evidence because login walls, deletion, ranking, and indexing gaps can hide relevant posts.
- Treat deleted, protected, suspended, login-blocked, or incomplete posts as unavailable and say so.
- Do not present search snippets as full post contents.
- Do not infer identity from a handle alone when attribution matters.
- Do not infer frequency from a few loud posts. Mark these as anecdotal unless corroborated.
- Prefer direct post URLs when available; otherwise cite the Jina search result URL and explain the limitation.
- Do not use a logged-in browser session just to bypass protected or deleted X content unless the user explicitly asks.

## Evidence Rules

- Cite URLs for every material claim.
- Separate facts, quotes, and inference.
- Distinguish official sources, journalism/blogs, forums, GitHub, Reddit/HN, and X/Twitter.
- Call out missing or weak source access.
- Do not overclaim recency; include concrete dates when dates matter.
- Do not store API keys, cookies, bearer tokens, or other secrets in research files or repository artifacts.

## Output

Default to an in-chat brief unless the user asks for a saved report.

Include:

- Executive summary.
- Findings ranked by confidence and relevance.
- Source map showing what was searched and what each source contributed.
- X/Twitter signal section when searched.
- Gaps, caveats, and recommended next checks.
