---
name: refactoring
description: >-
  Plan and execute TS/JS/React refactoring orchestration: react-doctor diagnostics,
  dead code and unused exports, helper extraction, mutation-testing test-safety
  checks, and validation / Result / repository boundary ownership（「リファクタ」
  「コード整理」）. Duplicate-code detection itself is `similarity` and test-safety
  auditing itself is `mutation-testing-audit`; this skill consumes their reports.
  Not for feature work.
---

# Refactoring - Integrated TypeScript/JavaScript/React Refactoring Workflow

Orchestrator skill that combines `similarity-ts` (duplicate code detection),
`react-doctor` (React diagnostics), boundary ownership scanning, and focused
dead-code and code-quality cleanup guidance into a 3-phase refactoring workflow:
Diagnose -> Analyze & Plan -> Execute.

Save diagnostic outputs under `tmp/refactoring/` in the target repository
unless the user specifies another location.

## Prerequisites: Project Type Detection

| Project Type                                      | Parallel diagnostic tracks                    |
| ------------------------------------------------- | --------------------------------------------- |
| React + TypeScript/JS (`"react"` in package.json) | react-doctor + similarity-ts + dead-code scan |
| TypeScript/JS (non-React, has `tsconfig.json`)    | similarity-ts + dead-code scan                |

For React projects, choosing hooks / `useEffect` patterns themselves is
`react-hooks-refactoring`; this skill only digests `react-doctor` diagnostics.

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

Run duplicate detection by following the `similarity` skill
(`../similarity/SKILL.md`): it is the source of truth for `similarity-ts`
installation, invocation, thresholds, and their pitfalls, so this skill does
not restate those commands. It only consumes the report: save the severe
duplicates scan (90%+) as `tmp/refactoring/similarity-report.md`, and — when
collecting low-priority future candidates for the Phase 2 matrix — the
optional default-threshold scan as `tmp/refactoring/similarity-default.md`.
Classify the results with the Phase 2 priority matrix; threshold selection
and interpretation stay with `similarity`.

One scan this workflow adds on top of the `similarity` defaults:

```bash
# Optional: duplicate type definitions at 95%+ (skip if src/types/ does not exist)
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

Apply the deletion test as the positive criterion: imagine deleting the
candidate helper. If its complexity would reappear across N callers, it earns
its keep; if the complexity just vanishes, it is a pass-through, so inline it.
Load the `codebase-design` skill for the vocabulary (module, interface, seam).

### 1-E: Parallel Diagnostic Dispatch

When the diagnostic surface is broad enough to split safely, dispatch parallel
workers per track (React diagnostics, duplicate/similarity, boundary
ownership, dead-code surface, test safety when 1-F applies). Load `references/parallel_dispatch.md` for the
track definitions and the subagent result contract, and use the
`sol-loop` skill for review-loop mechanics.

### 1-F: Test-Safety Spot Check (Conditional)

When the refactoring scope includes pure-logic modules that already have unit
tests (sorting, parsing, date math, classification), audit whether those tests
actually pin the behavior before planning to move or consolidate the code.
This matters most for 3-3, where tests are replaced at a consolidated owner's
interface and the old ones deleted: "tests exist" says nothing about whether
they would notice a behavior change.

Run the audit by following the `mutation-testing-audit` skill
(`../mutation-testing-audit/SKILL.md`): it is the source of truth for tool
setup, survivor classification, and test-writing rules, so this skill does
not restate them. It only consumes the classification: save the audit brief
as `tmp/refactoring/mutation-audit.md` and carry the real-gap count into the
Phase 2 plan.

Skip this track when the scope has no pure-logic module with unit tests, or
when no machine fast enough for the dry run is available; mark it `not run`
in the plan instead of guessing at test quality.

## Phase 2: Analyze & Plan

Classify diagnostic results using the priority matrix. If a diagnostic tool was
not run, mark that value as `not run` in the plan. Do not invent scores,
duplicate counts, or owner names; base boundary findings only on file/import
evidence already collected.

### Priority Matrix

| Priority | Condition                                                                                        | Action                                                                 |
| -------- | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| Critical | react-doctor errors AND similarity 95%+                                                          | Fix immediately (this session)                                         |
| Critical | DB/query/transaction logic leaks into UI, route, or feature code while a repository owner exists | Move behind repository/db owner                                        |
| High     | react-doctor warnings OR similarity 90-95%                                                       | Plan fix (high priority)                                               |
| High     | Schema or Result/error conversion is duplicated outside the discovered owner boundary            | Consolidate behind owner export                                        |
| High     | Mutation audit (1-F) finds real gaps in the tests of a module in scope                           | Write the adversarial tests before moving or consolidating that module |
| Low      | similarity 87-90% (from the optional default-threshold scan)                                     | Future candidate (needs review)                                        |
| Low      | Test-only, mock, seed, migration, or thin wrapper boundary exceptions                            | Review and document if needed                                          |

### Plan Output Format

```markdown
## Refactoring Plan

### Diagnostics Summary

- react-doctor score: XX/100 (75+ = Great, 50-74 = Needs work, 0-49 = Critical)
- Duplicate code pairs: XX (95%+: X pairs, 90-95%: X pairs)
- Boundary ownership findings: XX (schema/validation: X, Result/error: X, DB/repository: X)
- Mutation audit (when run): XX% score, X real gaps in scope

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

Fix react-doctor errors first (highest severity), following each finding's own guidance.

### 3-2: Consolidate Duplicate Code at 95%+

Before consolidation, check impact scope with `rg` to list every reference
and identify callers.

### 3-3: Repair Technology Boundary Ownership

When a technology concern is implemented outside its owner folder, refactor to
the repository's existing boundary shape instead of inventing a new
abstraction. Hold to seam discipline: one adapter is a hypothetical seam, two
(for example production and test) make a real one, so introduce no port or
seam without two adapters. Load the `codebase-design` skill (its `DEEPENING.md`
for dependency categories) when the owner's interface or seam placement is in
question.

1. Move schema definitions, parsers, or validation helpers into the discovered
   schema/validation owner, then update callers to import the exported schema
   or parse helper.
2. Move repeated `Result`/error conversion into the existing repository,
   service, action, or adapter boundary that already owns that conversion.
3. Move direct DB, Drizzle, SQL, query builder, and transaction code out of
   UI, route, and feature modules into the existing `db` or repository owner.
4. Add or update focused tests for the boundary contract: parser shape, error
   conversion, repository return value, or transaction behavior. Replace,
   don't layer: once tests exist at the consolidated owner's interface, delete
   the old tests that exercised the shallow pieces past that interface.

### 3-4: Execute Bounded Refactor Slices

Use workers only for small implementation slices when the files/modules do not
overlap with other active edits (rules in `references/parallel_dispatch.md`).
Review every worker diff before building on it, then run the relevant focused
check before moving to the next slice.

### 3-5: Fix ESLint/Type Safety Issues

Fix remaining code quality issues after deduplication. Attempt the
repository's lint auto-fix task first, then review remaining errors. For a
large lint or type-safety backlog, load
`references/code_quality_cleanup.md` and execute one bounded risk category at
a time.

### 3-6: Remove Dead Code

Detect dead code with the repository's existing task, review the report, then
remove incrementally. When the repository uses TSR, load
`references/dead_code_tsr.md` for its actual CLI contract and safety checks.

### 3-7: Verification (Required)

After each fix step, run the focused check for the touched area with the repository's defined tasks (tests for the changed files, plus type-check and lint when types or lint rules are affected). Run the repository's full gate (`check` / `test` / `ci` / `verify`) before sharing. Do not move to the next step while the focused check fails.

Example of a full gate:

```bash
# Example for a pnpm repository
pnpm run type-check && pnpm run lint && pnpm run test
```

When tests were consolidated at a new owner interface (3-3), or adversarial
tests were added under the Phase 2 mutation-audit row, re-run the 1-F spot
check on the touched modules before sharing and confirm the targeted
survivors are gone.

## Related Skills and References

| Problem Area                                     | Skill or reference                   |
| ------------------------------------------------ | ------------------------------------ |
| Detailed duplicate code analysis                 | `../similarity/SKILL.md`             |
| Test quality of modules in scope                 | `../mutation-testing-audit/SKILL.md` |
| Large lint / type-safety cleanup                 | `references/code_quality_cleanup.md` |
| Dead code removal with TSR                       | `references/dead_code_tsr.md`        |
| React-specific pattern diagnosis                 | `react-doctor` skill (if installed)  |
| Parallel diagnostics / bounded slice review loop | `sol-loop` skill                     |
| Impact scope / reference tracking                | `rg` for full reference listing      |
| Interface / seam design vocabulary               | `codebase-design` skill              |

## Principle of Incremental Execution

1. Do not make large-scale changes at once: start with similarity 95%+, stop at
   90-95% in the planning phase.
2. End each phase at a verified checkpoint (checks green, diff reviewed). Whether
   to commit follows the global stop/confirm policy; hand commit splitting to `atomic-commit`.
3. Verify business logic: high similarity != must consolidate (may have
   different semantics).
4. Owner folder first: if a technology already has a clear owner folder, move
   implementation there and import its public API from other layers.

Done when every Critical/High item in the plan is fixed or explicitly parked
with a reason, and the repository's check tasks pass.
