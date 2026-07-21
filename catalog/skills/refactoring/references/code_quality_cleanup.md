# Large-Scale Code Quality Cleanup

Use this reference when lint or type-safety debt is too large for one safe
change. Preserve behavior while reducing the measured baseline in reviewable
slices.

## Establish the Baseline

1. Discover and use the repository-defined lint, typecheck, test, and format
   commands. Do not invent a parallel command path.
2. Run the relevant checks without changing files.
3. Record the total findings and group them by rule or diagnostic code. Keep
   the raw output available so the final count can be compared with the same
   command.
4. Identify existing failures that are outside the selected scope; do not
   attribute them to the cleanup.

## Classify by Risk

Plan slices by behavioral risk rather than language, framework, or directory:

- Low risk: deterministic formatting, unused imports, or equivalent findings
  whose fixes do not change runtime behavior.
- Medium risk: local rewrites, narrowing, or renames that may affect callers.
- High risk: boundary contracts, control flow, public APIs, persistence, or
  external IO.

Prefer the lowest-risk coherent slice first. A batch of roughly 50-100 findings
can be a useful review heuristic, but shrink it whenever the diff crosses
owners, behavior boundaries, or verification surfaces.

## Execute a Slice

1. Apply the repository's supported auto-fix for the selected scope when one
   exists.
2. Inspect the diff before accepting it. Revert or correct fixes that broaden
   scope, obscure intent, or alter behavior.
3. Resolve remaining findings manually within the same risk category.
4. Treat renames and `_`-prefix suppressions as behavior-sensitive. Search all
   references and verify that the change did not introduce an undefined use,
   stale property access, or mismatched callback parameter.
5. Run focused typecheck, lint, and tests for the touched boundary after every
   slice. Stop and repair regressions before starting another slice.

## Measure the Result

Re-run the same baseline commands with the same scope. Report before and after
counts by rule or diagnostic code, the checks executed, remaining known debt,
and any findings deliberately deferred because their risk requires a separate
change.
