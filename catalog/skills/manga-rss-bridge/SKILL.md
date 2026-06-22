---
name: manga-rss-bridge
description: "Use when working on the manga-rss-bridge repository: summarizing how to use the self-hosted manga RSS bridge, adding or verifying providers, checking route examples, running local development commands, or applying the repository's TypeScript quality gates."
---

# Manga RSS Bridge

## Overview

Use this skill for the `manga-rss-bridge` repository. It captures the practical usage of the tool and the repository workflow needed to modify it safely.

Source order:

1. Read repository-local `AGENTS.md`, then `CLAUDE.md`.
2. Use `README.md` as the source of truth for product usage, supported providers, setup, Docker, and policy.
3. Use `mise.toml` and `package.json` for current command definitions.

## Tool Usage Summary

Manga RSS Bridge is a self-hosted RSS bridge for public manga chapter metadata. It exposes provider routes that return RSS XML for readers such as FreshRSS.

Local development:

```bash
pnpm install
pnpm dev
```

Check a feed:

```bash
curl http://localhost:8080/gangan-online/2061.xml
```

Build and run with Docker:

```bash
docker build -t manga-rss-bridge .
docker run --rm -p 8080:8080 manga-rss-bridge
```

Run a published GHCR image:

```bash
docker pull ghcr.io/jey3dayo/manga-rss-bridge:latest
docker run --rm -p 8080:8080 ghcr.io/jey3dayo/manga-rss-bridge:latest
```

Supported route patterns:

```text
/gangan-online/<title-id>.xml
/kadocomi/<work-code>.xml
/comic-days/<series-id>.xml
/yanmaga/<comic-slug>.xml
/manga-one/<chapter-id>.xml
/gaugau/<work-id>.xml
/firecross/<series-id>.xml
/jump-rookie/<series-id>.xml
/hayacomic/<series-id>.xml
/mangabox/<reader-id>.xml
```

Policy boundary: do not add code that bypasses authentication, paid content, DRM, or access controls. The bridge should only emit RSS from publicly available work or chapter metadata.

## Development Workflow

Before editing:

1. Check `git status --short` and preserve unrelated changes.
2. Prefer existing files and local patterns.
3. Keep temporary research artifacts under `tmp/` when the repository has one; otherwise use `/tmp`.

When adding a provider:

1. Add a Zod schema in `src/schemas/<provider>.ts` for external JSON boundaries, when JSON is used.
2. Add `src/providers/<provider>.ts` implementing the `Provider` contract.
3. Register the provider in `src/providers/index.ts`.
4. Add README examples and policy notes if user-facing behavior changes.
5. Add focused Vitest coverage for RSS rendering or provider parsing helpers. Prefer fixtures over live network tests.
6. Run the relevant quality gate.

Repository patterns:

- Prefer TypeScript for new OSS code.
- Prefer `type` aliases for object shapes, unions, and contracts.
- Derive runtime-boundary types from Zod schemas with `z.infer` or `z.output`.
- Provider implementations should return `Result<MangaFeed, Error>` through the provider contract.
- Avoid `as` assertions except at narrow boundary points after validation or filtering.
- Do not edit generated `dist/` output directly.

## Quality Gates

Prefer mise tasks when available:

```bash
mise run format
mise run check
mise run ci
```

Use `mise run check` as the default TypeScript gate. Use `mise run ci` for broad confidence, PR handoff, release, or build-output validation. Before push or PR creation, run `mise run format`; if auto-format is unavailable, use the format check as the fallback.

Equivalent pnpm scripts exist for fallback:

```bash
pnpm check
pnpm test
pnpm build
pnpm run format
pnpm run format:check
pnpm run lint
```

## Reference

Read `references/usage.md` when the task is primarily about explaining current tool usage, route examples, Docker usage, or policy to a user. Do not read it for provider implementation workflow unless the user also asks for current route examples.
