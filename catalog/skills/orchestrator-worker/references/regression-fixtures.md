# Fixed-SHA regression fixtures

Use this procedure when a regression claim depends on seeing the failing test before the fix and the passing test after it. Keep the shared checkout untouched while testing the old behavior.

## Build the fixture

1. Record the full base SHA and materialize it into a task-specific scratch directory, for example with `git archive <full-sha> | tar -x -C <fixture-root>`. Do not switch the shared checkout to the old revision.
2. Keep dependencies independent of the shared worktree. Prefer an offline frozen install whose `node_modules` and package-manager store both live inside the fixture. If those packages are unavailable offline, stop rather than falling back to a shared store.
3. Run `python3 <orchestrator-worker-skill-root>/scripts/check-fixture-isolation.py <fixture-root>`. In the APM source tree, the skill root is `catalog/skills/orchestrator-worker`; the deployed skill retains the same relative `scripts/` path.
4. Treat a shared dependency tree as a separate, exceptional execution mode: it is usable only when the test process runs with an OS-enforced read-only mount or sandbox boundary. Verify that boundary from the OS/sandbox configuration; a clean Git status, a frozen lockfile, or file mode alone does not prove writes are denied. The containment checker intentionally rejects external dependency links, so a rejected link must never be reported as checker-approved or fixture-contained.

## Prove red and green

Keep the same fixture SHA and dependency tree for both runs. Overlay only the regression test and the source under test. Invoke the installed runner directly, such as `./node_modules/.bin/vitest run <focused-test>`; avoid a package-manager execution command that could resolve or install dependencies during the check.

Record the fixture's `package.json` and lockfile hashes before and after each run. Also record the real path and version of the runner and the key packages involved in the regression, resolved from the fixture directory. The hashes and resolution evidence must remain stable across red and green. If the test does not fail on the old source for the intended assertion, reject that red result and adjust the test or the fault injection.

The checker resolves dependency links against the fixture's real path. It rejects external `node_modules` links, external root or nested `.pnpm-store` links, and shallow external `.pnpm`, unscoped package, and `@scope/package` links. It follows an in-fixture `@scope` link for one shallow package-link inspection. It accepts real dependency directories and links whose targets remain under the fixture. To avoid walking dependency contents, it prunes `node_modules`, package stores, VCS data, caches, and build output; this is a path-containment check, not proof that the operating system denies every possible write.

If the repository formatter discovers a nested `biome.json` inside the scratch copy, keep that config out of the repository-level format scan. In the disposable copy, rename it to `.fixture-disabled` or run the formatter only against the intended repository files with the repository config. Do not change the tracked config to make a fixture pass.

The fixture checker accepts independent dependency directories and links whose real paths remain under the fixture root. Its Bats contract is `tests/regression-fixture-isolation.bats`.
