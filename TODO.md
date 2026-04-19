# TODO

## Open Tasks

- Decide whether top-level managed `commands/` should move into the APM catalog model.
- If `commands/` will move, define an authoritative source tree under `~/.config/agents/src/commands/`.
- Extend the catalog build/sync flow only after the `commands/` source-of-truth is defined.
- Decide whether `validate-catalog` should become a real `mise run validate-catalog` task in `~/.apm/mise.toml`, or whether docs should consistently describe it as a maintenance command only.
- Commit and push the current `~/.apm` doc updates, then run `mise run register-catalog` if the tracked catalog package changed.

## Notes

- `skills`, `agents`, `rules`, and `AGENTS.md` are already on the managed catalog path.
- Top-level `commands/` are the main remaining migration gap.
- The current coverage table lives in `docs/apm-task-coverage.md`.
