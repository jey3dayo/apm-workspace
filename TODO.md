# TODO

## Open Tasks

- Reconcile the `kiro` target: routine rollout runs with `--exclude kiro`, so `.kiro/**` (including the previously deployed caad agents/skills) is not refreshed. Decide whether to deploy once without `--exclude kiro` or keep kiro intentionally excluded, and document the rationale.
- Fix pre-existing Pester failures unrelated to gist work (5 failing as of 2026-07-02):
  - `installs MCP dependencies with apm install only mcp` / `deploys managed MCP dependencies during shell apply`: source now emits `--only mcp --exclude kiro`; update the expected strings (or the source) to match intended behavior.
  - `smoke:catalog normalizes Codex-installed skill paths ...` / `smoke-audits the workspace manifest via temp install`: environment-sensitive smoke tests; confirm whether they need a guard or a fixture.
  - `does not reference removed agents src paths in agent-facing docs`: check which listed doc still references `~/.config/agents/src` or a transitional mirror.
- Document the `--exclude kiro` behavior in the `mise run upgrade` descriptions (`llms.txt`, `AGENTS.md`) so the documented command matches actual behavior.
- Optional: run `apm prune` to drop the 14 orphaned package cache entries not declared in `apm.yml`.

## Notes

- `skills`, `agents`, `commands`, `rules`, and `AGENTS.md` now use `~/.apm/catalog/**` as the managed source of truth.
- `~/.config/nix/agent-skills-sources.nix` is now intentionally empty because external skill sources were retired.
- The current coverage table lives in `docs/apm-task-coverage.md`.
- `nextlevelbuilder/ui-ux-pro-max-skill/.claude/skills/ui-ux-pro-max` は subdir install だと `scripts/` などの相対参照が壊れるため、managed skill 化で扱う。
- Verified on 2026-04-20 with `validate-catalog`, `doctor`, `ci:check`, `apply`, `bash -n`, and `Invoke-Pester` while `~/.config/agents` was absent.
- `.config` still has unrelated pre-existing changes, but they are outside this APM migration slice.
