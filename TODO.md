# TODO

## Open Tasks

## Notes

- `skills`, `agents`, `commands`, `rules`, and `AGENTS.md` now use `~/.apm/catalog/**` as the managed source of truth.
- `~/.config/nix/agent-skills-sources.nix` is now intentionally empty because external skill sources were retired.
- The current coverage table lives in `docs/apm-task-coverage.md`.
- `nextlevelbuilder/ui-ux-pro-max-skill/.claude/skills/ui-ux-pro-max` は subdir install だと `scripts/` などの相対参照が壊れるため、managed skill 化で扱う。
- Verified on 2026-04-20 with `validate-catalog`, `doctor`, `ci:check`, `apply`, `bash -n`, and `Invoke-Pester` while `~/.config/agents` was absent.
- `.config` still has unrelated pre-existing changes, but they are outside this APM migration slice.
