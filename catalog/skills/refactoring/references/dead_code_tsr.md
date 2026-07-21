# Dead-Code Cleanup with TSR 1.3.4

Use this reference during Phase 1 and Phase 3-6 when a TypeScript cleanup
includes unused exports or files. Treat TSR as a detector first, not as an
automatic deletion policy.

## Start with the Repository Contract

1. Inspect `package.json`, `mise.toml`, and repository guidance for an existing
   dead-code or TSR task.
2. Prefer the repository-defined non-writing check task because it may pin the
   version, tsconfig, and framework entrypoints.
3. Read the task definition before running it. Do not assume a task named
   `fix`, `clean`, or `tsr` is detection-only.
4. If no task exists, use the repository's pinned TSR version. For the 1.3.4
   CLI, run without `--write` first.

```bash
tsr --project tsconfig.json 'src/main\.ts$'
```

## TSR 1.3.4 CLI Contract

```text
tsr [options] [...entrypoints]
-p, --project <file>  select the tsconfig; default is tsconfig.json
-w, --write           write fixable changes in place
-r, --recursive       revisit affected files until the project is clean
--include-d-ts         inspect unused exports in .d.ts files
```

Each positional entrypoint is a JavaScript regular-expression source. TSR
constructs `new RegExp(entrypoint)` and tests it against TypeScript project file
paths. Supply at least one pattern; an unmatched pattern is an error. Quote and
escape patterns for the current shell.

```bash
tsr --project tsconfig.app.json 'src/main\.ts$' '.*\.test\.ts$'
```

Entrypoints are roots that TSR must retain, not general include globs. Review
the selected tsconfig's `include`, `exclude`, and project references together
with the patterns.

## Detection and False-Positive Review

Run detection mode, then classify every candidate before editing. Frameworks
can load modules through file conventions, generated manifests, dynamic
imports, registries, plugins, or external tooling that static imports do not
show. Typical examples include routes, pages, middleware, workers, CLI files,
test setup, fixtures, generated declarations, and build/config entrypoints.

Add genuine runtime roots as entrypoint regexes or use a more accurate
tsconfig. Do not delete a candidate merely because TSR reports it. Re-run
detection after entrypoint changes and confirm that expected framework files
remain reachable.

## Remove in Reviewed Slices

Prefer small manual removals from a reviewed detection result. If `--write` is
used, start from a reviewable working tree, keep the project and entrypoint
scope narrow, inspect the diff immediately, and avoid combining unrelated
refactors. Introduce `--recursive` only after the entrypoint model is trusted;
it can surface cascading removals.

After each slice, run focused repository-defined typecheck, lint, and tests for
the affected package or behavior. Then re-run the non-writing TSR check to find
the next slice.

## Do Not Invent TSR Features

TSR 1.3.4 does not natively define `.tsrignore`, `.tsr-config`,
`maxDeletionPerRun`, report generation, or verification hooks. A repository
wrapper may provide concepts with those names, but document them as wrapper
behavior. Redirecting CLI output to a file is shell workflow, not a TSR report
feature. Use TSR's actual entrypoint regexes, tsconfig selection, and CLI flags
unless repository evidence proves an additional layer exists.
