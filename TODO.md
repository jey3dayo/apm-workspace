# TODO

## Open Tasks

- No open tasks in this migration slice.

## Notes

- `skills`, `agents`, `commands`, `rules`, and `AGENTS.md` now use `~/.apm/catalog/**` as the managed source of truth.
- The current coverage table lives in `docs/apm-task-coverage.md`.
- Verified on 2026-04-20 with `validate-catalog`, `doctor`, `ci:check`, `apply`, `bash -n`, and `Invoke-Pester` while `~/.config/agents` was absent.
- `.config` still has unrelated pre-existing changes, but they are outside this APM migration slice.
