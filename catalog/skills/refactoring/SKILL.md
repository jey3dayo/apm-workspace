---
name: refactoring
description: |
  [What] Integrated refactoring workflow for TypeScript/JavaScript/React:
  similarity-ts (duplicate detection), react-doctor (React diagnostics),
  tsr (dead code removal), and boundary ownership scanning, orchestrated
  with code-quality-improvement.
  [When] Use when users mention リファクタ / refactor, 重複コード /
  duplicate code, コード整理 / cleanup, デッドコード・未使用ファイル・
  未使用 export removal, 共通 helper extraction, validation / Result /
  repository boundary, folder ownership, or cleanup-only plans. Do not use
  for feature implementation or task execution; use the normal
  implementation flow or executing-plans instead.
---

# Refactoring - Integrated TypeScript/JavaScript/React Refactoring Workflow

Orchestrator skill that combines `similarity-ts` (duplicate code detection),
`react-doctor` (React diagnostics), boundary ownership scanning, and `tsr`
(dead code removal) into a 3-phase incremental refactoring workflow:
Diagnose -> Analyze & Plan -> Execute.

Save diagnostic outputs under `tmp/refactoring/` in the target repository
unless the user specifies another location.

## Prerequisites: Project Type Detection

```bash
# Detect React project
rg -q '"react"' package.json && echo "React project"

# Detect TypeScript project
[ -f tsconfig.json ] && echo "TypeScript project"
```

| Project Type              | Parallel diagnostic tracks         |
| ------------------------- | ---------------------------------- |
| React + TypeScript/JS     | react-doctor + similarity-ts + tsr |
| TypeScript/JS (non-React) | similarity-ts + tsr                |

## Phase 1: Diagnose

For broad cleanup requests, default to parallel diagnosis and evidence
gathering before planning. Keep the main session responsible for the immediate
blocking task, priority decisions, and integration judgment.

```bash
# Create the diagnostic output directory first
mkdir -p tmp/refactoring
```

### 1-A: React Project Diagnostics

```bash
# Run only if package.json contains "react"
npx -y react-doctor@latest . --verbose > tmp/refactoring/react-doctor-report.txt
```

The report includes a 0-100 score; use it in the Phase 2 plan.

### 1-B: Duplicate Code Detection (All TS/JS Projects)

If `similarity-ts` is not on PATH, read the `similarity` skill
(`../similarity/SKILL.md`) first for install and invocation guidance.

```bash
# Scan at 90%+ similarity (start with severe duplicates)
similarity-ts --threshold 0.9 . > tmp/refactoring/similarity-report.md

# Optional: broader scan at the tool default (0.87) to collect
# low-priority future candidates for the Phase 2 matrix
similarity-ts . > tmp/refactoring/similarity-default.md

# Optional: duplicate type definitions (skip if src/types/ does not exist)
similarity-ts --types --threshold 0.95 src/types/ >> tmp/refactoring/similarity-report.md
```

### 1-C: Technology Boundary Ownership Scan

Before moving code, find where the repository already expects each technology
concern to live. Search for owner folders and import patterns first:

```bash
rg --files | rg '(^|/)(schemas?|repositories?|repository|db|services?|actions?|adapters?)(/|$)'
rg -n "from ['\"].*(schemas?|repositories?|repository|db|services?|actions?|adapters?)|valibot|neverthrow|ResultAsync|drizzle|transaction|\\.select\\(|\\.insert\\(|\\.update\\("
```

Treat a folder as an owner only when repository evidence supports it: existing
imports, exports, tests, docs, or repeated call patterns. If multiple owner
folders are plausible, keep the plan conditional until the boundary is
confirmed. Use confirmed owner folders as the default destination for
refactoring; other layers should import the owner's exported schema, parser,
repository, helper, or adapter instead of re-implementing the concern locally.

Load `references/boundary_ownership.md` when validation, Result/error,
DB/query, config/env, or external IO drift is part of the refactoring scope.

### 1-D: Common Helper Extraction Judgment

Do not extract a helper only because duplicated text is similar; classify the
duplication by concern and owner first. Load `references/helper_extraction.md`
for the concern -> owner candidates -> caller rule table and the extract/keep
decision rule before deciding individual extractions.

### 1-E: Parallel Diagnostic Dispatch

When the diagnostic surface is broad enough to split safely, dispatch parallel
workers per track (React diagnostics, duplicate/similarity, boundary
ownership, dead-code surface). Load `references/parallel_dispatch.md` for the
track definitions and the subagent result contract, and use the
`review-fix-loop` skill for review-loop mechanics.

## Phase 2: Analyze & Plan

Classify diagnostic results using the priority matrix. If a diagnostic tool was
not run, mark that value as `not run` in the plan. Do not invent scores,
duplicate counts, or owner names; base boundary findings only on file/import
evidence already collected.

### Priority Matrix

| Priority | Condition                                                                                        | Action                          |
| -------- | ------------------------------------------------------------------------------------------------ | ------------------------------- |
| Critical | react-doctor errors AND similarity 95%+                                                          | Fix immediately (this session)  |
| Critical | DB/query/transaction logic leaks into UI, route, or feature code while a repository owner exists | Move behind repository/db owner |
| High     | react-doctor warnings OR similarity 90-95%                                                       | Plan fix (high priority)        |
| High     | Schema or Result/error conversion is duplicated outside the discovered owner boundary            | Consolidate behind owner export |
| Low      | similarity 87-90% (from the optional default-threshold scan)                                     | Future candidate (needs review) |
| Low      | Test-only, mock, seed, migration, or thin wrapper boundary exceptions                            | Review and document if needed   |

### Plan Output Format

```markdown
## Refactoring Plan

### Diagnostics Summary

- react-doctor score: XX/100 (75+ = Great, 50-74 = Needs work, 0-49 = Critical)
- Duplicate code pairs: XX (95%+: X pairs, 90-95%: X pairs)
- Boundary ownership findings: XX (schema/validation: X, Result/error: X, DB/repository: X)

### Subagent Findings Summary (when dispatch was used)

- do-now / accept / next / park / reject: <triaged findings per label>

### Priority Actions

1. [Critical] react-doctor error: <description> → <fix approach>
2. [Critical] Duplicate 95%+: <file1> ↔ <file2> → Extract common function
3. [High] Boundary ownership drift: <technology> in <file> → Move to <owner folder/export>

### Estimated Scope

- Immediate fixes: X items / Planned fixes: X items / Future candidates: X items
```

## Phase 3: Execute

Parallelize implementation only when slices have disjoint write scopes and
clear acceptance evidence. The main session owns sequencing, diff review,
integration, and quality gates even when a worker prepares a bounded slice.

### 3-1: Fix react-doctor Errors

Fix react-doctor errors first (highest severity).

```
Error Type → Fix Approach:
- Architecture: components inside components → Move components to top level
- State & Effects: useState from props → Change to proper state management
- Security: hardcoded secrets → Migrate to environment variables
- Bundle Size: barrel imports → Change to direct imports
- Next.js: missing metadata → Add metadata export
```

### 3-2: Consolidate Duplicate Code at 95%+

```typescript
// Pattern 1: Simple function extraction
// Before: 98% similar functions in 2 files
// After: Extract to common utils and import from both files

// Pattern 2: Generalization
// Before: getUserById / getAdminById (94% similar)
// After: Consolidate into findByIdOrThrow<T>(model, id, resourceName)

// Pattern 3: Extract common interface
// Before: Multiple similar type definitions
// After: Base type + extends to centralize common parts
```

Before consolidation, check impact scope with MCP Serena
(`find_referencing_symbols`, `find_symbol`) to identify callers.

### 3-3: Repair Technology Boundary Ownership

When a technology concern is implemented outside its owner folder, refactor to
the repository's existing boundary shape instead of inventing a new
abstraction:

1. Move schema definitions, parsers, or validation helpers into the discovered
   schema/validation owner, then update callers to import the exported schema
   or parse helper.
2. Move repeated `Result`/error conversion into the existing repository,
   service, action, or adapter boundary that already owns that conversion.
3. Move direct DB, Drizzle, SQL, query builder, and transaction code out of
   UI, route, and feature modules into the existing `db` or repository owner.
4. Add or update focused tests for the boundary contract: parser shape, error
   conversion, repository return value, or transaction behavior.

### 3-4: Execute Bounded Refactor Slices

Use workers only for small implementation slices when the files/modules do not
overlap with other active edits (rules in `references/parallel_dispatch.md`).
Review every worker diff before building on it, then run the relevant focused
check before moving to the next slice.

### 3-5: Fix ESLint/Type Safety Issues

Fix remaining code quality issues after deduplication. Attempt the
repository's lint auto-fix task first, then review remaining errors. For
complex type safety issues (any-type elimination, Result<T,E> patterns),
delegate to the `code-quality-improvement` skill.

### 3-6: Remove Dead Code

Detect dead code with the repository's tsr task (for example `pnpm tsr:check`),
review the report, then remove incrementally. For detailed usage, refer to the
`tsr` skill (`../tsr/SKILL.md`).

### 3-7: Verification (Required)

Run the repository's defined check tasks after every fix step. Prefer tasks
defined by the repository (mise/pnpm/npm scripts) over ad hoc commands:

```bash
# Example for a pnpm repository
pnpm type-check && pnpm lint && pnpm test
```

Do not proceed to the next step until all pass.

## Skill Delegation

| Problem Area                                     | Delegated Skill                        |
| ------------------------------------------------ | -------------------------------------- |
| Detailed duplicate code analysis                 | `../similarity/SKILL.md`               |
| ESLint errors / type safety                      | `../code-quality-improvement/SKILL.md` |
| Dead code removal                                | `../tsr/SKILL.md`                      |
| React-specific pattern diagnosis                 | `../react-doctor/SKILL.md` (if exists) |
| Parallel diagnostics / bounded slice review loop | `../review-fix-loop/SKILL.md`          |
| Impact scope / reference tracking                | MCP Serena: `find_referencing_symbols` |

## Principle of Incremental Execution

1. Do not make large-scale changes at once: start with similarity 95%+, stop at
   90-95% in the planning phase.
2. Commit between phases: after each phase, run `git commit` to keep rollback
   possible.
3. Verify business logic: high similarity != must consolidate (may have
   different semantics).
4. Owner folder first: if a technology already has a clear owner folder, move
   implementation there and import its public API from other layers.

Goals: zero similarity 90%+ pairs, react-doctor score 75+, 0 type errors,
0 lint violations.
