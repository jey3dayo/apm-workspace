---
name: architecture-boundary-docs
description: Create or update audit-friendly architecture boundary documentation for a codebase. Use when documenting architecture boundaries, layer maps, folder or type responsibilities, Result/ServerAction boundaries, data flow, error flow, side effects, dependency direction, verification maps, forbidden crossings, or agent-facing architecture maps from repository evidence.
---

# Architecture Boundary Docs

Use this skill to document the architecture boundaries that already exist in a repository. This is for evidence-backed documentation generation, not architecture enforcement or broad refactoring.

If the target repository, requested path, or evidence pack is unavailable or too thin to support boundary claims, do not fill the document shape with `Unknown`, `N/A`, or placeholder rows. Stop with an evidence-gap report that lists what was available, what could not be inspected, the commands attempted, and the minimum evidence needed before a boundary document can be created or updated.

## Workflow

1. Gather source of truth:
   - Read repo guidance first: `AGENTS.md`, `CLAUDE.md`, linked docs, package scripts, and existing architecture docs when present.
   - Use `rg --files`, `rg`, package manifests, route/action files, schema/type files, and repository entrypoints to ground the map.
   - When running shell commands, quote every path that contains shell metacharacters such as parentheses, spaces, brackets, `*`, `?`, or `!`; this especially applies to framework route groups like `src/app/(admin)/...`.
   - If docs governance matters, inspect the repository's local docs rules, metadata conventions, tags, size limits, and link checks directly.

2. Inventory boundaries:
   - Folders and ownership: app routes/actions, features, repositories, schemas, shared components, shared lib, scripts, infra, and generated docs.
   - Public contracts: exported types, schemas, action result shapes, DTOs, repository entrypoints, and UI props when they cross feature boundaries.
   - Data flow: input -> validation -> domain/repository -> action/API -> UI, including external services and side effects.
   - Error flow: expected failures, thrown failures, translation or fallback boundaries, and user-facing message ownership.
   - Dependency direction: who may import whom, forbidden direct access, and allowed helper or shared layers.
   - Verification: checks, tests, build commands, and docs gates tied to each boundary.

3. Choose the document target:
   - Prefer the owner named by repo guidance.
   - Treat an existing document as the owner only when repo guidance or document content covers the requested boundary; a matching filename alone is not enough.
   - Update an existing boundary, architecture, or domain doc in-place when it is clearly the owner.
   - If the existing owner is broad, add a scoped section such as `Application Boundary Map`, `Dependency Direction`, or `Verification Gates` instead of creating a parallel doc.
   - If the requested boundary is app-wide and no owner is defined, propose `docs/architecture-boundaries.md` and note that repo guidance may need a Source of Truth entry when the doc is created.
   - If the user asked to create or update boundary documentation, create `docs/architecture-boundaries.md` when no stronger target exists and repository evidence is sufficient.
   - If the task is planning or review-only, propose `docs/architecture-boundaries.md` instead of creating it, unless the user or repo guidance names another path.

4. Write the document:
   - Use `references/document-shape.md` as the default shape.
   - Keep claims tied to observed files, commands, or docs.
   - Mark uncertain areas as open questions instead of inventing rules.
   - Do not include secrets, environment values, generated output, UI copy rewrites, or unrelated refactor notes.

5. Report evidence:
   - List files inspected, target document path, commands run and exit status, sections created or updated, and remaining risks or open questions.

## Output Rules

- Prefer compact trees and tables over long prose.
- Separate facts from recommendations.
- Separate stable rules from drift and open questions.
- Keep product copy, UI copy, and exact user-facing messages out of the boundary doc unless documenting ownership of those copies.
- Omit sections that would only contain `Unknown`, `N/A`, or template filler.
- If the task is only to review boundary drift without editing docs, report findings first and do not create a document.
