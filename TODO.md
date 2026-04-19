# TODO

## Open Tasks

- Verify the new `catalog`-as-source flow on both PowerShell and POSIX shells after the script changes.
- Decide when the transitional mirror in `~/.config/agents/src/**` can be downgraded further or removed.
- Update any remaining helper docs or prompts that still tell operators to edit `~/.config/agents/src/**` first.

## Notes

- `skills`, `agents`, `commands`, `rules`, and `AGENTS.md` now use `~/.apm/catalog/**` as the managed source of truth.
- `~/.config/agents/src/**` is a transitional mirror refreshed by `mise run stage-catalog`.
- The current coverage table lives in `docs/apm-task-coverage.md`.
- The current blockers are follow-up cleanup and confidence checks, not APM install health.
- `.config` still has unrelated pre-existing changes, but they are outside this APM migration slice.
