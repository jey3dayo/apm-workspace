# TODO

## Open Tasks

- [x] Remove stale external sources with no current manifest/runtime usage: `gonta223-humanizer-ja`, `obra-episodic-memory`, `sawyerhood-dev-browser`
- [x] Migrate first managed skill-only batch and remove their source/input/lock entries:
  `millionco-react-doctor`, `anthropics-claude-code`, `epicenterhq-epicenter`
- [x] Migrate second managed skill-only batch and remove their source/input/lock entries:
  `benjitaylor-agentation`, `tokoroten-prompt-review`, `trailofbits-supply-chain-risk-auditor`, `mizchi-chezmoi-dotfiles`
- [x] Migrate third managed skill-only batch and remove their source/input/lock entries:
  `nyosegawa-skills`, `trailofbits-agentic-actions-auditor`, `ui-ux-pro-max`
- [ ] Migrate or retire remaining skill-only external repos, then remove their source/input/lock entries:
  `openai-skills`, `vercel-agent-skills`, `vercel-agent-browser`, `heyvhuang-ship-faster`, `trailofbits-sharp-edges`
- [ ] Migrate or retire remaining external repos that also carry non-skill assets before removal:
  `obra-superpowers`, `openai-codex-plugin-cc`, `lum1104-understand-anything`, `trailofbits-audit-context-building`, `trailofbits-static-analysis`
- [ ] After each removal batch, reconcile `~/.apm/apm.yml` with `mise run migrate-external` and `mise run apply`
- [ ] Refresh `flake.lock` only after the matching source/input entries are gone

## Notes

- `skills`, `agents`, `commands`, `rules`, and `AGENTS.md` now use `~/.apm/catalog/**` as the managed source of truth.
- The current coverage table lives in `docs/apm-task-coverage.md`.
- Verified on 2026-04-20 with `validate-catalog`, `doctor`, `ci:check`, `apply`, `bash -n`, and `Invoke-Pester` while `~/.config/agents` was absent.
- `.config` still has unrelated pre-existing changes, but they are outside this APM migration slice.
