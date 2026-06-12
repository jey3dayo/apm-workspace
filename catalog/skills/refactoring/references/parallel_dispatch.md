# Parallel Diagnostic Dispatch and Subagent Result Contract

Use this reference during Phase 1-E and Phase 3-4 when the diagnostic surface
or execution scope is broad enough to split safely across subagents. For the
review-loop mechanics themselves (worker prompts, review rubric, stop
conditions), use the `subagent-task-review-loop` skill; this reference only
defines the refactoring-specific tracks and result contract.

## Diagnostic Tracks

Prefer parallel workers for read-heavy or bounded tasks:

- React diagnostics: inspect `react-doctor` findings and likely component risk.
- Duplicate/similarity: classify 95%+ and 90-95% candidates by extraction value.
- Boundary ownership: map validation, Result/error, DB/repository, config/env,
  and external IO drift to evidence-backed owner folders.
- Dead-code surface: identify unused exports/files and note dependencies that
  may change after extraction or ownership moves.

## Dispatch Rules

- Do not ask multiple workers to make overlapping edits.
- For implementation work, dispatch only disjoint bounded slices.
- Each slice must name the behavior that should remain unchanged and the
  evidence that proves it.
- Keep the main session responsible for diff review, sequencing, final
  integration, and quality gates.

## Subagent Result Contract

Ask each worker to return the following compact contract:

```markdown
## Subagent Result

- Task: <assigned bounded task>
- Mode: diagnostic | bounded-slice | review
- Scope: <files/modules/concern inspected>
- Files inspected: <paths>
- Files changed: <paths or none>
- Findings:
  - <evidence-backed finding with file path/line when applicable>
- Recommended backlog entries:
  - do-now | accept | next | park | reject: <reason>
- Proposed refactor slice:
  - Goal:
  - Files:
  - Behavior expected to remain unchanged:
  - Acceptance evidence:
- Verification:
  - <command/check run or not run, with reason>
- Risks / unknowns:
  - <remaining uncertainty>
```

## Triage Labels

Classify each returned finding before planning:

- do-now: blocking findings accepted into this session
- accept: evidence-backed improvements scheduled in the current slice
- next: useful follow-up after the current slice
- park: valid but outside current scope
- reject: duplicated, contradicted, or unsupported findings
